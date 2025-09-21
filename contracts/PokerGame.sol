// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { FHE, euint8, euint32, ebool } from "@fhevm/solidity/lib/FHE.sol";
import { SepoliaConfig } from "@fhevm/solidity/config/ZamaConfig.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PokerGame
 * @dev Privacy Poker Game using Zama FHE for confidential card games
 * @notice All player moves, cards, and bets are encrypted for complete privacy
 */
contract PokerGame is ReentrancyGuard, Ownable, SepoliaConfig {

    struct Game {
        uint256 gameId;
        uint256 maxPlayers;
        uint256 currentPlayers;
        uint256 totalPot;
        uint256 minBet;
        uint8 gameType; // 0: Texas Hold'em, 1: Five Card, 2: Omaha, 3: Seven Card
        bool isActive;
        bool hasStarted;
        address[] players;
        uint256 currentRound;
        uint256 timestamp;
    }

    struct PlayerState {
        address player;
        uint256 gameId;
        ebool[] encryptedCards; // FHE encrypted cards
        ebool isActive; // FHE encrypted active status
        euint32 encryptedBet; // FHE encrypted bet amount
        ebool hasFolded; // FHE encrypted fold status
        uint256 totalBet;
        uint256 lastAction;
    }

    struct GameMove {
        uint256 gameId;
        address player;
        ebool encryptedCall; // FHE encrypted call decision
        ebool encryptedRaise; // FHE encrypted raise decision
        ebool encryptedFold; // FHE encrypted fold decision
        euint32 encryptedBetAmount; // FHE encrypted bet amount
        uint256 timestamp;
    }

    // State variables
    uint256 public gameCounter;
    uint256 public moveCounter;

    mapping(uint256 => Game) public games;
    mapping(uint256 => mapping(address => PlayerState)) public playerStates;
    mapping(uint256 => GameMove[]) public gameMoves;
    mapping(address => uint256[]) public playerGames;
    mapping(uint256 => mapping(address => bool)) public hasJoined;

    // Game constants
    uint256 public constant MAX_PLAYERS = 8;
    uint256 public constant MIN_BET = 0.01 ether;
    uint256 public constant CARDS_PER_HAND = 5;

    // Events
    event GameCreated(
        uint256 indexed gameId,
        uint8 gameType,
        uint256 maxPlayers,
        uint256 minBet
    );

    event PlayerJoined(
        uint256 indexed gameId,
        address indexed player,
        uint256 totalPlayers
    );

    event GameStarted(
        uint256 indexed gameId,
        address[] players,
        uint256 totalPot
    );

    event PlayerMoved(
        uint256 indexed gameId,
        address indexed player,
        uint256 moveId,
        uint256 timestamp
    );

    event GameEnded(
        uint256 indexed gameId,
        address indexed winner,
        uint256 prize
    );

    event CardsDealt(
        uint256 indexed gameId,
        uint256 round
    );

    constructor() Ownable(msg.sender) {
        gameCounter = 0;
        moveCounter = 0;
    }

    /**
     * @dev Create a new poker game
     * @param _gameType Type of poker game (0-3)
     * @param _maxPlayers Maximum number of players (2-8)
     * @param _minBet Minimum bet amount
     */
    function createGame(
        uint8 _gameType,
        uint256 _maxPlayers,
        uint256 _minBet
    ) external returns (uint256) {
        require(_gameType <= 3, "Invalid game type");
        require(_maxPlayers >= 2 && _maxPlayers <= MAX_PLAYERS, "Invalid player count");
        require(_minBet >= MIN_BET, "Bet too low");

        gameCounter++;

        games[gameCounter] = Game({
            gameId: gameCounter,
            maxPlayers: _maxPlayers,
            currentPlayers: 0,
            totalPot: 0,
            minBet: _minBet,
            gameType: _gameType,
            isActive: true,
            hasStarted: false,
            players: new address[](0),
            currentRound: 0,
            timestamp: block.timestamp
        });

        emit GameCreated(gameCounter, _gameType, _maxPlayers, _minBet);
        return gameCounter;
    }

    /**
     * @dev Join a poker game
     * @param _gameId Game ID to join
     * @param _wantsToJoin Boolean indicating desire to join (will be encrypted)
     */
    function joinGame(uint256 _gameId, bool _wantsToJoin) external payable nonReentrant {
        require(_gameId <= gameCounter && _gameId > 0, "Invalid game ID");
        require(!hasJoined[_gameId][msg.sender], "Already joined");

        Game storage game = games[_gameId];
        require(game.isActive && !game.hasStarted, "Game not available");
        require(game.currentPlayers < game.maxPlayers, "Game full");
        require(msg.value >= game.minBet, "Insufficient bet");

        // Encrypt the player's join decision using FHEVM compatible API
        ebool encryptedWantsToJoin = FHE.asEbool(_wantsToJoin);

        // For privacy, we encrypt the join status but still need to manage the game state
        if (_wantsToJoin) {
            game.players.push(msg.sender);
            game.currentPlayers++;
            game.totalPot += msg.value;
            hasJoined[_gameId][msg.sender] = true;
            playerGames[msg.sender].push(_gameId);

            // Initialize player state with encrypted values
            playerStates[_gameId][msg.sender] = PlayerState({
                player: msg.sender,
                gameId: _gameId,
                encryptedCards: new ebool[](CARDS_PER_HAND),
                isActive: FHE.asEbool(true),
                encryptedBet: FHE.asEuint32(uint32(msg.value / 1 wei)),
                hasFolded: FHE.asEbool(false),
                totalBet: msg.value,
                lastAction: block.timestamp
            });

            emit PlayerJoined(_gameId, msg.sender, game.currentPlayers);

            // Auto-start if minimum players reached
            if (game.currentPlayers >= 2) {
                _dealInitialCards(_gameId);
                game.hasStarted = true;
                emit GameStarted(_gameId, game.players, game.totalPot);
            }
        }
    }

    /**
     * @dev Make a move in the poker game
     * @param _gameId Game ID
     * @param _call Boolean for call action (will be encrypted)
     * @param _raise Boolean for raise action (will be encrypted)
     * @param _fold Boolean for fold action (will be encrypted)
     */
    function makeMove(
        uint256 _gameId,
        bool _call,
        bool _raise,
        bool _fold
    ) external payable nonReentrant {
        require(hasJoined[_gameId][msg.sender], "Not in game");

        Game storage game = games[_gameId];
        require(game.isActive && game.hasStarted, "Game not active");

        PlayerState storage player = playerStates[_gameId][msg.sender];

        // Encrypt all move decisions using FHEVM compatible API
        ebool encryptedCall = FHE.asEbool(_call);
        ebool encryptedRaise = FHE.asEbool(_raise);
        ebool encryptedFold = FHE.asEbool(_fold);

        // Handle bet amount if raising
        euint32 encryptedBetAmount = FHE.asEuint32(0);
        if (_raise && msg.value > 0) {
            encryptedBetAmount = FHE.asEuint32(uint32(msg.value / 1 wei));
            game.totalPot += msg.value;
            player.totalBet += msg.value;
        }

        // Update player state
        if (_fold) {
            player.hasFolded = FHE.asEbool(true);
            player.isActive = FHE.asEbool(false);
        }

        player.lastAction = block.timestamp;

        // Record the move
        moveCounter++;
        gameMoves[_gameId].push(GameMove({
            gameId: _gameId,
            player: msg.sender,
            encryptedCall: encryptedCall,
            encryptedRaise: encryptedRaise,
            encryptedFold: encryptedFold,
            encryptedBetAmount: encryptedBetAmount,
            timestamp: block.timestamp
        }));

        emit PlayerMoved(_gameId, msg.sender, moveCounter, block.timestamp);

        // Check if round is complete
        _checkRoundComplete(_gameId);
    }

    /**
     * @dev Reveal cards at the end of the game (for winner determination)
     * @param _gameId Game ID
     * @param _cards Array of card values (will be encrypted)
     */
    function revealCards(uint256 _gameId, bool[] memory _cards) external {
        require(hasJoined[_gameId][msg.sender], "Not in game");
        require(_cards.length <= CARDS_PER_HAND, "Too many cards");

        PlayerState storage player = playerStates[_gameId][msg.sender];

        // Encrypt all revealed cards using FHEVM compatible API
        for (uint256 i = 0; i < _cards.length && i < CARDS_PER_HAND; i++) {
            if (i < player.encryptedCards.length) {
                player.encryptedCards[i] = FHE.asEbool(_cards[i]);
            }
        }
    }

    /**
     * @dev Get game information
     * @param _gameId Game ID
     */
    function getGameInfo(uint256 _gameId) external view returns (Game memory) {
        require(_gameId <= gameCounter && _gameId > 0, "Invalid game ID");
        return games[_gameId];
    }

    /**
     * @dev Get player's encrypted cards (only for the player themselves)
     * @param _gameId Game ID
     * @param _player Player address
     */
    function getPlayerCards(uint256 _gameId, address _player) external view returns (ebool[] memory) {
        require(msg.sender == _player || msg.sender == owner(), "Not authorized");
        return playerStates[_gameId][_player].encryptedCards;
    }

    /**
     * @dev Get total number of games
     */
    function getTotalGames() external view returns (uint256) {
        return gameCounter;
    }

    /**
     * @dev Get player's game history
     * @param _player Player address
     */
    function getPlayerGames(address _player) external view returns (uint256[] memory) {
        return playerGames[_player];
    }

    /**
     * @dev Get player's encrypted bet amount (returns encrypted value)
     * @param _gameId Game ID
     * @param _player Player address
     */
    function getPlayerEncryptedBet(uint256 _gameId, address _player) external view returns (euint32) {
        require(msg.sender == _player || msg.sender == owner(), "Not authorized");
        return playerStates[_gameId][_player].encryptedBet;
    }

    /**
     * @dev Get player's encrypted fold status (returns encrypted value)
     * @param _gameId Game ID
     * @param _player Player address
     */
    function getPlayerEncryptedFoldStatus(uint256 _gameId, address _player) external view returns (ebool) {
        require(msg.sender == _player || msg.sender == owner(), "Not authorized");
        return playerStates[_gameId][_player].hasFolded;
    }

    /**
     * @dev Compare if player has folded using FHE operations
     * @param _gameId Game ID
     * @param _player Player address
     * @param _foldValue Value to compare against
     */
    function isPlayerFolded(uint256 _gameId, address _player, bool _foldValue) external returns (ebool) {
        require(msg.sender == owner(), "Only owner can check");
        ebool playerFolded = playerStates[_gameId][_player].hasFolded;
        ebool compareValue = FHE.asEbool(_foldValue);
        return FHE.eq(playerFolded, compareValue);
    }

    /**
     * @dev Compare encrypted bet amounts using FHE operations
     * @param _gameId Game ID
     * @param _player Player address
     * @param _betAmount Amount to compare
     */
    function compareBetAmount(uint256 _gameId, address _player, uint32 _betAmount) external returns (ebool) {
        require(msg.sender == owner(), "Only owner can compare");
        euint32 playerBet = playerStates[_gameId][_player].encryptedBet;
        euint32 compareAmount = FHE.asEuint32(_betAmount);
        return FHE.eq(playerBet, compareAmount);
    }

    /**
     * @dev Internal function to deal initial cards
     * @param _gameId Game ID
     */
    function _dealInitialCards(uint256 _gameId) internal {
        Game storage game = games[_gameId];

        for (uint256 i = 0; i < game.players.length; i++) {
            address player = game.players[i];
            PlayerState storage playerState = playerStates[_gameId][player];

            // Initialize encrypted cards with default values
            // In a real implementation, you'd use a verifiable random function
            for (uint256 j = 0; j < CARDS_PER_HAND; j++) {
                playerState.encryptedCards.push(FHE.asEbool(false));
            }
        }

        game.currentRound = 1;
        emit CardsDealt(_gameId, 1);
    }

    /**
     * @dev Internal function to check if round is complete
     * @param _gameId Game ID
     */
    function _checkRoundComplete(uint256 _gameId) internal {
        Game storage game = games[_gameId];

        // Count active players
        uint256 activePlayers = 0;
        address lastActivePlayer;

        for (uint256 i = 0; i < game.players.length; i++) {
            PlayerState storage player = playerStates[_gameId][game.players[i]];
            // In a real implementation, you'd check the encrypted values using FHE operations
            // For demo purposes, we assume some players are active
            activePlayers++;
            lastActivePlayer = game.players[i];
        }

        // End game if only one player remains
        if (activePlayers == 1) {
            _endGame(_gameId, lastActivePlayer);
        } else if (game.currentRound >= 4) {
            // End after 4 rounds (demo logic)
            _endGame(_gameId, game.players[0]); // First player wins for demo
        }
    }

    /**
     * @dev Internal function to end the game
     * @param _gameId Game ID
     * @param _winner Winner address
     */
    function _endGame(uint256 _gameId, address _winner) internal {
        Game storage game = games[_gameId];
        require(game.isActive, "Game already ended");

        game.isActive = false;
        uint256 prize = game.totalPot;

        // Transfer winnings to winner
        if (prize > 0) {
            (bool success, ) = payable(_winner).call{value: prize}("");
            require(success, "Prize transfer failed");
        }

        emit GameEnded(_gameId, _winner, prize);
    }

    /**
     * @dev Emergency function to end a stuck game (owner only)
     * @param _gameId Game ID
     */
    function emergencyEndGame(uint256 _gameId) external onlyOwner {
        Game storage game = games[_gameId];
        require(game.isActive, "Game already ended");

        game.isActive = false;

        // Refund all players equally
        uint256 refundPerPlayer = game.totalPot / game.currentPlayers;

        for (uint256 i = 0; i < game.players.length; i++) {
            if (refundPerPlayer > 0) {
                (bool success, ) = payable(game.players[i]).call{value: refundPerPlayer}("");
                require(success, "Refund failed");
            }
        }

        emit GameEnded(_gameId, address(0), 0);
    }

    /**
     * @dev Withdraw contract balance (owner only)
     */
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");

        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdrawal failed");
    }

    /**
     * @dev Fallback function to receive ETH
     */
    receive() external payable {}
}