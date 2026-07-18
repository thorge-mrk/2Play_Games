import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_nearby_connections/flutter_nearby_connections.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data Models
// ─────────────────────────────────────────────────────────────────────────────

enum PeerState { notConnected, connecting, connected }

class AppPeer {
  final String id;
  final String name;
  final PeerState state;
  final bool isMock;

  const AppPeer({
    required this.id,
    required this.name,
    required this.state,
    this.isMock = false,
  });

  AppPeer copyWith({String? id, String? name, PeerState? state, bool? isMock}) {
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

  const ChatMessage({
    required this.senderName,
    required this.text,
    required this.timestamp,
    required this.isMe,
  });
}

// Kept for backward compatibility
enum AppConnectivityMode { real, simulated }

// Internal handshake state machine
enum _HandshakeState {
  idle,
  sent,     // We sent our handshake, waiting for peer
  complete, // Both handshakes exchanged
}

// ─────────────────────────────────────────────────────────────────────────────
// ConnectivityService
// ─────────────────────────────────────────────────────────────────────────────

class ConnectivityService extends ChangeNotifier with WidgetsBindingObserver {
  // SharedPreferences keys
  static const String _keyUsername       = 'two_play_username';
  static const String _keyDarkMode       = 'two_play_dark_mode';
  static const String _keyKnownPlayers   = 'two_play_known_players';
  static const String _keyBotDifficulty  = 'two_play_bot_difficulty';
  static const String _keyGameStats      = 'two_play_game_stats';
  static const String _keyPlayTime       = 'two_play_play_time';
  static const String _keyBlockedPlayers = 'two_play_blocked_players';

  // ── Settings ────────────────────────────────────────────────────────────
  String _myUsername   = 'Player';
  bool   _isDarkMode   = true;
  String _botDifficulty = 'mittel';

  String get myUsername    => _myUsername;
  bool   get isDarkMode    => _isDarkMode;
  String get botDifficulty => _botDifficulty;
  AppConnectivityMode get mode => AppConnectivityMode.real; // compat

  // ── Blocked players ──────────────────────────────────────────────────────
  final Map<String, DateTime> _blockedPlayers = {};
  Map<String, DateTime> get blockedPlayers => Map.unmodifiable(_blockedPlayers);

  // ── Discovery ────────────────────────────────────────────────────────────
  bool _isAdvertising = false;
  bool _isScanning    = false;
  bool _showMockBots  = false;
  List<AppPeer> _discoveredPeers = [];

  Timer? _botTimer;
  Timer? _advertiserBotTimer;
  Timer? _verifyTimeoutTimer;

  bool get isAdvertising => _isAdvertising;
  bool get isScanning    => _isScanning;

  /// Filtered list: blocked players hidden, bots hidden when real peers exist.
  List<AppPeer> get discoveredPeers {
    final now = DateTime.now();
    final filtered = _discoveredPeers.where((peer) {
      final unblockTime = _blockedPlayers[peer.id];
      if (unblockTime != null && now.isBefore(unblockTime)) return false;
      return true;
    }).toList();

    final realPeers = filtered.where((p) => !p.isMock).toList();

    List<AppPeer> list;
    if (realPeers.isNotEmpty) {
      list = realPeers;
    } else if (_showMockBots) {
      final mockPeers = filtered.where((p) => p.isMock).toList();
      list = mockPeers.isNotEmpty ? mockPeers : _getMockBotsList();
    } else {
      list = [];
    }

    // Update bot name to reflect current difficulty
    return list.map((peer) {
      if (peer.isMock) {
        final label = _botDifficulty == 'einfach'
            ? 'Einfach'
            : (_botDifficulty == 'schwer' ? 'Schwer' : 'Mittel');
        return peer.copyWith(name: '2Play Bot [$label]');
      }
      return peer;
    }).toList();
  }

  List<AppPeer> _getMockBotsList() => [
    const AppPeer(id: 'mock_bot', name: '2Play Bot', state: PeerState.notConnected, isMock: true),
  ];

  // ── Connection ───────────────────────────────────────────────────────────
  AppPeer? _connectedPeer;
  bool     _isHost = false;

  AppPeer? get connectedPeer => _connectedPeer;
  bool     get isConnected   => _connectedPeer?.state == PeerState.connected;
  bool     get isHost        => _isHost;

  // ── Handshake & PIN ──────────────────────────────────────────────────────
  _HandshakeState _handshakeState = _HandshakeState.idle;
  bool   _isVerifying      = false;
  int?   _verificationPin;
  bool   _pinError         = false;
  String? _pinErrorMessage;

  bool   get isVerifying      => _isVerifying;
  int?   get verificationPin  => _verificationPin;
  bool   get pinError         => _pinError;
  String? get pinErrorMessage => _pinErrorMessage;

  // ── Statistics ───────────────────────────────────────────────────────────
  Map<String, Map<String, int>> _gameStats = {};
  int       _totalPlayTimeSeconds = 0;
  DateTime? _gameStartTime;

