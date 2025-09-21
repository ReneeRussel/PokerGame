// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PokerGameSimple
 * @dev Simplified Poker Game for standard EVM networks
 * @notice This version uses standard types instead of FHE for compatibility
 */
contract PokerGameSimple is ReentrancyGuard, Ownable {

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
        bool[] cards; // Simplified cards (public for now)
        bool isActive;
        uint256 betAmount;
        bool hasFolded;
        uint256 totalBet;
        uint256 lastAction;
    }

    struct GameMove {
        uint256 gameId;
        address player;
        bool call;
        bool raise;
        bool fold;
        uint256 betAmount;
        uint256 timestamp;
    }

    // State variables
    mapping(uint256 => Game) public games;
    mapping(uint256 => mapping(address => PlayerState)) public playerStates;
    mapping(uint256 => GameMove[]) public gameMoves;
    mapping(address => uint256[]) public playerGames;
    mapping(uint256 => mapping(address => bool)) public hasJoined;

    // Game constants
    uint256 public constant MAX_PLAYERS = 8;
    uint256 public constant MIN_BET = 0.01 ether;
    uint256 public constant CARDS_PER_HAND = 5;

    // Counters
    uint256 public gameCounter;
    uint256 public moveCounter;

    // Events
    event GameCreated(uint256 indexed gameId, uint8 gameType, uint256 maxPlayers, uint256 minBet);
    event PlayerJoined(uint256 indexed gameId, address indexed player, uint256 totalPlayers);
    event GameStarted(uint256 indexed gameId, address[] players, uint256 totalPot);
    event PlayerMoved(uint256 indexed gameId, address indexed player, uint256 moveId, uint256 timestamp);
    event GameEnded(uint256 indexed gameId, address indexed winner, uint256 prize);

    constructor() Ownable(msg.sender) {
        gameCounter = 0;
        moveCounter = 0;
    }

    /**
     * @dev Create a new poker game
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
     * @dev Join an existing game
     */
    function joinGame(uint256 _gameId, bool _wantsToJoin) external payable nonReentrant {
        require(games[_gameId].isActive, "Game not active");
        require(!games[_gameId].hasStarted, "Game already started");
        require(games[_gameId].currentPlayers < games[_gameId].maxPlayers, "Game full");
        require(!hasJoined[_gameId][msg.sender], "Already joined");
        require(msg.value >= games[_gameId].minBet, "Insufficient bet amount");
        require(_wantsToJoin, "Player must want to join");

        Game storage game = games[_gameId];

        // Add player to game
        game.players.push(msg.sender);
        game.currentPlayers++;
        game.totalPot += msg.value;
        hasJoined[_gameId][msg.sender] = true;

        // Initialize player state with simplified data
        playerStates[_gameId][msg.sender] = PlayerState({
            player: msg.sender,
            gameId: _gameId,
            cards: new bool[](CARDS_PER_HAND),
            isActive: true,
            betAmount: msg.value,
            hasFolded: false,
            totalBet: msg.value,
            lastAction: block.timestamp
        });

        // Add to player's game list
        playerGames[msg.sender].push(_gameId);

        emit PlayerJoined(_gameId, msg.sender, game.currentPlayers);

        // Start game if full
        if (game.currentPlayers == game.maxPlayers) {
            game.hasStarted = true;
            game.currentRound = 1;
            _dealCards(_gameId);
            emit GameStarted(_gameId, game.players, game.totalPot);
        }
    }

    /**
     * @dev Make a move in the game
     */
    function makeMove(uint256 _gameId, bool _call, bool _raise, bool _fold) external payable nonReentrant {
        require(games[_gameId].isActive, "Game not active");
        require(games[_gameId].hasStarted, "Game not started");
        require(hasJoined[_gameId][msg.sender], "Not in game");

        Game storage game = games[_gameId];
        PlayerState storage player = playerStates[_gameId][msg.sender];
        require(!player.hasFolded, "Player has folded");

        moveCounter++;

        // Handle bet amount if raising
        uint256 betAmount = 0;
        if (_raise && msg.value > 0) {
            betAmount = msg.value;
            game.totalPot += msg.value;
            player.totalBet += msg.value;
        }

        // Update player state
        if (_fold) {
            player.hasFolded = true;
            player.isActive = false;
        }

        player.lastAction = block.timestamp;

        // Record the move
        gameMoves[_gameId].push(GameMove({
            gameId: _gameId,
            player: msg.sender,
            call: _call,
            raise: _raise,
            fold: _fold,
            betAmount: betAmount,
            timestamp: block.timestamp
        }));

        emit PlayerMoved(_gameId, msg.sender, moveCounter, block.timestamp);

        // Check if round/game should end
        _checkGameEnd(_gameId);
    }

    /**
     * @dev Reveal cards (simplified - no encryption)
     */
    function revealCards(uint256 _gameId, bool[] memory _cards) external {
        require(games[_gameId].isActive, "Game not active");
        require(hasJoined[_gameId][msg.sender], "Not in game");
        require(_cards.length <= CARDS_PER_HAND, "Too many cards");

        PlayerState storage player = playerStates[_gameId][msg.sender];

        // Update player cards
        for (uint256 i = 0; i < _cards.length && i < CARDS_PER_HAND; i++) {
            if (i < player.cards.length) {
                player.cards[i] = _cards[i];
            }
        }
    }

    /**
     * @dev Deal cards to all players in a game (simplified)
     */
    function _dealCards(uint256 _gameId) internal {
        Game storage game = games[_gameId];

        for (uint256 i = 0; i < game.players.length; i++) {
            PlayerState storage playerState = playerStates[_gameId][game.players[i]];

            // In a real implementation, you'd use a verifiable random function
            for (uint256 j = 0; j < CARDS_PER_HAND; j++) {
                playerState.cards.push(false); // Simplified card representation
            }
        }
    }

    /**
     * @dev Check if game should end
     */
    function _checkGameEnd(uint256 _gameId) internal {
        Game storage game = games[_gameId];
        uint256 activePlayers = 0;
        address lastActivePlayer;

        for (uint256 i = 0; i < game.players.length; i++) {
            if (!playerStates[_gameId][game.players[i]].hasFolded) {
                activePlayers++;
                lastActivePlayer = game.players[i];
            }
        }

        // End game if only one player left
        if (activePlayers <= 1) {
            game.isActive = false;
            if (activePlayers == 1) {
                // Transfer pot to winner
                payable(lastActivePlayer).transfer(game.totalPot);
                emit GameEnded(_gameId, lastActivePlayer, game.totalPot);
            }
        }
    }

    // View functions
    function getGameInfo(uint256 _gameId) external view returns (
        uint256 gameId,
        uint256 maxPlayers,
        uint256 currentPlayers,
        uint256 totalPot,
        uint256 minBet,
        uint8 gameType,
        bool isActive,
        bool hasStarted,
        address[] memory players,
        uint256 currentRound,
        uint256 timestamp
    ) {
        Game storage game = games[_gameId];
        return (
            game.gameId,
            game.maxPlayers,
            game.currentPlayers,
            game.totalPot,
            game.minBet,
            game.gameType,
            game.isActive,
            game.hasStarted,
            game.players,
            game.currentRound,
            game.timestamp
        );
    }

    function getPlayerCards(uint256 _gameId, address _player) external view returns (bool[] memory) {
        return playerStates[_gameId][_player].cards;
    }

    function getTotalGames() external view returns (uint256) {
        return gameCounter;
    }

    function getPlayerGames(address _player) external view returns (uint256[] memory) {
        return playerGames[_player];
    }
}