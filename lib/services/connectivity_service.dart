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

// Kept for backward compatibility with any code that references this enum
enum AppConnectivityMode {
  real,
  simulated
}

// Internal handshake state machine
enum _HandshakeState {
  idle,
  sent,        // We sent our handshake, waiting for peer
  received,    // We received peer's handshake before sending ours
  complete,    // Both handshakes exchanged
}

class ConnectivityService extends ChangeNotifier with WidgetsBindingObserver {
  static const String _keyUsername = 'two_play_username';
  static const String _keyDarkMode = 'two_play_dark_mode';
  static const String _keyKnownPlayers = 'two_play_known_players';
  static const String _keyBotDifficulty = 'two_play_bot_difficulty';
  static const String _keyGameStats = 'two_play_game_stats';
  static const String _keyPlayTime = 'two_play_play_time';
  static const String _keyBlockedPlayers = 'two_play_blocked_players';

  String _myUsername = 'Player';
  bool _isDarkMode = true;

  String get myUsername => _myUsername;
  bool get isDarkMode => _isDarkMode;
  // Kept for compatibility
  AppConnectivityMode get mode => AppConnectivityMode.real;

  // Bot difficulty
  String _botDifficulty = 'mittel';
  String get botDifficulty => _botDifficulty;

  // Blocked players (ID -> Unblock Time)
  final Map<String, DateTime> _blockedPlayers = {};
  Map<String, DateTime> get blockedPlayers => Map.unmodifiable(_blockedPlayers);

  // Connection states
  bool _isAdvertising = false;
  bool _isScanning = false;
  List<AppPeer> _discoveredPeers = [];
  AppPeer? _connectedPeer;
  bool _isHost = false;
  bool _showMockBots = false;
  Timer? _botTimer;
  Timer? _advertiserBotTimer;
  Timer? _verifyTimeoutTimer;

  bool get isAdvertising => _isAdvertising;
  bool get isScanning => _isScanning;

  /// Returns filtered, formatted list of discovered peers.
  /// - Blocked players are hidden.
  /// - If real peers exist, mock bots are hidden.
  /// - Bot name includes current difficulty label.
  List<AppPeer> get discoveredPeers {
    final now = DateTime.now();
    final filtered = _discoveredPeers.where((peer) {
      final unblockTime = _blockedPlayers[peer.id];
      if (unblockTime != null && now.isBefore(unblockTime)) {
        return false; // Still blocked
      }
      return true;
    }).toList();

    final realPeers = filtered.where((p) => !p.isMock).toList();

    List<AppPeer> listToReturn;
    if (realPeers.isNotEmpty) {
      // Real peers found – hide bots
      listToReturn = realPeers;
    } else if (_showMockBots) {
      final mockPeers = filtered.where((p) => p.isMock).toList();
      listToReturn = mockPeers.isNotEmpty ? mockPeers : _getMockBotsList();
    } else {
      listToReturn = [];
    }

    // Attach current difficulty label to bot name
    return listToReturn.map((peer) {
      if (peer.isMock) {
        String diffLabel;
        switch (_botDifficulty) {
          case 'einfach':
            diffLabel = 'Einfach';
            break;
          case 'schwer':
            diffLabel = 'Schwer';
            break;
          default:
            diffLabel = 'Mittel';
        }
        return peer.copyWith(name: '2Play Bot [$diffLabel]');
      }
      return peer;
    }).toList();
  }

  /// Single bot definition – always named "2Play Bot".
  List<AppPeer> _getMockBotsList() {
    return [
      AppPeer(
        id: 'mock_bot',
        name: '2Play Bot',
        state: PeerState.notConnected,
        isMock: true,
      ),
    ];
  }

  AppPeer? get connectedPeer => _connectedPeer;
  bool get isConnected => _connectedPeer?.state == PeerState.connected;
  bool get isHost => _isHost;