  Map<String, Map<String, int>> get gameStats           => _gameStats;
  int                           get totalPlayTimeSeconds => _totalPlayTimeSeconds;

  String get favoriteGame {
    String bestGame = 'Keines';
    int    maxPlays = -1;
    const names = {
      'tictactoe':         'Tic-Tac-Toe',
      'connect4':          'Vier Gewinnt',
      'battleship':        'Schiffe Versenken',
      'rockpaperscissors': 'Schere, Stein, Papier',
      'minigolf':          'Minigolf',
    };
    _gameStats.forEach((id, stats) {
      final plays = stats['play_count'] ?? 0;
      if (plays > maxPlays && plays > 0) {
        maxPlays = plays;
        bestGame = names[id] ?? id;
      }
    });
    return bestGame;
  }

  // ── Active game / suggestion ──────────────────────────────────────────────
  String? _activeGameId;
  String? _suggestedGameId;
  String? get activeGameId    => _activeGameId;
  String? get suggestedGameId => _suggestedGameId;

  // ── Known players ────────────────────────────────────────────────────────
  List<Map<String, String>> _knownPlayers = [];
  List<Map<String, String>> get knownPlayers => List.unmodifiable(_knownPlayers);
  bool isKnownPlayer(String id) => _knownPlayers.any((p) => p['id'] == id);

  // ── Chat ─────────────────────────────────────────────────────────────────
  final List<ChatMessage> _chatMessages = [];
  int _unreadChatCount = 0;

  List<ChatMessage> get chatMessages    => List.unmodifiable(_chatMessages);
  int               get unreadChatCount => _unreadChatCount;

  // ── Message stream ───────────────────────────────────────────────────────
  final _msgCtrl = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messageStream => _msgCtrl.stream;

  // ── P2P Plugin ───────────────────────────────────────────────────────────
  NearbyService? _nearbyService;
  StreamSubscription? _subState;
  StreamSubscription? _subData;
  bool _pluginInitialized = false;

  final Random _rng = Random();

  // ─────────────────────────────────────────────────────────────────────────
  // Constructor / Dispose
  // ─────────────────────────────────────────────────────────────────────────

  ConnectivityService() {
    _loadSettings();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _botTimer?.cancel();
    _advertiserBotTimer?.cancel();
    _verifyTimeoutTimer?.cancel();
    _subState?.cancel();
    _subData?.cancel();
    _msgCtrl.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only tear down on real backgrounding – "inactive" also fires for
    // temporary interruptions (control center, incoming call, app switcher)
    // and would needlessly kill an active session.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (isConnected) sendPayload({'type': 'game_exit'});
      disconnect();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Settings
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _myUsername   = prefs.getString(_keyUsername)     ?? 'Player_${_rng.nextInt(900) + 100}';
    _isDarkMode   = prefs.getBool(_keyDarkMode)       ?? true;
    _botDifficulty = prefs.getString(_keyBotDifficulty) ?? 'mittel';
    _totalPlayTimeSeconds = prefs.getInt(_keyPlayTime) ?? 0;

    // Stats
    final statsJson = prefs.getString(_keyGameStats);
    if (statsJson != null) {
      try {
        final decoded = jsonDecode(statsJson) as Map<String, dynamic>;
        _gameStats = decoded.map((k, v) => MapEntry(k, Map<String, int>.from(v as Map)));
      } catch (_) {
        _initDefaultStats();
      }
    } else {
      _initDefaultStats();
    }

    // Known players
    final knownJson = prefs.getString(_keyKnownPlayers);
    if (knownJson != null) {
      try {
        _knownPlayers = (jsonDecode(knownJson) as List)
            .map((e) => Map<String, String>.from(e))
            .toList();
      } catch (_) {}
    }

    _loadBlockedPlayers(prefs);
    notifyListeners();
    _initPlugin();
  }

  void _initDefaultStats() {
    _gameStats = {
      for (final id in ['tictactoe', 'connect4', 'battleship', 'rockpaperscissors', 'minigolf'])
        id: {'wins_vs_bot': 0, 'losses_vs_bot': 0, 'wins_vs_player': 0, 'losses_vs_player': 0, 'play_count': 0},
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

  void _loadBlockedPlayers(SharedPreferences prefs) {
    final raw = prefs.getString(_keyBlockedPlayers);
    if (raw == null) return;
    try {
      (jsonDecode(raw) as Map<String, dynamic>).forEach((k, v) {
        final t = DateTime.parse(v as String);
        if (t.isAfter(DateTime.now())) _blockedPlayers[k] = t;
      });
    } catch (_) {}
  }

  Future<void> _saveBlockedPlayers() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _blockedPlayers.map((k, v) => MapEntry(k, v.toIso8601String()));
    await prefs.setString(_keyBlockedPlayers, jsonEncode(data));
  }

  // ── Public setters ───────────────────────────────────────────────────────

  Future<void> setUsername(String name) async {
    final t = name.trim();
    if (t.isEmpty) return;
    _myUsername = t;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUsername, t);
    notifyListeners();
    if (_isAdvertising) { await stopAdvertising(); await startAdvertising(); }
  }

