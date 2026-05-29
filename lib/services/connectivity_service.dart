import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_nearby_connections/flutter_nearby_connections.dart';

enum PeerState {
  notConnected,
  connecting,
  connected
}

class AppPeer {
  final String id;
  final String name;
  final PeerState state;
  final bool isMock;

  AppPeer({
    required this.id,
    required this.name,
    required this.state,
    this.isMock = false,
  });

  AppPeer copyWith({
    String? id,
    String? name,
    PeerState? state,
    bool? isMock,
  }) {
    return AppPeer(
      id: id ?? this.id,
      name: name ?? this.name,
      state: state ?? this.state,
      isMock: isMock ?? this.isMock,
    );
  }
}

class ChatMessage {
  final String senderName;
  final String text;
  final DateTime timestamp;
  final bool isMe;

  ChatMessage({
    required this.senderName,
    required this.text,
    required this.timestamp,
    required this.isMe,
  });
}

enum AppConnectivityMode {
  real,
  simulated
}

class ConnectivityService extends ChangeNotifier {
  static const String _keyUsername = 'two_play_username';
  static const String _keyDarkMode = 'two_play_dark_mode';
  static const String _keyMode = 'two_play_conn_mode';

  String _myUsername = 'Player';
  bool _isDarkMode = true;
  AppConnectivityMode _mode = AppConnectivityMode.simulated;

  String get myUsername => _myUsername;
  bool get isDarkMode => _isDarkMode;
  AppConnectivityMode get mode => _mode;

  // Connection states
  bool _isAdvertising = false;
  bool _isScanning = false;
  List<AppPeer> _discoveredPeers = [];
  AppPeer? _connectedPeer;
  bool _isHost = false;

  bool get isAdvertising => _isAdvertising;
  bool get isScanning => _isScanning;
  List<AppPeer> get discoveredPeers => _discoveredPeers;
  AppPeer? get connectedPeer => _connectedPeer;
  bool get isConnected => _connectedPeer?.state == PeerState.connected;
  bool get isHost => _isHost;

  // Active game syncing
  String? _activeGameId;
  String? get activeGameId => _activeGameId;

  // Chat support
  final List<ChatMessage> _chatMessages = [];
  int _unreadChatCount = 0;

  List<ChatMessage> get chatMessages => _chatMessages;
  int get unreadChatCount => _unreadChatCount;

  void sendChatMessage(String text) {
    if (!isConnected) return;
    
    _chatMessages.add(ChatMessage(
      senderName: _myUsername,
      text: text,
      timestamp: DateTime.now(),
      isMe: true,
    ));
    notifyListeners();

    sendPayload({
      'type': 'chat_message',
      'senderName': _myUsername,
      'text': text,
    });
  }

  void clearUnreadChatCount() {
    _unreadChatCount = 0;
    notifyListeners();
  }

  // Streams for screens to listen to
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  // Real Mode Plugin References
  NearbyService? _nearbyService;
  StreamSubscription? _subscriptionState;
  StreamSubscription? _subscriptionData;
  bool _pluginInitialized = false;

  // Simulated Mode variables
  Timer? _simulationScanTimer;
  final List<String> _mockNames = ['AeroGamer', 'LiquidGlass_User', 'NeoRetro', 'QuantumPlay', 'CyberGlow'];
  final Random _random = Random();

  ConnectivityService() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _myUsername = prefs.getString(_keyUsername) ?? 'Player_${_random.nextInt(900) + 100}';
    _isDarkMode = prefs.getBool(_keyDarkMode) ?? true;
    final modeStr = prefs.getString(_keyMode);
    if (modeStr != null) {
      _mode = modeStr == 'real' ? AppConnectivityMode.real : AppConnectivityMode.simulated;
    }
    notifyListeners();
    
