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

class ConnectivityService extends ChangeNotifier with WidgetsBindingObserver {
  static const String _keyUsername = 'two_play_username';
  static const String _keyDarkMode = 'two_play_dark_mode';
  static const String _keyMode = 'two_play_conn_mode';
  static const String _keyKnownPlayers = 'two_play_known_players';
  static const String _keyBotDifficulty = 'two_play_bot_difficulty';
  static const String _keyGameStats = 'two_play_game_stats';
  static const String _keyPlayTime = 'two_play_play_time';

  String _myUsername = 'Player';
  bool _isDarkMode = true;
  AppConnectivityMode _mode = AppConnectivityMode.real; // Default to real P2P

  String get myUsername => _myUsername;
  bool get isDarkMode => _isDarkMode;
  AppConnectivityMode get mode => _mode;

  // Bot difficulty
  String _botDifficulty = 'mittel';
  String get botDifficulty => _botDifficulty;

  // Blocked players (ID -> Unblock Time)
  final Map<String, DateTime> _blockedPlayers = {};
  Map<String, DateTime> get blockedPlayers => _blockedPlayers;

  // Connection states
  bool _isAdvertising = false;
  bool _isScanning = false;
  List<AppPeer> _discoveredPeers = [];
  AppPeer? _connectedPeer;
  bool _isHost = false;
  bool _showMockBots = false;
  Timer? _botTimer;

  bool get isAdvertising => _isAdvertising;
  bool get isScanning => _isScanning;
  
  // Filter out blocked players and format Bot difficulty labels
  List<AppPeer> get discoveredPeers {
    final now = DateTime.now();
    final filtered = _discoveredPeers.where((peer) {
      if (_blockedPlayers.containsKey(peer.id)) {
        final unblockTime = _blockedPlayers[peer.id]!;
        if (now.isBefore(unblockTime)) {
          return false; // Blocked!
        }
      }
      return true;
    }).toList();

    final realPeers = filtered.where((p) => !p.isMock).toList();
    final mockPeers = filtered.where((p) => p.isMock).toList();

    List<AppPeer> listToReturn;
    if (realPeers.isNotEmpty) {
      listToReturn = realPeers;
    } else if (_showMockBots) {
      listToReturn = mockPeers.isNotEmpty ? mockPeers : _getMockBotsList();
    } else {
      listToReturn = [];
    }

    return listToReturn.map((peer) {
      if (peer.isMock) {
        String difficultyLabel = 'Mittel';
        if (_botDifficulty == 'einfach') difficultyLabel = 'Einfach';
        if (_botDifficulty == 'schwer') difficultyLabel = 'Schwer';
        
        final cleanName = peer.name.split(' [')[0];
        return peer.copyWith(name: '$cleanName [$difficultyLabel]');
      }
      return peer;
    }).toList();
  }

  List<AppPeer> _getMockBotsList() {
    return [
      AppPeer(id: 'mock_bot_einfach', name: 'Bot AeroGamer', state: PeerState.notConnected, isMock: true),
      AppPeer(id: 'mock_bot_mittel', name: 'Bot QuantumPlay', state: PeerState.notConnected, isMock: true),
      AppPeer(id: 'mock_bot_schwer', name: 'Bot CyberGlow', state: PeerState.notConnected, isMock: true),
    ];
  }

  AppPeer? get connectedPeer => _connectedPeer;
  bool get isConnected => _connectedPeer?.state == PeerState.connected;
  bool get isHost => _isHost;

  // Verification PIN handshake state
  bool _isVerifying = false;
  int? _verificationPin;
  bool _pinError = false;
  String? _pinErrorMessage;

  bool get isVerifying => _isVerifying;
  int? get verificationPin => _verificationPin;
  bool get pinError => _pinError;
  String? get pinErrorMessage => _pinErrorMessage;

  // Statistics
  Map<String, Map<String, int>> _gameStats = {};
  int _totalPlayTimeSeconds = 0;
  DateTime? _gameStartTime;

  Map<String, Map<String, int>> get gameStats => _gameStats;
  int get totalPlayTimeSeconds => _totalPlayTimeSeconds;