  // Handshake & PIN state
  _HandshakeState _handshakeState = _HandshakeState.idle;
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
    const gameNames = {
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

  // Known players (up to 10, sorted by recency)
  List<Map<String, String>> _knownPlayers = [];
  List<Map<String, String>> get knownPlayers => List.unmodifiable(_knownPlayers);

  /// Returns true if a player with [id] is in the known players list.
  bool isKnownPlayer(String id) => _knownPlayers.any((p) => p['id'] == id);

  // Chat support
  final List<ChatMessage> _chatMessages = [];
  int _unreadChatCount = 0;

  List<ChatMessage> get chatMessages => List.unmodifiable(_chatMessages);
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

  // Broadcast stream for screens to listen to
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  // Real P2P Plugin
  NearbyService? _nearbyService;
  // ignore: unused_field
  StreamSubscription? _subscriptionState;
  // ignore: unused_field
  StreamSubscription? _subscriptionData;
  bool _pluginInitialized = false;

  final Random _random = Random();

  ConnectivityService() {
    _loadSettings();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (isConnected) {
        sendPayload({'type': 'game_exit'});
      }
      disconnect();
    }
  }

  // ---------------------------------------------------------------------------
  // Settings Loading & Saving
  // ---------------------------------------------------------------------------

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _myUsername = prefs.getString(_keyUsername) ?? 'Player_${_random.nextInt(900) + 100}';
    _isDarkMode = prefs.getBool(_keyDarkMode) ?? true;
    _botDifficulty = prefs.getString(_keyBotDifficulty) ?? 'mittel';
    _totalPlayTimeSeconds = prefs.getInt(_keyPlayTime) ?? 0;

    // Game stats
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

    // Known players
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

  void _loadBlockedPlayers(SharedPreferences prefs) {
    final jsonStr = prefs.getString(_keyBlockedPlayers);
    if (jsonStr == null) return;
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

  Future<void> _saveBlockedPlayers() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _blockedPlayers.map((key, value) => MapEntry(key, value.toIso8601String()));
    await prefs.setString(_keyBlockedPlayers, jsonEncode(data));
  }

  // ---------------------------------------------------------------------------
  // Public setters
  // ---------------------------------------------------------------------------

  Future<void> setBotDifficulty(String difficulty) async {
    if (difficulty == 'einfach' || difficulty == 'mittel' || difficulty == 'schwer') {
      _botDifficulty = difficulty;
      await _saveBotDifficulty();
      notifyListeners();
    }
  }

  Future<void> setUsername(String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    _myUsername = trimmed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUsername, trimmed);
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

