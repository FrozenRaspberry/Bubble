// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./Invitation.sol";

contract MinorityGame is Ownable, ReentrancyGuard, IERC721Receiver {
    enum Vote {YES, NO}
    enum GameStatus {NONE, START, VOTE, REVEAL, CLAIM}
    struct Status { 
        GameStatus status;
        uint activeBlock;
    }
    struct PlayerStatus {
        uint round;
        GameStatus status;
        bytes32 encrVote;
        Vote voteRevealed;
        bool registered;
    }

    // Game Info
    Invitation public invitation;
    uint public currentRound;
    Status public currentStatus;
    string public currentTopic;
    uint public voteYesCount;
    uint public voteNoCount;
    uint public voteCost = 0.001 ether;
    // Player Info
    mapping(address => PlayerStatus) public playerStatus;
    mapping(address => uint) public registeredInvitationId;

    function register(uint tokenId, address player) internal {
        playerStatus[player].registered = true;
        registeredInvitationId[player] = tokenId;
    }

    function isRegistered() public view returns (bool) {
        return playerStatus[msg.sender].registered;
    }

    // Prepare Game
    function setInvitationAddress(address addr) public onlyOwner {
        invitation = Invitation(addr);
    }

    function newGame(uint round, string memory topic, uint blockNum) public onlyOwner {
        currentRound = round;
        currentTopic = topic;
        currentStatus = Status(GameStatus.START, blockNum);
        voteYesCount = 0;
        voteNoCount = 0;
    }

    function setGameStatus(GameStatus status, uint blockNum) public onlyOwner {
        currentStatus = Status(status, blockNum);
    }

    function gameVote(bytes32 encrVote) payable public nonReentrant {
        require (msg.value >= voteCost, "Game: Vote costs 0.01ETH");
        require (currentStatus.status == GameStatus.VOTE, "Game: Invalid game status (vote)");
        require (currentStatus.activeBlock < block.number, "Game: Vote not start yet");
        require (isRegistered(), "Game: You have not registered");
        // The player need to participate all games before
        if (currentRound > 1) {
            require (playerStatus[msg.sender].round == currentRound - 1, "Game: You didn't play last round.");
            require (playerStatus[msg.sender].status == GameStatus.CLAIM, "Game: You didn't claim in the last round.");
        } else {
            require (playerStatus[msg.sender].status == GameStatus.NONE, "Game: Invalid status.");
        }
        playerStatus[msg.sender].round = currentRound;
        playerStatus[msg.sender].status = GameStatus.VOTE;
        playerStatus[msg.sender].encrVote = encrVote;
    }

    function reveal(string memory pass, uint vote) public nonReentrant {
        require (currentStatus.status == GameStatus.REVEAL, "Game: Invalid game status (reveal)");
        require (currentStatus.activeBlock < block.number, "Game: Reveal not start yet");
        require (isRegistered(), "Game: You have not registered");
        // The player need to vote before
        require (playerStatus[msg.sender].round == currentRound, "Game: You didn't vote this round.");
        require (playerStatus[msg.sender].status == GameStatus.VOTE, "Game: Invalid player status.");
        require (playerStatus[msg.sender].encrVote == keccak256(abi.encodePacked(pass, vote)),"Game: Incorrect password or vote data.");
        // Result
        if (vote == 0) {
            voteYesCount ++;
            playerStatus[msg.sender].status = GameStatus.REVEAL;
            playerStatus[msg.sender].voteRevealed = Vote.YES;
            payable(msg.sender).transfer(voteCost * 4 / 10);
        } else if (vote == 1) {
            voteNoCount ++;
            playerStatus[msg.sender].status = GameStatus.REVEAL;
            playerStatus[msg.sender].voteRevealed = Vote.NO;
            payable(msg.sender).transfer(voteCost * 4 / 10);
        } else {
            revert("Game: Incorrect vote input.");
        }
    }

    function claim(uint tokenId) public nonReentrant {
        require (currentStatus.status == GameStatus.CLAIM, "Game: Invalid game status (claim)");
        require (currentStatus.activeBlock < block.number, "Game: Claim not start yet");
        require (isRegistered(), "Game: You have not registered");
        // The player need to vote before
        require (playerStatus[msg.sender].round == currentRound, "Game: You didn't vote this round.");
        require (playerStatus[msg.sender].status == GameStatus.REVEAL, "Game: Invalid player status.");
        // Result
        require (voteYesCount != 0 && voteNoCount != 0, "Game: No Winner.");
        if (voteYesCount == voteNoCount) {
            // DRAW
            payable(msg.sender).transfer(voteCost * 4 / 10);
        } else if (voteYesCount < voteNoCount && playerStatus[msg.sender].voteRevealed == Vote.YES) {
            // vote YES and win
            payable(msg.sender).transfer(voteCost * 6 / 10 + voteCost * 4 / 10 * voteNoCount / voteYesCount);
        } else if (voteYesCount > voteNoCount && playerStatus[msg.sender].voteRevealed == Vote.NO) {
            // vote NO and win
            payable(msg.sender).transfer(voteCost * 6 / 10 + voteCost * 4 / 10 * voteYesCount / voteNoCount);
        } else {
            // lose, new invitation is required to continue playing
            revert("Game: You lost, reregister with another invitation to play the next round.");
        }
        playerStatus[msg.sender].status = GameStatus.CLAIM;
    }

    function onERC721Received( address operator, address from, uint256 tokenId, bytes calldata data ) public override returns (bytes4) {
        register(tokenId, from);
        return this.onERC721Received.selector;
    }
}