  String get favoriteGame {
    String bestGame = 'Keines';
    int maxPlays = -1;
    final gameNames = {
      'tictactoe': 'Tic-Tac-Toe',
      'connect4': 'Vier Gewinnt',
      'battleship': 'Schiffe Versenken',
      'rockpaperscissors': 'Schere, Stein, Papier',
      'minigolf': 'Minigolf',
    };
    
    _gameStats.forEach((gameId, stats) {
      final plays = stats['play_count'] ?? 0;
      if (plays > maxPlays && plays > 0) {
        maxPlays = plays;
        bestGame = gameNames[gameId] ?? gameId;
      }
    });
    return bestGame;
  }

  // Active game syncing
  String? _activeGameId;
  String? get activeGameId => _activeGameId;

  // Game Suggestion syncing
  String? _suggestedGameId;
  String? get suggestedGameId => _suggestedGameId;

  // Known players
  List<Map<String, String>> _knownPlayers = [];
  List<Map<String, String>> get knownPlayers => _knownPlayers;

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
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (isConnected) {
        sendPayload({
          'type': 'game_exit',
        });
      }
      disconnect();
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _myUsername = prefs.getString(_keyUsername) ?? 'Player_${_random.nextInt(900) + 100}';
    _isDarkMode = prefs.getBool(_keyDarkMode) ?? true;
    _mode = AppConnectivityMode.real; // Always real by default, we are P2P first

    _botDifficulty = prefs.getString(_keyBotDifficulty) ?? 'mittel';
    _totalPlayTimeSeconds = prefs.getInt(_keyPlayTime) ?? 0;
    
    // Load game stats
    final statsJson = prefs.getString(_keyGameStats);
    if (statsJson != null) {
      try {
        final decoded = jsonDecode(statsJson) as Map<String, dynamic>;
        _gameStats = decoded.map((key, value) {
          final gameMap = Map<String, int>.from(value as Map);
          return MapEntry(key, gameMap);
        });
      } catch (e) {
        debugPrint('Error decoding stats: $e');
        _initDefaultStats();
      }
    } else {
      _initDefaultStats();
    }
    
    // Load known players
    final knownJson = prefs.getString(_keyKnownPlayers);
    if (knownJson != null) {
      try {
        final decoded = jsonDecode(knownJson) as List;
        _knownPlayers = decoded.map((item) => Map<String, String>.from(item)).toList();
      } catch (e) {
        debugPrint('Error decoding known players: $e');
      }
    }

    _loadBlockedPlayers(prefs);
    
    notifyListeners();
    