  // Backward compatibility stub
  Future<void> setConnectivityMode(AppConnectivityMode selectedMode) async {
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Known Players Management
  // ---------------------------------------------------------------------------

  Future<void> _registerKnownPlayer(AppPeer peer) async {
    if (peer.isMock) return;

    // Move to top if already known, otherwise insert at front
    _knownPlayers.removeWhere((p) => p['id'] == peer.id);
    _knownPlayers.insert(0, {
      'id': peer.id,
      'name': peer.name,
    });

    // Keep max 10 entries
    if (_knownPlayers.length > 10) {
      _knownPlayers = _knownPlayers.sublist(0, 10);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyKnownPlayers, jsonEncode(_knownPlayers));
    notifyListeners();
  }

  Future<void> removeKnownPlayer(String id) async {
    _knownPlayers.removeWhere((p) => p['id'] == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyKnownPlayers, jsonEncode(_knownPlayers));
    notifyListeners();
  }

  Future<void> clearKnownPlayers() async {
    final prefs = await SharedPreferences.getInstance();
    _knownPlayers.clear();
    await prefs.remove(_keyKnownPlayers);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Statistics
  // ---------------------------------------------------------------------------

  void incrementWin(String gameId) {
    final vsBot = _connectedPeer?.isMock ?? true;
    final statKey = vsBot ? 'wins_vs_bot' : 'wins_vs_player';

    _gameStats.putIfAbsent(gameId, () => {'wins_vs_bot': 0, 'losses_vs_bot': 0, 'wins_vs_player': 0, 'losses_vs_player': 0, 'play_count': 0});
    _gameStats[gameId]![statKey] = (_gameStats[gameId]![statKey] ?? 0) + 1;
    _gameStats[gameId]!['play_count'] = (_gameStats[gameId]!['play_count'] ?? 0) + 1;
    _saveStats();
    notifyListeners();
  }

  void incrementLoss(String gameId) {
    final vsBot = _connectedPeer?.isMock ?? true;
    final statKey = vsBot ? 'losses_vs_bot' : 'losses_vs_player';

    _gameStats.putIfAbsent(gameId, () => {'wins_vs_bot': 0, 'losses_vs_bot': 0, 'wins_vs_player': 0, 'losses_vs_player': 0, 'play_count': 0});
    _gameStats[gameId]![statKey] = (_gameStats[gameId]![statKey] ?? 0) + 1;
    _gameStats[gameId]!['play_count'] = (_gameStats[gameId]!['play_count'] ?? 0) + 1;
    _saveStats();
    notifyListeners();
  }

  void _updatePlayTime() {
    if (_gameStartTime != null) {
      final diff = DateTime.now().difference(_gameStartTime!).inSeconds;
      _totalPlayTimeSeconds += diff;
      _savePlayTime();
      _gameStartTime = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Blocking
  // ---------------------------------------------------------------------------

  void blockPlayer(String id) {
    _blockedPlayers[id] = DateTime.now().add(const Duration(minutes: 10));
    _saveBlockedPlayers();
    notifyListeners();

    if (_connectedPeer != null && _connectedPeer!.id == id) {
      disconnect();
    }
  }

  void unblockPlayer(String id) {
    _blockedPlayers.remove(id);
    _saveBlockedPlayers();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Advertising & Scanning
  // ---------------------------------------------------------------------------

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

    // After 5 s with no real connection, show the single bot as a pending invite
    _advertiserBotTimer?.cancel();
    _advertiserBotTimer = Timer(const Duration(seconds: 5), () {
      if (_isAdvertising && !isConnected) {
        const mockId = 'mock_bot';
        const mockName = '2Play Bot';

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

    // After 4 s with no real peers, show the single mock bot
    _botTimer?.cancel();
    _botTimer = Timer(const Duration(seconds: 4), () {
      if (_discoveredPeers.where((p) => !p.isMock).isEmpty && _isScanning) {
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
    notifyListeners();

    try {
      await _nearbyService?.stopBrowsingForPeers();
    } catch (e) {
      debugPrint('Error stopping scanning: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Connection Actions
  // ---------------------------------------------------------------------------

  /// Called by the SCANNER (client) to invite a peer.
  Future<void> invitePeer(AppPeer peer) async {
    _isHost = false;
    _updatePeerState(peer.id, PeerState.connecting);

    if (peer.isMock) {
      // Bot connects instantly – use current difficulty setting
      Timer(const Duration(milliseconds: 900), () {
        if (!_isScanning && !isConnected) return;
        _connectedPeer = peer.copyWith(state: PeerState.connected);
        _updatePeerState(peer.id, PeerState.connected);
        stopScanning();
        notifyListeners();
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

  /// Called by the ADVERTISER (host) to accept an invite from a peer.
  Future<void> acceptInvite(AppPeer peer) async {
    _isHost = true;
    _updatePeerState(peer.id, PeerState.connecting);

    if (peer.isMock) {
      Timer(const Duration(milliseconds: 900), () {
        _connectedPeer = peer.copyWith(state: PeerState.connected);
        _updatePeerState(peer.id, PeerState.connected);
        stopAdvertising();
        notifyListeners();
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

  /// Decline an incoming invite request (real peer, advertiser side).
  void declineInvite(AppPeer peer) {
    sendPayload({'type': 'invite_declined'});
    _updatePeerState(peer.id, PeerState.notConnected);
    notifyListeners();
  }

  /// Block an inviting peer (advertiser side).
  void blockInvitingPeer(AppPeer peer) {
    blockPlayer(peer.id);
    sendPayload({'type': 'invite_blocked'});
    notifyListeners();
  }

  Future<void> disconnect() async {
    _updatePlayTime();
    _verifyTimeoutTimer?.cancel();

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
    _resetHandshake();
    _updatePeerState(peerId, PeerState.notConnected);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // PIN Verification Handshake
  // ---------------------------------------------------------------------------

  void _resetHandshake() {
    _handshakeState = _HandshakeState.idle;
    _isVerifying = false;
    _verificationPin = null;
    _pinError = false;
    _pinErrorMessage = null;
    _verifyTimeoutTimer?.cancel();
  }

  /// Called right after a real P2P connection is established.
  void _initiateHandshake() {
    if (_connectedPeer == null || _connectedPeer!.isMock) return;

    _resetHandshake();
    _handshakeState = _HandshakeState.sent;

    sendPayload({
      'type': 'handshake',
      'username': _myUsername,
      'isKnown': isKnownPlayer(_connectedPeer!.id),
    });
  }

  /// Called by the GUEST after reading the PIN from the host's screen.
  void verifyCode(int pin) {
    if (isHost) {
      // Host verifies locally (shouldn't normally be called on host side)
      if (pin == _verificationPin) {
        _isVerifying = false;
        _verifyTimeoutTimer?.cancel();
        _registerKnownPlayer(_connectedPeer!);
        sendPayload({'type': 'pin_success'});
        notifyListeners();
      } else {
        _pinError = true;
        _pinErrorMessage = 'Falscher PIN. Bitte erneut versuchen.';
        notifyListeners();
      }
    } else {
      // Guest submits PIN to host
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

  // ---------------------------------------------------------------------------
  // Game Selection Syncing
  // ---------------------------------------------------------------------------

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
    sendPayload({'type': 'game_exit'});
  }

  // ---------------------------------------------------------------------------
  // Message / Payload Sending
  // ---------------------------------------------------------------------------

  void sendPayload(Map<String, dynamic> payload) {
    if (!isConnected) return;
    final jsonStr = jsonEncode(payload);

    if (_connectedPeer != null && !_connectedPeer!.isMock) {
      _nearbyService?.sendMessage(connectedPeer!.id, jsonStr);
    } else {
      _handleSimulatedMessage(payload);
    }
  }

  // ---------------------------------------------------------------------------
  // Real P2P Plugin Setup
  // ---------------------------------------------------------------------------

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
          return AppPeer(
            id: device.deviceId,
            name: device.deviceName,
            state: state,
            isMock: false,
          );
        }).toList();

        // Merge: keep mock bots if no real peers visible
        final prevMocks = _discoveredPeers.where((p) => p.isMock).toList();
        if (realDevices.isNotEmpty) {
          _discoveredPeers = realDevices;
          _showMockBots = false;
        } else {
          // Keep mocks visible unless we had a real update clearing them
          _discoveredPeers = [...realDevices, ...prevMocks];
        }

        final connectedDevice = realDevices.firstWhere(
          (p) => p.state == PeerState.connected,
          orElse: () => AppPeer(id: '', name: '', state: PeerState.notConnected),
        );

        if (connectedDevice.id.isNotEmpty) {
          final wasAlreadyConnected = _connectedPeer?.state == PeerState.connected
              && _connectedPeer?.id == connectedDevice.id;

          _connectedPeer = connectedDevice;

          if (!wasAlreadyConnected) {
            // New connection established
            _isHost = _isAdvertising;
            _initiateHandshake();
          }
        } else {
          // Lost connection to real peer
          if (_connectedPeer != null && !_connectedPeer!.isMock) {
            _connectedPeer = null;
            _activeGameId = null;
            _updatePlayTime();
            _resetHandshake();
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
          debugPrint('Error parsing incoming message: $e\nData: $data');
        }
      });

      _pluginInitialized = true;
    } catch (e) {
      debugPrint('Failed to initialize Nearby Service: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Incoming Payload Handling
  // ---------------------------------------------------------------------------

  void _handleIncomingPayload(Map<String, dynamic> payload) {
    final type = payload['type'] as String?;

    switch (type) {
      case 'handshake':
        _handleHandshake(payload);
        break;

      case 'pin_submit':
        _handlePinSubmit(payload);
        break;

      case 'pin_success':
        _isVerifying = false;
        _verifyTimeoutTimer?.cancel();
        _registerKnownPlayer(_connectedPeer!);
        notifyListeners();
        break;

      case 'pin_fail':
        _pinError = true;
        _pinErrorMessage = payload['message'] as String? ?? 'Falscher PIN.';
        notifyListeners();
        break;

      case 'game_select':
        _activeGameId = payload['gameId'] as String?;
        _suggestedGameId = null;
        _gameStartTime = DateTime.now();
        notifyListeners();
        break;

      case 'game_exit':
        _updatePlayTime();
        _activeGameId = null;
        _suggestedGameId = null;
        notifyListeners();
        break;

      case 'game_suggest':
        _suggestedGameId = payload['gameId'] as String?;
        notifyListeners();
        break;

      case 'chat_message':
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
        break;

      case 'invite_declined':
        // Peer declined our invite – notify UI
        _messageController.add({'type': 'invite_declined'});
        _updatePeerState(_connectedPeer?.id ?? '', PeerState.notConnected);
        notifyListeners();
        return; // Don't re-add to stream below

      case 'invite_blocked':
        // Peer blocked us – notify UI
        _messageController.add({'type': 'invite_blocked'});
        _updatePeerState(_connectedPeer?.id ?? '', PeerState.notConnected);
        notifyListeners();
        return;
    }

    // Forward to listening screens (game screens, lobby)
    _messageController.add(payload);
  }

  void _handleHandshake(Map<String, dynamic> payload) {
    final peerName = payload['username'] as String? ?? 'Gegner';
    final isPeerKnown = payload['isKnown'] as bool? ?? false;

    // Update peer name from handshake
    if (_connectedPeer != null) {
      _connectedPeer = _connectedPeer!.copyWith(name: peerName);
    }

    // Determine if we need verification
    final weKnowThem = _connectedPeer != null && isKnownPlayer(_connectedPeer!.id);
    final mutuallyKnown = weKnowThem && isPeerKnown;

    if (_handshakeState == _HandshakeState.idle) {
      // We haven't sent our handshake yet; send now, then evaluate
      _handshakeState = _HandshakeState.received;
      sendPayload({
        'type': 'handshake',
        'username': _myUsername,
        'isKnown': weKnowThem,
      });
      _handshakeState = _HandshakeState.complete;
    } else {
      // We already sent – handshake complete
      _handshakeState = _HandshakeState.complete;
    }

    if (mutuallyKnown) {
      // Both know each other – skip PIN
      _isVerifying = false;
      _registerKnownPlayer(_connectedPeer!);
    } else {
      // Need PIN verification
      _isVerifying = true;
      if (_isHost) {
        // Host generates the PIN
        _verificationPin = _random.nextInt(9000) + 1000;

        // Timeout: if guest doesn't verify in 60 s, disconnect
        _verifyTimeoutTimer?.cancel();
        _verifyTimeoutTimer = Timer(const Duration(seconds: 60), () {
          if (_isVerifying) {
            disconnect();
          }
        });
      }
    }

    notifyListeners();
  }

  void _handlePinSubmit(Map<String, dynamic> payload) {
    // Only the host handles pin_submit
    if (!_isHost) return;

    final submittedPin = payload['pin'];
    final pin = submittedPin is int ? submittedPin : int.tryParse(submittedPin.toString());

    if (pin != null && pin == _verificationPin) {
      _isVerifying = false;
      _verifyTimeoutTimer?.cancel();
      _registerKnownPlayer(_connectedPeer!);
      sendPayload({'type': 'pin_success'});
    } else {
      sendPayload({
        'type': 'pin_fail',
        'message': 'Falscher PIN. Bitte erneut versuchen.',
      });
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Simulated Bot Mode (AI Opponent)
  // ---------------------------------------------------------------------------

  void _handleSimulatedMessage(Map<String, dynamic> payload) {
    final type = payload['type'] as String?;

    switch (type) {
      case 'game_select':
      case 'game_exit':
        _handleIncomingPayload(payload);
        break;

      case 'game_suggest':
        _handleIncomingPayload(payload);
        // Bot (as host) auto-accepts game suggestions after short delay
        if (!_isHost) {
          Timer(const Duration(milliseconds: 1200), () {
            if (!isConnected || _activeGameId != null) return;
            selectGame(payload['gameId'] as String);
          });
        }
        break;

      case 'game_move':
        // Simulate bot thinking delay
        Timer(Duration(milliseconds: 700 + _random.nextInt(500)), () {
          if (!isConnected) return;
          final response = _generateAIResponse(payload);
          if (response != null) {
            _handleIncomingPayload(response);
          }
        });
        break;

      case 'game_reset':
        Timer(const Duration(milliseconds: 500), () {
          _handleIncomingPayload({
            'type': 'game_reset_accept',
            'gameId': payload['gameId'],
          });
        });
        break;

      case 'chat_message':
        Timer(Duration(seconds: 1 + _random.nextInt(2)), () {
          if (!isConnected) return;
          const aiReplies = [
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
          _handleIncomingPayload({
            'type': 'chat_message',
            'senderName': connectedPeer?.name ?? '2Play Bot',
            'text': replyText,
          });
        });
        break;
    }
  }

  Map<String, dynamic>? _generateAIResponse(Map<String, dynamic> userMove) {
    final gameId = userMove['gameId'] as String?;
    final userMoveData = userMove['data'] as Map<String, dynamic>?;
    if (userMoveData == null) return null;

    final roll = _random.nextDouble();
    final threshold = _botDifficulty == 'einfach' ? 0.60 : (_botDifficulty == 'mittel' ? 0.30 : 0.0);

    if (gameId == 'tictactoe') {
      return _aiTicTacToe(userMoveData, roll, threshold);
    } else if (gameId == 'connect4') {
      return _aiConnect4(userMoveData, roll, threshold);
    } else if (gameId == 'battleship') {
      return _aiBattleship(userMoveData, roll, threshold);
    } else if (gameId == 'rockpaperscissors') {
      return _aiRockPaperScissors(userMoveData, roll, threshold);
    }
    return null;
  }

  Map<String, dynamic>? _aiTicTacToe(Map<String, dynamic> data, double roll, double threshold) {
    final board = List<String>.from(data['board']);
    final aiSymbol = data['playerSymbol'] == 'X' ? 'O' : 'X';

    int bestMove = -1;

    if (roll < threshold) {
      final emptyCells = [for (int i = 0; i < 9; i++) if (board[i].isEmpty) i];
      if (emptyCells.isNotEmpty) bestMove = emptyCells[_random.nextInt(emptyCells.length)];
    } else {
      bestMove = _findTicTacToeWinningMove(board, aiSymbol);
      if (bestMove == -1) bestMove = _findTicTacToeWinningMove(board, data['playerSymbol']);
      if (bestMove == -1 && board[4].isEmpty) bestMove = 4;
      if (bestMove == -1) {
        final emptyCells = [for (int i = 0; i < 9; i++) if (board[i].isEmpty) i];
        if (emptyCells.isNotEmpty) bestMove = emptyCells[_random.nextInt(emptyCells.length)];
      }
    }

    if (bestMove == -1) return null;
    board[bestMove] = aiSymbol;
    return {
      'type': 'game_move',
      'gameId': 'tictactoe',
      'data': {
        'board': board,
        'lastMoveIndex': bestMove,
        'nextTurn': data['playerSymbol'],
      }
    };
  }

  Map<String, dynamic>? _aiConnect4(Map<String, dynamic> data, double roll, double threshold) {
    final board = List<List<int>>.from(
      (data['board'] as List).map((col) => List<int>.from(col))
    );
    const userPlayer = 1;
    const aiPlayer = 2;

    int bestCol = -1;

    if (roll < threshold) {
      final validCols = [for (int c = 0; c < 7; c++) if (_canPlayColumn(board, c)) c];
      if (validCols.isNotEmpty) bestCol = validCols[_random.nextInt(validCols.length)];
    } else {
      for (int c = 0; c < 7; c++) {
        if (_canPlayColumn(board, c) && _checkConnect4Win(_simulatePlay(board, c, aiPlayer), aiPlayer)) {
          bestCol = c;
          break;
        }
      }
      if (bestCol == -1) {
        for (int c = 0; c < 7; c++) {
          if (_canPlayColumn(board, c) && _checkConnect4Win(_simulatePlay(board, c, userPlayer), userPlayer)) {
            bestCol = c;
            break;
          }
        }
      }
      if (bestCol == -1) {
        const preferences = [3, 2, 4, 1, 5, 0, 6];
        for (int c in preferences) {
          if (_canPlayColumn(board, c)) {
            bestCol = c;
            break;
          }
        }
      }
    }

    if (bestCol == -1) return null;

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

  Map<String, dynamic>? _aiBattleship(Map<String, dynamic> data, double roll, double threshold) {
    final subtype = data['subtype'] as String?;

    if (subtype == 'player_ready') {
      return {
        'type': 'game_move',
        'gameId': 'battleship',
        'data': {
          'subtype': 'ai_ready',
          'aiBoard': _generateRandomBattleshipBoard(),
        }
      };
    } else if (subtype == 'fire') {
      final userFleet = List<List<int>>.from(
        (data['userBoard'] as List).map((row) => List<int>.from(row))
      );

      int targetX = -1;
      int targetY = -1;

      if (roll >= threshold) {
        // Hunt mode: target adjacent to existing hits
        outer:
        for (int r = 0; r < 10; r++) {
          for (int c = 0; c < 10; c++) {
            if (userFleet[r][c] == 2) {
              for (final adj in [[r-1, c], [r+1, c], [r, c-1], [r, c+1]]) {
                final ar = adj[0], ac = adj[1];
                if (ar >= 0 && ar < 10 && ac >= 0 && ac < 10 &&
                    (userFleet[ar][ac] == 0 || userFleet[ar][ac] == 1)) {
                  targetX = ac;
                  targetY = ar;
                  break outer;
                }
              }
            }
          }
        }
      }

      if (targetX == -1) {
        final potentials = [
          for (int r = 0; r < 10; r++)
            for (int c = 0; c < 10; c++)
              if (userFleet[r][c] == 0 || userFleet[r][c] == 1) Point(c, r)
        ];
        if (potentials.isEmpty) return null;
        final pt = potentials[_random.nextInt(potentials.length)];
        targetX = pt.x.toInt();
        targetY = pt.y.toInt();
      }

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
    return null;
  }

  Map<String, dynamic> _aiRockPaperScissors(Map<String, dynamic> data, double roll, double threshold) {
    const choices = ['rock', 'paper', 'scissors'];
    final userChoice = data['userChoice'] as String;

    String aiChoice;
    if (roll < threshold) {
      if (_random.nextBool()) {
        // Sub-optimal: intentionally lose
        if (userChoice == 'rock') aiChoice = 'scissors';
        else if (userChoice == 'paper') aiChoice = 'rock';
        else aiChoice = 'paper';
      } else {
        aiChoice = choices[_random.nextInt(3)];
      }
    } else {
      // Optimal: win with 75% probability
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

  // ---------------------------------------------------------------------------
  // Helper: Peer State Update
  // ---------------------------------------------------------------------------

  void _updatePeerState(String id, PeerState state) {
    final index = _discoveredPeers.indexWhere((p) => p.id == id);
    if (index != -1) {
      _discoveredPeers[index] = _discoveredPeers[index].copyWith(state: state);
    }
    if (_connectedPeer?.id == id) {
      _connectedPeer = _connectedPeer!.copyWith(state: state);
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // AI Helper Methods
  // ---------------------------------------------------------------------------

  int _findTicTacToeWinningMove(List<String> board, String symbol) {
    const lines = [
      [0, 1, 2], [3, 4, 5], [6, 7, 8],
      [0, 3, 6], [1, 4, 7], [2, 5, 8],
      [0, 4, 8], [2, 4, 6],
    ];
    for (final line in lines) {
      int count = 0;
      int emptyIndex = -1;
      for (final index in line) {
        if (board[index] == symbol) count++;
        else if (board[index].isEmpty) emptyIndex = index;
      }
      if (count == 2 && emptyIndex != -1) return emptyIndex;
    }
    return -1;
  }

  bool _canPlayColumn(List<List<int>> board, int col) => board[col][0] == 0;

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
        if (board[c][r] == player && board[c+1][r] == player &&
            board[c+2][r] == player && board[c+3][r] == player) return true;
      }
    }
    // Vertical
    for (int c = 0; c < 7; c++) {
      for (int r = 0; r < 3; r++) {
        if (board[c][r] == player && board[c][r+1] == player &&
            board[c][r+2] == player && board[c][r+3] == player) return true;
      }
    }
    // Diagonal /
    for (int c = 0; c < 4; c++) {
      for (int r = 3; r < 6; r++) {
        if (board[c][r] == player && board[c+1][r-1] == player &&
            board[c+2][r-2] == player && board[c+3][r-3] == player) return true;
      }
    }
    // Diagonal \
    for (int c = 0; c < 4; c++) {
      for (int r = 0; r < 3; r++) {
        if (board[c][r] == player && board[c+1][r+1] == player &&
            board[c+2][r+2] == player && board[c+3][r+3] == player) return true;
      }
    }
    return false;
  }

  List<List<int>> _generateRandomBattleshipBoard() {
    final board = List.generate(10, (_) => List.generate(10, (_) => 0));
    const shipSizes = [5, 4, 3, 3, 2];

    for (final size in shipSizes) {
      bool placed = false;
      while (!placed) {
        final isHorizontal = _random.nextBool();
        final x = _random.nextInt(10);
        final y = _random.nextInt(10);

        if (isHorizontal && x + size <= 10) {
          bool overlap = false;
          for (int i = 0; i < size; i++) {
            if (board[y][x + i] != 0) { overlap = true; break; }
          }
          if (!overlap) {
            for (int i = 0; i < size; i++) board[y][x + i] = 1;
            placed = true;
          }
        } else if (!isHorizontal && y + size <= 10) {
          bool overlap = false;
          for (int i = 0; i < size; i++) {
            if (board[y + i][x] != 0) { overlap = true; break; }
          }
          if (!overlap) {
            for (int i = 0; i < size; i++) board[y + i][x] = 1;
            placed = true;
          }
        }
      }
    }
    return board;
  }
}