    if (_mode == AppConnectivityMode.real) {
      _initRealPlugin();
    }
  }

  Future<void> setUsername(String newName) async {
    _myUsername = newName;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUsername, newName);
    notifyListeners();
    
    // If advertising in real mode, restart with the new name
    if (_mode == AppConnectivityMode.real && _isAdvertising) {
      await stopAdvertising();
      await startAdvertising();
    }
  }

  Future<void> setDarkMode(bool value) async {
    _isDarkMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDarkMode, value);
    notifyListeners();
  }

  Future<void> setConnectivityMode(AppConnectivityMode selectedMode) async {
    // Clean up current state
    await disconnect();
    await stopScanning();
    await stopAdvertising();

    _mode = selectedMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMode, selectedMode == AppConnectivityMode.real ? 'real' : 'simulated');
    
    if (_mode == AppConnectivityMode.real) {
      await _initRealPlugin();
    } else {
      _closeRealPlugin();
    }
    notifyListeners();
  }

  // --- Core Actions ---

  Future<void> startAdvertising() async {
    if (_isAdvertising) return;
    _isAdvertising = true;
    _isHost = true;
    notifyListeners();

    if (_mode == AppConnectivityMode.real) {
      try {
        await _nearbyService?.startAdvertisingPeer();
      } catch (e) {
        debugPrint('Error starting advertising: $e');
      }
    } else {
      // Simulator: simulate incoming join requests occasionally
      _startSimulatedAdvertising();
    }
  }

  Future<void> stopAdvertising() async {
    if (!_isAdvertising) return;
    _isAdvertising = false;
    notifyListeners();

    if (_mode == AppConnectivityMode.real) {
      try {
        await _nearbyService?.stopAdvertisingPeer();
      } catch (e) {
        debugPrint('Error stopping advertising: $e');
      }
    }
  }

  Future<void> startScanning() async {
    if (_isScanning) return;
    _isScanning = true;
    _discoveredPeers = [];
    notifyListeners();

    if (_mode == AppConnectivityMode.real) {
      try {
        await _nearbyService?.startBrowsingForPeers();
      } catch (e) {
        debugPrint('Error starting scanning: $e');
      }
    } else {
      // Simulator scanning logic
      _simulationScanTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
        if (_discoveredPeers.length < 4) {
          final mockName = _mockNames[_random.nextInt(_mockNames.length)];
          final mockId = 'mock_${mockName.toLowerCase()}_${_random.nextInt(1000)}';
          if (!_discoveredPeers.any((p) => p.name == mockName)) {
            _discoveredPeers.add(AppPeer(
              id: mockId,
              name: mockName,
              state: PeerState.notConnected,
              isMock: true,
            ));
            notifyListeners();
          }
        } else {
          timer.cancel();
        }
      });
    }
  }

  Future<void> stopScanning() async {
    if (!_isScanning) return;
    _isScanning = false;
    _simulationScanTimer?.cancel();
    notifyListeners();

    if (_mode == AppConnectivityMode.real) {
      try {
        await _nearbyService?.stopBrowsingForPeers();
      } catch (e) {
        debugPrint('Error stopping scanning: $e');
      }
    }
  }

  Future<void> invitePeer(AppPeer peer) async {
    _isHost = false; // We joined/invited their lobby, so remote is host
    _updatePeerState(peer.id, PeerState.connecting);

    if (_mode == AppConnectivityMode.real) {
      try {
        await _nearbyService?.invitePeer(deviceID: peer.id, deviceName: peer.name);
      } catch (e) {
        debugPrint('Error inviting peer: $e');
        _updatePeerState(peer.id, PeerState.notConnected);
      }
    } else {
      // Simulated connection process
      Timer(const Duration(milliseconds: 1500), () {
        _connectedPeer = peer.copyWith(state: PeerState.connected);
        _updatePeerState(peer.id, PeerState.connected);
        stopScanning();
      });
    }
  }

  Future<void> acceptInvite(AppPeer peer) async {
    _isHost = true; // We created the lobby (advertised), so we are host
    _updatePeerState(peer.id, PeerState.connecting);

    if (_mode == AppConnectivityMode.real) {
      try {
        // Accept invitation is handled automatically or by inviting back in flutter_nearby_connections
        await _nearbyService?.invitePeer(deviceID: peer.id, deviceName: peer.name);
      } catch (e) {
        debugPrint('Error accepting invite: $e');
        _updatePeerState(peer.id, PeerState.notConnected);
      }
    } else {
      Timer(const Duration(milliseconds: 1000), () {
        _connectedPeer = peer.copyWith(state: PeerState.connected);
        _updatePeerState(peer.id, PeerState.connected);
        stopAdvertising();
      });
    }
  }

  Future<void> disconnect() async {
    if (_connectedPeer == null) return;
    final peerId = _connectedPeer!.id;

    if (_mode == AppConnectivityMode.real) {
      try {
        await _nearbyService?.disconnectPeer(deviceID: peerId);
      } catch (e) {
        debugPrint('Error disconnecting: $e');
      }
    }

    _connectedPeer = null;
    _activeGameId = null;
    _chatMessages.clear();
    _unreadChatCount = 0;
    _updatePeerState(peerId, PeerState.notConnected);
    notifyListeners();
  }

  void _updatePeerState(String id, PeerState state) {
    int index = _discoveredPeers.indexWhere((p) => p.id == id);
    if (index != -1) {
      _discoveredPeers[index] = _discoveredPeers[index].copyWith(state: state);
    }
    if (_connectedPeer != null && _connectedPeer!.id == id) {
      _connectedPeer = _connectedPeer!.copyWith(state: state);
    }
    notifyListeners();
  }

  // --- Game Selection Syncing ---

  void selectGame(String gameId) {
    _activeGameId = gameId;
    notifyListeners();
    sendPayload({
      'type': 'game_select',
      'gameId': gameId,
    });
  }

  void exitGame() {
    _activeGameId = null;
    notifyListeners();
    sendPayload({
      'type': 'game_exit',
    });
  }

  // --- Message / Payload Sending ---

  void sendPayload(Map<String, dynamic> payload) {
    if (!isConnected) return;
    final jsonStr = jsonEncode(payload);

    if (_mode == AppConnectivityMode.real) {
      _nearbyService?.sendMessage(connectedPeer!.id, jsonStr);
    } else {
      // Simulator: trigger AI response if it's a move payload
      _handleSimulatedMessage(payload);
    }
  }

  // --- Real Mode Setup ---

  Future<void> _initRealPlugin() async {
    if (_pluginInitialized) return;
    try {
      _nearbyService = NearbyService();
      await _nearbyService!.init(
        serviceType: 'mp-connection',
        deviceName: _myUsername,
        strategy: Strategy.P2P_CLUSTER,
        callback: (isRunning) async {
          debugPrint('NearbyService initialized: $isRunning');
        },
      );

      _subscriptionState = _nearbyService!.stateChangedSubscription(callback: (devicesList) {
        _discoveredPeers = devicesList.map((device) {
          PeerState state = PeerState.notConnected;
          if (device.state == SessionState.connected) {
            state = PeerState.connected;
          } else if (device.state == SessionState.connecting) {
            state = PeerState.connecting;
          }
          
          final appPeer = AppPeer(id: device.deviceId, name: device.deviceName, state: state);
          if (state == PeerState.connected) {
            _connectedPeer = appPeer;
            // The advertiser/browser logic maps who is host
            // If we were scanning, we invited, hence we are guest
            if (_isScanning) _isHost = false;
            // If we were advertising, they invited us, hence we are host
            if (_isAdvertising) _isHost = true;
          }
          return appPeer;
        }).toList();

        // Check if previously connected peer got disconnected
        if (_connectedPeer != null && !_discoveredPeers.any((p) => p.id == _connectedPeer!.id && p.state == PeerState.connected)) {
          _connectedPeer = null;
          _activeGameId = null;
        }

        notifyListeners();
      });

      _subscriptionData = _nearbyService!.dataReceivedSubscription(callback: (data) {
        // Data format on iOS: { 'id': deviceID, 'message': text }
        try {
          final rawMessage = data['message'] as String;
          final decoded = jsonDecode(rawMessage) as Map<String, dynamic>;
          _handleIncomingPayload(decoded);
        } catch (e) {
          debugPrint('Error parsing incoming message: $e \nData: $data');
        }
      });

      _pluginInitialized = true;
    } catch (e) {
      debugPrint('Failed to initialize Nearby Service: $e');
    }
  }

  void _closeRealPlugin() {
    _subscriptionState?.cancel();
    _subscriptionData?.cancel();
    _nearbyService = null;
    _pluginInitialized = false;
  }

  void _handleIncomingPayload(Map<String, dynamic> payload) {
    final type = payload['type'] as String?;
    if (type == 'game_select') {
      _activeGameId = payload['gameId'] as String?;
      notifyListeners();
    } else if (type == 'game_exit') {
      _activeGameId = null;
      notifyListeners();
    } else if (type == 'chat_message') {
      final senderName = payload['senderName'] as String? ?? 'Gegner';
      final text = payload['text'] as String? ?? '';
      _chatMessages.add(ChatMessage(
        senderName: senderName,
        text: text,
        timestamp: DateTime.now(),
        isMe: false,
      ));
      _unreadChatCount++;
      notifyListeners();
    }
    
    // Pass downstream to active game screens
    _messageController.add(payload);
  }

  // --- Simulated Mode AI & Logic ---

  void _startSimulatedAdvertising() {
    // Generate a simulated invite after 3-5 seconds
    Timer(Duration(seconds: _random.nextInt(3) + 3), () {
      if (!_isAdvertising || isConnected) return;
      final mockName = _mockNames[_random.nextInt(_mockNames.length)];
      final mockId = 'mock_${mockName.toLowerCase()}_${_random.nextInt(1000)}';
      
      final mockPeer = AppPeer(
        id: mockId,
        name: mockName,
        state: PeerState.connecting,
        isMock: true,
      );

      _discoveredPeers = [mockPeer];
      notifyListeners();

      // Dispatch request to screen
      _messageController.add({
        'type': 'simulated_invite_request',
        'peer': {
          'id': mockId,
          'name': mockName,
        }
      });
    });
  }

  void _handleSimulatedMessage(Map<String, dynamic> payload) {
    final type = payload['type'] as String?;
    if (type == 'game_select') {
      // Echo it back locally
      _handleIncomingPayload(payload);
    } else if (type == 'game_exit') {
      _handleIncomingPayload(payload);
    } else if (type == 'game_move') {
      // Simulate opponent thinking
      Timer(Duration(milliseconds: 700 + _random.nextInt(500)), () {
        if (!isConnected) return;
        final response = _generateAIResponse(payload);
        if (response != null) {
          _handleIncomingPayload(response);
        }
      });
    } else if (type == 'game_reset') {
      // Opponent automatically accepts game resets
      Timer(const Duration(milliseconds: 500), () {
        _handleIncomingPayload({
          'type': 'game_reset_accept',
          'gameId': payload['gameId'],
        });
      });
    } else if (type == 'chat_message') {
      // Simulate opponent typing and replying after 1-2 seconds
      Timer(Duration(seconds: 1 + _random.nextInt(2)), () {
        if (!isConnected) return;
        final aiReplies = [
          'Gutes Spiel!',
          'Huch, das war knapp!',
          'Haha, nett versucht!',
          'Bereit für die nächste Runde?',
          'Schöne Grüße!',
          'Wow, du spielst echt gut!',
          'Kannst du das noch mal machen?',
          'Gleich habe ich dich!',
          'Ein toller Tag für 2Play!',
          'Spielen wir danach noch was anderes?',
        ];
        final replyText = aiReplies[_random.nextInt(aiReplies.length)];
        
        final replyPayload = {
          'type': 'chat_message',
          'senderName': connectedPeer?.name ?? 'Gegner',
          'text': replyText,
        };
        _handleIncomingPayload(replyPayload);
      });
    }
  }

  Map<String, dynamic>? _generateAIResponse(Map<String, dynamic> userMove) {
    final gameId = userMove['gameId'] as String?;
    final userMoveData = userMove['data'] as Map<String, dynamic>?;

    if (gameId == 'tictactoe' && userMoveData != null) {
      final board = List<String>.from(userMoveData['board']);
      final aiSymbol = userMoveData['playerSymbol'] == 'X' ? 'O' : 'X';
      
      // Smart Tic-Tac-Toe Move
      int bestMove = -1;
      
      // 1. Can AI Win?
      bestMove = _findTicTacToeWinningMove(board, aiSymbol);
      // 2. Can Player Win? Block it.
      if (bestMove == -1) {
        bestMove = _findTicTacToeWinningMove(board, userMoveData['playerSymbol']);
      }
      // 3. Take Center
      if (bestMove == -1 && board[4].isEmpty) {
        bestMove = 4;
      }
      // 4. Take random empty cell
      if (bestMove == -1) {
        final emptyCells = <int>[];
        for (int i = 0; i < 9; i++) {
          if (board[i].isEmpty) emptyCells.add(i);
        }
        if (emptyCells.isNotEmpty) {
          bestMove = emptyCells[_random.nextInt(emptyCells.length)];
        }
      }

      if (bestMove != -1) {
        board[bestMove] = aiSymbol;
        return {
          'type': 'game_move',
          'gameId': 'tictactoe',
          'data': {
            'board': board,
            'lastMoveIndex': bestMove,
            'nextTurn': userMoveData['playerSymbol'],
          }
        };
      }
    } else if (gameId == 'connect4' && userMoveData != null) {
      final board = List<List<int>>.from(
        (userMoveData['board'] as List).map((col) => List<int>.from(col))
      );
      // User is 1, AI is 2
      final userPlayer = 1;
      final aiPlayer = 2;

      // Smart Column picker
      int bestCol = -1;

      // Check if AI can win in 1 move
      for (int c = 0; c < 7; c++) {
        if (_canPlayColumn(board, c)) {
          final tempBoard = _simulatePlay(board, c, aiPlayer);
          if (_checkConnect4Win(tempBoard, aiPlayer)) {
            bestCol = c;
            break;
          }
        }
      }

      // Check if Player can win in 1 move, block them
      if (bestCol == -1) {
        for (int c = 0; c < 7; c++) {
          if (_canPlayColumn(board, c)) {
            final tempBoard = _simulatePlay(board, c, userPlayer);
            if (_checkConnect4Win(tempBoard, userPlayer)) {
              bestCol = c;
              break;
            }
          }
        }
      }

      // Take middle columns preferred
      if (bestCol == -1) {
        final preferences = [3, 2, 4, 1, 5, 0, 6];
        for (int c in preferences) {
          if (_canPlayColumn(board, c)) {
            bestCol = c;
            break;
          }
        }
      }

      if (bestCol != -1) {
        // Perform move
        int rowPlayed = -1;
        for (int r = 5; r >= 0; r--) {
          if (board[bestCol][r] == 0) {
            board[bestCol][r] = aiPlayer;
            rowPlayed = r;
            break;
          }
        }
        return {
          'type': 'game_move',
          'gameId': 'connect4',
          'data': {
            'board': board,
            'playedCol': bestCol,
            'playedRow': rowPlayed,
            'nextTurn': userPlayer,
          }
        };
      }
    } else if (gameId == 'battleship' && userMoveData != null) {
      // Battleship flow is split into setup and game turns
      final subtype = userMoveData['subtype'] as String?;
      if (subtype == 'player_ready') {
        // AI is immediately ready with their own randomized board
        final aiBoard = _generateRandomBattleshipBoard();
        return {
          'type': 'game_move',
          'gameId': 'battleship',
          'data': {
            'subtype': 'ai_ready',
            'aiBoard': aiBoard,
          }
        };
      } else if (subtype == 'fire') {
        // Receive fire response, then generate AI's shot
        // AI generates shot at User Board
        final userFleet = List<List<int>>.from(
          (userMoveData['userBoard'] as List).map((row) => List<int>.from(row))
        );
        
        // Simple Battleship AI: target hits or random shots
        int targetX = -1;
        int targetY = -1;

        // Hunt mode: search user board for hits (value 2 = Hit) and fire adjacent
        bool foundHunt = false;
        for (int r = 0; r < 10; r++) {
          for (int c = 0; c < 10; c++) {
            if (userFleet[r][c] == 2) { // Hit ship
              // Look around
              final adjacents = [[r-1, c], [r+1, c], [r, c-1], [r, c+1]];
              for (var adj in adjacents) {
                int ar = adj[0];
                int ac = adj[1];
                if (ar >= 0 && ar < 10 && ac >= 0 && ac < 10) {
                  if (userFleet[ar][ac] == 0 || userFleet[ar][ac] == 1) { // Untargeted empty or ship
                    targetX = ac;
                    targetY = ar;
                    foundHunt = true;
                    break;
                  }
                }
              }
            }
            if (foundHunt) break;
          }
          if (foundHunt) break;
        }

        // Random mode
        if (targetX == -1) {
          final potentials = <Point>[];
          for (int r = 0; r < 10; r++) {
            for (int c = 0; c < 10; c++) {
              if (userFleet[r][c] == 0 || userFleet[r][c] == 1) { // Empty or unhit ship
                potentials.add(Point(c, r));
              }
            }
          }
          if (potentials.isNotEmpty) {
            final pt = potentials[_random.nextInt(potentials.length)];
            targetX = pt.x.toInt();
            targetY = pt.y.toInt();
          }
        }

        if (targetX != -1) {
          // Process shot results: userFleet[targetY][targetX] == 1 -> Hit (value 2), else Miss (value 3)
          final isHit = userFleet[targetY][targetX] == 1;
          userFleet[targetY][targetX] = isHit ? 2 : 3;

          return {
            'type': 'game_move',
            'gameId': 'battleship',
            'data': {
              'subtype': 'ai_fire',
              'targetX': targetX,
              'targetY': targetY,
              'isHit': isHit,
              'userBoard': userFleet,
            }
          };
        }
      }
    } else if (gameId == 'rockpaperscissors' && userMoveData != null) {
      // User locked choice. AI reveals choice.
      final choices = ['rock', 'paper', 'scissors'];
      final aiChoice = choices[_random.nextInt(3)];
      return {
        'type': 'game_move',
        'gameId': 'rockpaperscissors',
        'data': {
          'aiChoice': aiChoice,
          'userChoice': userMoveData['userChoice'],
        }
      };
    }
    return null;
  }

  // --- Helper calculations for Game AI ---

  int _findTicTacToeWinningMove(List<String> board, String symbol) {
    const lines = [
      [0, 1, 2], [3, 4, 5], [6, 7, 8], // Rows
      [0, 3, 6], [1, 4, 7], [2, 5, 8], // Cols
      [0, 4, 8], [2, 4, 6]             // Diag
    ];
    for (var line in lines) {
      int count = 0;
      int emptyIndex = -1;
      for (int index in line) {
        if (board[index] == symbol) {
          count++;
        } else if (board[index].isEmpty) {
          emptyIndex = index;
        }
      }
      if (count == 2 && emptyIndex != -1) {
        return emptyIndex;
      }
    }
    return -1;
  }

  bool _canPlayColumn(List<List<int>> board, int col) {
    return board[col][0] == 0;
  }

  List<List<int>> _simulatePlay(List<List<int>> original, int col, int player) {
    final copy = List<List<int>>.from(original.map((c) => List<int>.from(c)));
    for (int r = 5; r >= 0; r--) {
      if (copy[col][r] == 0) {
        copy[col][r] = player;
        break;
      }
    }
    return copy;
  }

  bool _checkConnect4Win(List<List<int>> board, int player) {
    // Horizontal
    for (int r = 0; r < 6; r++) {
      for (int c = 0; c < 4; c++) {
        if (board[c][r] == player && board[c+1][r] == player && board[c+2][r] == player && board[c+3][r] == player) {
          return true;
        }
      }
    }
    // Vertical
    for (int c = 0; c < 7; c++) {
      for (int r = 0; r < 3; r++) {
        if (board[c][r] == player && board[c][r+1] == player && board[c][r+2] == player && board[c][r+3] == player) {
          return true;
        }
      }
    }
    // Positive diagonal
    for (int c = 0; c < 4; c++) {
      for (int r = 3; r < 6; r++) {
        if (board[c][r] == player && board[c+1][r-1] == player && board[c+2][r-2] == player && board[c+3][r-3] == player) {
          return true;
        }
      }
    }
    // Negative diagonal
    for (int c = 0; c < 4; c++) {
      for (int r = 0; r < 3; r++) {
        if (board[c][r] == player && board[c+1][r+1] == player && board[c+2][r+2] == player && board[c+3][r+3] == player) {
          return true;
        }
      }
    }
    return false;
  }

  List<List<int>> _generateRandomBattleshipBoard() {
    final board = List.generate(10, (_) => List.generate(10, (_) => 0));
    final shipSizes = [5, 4, 3, 3, 2];

    for (int size in shipSizes) {
      bool placed = false;
      while (!placed) {
        final isHorizontal = _random.nextBool();
        final x = _random.nextInt(10);
        final y = _random.nextInt(10);

        if (isHorizontal) {
          if (x + size <= 10) {
            bool overlap = false;
            for (int i = 0; i < size; i++) {
              if (board[y][x + i] != 0) overlap = true;
            }
            if (!overlap) {
              for (int i = 0; i < size; i++) {
                board[y][x + i] = 1;
              }
              placed = true;
            }
          }
        } else {
          if (y + size <= 10) {
            bool overlap = false;
            for (int i = 0; i < size; i++) {
              if (board[y + i][x] != 0) overlap = true;
            }
            if (!overlap) {
              for (int i = 0; i < size; i++) {
                board[y + i][x] = 1;
              }
              placed = true;
            }
          }
        }
      }
    }
    return board;
  }
}