    _initRealPlugin();
  }

  void _initDefaultStats() {
    _gameStats = {
      'tictactoe': {'wins_vs_bot': 0, 'losses_vs_bot': 0, 'wins_vs_player': 0, 'losses_vs_player': 0, 'play_count': 0},
      'connect4': {'wins_vs_bot': 0, 'losses_vs_bot': 0, 'wins_vs_player': 0, 'losses_vs_player': 0, 'play_count': 0},
      'battleship': {'wins_vs_bot': 0, 'losses_vs_bot': 0, 'wins_vs_player': 0, 'losses_vs_player': 0, 'play_count': 0},
      'rockpaperscissors': {'wins_vs_bot': 0, 'losses_vs_bot': 0, 'wins_vs_player': 0, 'losses_vs_player': 0, 'play_count': 0},
      'minigolf': {'wins_vs_bot': 0, 'losses_vs_bot': 0, 'wins_vs_player': 0, 'losses_vs_player': 0, 'play_count': 0},
    };
  }

  Future<void> _saveStats() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGameStats, jsonEncode(_gameStats));
  }

  Future<void> _savePlayTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyPlayTime, _totalPlayTimeSeconds);
  }

  Future<void> _saveBotDifficulty() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBotDifficulty, _botDifficulty);
  }

  void incrementWin(String gameId) {
    final vsBot = _connectedPeer?.isMock ?? true;
    final statKey = vsBot ? 'wins_vs_bot' : 'wins_vs_player';
    
    if (_gameStats.isEmpty || !_gameStats.containsKey(gameId)) {
      _initDefaultStats();
    }
    
    _gameStats[gameId]![statKey] = (_gameStats[gameId]![statKey] ?? 0) + 1;
    _gameStats[gameId]!['play_count'] = (_gameStats[gameId]!['play_count'] ?? 0) + 1;
    _saveStats();
    notifyListeners();
  }

  void incrementLoss(String gameId) {
    final vsBot = _connectedPeer?.isMock ?? true;
    final statKey = vsBot ? 'losses_vs_bot' : 'losses_vs_player';
    
    if (_gameStats.isEmpty || !_gameStats.containsKey(gameId)) {
      _initDefaultStats();
    }
    
    _gameStats[gameId]![statKey] = (_gameStats[gameId]![statKey] ?? 0) + 1;
    _gameStats[gameId]!['play_count'] = (_gameStats[gameId]!['play_count'] ?? 0) + 1;
    _saveStats();
    notifyListeners();
  }

  void _loadBlockedPlayers(SharedPreferences prefs) {
    final jsonStr = prefs.getString('two_play_blocked_players');
    if (jsonStr != null) {
      try {
        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        decoded.forEach((key, value) {
          final time = DateTime.parse(value as String);
          if (time.isAfter(DateTime.now())) {
            _blockedPlayers[key] = time;
          }
        });
      } catch (e) {
        debugPrint('Error loading blocked players: $e');
      }
    }
  }

  Future<void> _saveBlockedPlayers() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _blockedPlayers.map((key, value) => MapEntry(key, value.toIso8601String()));
    await prefs.setString('two_play_blocked_players', jsonEncode(data));
  }

  Future<void> setBotDifficulty(String difficulty) async {
    if (difficulty == 'einfach' || difficulty == 'mittel' || difficulty == 'schwer') {
      _botDifficulty = difficulty;
      await _saveBotDifficulty();
      notifyListeners();
    }
  }

  Future<void> _registerConnectedPlayer(AppPeer peer) async {
    if (peer.isMock) return;
    final prefs = await SharedPreferences.getInstance();
    final existingIndex = _knownPlayers.indexWhere((p) => p['id'] == peer.id);
    
    if (existingIndex != -1) {
      _knownPlayers.removeAt(existingIndex);
    }
    
    _knownPlayers.insert(0, {
      'id': peer.id,
      'name': peer.name,
      'isMock': peer.isMock ? 'true' : 'false',
    });
    
    if (_knownPlayers.length > 5) {
      _knownPlayers = _knownPlayers.sublist(0, 5);
    }
    
    await prefs.setString(_keyKnownPlayers, jsonEncode(_knownPlayers));
    notifyListeners();
  }

  Future<void> clearKnownPlayers() async {
    final prefs = await SharedPreferences.getInstance();
    _knownPlayers.clear();
    await prefs.remove(_keyKnownPlayers);
    notifyListeners();
  }

  Future<void> setUsername(String newName) async {
    _myUsername = newName;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUsername, newName);
    notifyListeners();
    
    if (_isAdvertising) {
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
    // Kept for backward compatibility but always keep real P2P behavior internally
    notifyListeners();
  }

  bool _isKnownPlayer(String id) {
    return _knownPlayers.any((p) => p['id'] == id);
  }

  void _initiateHandshake() {
    if (_connectedPeer == null || _connectedPeer!.isMock) return;
    
    _isVerifying = false;
    _verificationPin = null;
    _pinError = false;
    _pinErrorMessage = null;
    
    sendPayload({
      'type': 'handshake',
      'username': _myUsername,
      'isKnown': _isKnownPlayer(_connectedPeer!.id),
    });
  }

  void verifyCode(int pin) {
    if (isHost) {
      if (pin == _verificationPin) {
        _isVerifying = false;
        _registerConnectedPlayer(_connectedPeer!);
        sendPayload({'type': 'pin_success'});
        notifyListeners();
      } else {
        _pinError = true;
        _pinErrorMessage = 'Falscher PIN. Bitte erneut versuchen.';
        notifyListeners();
      }
    } else {
      sendPayload({
        'type': 'pin_submit',
        'pin': pin,
      });
    }
  }

  void clearPinError() {
    _pinError = false;
    _pinErrorMessage = null;
    notifyListeners();
  }

  void blockPlayer(String id) {
    _blockedPlayers[id] = DateTime.now().add(const Duration(minutes: 10));
    _saveBlockedPlayers();
    notifyListeners();
    
    if (_connectedPeer != null && _connectedPeer!.id == id) {
      disconnect();
    }
  }

  // --- Core Actions ---

  Timer? _advertiserBotTimer;

  Future<void> startAdvertising() async {
    if (_isAdvertising) return;
    _isAdvertising = true;
    _isHost = true;
    notifyListeners();

    try {
      await _nearbyService?.startAdvertisingPeer();
    } catch (e) {
      debugPrint('Error starting advertising: $e');
    }

    _advertiserBotTimer?.cancel();
    _advertiserBotTimer = Timer(const Duration(seconds: 5), () {
      if (_isAdvertising && !isConnected) {
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

        _messageController.add({
          'type': 'simulated_invite_request',
          'peer': {
            'id': mockId,
            'name': mockName,
          }
        });
      }
    });
  }

  Future<void> stopAdvertising() async {
    if (!_isAdvertising) return;
    _isAdvertising = false;
    _advertiserBotTimer?.cancel();
    notifyListeners();

    try {
      await _nearbyService?.stopAdvertisingPeer();
    } catch (e) {
      debugPrint('Error stopping advertising: $e');
    }
  }

  Future<void> startScanning() async {
    if (_isScanning) return;
    _isScanning = true;
    _discoveredPeers = [];
    _showMockBots = false;
    notifyListeners();

    _botTimer?.cancel();
    _botTimer = Timer(const Duration(seconds: 4), () {
      if (_discoveredPeers.isEmpty && _isScanning) {
        _showMockBots = true;
        notifyListeners();
      }
    });

    try {
      await _nearbyService?.startBrowsingForPeers();
    } catch (e) {
      debugPrint('Error starting scanning: $e');
    }
  }

  Future<void> stopScanning() async {
    if (!_isScanning) return;
    _isScanning = false;
    _botTimer?.cancel();
    _simulationScanTimer?.cancel();
    notifyListeners();

    try {
      await _nearbyService?.stopBrowsingForPeers();
    } catch (e) {
      debugPrint('Error stopping scanning: $e');
    }
  }

  Future<void> invitePeer(AppPeer peer) async {
    _isHost = false;
    _updatePeerState(peer.id, PeerState.connecting);

    if (peer.isMock) {
      if (peer.id == 'mock_bot_einfach') {
        _botDifficulty = 'einfach';
      } else if (peer.id == 'mock_bot_mittel') {
        _botDifficulty = 'mittel';
      } else if (peer.id == 'mock_bot_schwer') {
        _botDifficulty = 'schwer';
      }
      _saveBotDifficulty();

      Timer(const Duration(milliseconds: 1000), () {
        _connectedPeer = peer.copyWith(state: PeerState.connected);
        _updatePeerState(peer.id, PeerState.connected);
        stopScanning();
      });
    } else {
      try {
        await _nearbyService?.invitePeer(deviceID: peer.id, deviceName: peer.name);
      } catch (e) {
        debugPrint('Error inviting peer: $e');
        _updatePeerState(peer.id, PeerState.notConnected);
      }
    }
  }

  Future<void> acceptInvite(AppPeer peer) async {
    _isHost = true;
    _updatePeerState(peer.id, PeerState.connecting);

    if (peer.isMock) {
      Timer(const Duration(milliseconds: 1000), () {
        _connectedPeer = peer.copyWith(state: PeerState.connected);
        _updatePeerState(peer.id, PeerState.connected);
        stopAdvertising();
      });
    } else {
      try {
        await _nearbyService?.invitePeer(deviceID: peer.id, deviceName: peer.name);
      } catch (e) {
        debugPrint('Error accepting invite: $e');
        _updatePeerState(peer.id, PeerState.notConnected);
      }
    }
  }

  void _updatePlayTime() {
    if (_gameStartTime != null) {
      final diff = DateTime.now().difference(_gameStartTime!).inSeconds;
      _totalPlayTimeSeconds += diff;
      _savePlayTime();
      _gameStartTime = null;
    }
  }

  Future<void> disconnect() async {
    _updatePlayTime();
    
    if (_connectedPeer == null) return;
    final peerId = _connectedPeer!.id;
    final isMock = _connectedPeer!.isMock;

    if (!isMock) {
      try {
        await _nearbyService?.disconnectPeer(deviceID: peerId);
      } catch (e) {
        debugPrint('Error disconnecting: $e');
      }
    }

    _connectedPeer = null;
    _activeGameId = null;
    _suggestedGameId = null;
    _chatMessages.clear();
    _unreadChatCount = 0;
    _isVerifying = false;
    _verificationPin = null;
    _pinError = false;
    _pinErrorMessage = null;
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
    _suggestedGameId = null;
    _gameStartTime = DateTime.now();
    notifyListeners();
    sendPayload({
      'type': 'game_select',
      'gameId': gameId,
    });
  }

  void suggestGame(String gameId) {
    _suggestedGameId = gameId;
    notifyListeners();
    sendPayload({
      'type': 'game_suggest',
      'gameId': gameId,
    });
  }

  void exitGame() {
    _updatePlayTime();
    _activeGameId = null;
    _suggestedGameId = null;
    notifyListeners();
    sendPayload({
      'type': 'game_exit',
    });
  }

  // --- Message / Payload Sending ---

  void sendPayload(Map<String, dynamic> payload) {
    if (!isConnected) return;
    final jsonStr = jsonEncode(payload);

    if (_connectedPeer != null && !_connectedPeer!.isMock) {
      _nearbyService?.sendMessage(connectedPeer!.id, jsonStr);
    } else {
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
        final realDevices = devicesList.map((device) {
          PeerState state = PeerState.notConnected;
          if (device.state == SessionState.connected) {
            state = PeerState.connected;
          } else if (device.state == SessionState.connecting) {
            state = PeerState.connecting;
          }
          return AppPeer(id: device.deviceId, name: device.deviceName, state: state, isMock: false);
        }).toList();

        _discoveredPeers = realDevices;
        
        if (realDevices.isNotEmpty) {
          _showMockBots = false;
        }

        final connectedIndex = realDevices.indexWhere((p) => p.state == PeerState.connected);
        if (connectedIndex != -1) {
          final oldConnected = _connectedPeer;
          _connectedPeer = realDevices[connectedIndex];
          if (oldConnected == null || oldConnected.state != PeerState.connected) {
            _isHost = _isAdvertising;
            _registerConnectedPlayer(_connectedPeer!);
            _initiateHandshake();
          }
        } else {
          if (_connectedPeer != null && !_connectedPeer!.isMock) {
            _connectedPeer = null;
            _activeGameId = null;
            _updatePlayTime();
          }
        }
        notifyListeners();
      });

      _subscriptionData = _nearbyService!.dataReceivedSubscription(callback: (data) {
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
      _suggestedGameId = null;
      _gameStartTime = DateTime.now();
      notifyListeners();
    } else if (type == 'game_exit') {
      _updatePlayTime();
      _activeGameId = null;
      _suggestedGameId = null;
      notifyListeners();
    } else if (type == 'game_suggest') {
      _suggestedGameId = payload['gameId'] as String?;
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
    } else if (type == 'handshake') {
      final peerName = payload['username'] as String? ?? 'Gegner';
      final isPeerKnown = payload['isKnown'] as bool? ?? false;
      
      if (_connectedPeer != null) {
        _connectedPeer = _connectedPeer!.copyWith(name: peerName);
      }
      
      final weKnowThem = _isKnownPlayer(_connectedPeer!.id);
      if (!weKnowThem || !isPeerKnown) {
        _isVerifying = true;
        if (_isHost) {
          _verificationPin = _random.nextInt(9000) + 1000;
          notifyListeners();
        } else {
          notifyListeners();
        }
      } else {
        _isVerifying = false;
        _registerConnectedPlayer(_connectedPeer!);
        notifyListeners();
      }
    } else if (type == 'pin_submit') {
      final pin = payload['pin'] as int?;
      if (pin == _verificationPin) {
        _isVerifying = false;
        _registerConnectedPlayer(_connectedPeer!);
        sendPayload({'type': 'pin_success'});
        notifyListeners();
      } else {
        sendPayload({
          'type': 'pin_fail',
          'message': 'Falscher PIN. Bitte erneut versuchen.',
        });
      }
    } else if (type == 'pin_success') {
      _isVerifying = false;
      _registerConnectedPlayer(_connectedPeer!);
      notifyListeners();
    } else if (type == 'pin_fail') {
      _pinError = true;
      _pinErrorMessage = payload['message'] as String? ?? 'Falscher PIN.';
      notifyListeners();
    }
    
    _messageController.add(payload);
    
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
    } else if (type == 'game_suggest') {
      _handleIncomingPayload(payload);
      
      // If we suggest a game and the simulated peer is the host, they will accept our suggestion after a short delay
      if (!_isHost) {
        Timer(const Duration(milliseconds: 1200), () {
          if (!isConnected || _activeGameId != null) return;
          selectGame(payload['gameId']);
        });
      }
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

    final roll = _random.nextDouble();
    final threshold = _botDifficulty == 'einfach' ? 0.60 : (_botDifficulty == 'mittel' ? 0.30 : 0.0);

    if (gameId == 'tictactoe' && userMoveData != null) {
      final board = List<String>.from(userMoveData['board']);
      final aiSymbol = userMoveData['playerSymbol'] == 'X' ? 'O' : 'X';
      
      int bestMove = -1;
      
      if (roll < threshold) {
        // Sub-optimal: choose random empty cell
        final emptyCells = <int>[];
        for (int i = 0; i < 9; i++) {
          if (board[i].isEmpty) emptyCells.add(i);
        }
        if (emptyCells.isNotEmpty) {
          bestMove = emptyCells[_random.nextInt(emptyCells.length)];
        }
      } else {
        // Optimal Tic-Tac-Toe Move
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
      final userPlayer = 1;
      final aiPlayer = 2;

      int bestCol = -1;

      if (roll < threshold) {
        // Sub-optimal: choose random column
        final validCols = <int>[];
        for (int c = 0; c < 7; c++) {
          if (_canPlayColumn(board, c)) validCols.add(c);
        }
        if (validCols.isNotEmpty) {
          bestCol = validCols[_random.nextInt(validCols.length)];
        }
      } else {
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
      }

      if (bestCol != -1) {
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
      final subtype = userMoveData['subtype'] as String?;
      if (subtype == 'player_ready') {
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
        final userFleet = List<List<int>>.from(
          (userMoveData['userBoard'] as List).map((row) => List<int>.from(row))
        );
        
        int targetX = -1;
        int targetY = -1;

        bool huntAllowed = roll >= threshold;

        if (huntAllowed) {
          // Hunt mode: search user board for hits (value 2 = Hit) and fire adjacent
          bool foundHunt = false;
          for (int r = 0; r < 10; r++) {
            for (int c = 0; c < 10; c++) {
              if (userFleet[r][c] == 2) {
                final adjacents = [[r-1, c], [r+1, c], [r, c-1], [r, c+1]];
                for (var adj in adjacents) {
                  int ar = adj[0];
                  int ac = adj[1];
                  if (ar >= 0 && ar < 10 && ac >= 0 && ac < 10) {
                    if (userFleet[ar][ac] == 0 || userFleet[ar][ac] == 1) {
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
        }

        // Random mode fallback
        if (targetX == -1) {
          final potentials = <Point>[];
          for (int r = 0; r < 10; r++) {
            for (int c = 0; c < 10; c++) {
              if (userFleet[r][c] == 0 || userFleet[r][c] == 1) {
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
      final choices = ['rock', 'paper', 'scissors'];
      final userChoice = userMoveData['userChoice'] as String;
      
      String aiChoice;
      if (roll < threshold) {
        // Easy / Medium sub-optimal choice (lose with high probability, or just random)
        if (_random.nextBool()) {
          // Sub-optimal: intentionally lose
          if (userChoice == 'rock') aiChoice = 'scissors';
          else if (userChoice == 'paper') aiChoice = 'rock';
          else aiChoice = 'paper';
        } else {
          aiChoice = choices[_random.nextInt(3)];
        }
      } else {
        // Optimal / Hard choice: win with 75% probability, otherwise random
        if (_random.nextDouble() < 0.75) {
          if (userChoice == 'rock') aiChoice = 'paper';
          else if (userChoice == 'paper') aiChoice = 'scissors';
          else aiChoice = 'rock';
        } else {
          aiChoice = choices[_random.nextInt(3)];
        }
      }

      return {
        'type': 'game_move',
        'gameId': 'rockpaperscissors',
        'data': {
          'aiChoice': aiChoice,
          'userChoice': userChoice,
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