  Future<void> setDarkMode(bool value) async {
    _isDarkMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDarkMode, value);
    notifyListeners();
  }

  Future<void> setBotDifficulty(String d) async {
    if (!['einfach', 'mittel', 'schwer'].contains(d)) return;
    _botDifficulty = d;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBotDifficulty, d);
    notifyListeners();
  }

  Future<void> setConnectivityMode(AppConnectivityMode _) async => notifyListeners();

  // ─────────────────────────────────────────────────────────────────────────
  // Known Players
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _registerKnownPlayer(AppPeer peer) async {
    if (peer.isMock) return;
    _knownPlayers.removeWhere((p) => p['id'] == peer.id);
    _knownPlayers.insert(0, {'id': peer.id, 'name': peer.name});
    if (_knownPlayers.length > 10) _knownPlayers = _knownPlayers.sublist(0, 10);
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
    _knownPlayers.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyKnownPlayers);
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Statistics
  // ─────────────────────────────────────────────────────────────────────────

  void incrementWin(String gameId) {
    final key = (_connectedPeer?.isMock ?? true) ? 'wins_vs_bot' : 'wins_vs_player';
    _gameStats.putIfAbsent(gameId, _defaultStatMap);
    _gameStats[gameId]![key] = (_gameStats[gameId]![key] ?? 0) + 1;
    _gameStats[gameId]!['play_count'] = (_gameStats[gameId]!['play_count'] ?? 0) + 1;
    _saveStats(); notifyListeners();
  }

  void incrementLoss(String gameId) {
    final key = (_connectedPeer?.isMock ?? true) ? 'losses_vs_bot' : 'losses_vs_player';
    _gameStats.putIfAbsent(gameId, _defaultStatMap);
    _gameStats[gameId]![key] = (_gameStats[gameId]![key] ?? 0) + 1;
    _gameStats[gameId]!['play_count'] = (_gameStats[gameId]!['play_count'] ?? 0) + 1;
    _saveStats(); notifyListeners();
  }

  Map<String, int> _defaultStatMap() =>
      {'wins_vs_bot': 0, 'losses_vs_bot': 0, 'wins_vs_player': 0, 'losses_vs_player': 0, 'play_count': 0};

  void _updatePlayTime() {
    if (_gameStartTime == null) return;
    _totalPlayTimeSeconds += DateTime.now().difference(_gameStartTime!).inSeconds;
    _savePlayTime();
    _gameStartTime = null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Blocking
  // ─────────────────────────────────────────────────────────────────────────

  void blockPlayer(String id) {
    _blockedPlayers[id] = DateTime.now().add(const Duration(minutes: 10));
    _saveBlockedPlayers();
    notifyListeners();
    if (_connectedPeer?.id == id) disconnect();
  }

  void unblockPlayer(String id) {
    _blockedPlayers.remove(id);
    _saveBlockedPlayers();
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Advertising & Scanning
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> startAdvertising() async {
    if (_isAdvertising) return;
    _isAdvertising = true;
    _isHost = true;
    _discoveredPeers = [];
    notifyListeners();

    try { await _nearbyService?.startAdvertisingPeer(); } catch (e) {
      debugPrint('startAdvertising error: $e');
    }

    // After 5 s without a real connection: show the bot invite dialog
    _advertiserBotTimer?.cancel();
    _advertiserBotTimer = Timer(const Duration(seconds: 5), () {
      if (!_isAdvertising || isConnected) return;
      const mockId   = 'mock_bot';
      const mockName = '2Play Bot';

      // Add bot to discovered peers so the list shows it
      final botPeer = AppPeer(
        id: mockId, name: mockName, state: PeerState.notConnected, isMock: true,
      );
      if (!_discoveredPeers.any((p) => p.id == mockId)) {
        _discoveredPeers = [botPeer];
      }
      _showMockBots = true;
      notifyListeners();

      // Emit invite request event → LobbyScreen will show the dialog
      _msgCtrl.add({
        'type': 'simulated_invite_request',
        'peer': {'id': mockId, 'name': mockName},
      });
    });
  }

  Future<void> stopAdvertising() async {
    if (!_isAdvertising) return;
    _isAdvertising = false;
    _advertiserBotTimer?.cancel();
    _showMockBots = false;
    notifyListeners();
    try { await _nearbyService?.stopAdvertisingPeer(); } catch (e) {
      debugPrint('stopAdvertising error: $e');
    }
  }

  Future<void> startScanning() async {
    if (_isScanning) return;
    _isScanning = true;
    _discoveredPeers = [];
    _showMockBots = false;
    notifyListeners();

    // After 4 s with no real peers: show single bot
    _botTimer?.cancel();
    _botTimer = Timer(const Duration(seconds: 4), () {
      if (!_isScanning || isConnected) return;
      if (_discoveredPeers.where((p) => !p.isMock).isEmpty) {
        _showMockBots = true;
        notifyListeners();
      }
    });

    try { await _nearbyService?.startBrowsingForPeers(); } catch (e) {
      debugPrint('startScanning error: $e');
    }
  }

  Future<void> stopScanning() async {
    if (!_isScanning) return;
    _isScanning = false;
    _botTimer?.cancel();
    notifyListeners();
    try { await _nearbyService?.stopBrowsingForPeers(); } catch (e) {
      debugPrint('stopScanning error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Connection Actions
  // ─────────────────────────────────────────────────────────────────────────

  /// Scanner (client) taps "Verbinden".
  Future<void> invitePeer(AppPeer peer) async {
    if (isConnected) return; // already connected
    _isHost = false;
    _updatePeerState(peer.id, PeerState.connecting);
    notifyListeners();

    if (peer.isMock) {
      // Against the bot the local player is always the host: the bot only
      // ever reacts to moves, so the human must be the first mover in every
      // game (otherwise TicTacToe/Connect4/Battleship/Minigolf deadlock).
      _isHost = true;
      Timer(const Duration(milliseconds: 800), () {
        if (isConnected) return; // already connected by other means
        _connectedPeer = peer.copyWith(state: PeerState.connected);
        _discoveredPeers = [_connectedPeer!];
        stopScanning();
        notifyListeners();
      });
    } else {
      try {
        await _nearbyService?.invitePeer(deviceID: peer.id, deviceName: peer.name);
      } catch (e) {
        debugPrint('invitePeer error: $e');
        _updatePeerState(peer.id, PeerState.notConnected);
        notifyListeners();
      }
    }
  }

  /// Advertiser (host) accepts incoming invite.
  Future<void> acceptInvite(AppPeer peer) async {
    if (isConnected) return;
    _isHost = true;
    _updatePeerState(peer.id, PeerState.connecting);
    notifyListeners();

    if (peer.isMock) {
      // Simulate bot connection
      Timer(const Duration(milliseconds: 800), () {
        if (isConnected) return;
        _connectedPeer = peer.copyWith(state: PeerState.connected);
        _discoveredPeers = [_connectedPeer!];
        stopAdvertising();
        notifyListeners();
      });
    } else {
      try {
        await _nearbyService?.invitePeer(deviceID: peer.id, deviceName: peer.name);
      } catch (e) {
        debugPrint('acceptInvite error: $e');
        _updatePeerState(peer.id, PeerState.notConnected);
        notifyListeners();
      }
    }
  }

  /// Advertiser declines an incoming invite (real peer only).
  void declineInvite(AppPeer peer) {
    _updatePeerState(peer.id, PeerState.notConnected);
    // Try to send the decline signal — connection may not be fully established yet
    try {
      _nearbyService?.sendMessage(peer.id, jsonEncode({'type': 'invite_declined'}));
    } catch (_) {}
    notifyListeners();
  }

  /// Advertiser blocks an incoming inviter.
  void blockInvitingPeer(AppPeer peer) {
    blockPlayer(peer.id);
    try {
      _nearbyService?.sendMessage(peer.id, jsonEncode({'type': 'invite_blocked'}));
    } catch (_) {}
    notifyListeners();
  }

  Future<void> disconnect() async {
    _updatePlayTime();
    _verifyTimeoutTimer?.cancel();

    final peer   = _connectedPeer;
    if (peer == null) return;

    if (!peer.isMock) {
      try { await _nearbyService?.disconnectPeer(deviceID: peer.id); } catch (_) {}
    }

    _connectedPeer  = null;
    _activeGameId   = null;
    _suggestedGameId = null;
    _chatMessages.clear();
    _unreadChatCount = 0;
    _resetHandshake();
    _updatePeerState(peer.id, PeerState.notConnected);
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PIN Verification Handshake
  // ─────────────────────────────────────────────────────────────────────────

  void _resetHandshake() {
    _handshakeState = _HandshakeState.idle;
    _isVerifying    = false;
    _verificationPin = null;
    _pinError        = false;
    _pinErrorMessage = null;
    _verifyTimeoutTimer?.cancel();
  }

  /// Sends our handshake as soon as a real P2P connection is established.
  void _initiateHandshake() {
    if (_connectedPeer == null || _connectedPeer!.isMock) return;
    _resetHandshake();
    _handshakeState = _HandshakeState.sent;
    _sendRaw(_connectedPeer!.id, {
      'type':    'handshake',
      'username': _myUsername,
      'isKnown': isKnownPlayer(_connectedPeer!.id),
    });
  }

  void _handleHandshake(Map<String, dynamic> payload) {
    final peerName    = payload['username'] as String? ?? 'Gegner';
    final isPeerKnown = payload['isKnown']  as bool?   ?? false;

    // Update peer name
    if (_connectedPeer != null) {
      _connectedPeer = _connectedPeer!.copyWith(name: peerName);
    }

    final weKnowThem    = _connectedPeer != null && isKnownPlayer(_connectedPeer!.id);
    final mutuallyKnown = weKnowThem && isPeerKnown;

    // If we haven't sent our handshake yet (we received first), send it now
    if (_handshakeState == _HandshakeState.idle) {
      _handshakeState = _HandshakeState.sent;
      _sendRaw(_connectedPeer!.id, {
        'type':    'handshake',
        'username': _myUsername,
        'isKnown': weKnowThem,
      });
    }
    _handshakeState = _HandshakeState.complete;

    if (mutuallyKnown) {
      // Both know each other → skip PIN
      _isVerifying = false;
      _registerKnownPlayer(_connectedPeer!);
    } else {
      _isVerifying = true;
      if (_isHost) {
        // Host generates a 4-digit PIN
        _verificationPin = _rng.nextInt(9000) + 1000;
        _verifyTimeoutTimer?.cancel();
        _verifyTimeoutTimer = Timer(const Duration(seconds: 90), () {
          if (_isVerifying) disconnect();
        });
      }
    }
    notifyListeners();
  }

  /// Called by the GUEST after reading the PIN from the host's screen.
  void verifyCode(int pin) {
    if (_isHost) {
      // Shouldn't be called on host, but handle defensively
      _handlePinResult(pin == _verificationPin);
    } else {
      // Send PIN to host for verification
      sendPayload({'type': 'pin_submit', 'pin': pin});
    }
  }

  void _handlePinResult(bool correct) {
    if (correct) {
      _isVerifying = false;
      _verifyTimeoutTimer?.cancel();
      if (_connectedPeer != null) _registerKnownPlayer(_connectedPeer!);
      sendPayload({'type': 'pin_success'});
    } else {
      _pinError        = true;
      _pinErrorMessage = 'Falscher PIN – bitte erneut versuchen.';
      sendPayload({'type': 'pin_fail', 'message': _pinErrorMessage});
    }
    notifyListeners();
  }

  void _handlePinSubmit(Map<String, dynamic> payload) {
    if (!_isHost) return;
    final raw = payload['pin'];
    final pin = raw is int ? raw : int.tryParse('$raw');
    _handlePinResult(pin != null && pin == _verificationPin);
  }

  void clearPinError() {
    _pinError        = false;
    _pinErrorMessage = null;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Game Selection / Sync
  // ─────────────────────────────────────────────────────────────────────────

  void selectGame(String gameId) {
    _activeGameId    = gameId;
    _suggestedGameId = null;
    _gameStartTime   = DateTime.now();
    notifyListeners();
    sendPayload({'type': 'game_select', 'gameId': gameId});
  }

  void suggestGame(String gameId) {
    _suggestedGameId = gameId;
    notifyListeners();
    sendPayload({'type': 'game_suggest', 'gameId': gameId});
  }

  void exitGame() {
    _updatePlayTime();
    _activeGameId    = null;
    _suggestedGameId = null;
    notifyListeners();
    sendPayload({'type': 'game_exit'});
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Chat
  // ─────────────────────────────────────────────────────────────────────────

  void sendChatMessage(String text) {
    if (!isConnected) return;
    _chatMessages.add(ChatMessage(
      senderName: _myUsername, text: text, timestamp: DateTime.now(), isMe: true,
    ));
    notifyListeners();
    sendPayload({'type': 'chat_message', 'senderName': _myUsername, 'text': text});
  }

  void clearUnreadChatCount() {
    _unreadChatCount = 0;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Payload Sending
  // ─────────────────────────────────────────────────────────────────────────

  void sendPayload(Map<String, dynamic> payload) {
    if (!isConnected) return;
    if (_connectedPeer != null && !_connectedPeer!.isMock) {
      _sendRaw(_connectedPeer!.id, payload);
    } else {
      _handleSimulatedMessage(payload);
    }
  }

  void _sendRaw(String deviceId, Map<String, dynamic> payload) {
    try {
      _nearbyService?.sendMessage(deviceId, jsonEncode(payload));
    } catch (e) {
      debugPrint('sendRaw error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Real P2P Plugin
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _initPlugin() async {
    if (_pluginInitialized) return;
    try {
      _nearbyService = NearbyService();
      await _nearbyService!.init(
        serviceType: 'mp-connection',
        deviceName:  _myUsername,
        strategy:    Strategy.P2P_CLUSTER,
        callback:    (running) => debugPrint('NearbyService running=$running'),
      );

      _subState = _nearbyService!.stateChangedSubscription(callback: (devices) {
        final realDevices = devices.map((d) {
          final state = d.state == SessionState.connected
              ? PeerState.connected
              : (d.state == SessionState.connecting ? PeerState.connecting : PeerState.notConnected);
          return AppPeer(id: d.deviceId, name: d.deviceName, state: state);
        }).toList();

        // Merge real devices with any existing mocks
        final mocks = _discoveredPeers.where((p) => p.isMock).toList();
        _discoveredPeers = realDevices.isNotEmpty ? realDevices : [...realDevices, ...mocks];
        if (realDevices.isNotEmpty) _showMockBots = false;

        final connected = realDevices.firstWhere(
          (p) => p.state == PeerState.connected,
          orElse: () => const AppPeer(id: '', name: '', state: PeerState.notConnected),
        );

        if (connected.id.isNotEmpty) {
          final alreadyConnected = _connectedPeer?.state == PeerState.connected
              && _connectedPeer?.id == connected.id;
          _connectedPeer = connected;
          if (!alreadyConnected) {
            _isHost = _isAdvertising;
            _initiateHandshake();
          }
        } else if (_connectedPeer != null && !_connectedPeer!.isMock) {
          _connectedPeer = null;
          _activeGameId  = null;
          _updatePlayTime();
          _resetHandshake();
        }

        notifyListeners();
      });

      _subData = _nearbyService!.dataReceivedSubscription(callback: (data) {
        try {
          final msg = jsonDecode(data['message'] as String) as Map<String, dynamic>;
          _handleIncomingPayload(msg);
        } catch (e) {
          debugPrint('data parse error: $e  raw=$data');
        }
      });

      _pluginInitialized = true;
    } catch (e) {
      debugPrint('Plugin init failed: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Incoming Payload Handling
  // ─────────────────────────────────────────────────────────────────────────

  void _handleIncomingPayload(Map<String, dynamic> payload) {
    final type = payload['type'] as String?;

    switch (type) {
      case 'handshake':
        _handleHandshake(payload);
        return; // don't forward to UI stream

      case 'pin_submit':
        _handlePinSubmit(payload);
        return;

      case 'pin_success':
        _isVerifying = false;
        _verifyTimeoutTimer?.cancel();
        if (_connectedPeer != null) _registerKnownPlayer(_connectedPeer!);
        notifyListeners();
        return;

      case 'pin_fail':
        _pinError        = true;
        _pinErrorMessage = payload['message'] as String? ?? 'Falscher PIN.';
        notifyListeners();
        return;

      case 'invite_declined':
        _msgCtrl.add({'type': 'invite_declined'});
        if (_connectedPeer != null) _updatePeerState(_connectedPeer!.id, PeerState.notConnected);
        notifyListeners();
        return;

      case 'invite_blocked':
        _msgCtrl.add({'type': 'invite_blocked'});
        if (_connectedPeer != null) _updatePeerState(_connectedPeer!.id, PeerState.notConnected);
        notifyListeners();
        return;

      case 'game_select':
        _activeGameId    = payload['gameId'] as String?;
        _suggestedGameId = null;
        _gameStartTime   = DateTime.now();
        notifyListeners();
        break;

      case 'game_exit':
        _updatePlayTime();
        _activeGameId    = null;
        _suggestedGameId = null;
        notifyListeners();
        break;

      case 'game_suggest':
        _suggestedGameId = payload['gameId'] as String?;
        notifyListeners();
        break;

      case 'chat_message':
        _chatMessages.add(ChatMessage(
          senderName: payload['senderName'] as String? ?? 'Gegner',
          text:       payload['text']       as String? ?? '',
          timestamp:  DateTime.now(),
          isMe:       false,
        ));
        _unreadChatCount++;
        notifyListeners();
        break;
    }

    // Forward everything to listening screens
    _msgCtrl.add(payload);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Simulated Bot AI
  // ─────────────────────────────────────────────────────────────────────────

  void _handleSimulatedMessage(Map<String, dynamic> payload) {
    final type = payload['type'] as String?;

    switch (type) {
      case 'game_select':
        _handleIncomingPayload(payload);
        break;

      case 'game_exit':
        // Update state directly instead of echoing the payload back through
        // the message stream – the sending screen already popped itself and
        // an echoed 'game_exit' would pop a second (wrong) route.
        _updatePlayTime();
        _activeGameId    = null;
        _suggestedGameId = null;
        notifyListeners();
        break;

      case 'game_suggest':
        _handleIncomingPayload(payload);
        // Bot auto-accepts game suggestion after a short delay
        Timer(const Duration(milliseconds: 1200), () {
          if (!isConnected || _activeGameId != null) return;
          selectGame(payload['gameId'] as String);
        });
        break;

      case 'game_move':
        Timer(Duration(milliseconds: 600 + _rng.nextInt(600)), () {
          if (!isConnected) return;
          final resp = _generateBotResponse(payload);
          if (resp != null) _handleIncomingPayload(resp);
        });
        break;

      case 'game_reset':
        Timer(const Duration(milliseconds: 500), () {
          _handleIncomingPayload({'type': 'game_reset_accept', 'gameId': payload['gameId']});
        });
        break;

      case 'chat_message':
        Timer(Duration(seconds: 1 + _rng.nextInt(2)), () {
          if (!isConnected) return;
          const replies = [
            'Gutes Spiel!', 'Das war knapp!', 'Nett versucht!',
            'Bereit für die nächste Runde?', 'Wow, du spielst echt gut!',
            'Gleich habe ich dich!', 'Spielen wir danach noch was anderes?',
          ];
          _handleIncomingPayload({
            'type':       'chat_message',
            'senderName': _connectedPeer?.name ?? '2Play Bot',
            'text':       replies[_rng.nextInt(replies.length)],
          });
        });
        break;
    }
  }

  Map<String, dynamic>? _generateBotResponse(Map<String, dynamic> move) {
    final gameId   = move['gameId']  as String?;
    final moveData = move['data']    as Map<String, dynamic>?;
    if (moveData == null) return null;

    final roll      = _rng.nextDouble();
    final threshold = _botDifficulty == 'einfach' ? 0.60 : (_botDifficulty == 'mittel' ? 0.30 : 0.0);

    switch (gameId) {
      case 'tictactoe':         return _botTicTacToe(moveData, roll, threshold);
      case 'connect4':          return _botConnect4(moveData, roll, threshold);
      case 'battleship':        return _botBattleship(moveData, roll, threshold);
      case 'rockpaperscissors': return _botRPS(moveData, roll, threshold);
      default: return null;
    }
  }

  // ── TicTacToe ────────────────────────────────────────────────────────────

  Map<String, dynamic>? _botTicTacToe(Map<String, dynamic> d, double roll, double threshold) {
    final board = List<String>.from(d['board']);
    final aiSym = d['playerSymbol'] == 'X' ? 'O' : 'X';
    int best = -1;

    if (roll < threshold) {
      final empty = [for (int i = 0; i < 9; i++) if (board[i].isEmpty) i];
      if (empty.isNotEmpty) best = empty[_rng.nextInt(empty.length)];
    } else {
      best = _tttWinMove(board, aiSym);
      if (best == -1) best = _tttWinMove(board, d['playerSymbol']);
      if (best == -1 && board[4].isEmpty) best = 4;
      if (best == -1) {
        final empty = [for (int i = 0; i < 9; i++) if (board[i].isEmpty) i];
        if (empty.isNotEmpty) best = empty[_rng.nextInt(empty.length)];
      }
    }
    if (best == -1) return null;
    board[best] = aiSym;
    return {
      'type': 'game_move', 'gameId': 'tictactoe',
      'data': {'board': board, 'lastMoveIndex': best, 'nextTurn': d['playerSymbol']},
    };
  }

  int _tttWinMove(List<String> board, String sym) {
    const lines = [[0,1,2],[3,4,5],[6,7,8],[0,3,6],[1,4,7],[2,5,8],[0,4,8],[2,4,6]];
    for (final l in lines) {
      int cnt = 0, empty = -1;
      for (final i in l) {
        if (board[i] == sym) {
          cnt++;
        } else if (board[i].isEmpty) {
          empty = i;
        }
      }
      if (cnt == 2 && empty != -1) return empty;
    }
    return -1;
  }

  // ── Connect4 ─────────────────────────────────────────────────────────────

  Map<String, dynamic>? _botConnect4(Map<String, dynamic> d, double roll, double threshold) {
    final board = (d['board'] as List).map((c) => List<int>.from(c)).toList();
    const ai = 2, user = 1;
    int bestCol = -1;

    if (roll < threshold) {
      final valid = [for (int c = 0; c < 7; c++) if (_c4CanPlay(board, c)) c];
      if (valid.isNotEmpty) bestCol = valid[_rng.nextInt(valid.length)];
    } else {
      for (int c = 0; c < 7 && bestCol == -1; c++) {
        if (_c4CanPlay(board, c) && _c4CheckWin(_c4Play(board, c, ai), ai)) bestCol = c;
      }
      for (int c = 0; c < 7 && bestCol == -1; c++) {
        if (_c4CanPlay(board, c) && _c4CheckWin(_c4Play(board, c, user), user)) bestCol = c;
      }
      if (bestCol == -1) {
        for (final c in [3, 2, 4, 1, 5, 0, 6]) {
          if (_c4CanPlay(board, c)) { bestCol = c; break; }
        }
      }
    }
    if (bestCol == -1) return null;

    int rowPlayed = -1;
    for (int r = 5; r >= 0; r--) {
      if (board[bestCol][r] == 0) { board[bestCol][r] = ai; rowPlayed = r; break; }
    }
    return {
      'type': 'game_move', 'gameId': 'connect4',
      'data': {'board': board, 'playedCol': bestCol, 'playedRow': rowPlayed, 'nextTurn': user},
    };
  }

  bool _c4CanPlay(List<List<int>> b, int c) => b[c][0] == 0;

  List<List<int>> _c4Play(List<List<int>> b, int col, int p) {
    final copy = b.map((c) => List<int>.from(c)).toList();
    for (int r = 5; r >= 0; r--) { if (copy[col][r] == 0) { copy[col][r] = p; break; } }
    return copy;
  }

  bool _c4CheckWin(List<List<int>> b, int p) {
    // Horizontal
    for (int r = 0; r < 6; r++) {
      for (int c = 0; c < 4; c++) {
        if (b[c][r]==p && b[c+1][r]==p && b[c+2][r]==p && b[c+3][r]==p) {
          return true;
        }
      }
    }
    // Vertical
    for (int c = 0; c < 7; c++) {
      for (int r = 0; r < 3; r++) {
        if (b[c][r]==p && b[c][r+1]==p && b[c][r+2]==p && b[c][r+3]==p) {
          return true;
        }
      }
    }
    // Diagonal /
    for (int c = 0; c < 4; c++) {
      for (int r = 3; r < 6; r++) {
        if (b[c][r]==p && b[c+1][r-1]==p && b[c+2][r-2]==p && b[c+3][r-3]==p) {
          return true;
        }
      }
    }
    // Diagonal \
    for (int c = 0; c < 4; c++) {
      for (int r = 0; r < 3; r++) {
        if (b[c][r]==p && b[c+1][r+1]==p && b[c+2][r+2]==p && b[c+3][r+3]==p) {
          return true;
        }
      }
    }
    return false;
  }

  // ── Battleship ───────────────────────────────────────────────────────────

  Map<String, dynamic>? _botBattleship(Map<String, dynamic> d, double roll, double threshold) {
    final sub = d['subtype'] as String?;

    if (sub == 'player_ready') {
      return {
        'type': 'game_move', 'gameId': 'battleship',
        'data': {'subtype': 'ai_ready', 'aiBoard': _genBattleshipBoard()},
      };
    }
    if (sub == 'fire') {
      final fleet = (d['userBoard'] as List).map((r) => List<int>.from(r)).toList();
      int tx = -1, ty = -1;

      if (roll >= threshold) {
        outer:
        for (int r = 0; r < 10; r++) {
          for (int c = 0; c < 10; c++) {
            if (fleet[r][c] == 2) {
              for (final adj in [[-1,0],[1,0],[0,-1],[0,1]]) {
                final ar = r+adj[0], ac = c+adj[1];
                if (ar >= 0 && ar < 10 && ac >= 0 && ac < 10
                    && (fleet[ar][ac] == 0 || fleet[ar][ac] == 1)) {
                  ty = ar; tx = ac; break outer;
                }
              }
            }
          }
        }
      }

      if (tx == -1) {
        final pts = [
          for (int r = 0; r < 10; r++)
            for (int c = 0; c < 10; c++)
              if (fleet[r][c] == 0 || fleet[r][c] == 1) [c, r],
        ];
        if (pts.isEmpty) return null;
        final pt = pts[_rng.nextInt(pts.length)];
        tx = pt[0]; ty = pt[1];
      }

      final hit = fleet[ty][tx] == 1;
      fleet[ty][tx] = hit ? 2 : 3;
      return {
        'type': 'game_move', 'gameId': 'battleship',
        'data': {'subtype': 'ai_fire', 'targetX': tx, 'targetY': ty, 'isHit': hit, 'userBoard': fleet},
      };
    }
    return null;
  }

  List<List<int>> _genBattleshipBoard() {
    final board = List.generate(10, (_) => List.filled(10, 0));
    for (final size in [5, 4, 3, 3, 2]) {
      bool placed = false;
      while (!placed) {
        final horiz = _rng.nextBool();
        final x = _rng.nextInt(10), y = _rng.nextInt(10);
        if (horiz && x + size <= 10) {
          if ([for (int i = 0; i < size; i++) board[y][x+i]].every((v) => v == 0)) {
            for (int i = 0; i < size; i++) {
              board[y][x+i] = 1;
            }
            placed = true;
          }
        } else if (!horiz && y + size <= 10) {
          if ([for (int i = 0; i < size; i++) board[y+i][x]].every((v) => v == 0)) {
            for (int i = 0; i < size; i++) {
              board[y+i][x] = 1;
            }
            placed = true;
          }
        }
      }
    }
    return board;
  }

  // ── RockPaperScissors ────────────────────────────────────────────────────

  Map<String, dynamic> _botRPS(Map<String, dynamic> d, double roll, double threshold) {
    const choices = ['rock', 'paper', 'scissors'];
    final user = d['userChoice'] as String;
    String ai;

    if (roll < threshold) {
      // Random / sometimes lose intentionally
      ai = _rng.nextBool()
          ? (user == 'rock' ? 'scissors' : user == 'paper' ? 'rock' : 'paper')
          : choices[_rng.nextInt(3)];
    } else {
      // Win 75 % of the time
      ai = _rng.nextDouble() < 0.75
          ? (user == 'rock' ? 'paper' : user == 'paper' ? 'scissors' : 'rock')
          : choices[_rng.nextInt(3)];
    }
    return {
      'type': 'game_move', 'gameId': 'rockpaperscissors',
      'data': {'aiChoice': ai, 'userChoice': user},
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helper
  // ─────────────────────────────────────────────────────────────────────────

  void _updatePeerState(String id, PeerState state) {
    final idx = _discoveredPeers.indexWhere((p) => p.id == id);
    if (idx != -1) _discoveredPeers[idx] = _discoveredPeers[idx].copyWith(state: state);
    if (_connectedPeer?.id == id) _connectedPeer = _connectedPeer!.copyWith(state: state);
  }
}
