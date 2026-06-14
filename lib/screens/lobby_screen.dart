import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';
import 'game_selection_screen.dart';
import 'settings_screen.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  StreamSubscription? _msgSubscription;
  bool _hasNavigated = false;
  String _enteredPin = '';

  @override
  void initState() {
    super.initState();
    _listenToInvitations();
  }

  void _listenToInvitations() {
    final connService = Provider.of<ConnectivityService>(context, listen: false);
    _msgSubscription = connService.messageStream.listen((payload) {
      if (payload['type'] == 'simulated_invite_request') {
        final peerData = payload['peer'] as Map<String, dynamic>;
        _showInviteDialog(
          AppPeer(
            id: peerData['id'],
            name: peerData['name'],
            state: PeerState.connecting,
            isMock: true,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _msgSubscription?.cancel();
    super.dispose();
  }

  void _showInviteDialog(AppPeer peer) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: Colors.transparent,
          contentPadding: EdgeInsets.zero,
          content: GlassContainer(
            padding: const EdgeInsets.all(24),
            borderRadius: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.sports_esports_rounded,
                  size: 48,
                  color: Color(0xFF00F2FE),
                ).animate().scaleXY(begin: 0.8, end: 1.2, duration: 800.ms, curve: Curves.bounceOut),
                const SizedBox(height: 16),
                Text(
                  'Spiel-Einladung',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 22),
                ),
                const SizedBox(height: 8),
                Text(
                  '${peer.name} möchte sich mit dir verbinden und spielen!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black87,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                      },
                      child: Text(
                        'Ablehnen',
                        style: TextStyle(
                          color: isDark ? Colors.white60 : Colors.black54,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8A2387),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        Provider.of<ConnectivityService>(context, listen: false).acceptInvite(peer);
                      },
                      child: const Text('Akzeptieren'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showStatsDialog(ConnectivityService connService) {
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: Colors.transparent,
          contentPadding: EdgeInsets.zero,
          content: GlassContainer(
            padding: const EdgeInsets.all(24),
            borderRadius: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Statistiken',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 22),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: isDark ? Colors.white70 : Colors.black87),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Online-Zeit', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text(
                          '${(connService.totalPlayTimeSeconds / 3600).toStringAsFixed(1)} Std',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Lieblingsspiel', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text(
                          connService.favoriteGame,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
                const Divider(height: 32, thickness: 1),
                const Text(
                  'Spiel-Statistiken:',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                for (var entry in connService.gameStats.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          entry.key == 'tictactoe'
                              ? 'Tic-Tac-Toe'
                              : (entry.key == 'connect4'
                                  ? 'Vier Gewinnt'
                                  : (entry.key == 'battleship'
                                      ? 'Schiffe Versenken'
                                      : (entry.key == 'rockpaperscissors'
                                          ? 'Schere, Stein, Papier'
                                          : 'Minigolf'))),
                          style: const TextStyle(fontSize: 13),
                        ),
                        Text(
                          'Siege: ${entry.value['wins_vs_bot']! + entry.value['wins_vs_player']!} | Niederlagen: ${entry.value['losses_vs_bot']! + entry.value['losses_vs_player']!}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPeerOptions(ConnectivityService service, AppPeer peer) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return GlassContainer(
          borderRadius: 24,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                peer.name,
                style: TextStyle(
                  fontSize: 18, 
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppTheme.darkBg,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.play_arrow_rounded, color: Color(0xFF00F2FE)),
                title: Text('Spielen', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.darkBg)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  if (service.isScanning) {
                    service.invitePeer(peer);
                  } else {
                    service.acceptInvite(peer);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.block_rounded, color: Color(0xFFFF007F)),
                title: Text('Blockieren (10 Min)', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.darkBg)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  service.blockPlayer(peer.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${peer.name} wurde für 10 Minuten blockiert.')),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.close_rounded, color: isDark ? Colors.white70 : Colors.black54),
                title: Text('Abbrechen', style: TextStyle(color: isDark ? Colors.white : AppTheme.darkBg)),
                onTap: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildKnownPlayersSection(ConnectivityService connService, bool isDark) {
    if (connService.knownPlayers.isEmpty) return const SizedBox();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'BEKANNTE SPIELER',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
            color: isDark ? Colors.white60 : Colors.grey[700],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: connService.knownPlayers.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final player = connService.knownPlayers[index];
              final name = player['name'] ?? 'Spieler';
              final peerId = player['id'] ?? '';
              
              final onlinePeer = connService.discoveredPeers.firstWhere(
                (p) => p.id == peerId || p.name == name,
                orElse: () => AppPeer(id: '', name: '', state: PeerState.notConnected),
              );
              final isOnline = onlinePeer.id.isNotEmpty;

              return GestureDetector(
                onTap: isOnline ? () => _showPeerOptions(connService, onlinePeer) : null,
                child: Container(
                  width: 130,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isOnline 
                          ? const Color(0xFF39FF14) 
                          : (isDark ? const Color(0xFF1F2937) : const Color(0xFFE5E7EB)),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: isOnline ? const Color(0xFF39FF14).withOpacity(0.2) : Colors.grey.withOpacity(0.2),
                        child: Icon(
                          Icons.person_rounded,
                          size: 14,
                          color: isOnline ? const Color(0xFF39FF14) : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              isOnline ? 'Online' : 'Offline',
                              style: TextStyle(
                                fontSize: 9,
                                color: isOnline ? const Color(0xFF39FF14) : Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final connService = Provider.of<ConnectivityService>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!connService.isVerifying && _enteredPin.isNotEmpty) {
      _enteredPin = '';
    }

    if (connService.isConnected && !_hasNavigated && !connService.isVerifying) {
      _hasNavigated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const GameSelectionScreen()),
        ).then((_) {
          _hasNavigated = false;
        });
      });
    }

    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: isDark
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF0F0B1E), Color(0xFF160E2C), Color(0xFF0F0B1E)],
                    )
                  : const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFF0F4FA), Color(0xFFE2E9F3), Color(0xFFF7F8FC)],
                    ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: isLandscape
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 4,
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 12),
                                  _buildHeader(connService, isDark),
                                  const SizedBox(height: 24),
                                  Text(
                                    'Spiel-Lobby',
                                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                          fontSize: 28,
                                          fontWeight: FontWeight.w900,
                                        ),
                                  ),
                                  const SizedBox(height: 20),
                                  _buildKnownPlayersSection(connService, isDark),
                                  const SizedBox(height: 12),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            flex: 5,
                            child: Column(
                              children: [
                                const SizedBox(height: 12),
                                _buildActionChoices(connService, isDark),
                                const SizedBox(height: 16),
                                _buildDevicesHeader(connService, isDark),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: _buildDevicesList(connService, isDark),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 12),
                          _buildHeader(connService, isDark).animate().fadeIn(duration: 500.ms),
                          const SizedBox(height: 24),
                          Text(
                            'Spiel-Lobby',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w900,
                                ),
                          ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1, end: 0),
                          const SizedBox(height: 24),
                          _buildActionChoices(connService, isDark).animate().fadeIn(delay: 300.ms),
                          const SizedBox(height: 24),
                          _buildKnownPlayersSection(connService, isDark),
                          const SizedBox(height: 24),
                          _buildDevicesHeader(connService, isDark).animate().fadeIn(delay: 400.ms),
                          const SizedBox(height: 16),
                          Expanded(
                            child: _buildDevicesList(connService, isDark),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          
          if (connService.isVerifying)
            _buildVerificationOverlay(connService, isDark),
        ],
      ),
    );
  }

  Widget _buildHeader(ConnectivityService connService, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: AppTheme.primaryGradient,
                ),
                boxShadow: isDark
                    ? AppTheme.neonGlow(const Color(0xFFE94057))
                    : AppTheme.softShadow,
              ),
              child: const Center(
                child: Icon(
                  Icons.person_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connService.myUsername,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Text(
                  'Eigene ID: Online',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
        Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.analytics_rounded,
                color: isDark ? Colors.white70 : Colors.black87,
                size: 28,
              ),
              onPressed: () => _showStatsDialog(connService),
            ),
            IconButton(
              icon: Icon(
                Icons.settings_rounded,
                color: isDark ? Colors.white70 : Colors.black87,
                size: 28,
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionChoices(ConnectivityService connService, bool isDark) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () {
              if (connService.isAdvertising) {
                connService.stopAdvertising();
              } else {
                connService.stopScanning();
                connService.startAdvertising();
              }
            },
            child: GlassContainer(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
              borderRadius: 20,
              gradientColors: connService.isAdvertising
                  ? AppTheme.primaryGradient
                  : null,
              child: Column(
                children: [
                  Icon(
                    Icons.wifi_tethering_rounded,
                    size: 32,
                    color: connService.isAdvertising
                        ? Colors.white
                        : (isDark ? const Color(0xFF8A2387) : Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Lobby erstellen',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: connService.isAdvertising ? Colors.white : (isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    connService.isAdvertising ? 'Sichtbar...' : 'Anderen beitreten lassen',
                    style: TextStyle(
                      fontSize: 10,
                      color: connService.isAdvertising ? Colors.white70 : Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () {
              if (connService.isScanning) {
                connService.stopScanning();
              } else {
                connService.stopAdvertising();
                connService.startScanning();
              }
            },
            child: GlassContainer(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
              borderRadius: 20,
              gradientColors: connService.isScanning
                  ? AppTheme.neonBlueGradient
                  : null,
              child: Column(
                children: [
                  Icon(
                    Icons.youtube_searched_for_rounded,
                    size: 32,
                    color: connService.isScanning
                        ? Colors.white
                        : (isDark ? const Color(0xFF00F2FE) : Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Lobby suchen',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: connService.isScanning ? Colors.white : (isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    connService.isScanning ? 'Suche läuft...' : 'Finde Lobbys in der Nähe',
                    style: TextStyle(
                      fontSize: 10,
                      color: connService.isScanning ? Colors.white70 : Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDevicesHeader(ConnectivityService connService, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'GERÄTE IN DER NÄHE',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
            color: isDark ? Colors.white60 : Colors.grey[700],
          ),
        ),
        if (connService.isScanning || connService.isAdvertising)
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
      ],
    );
  }

  Widget _buildDevicesList(ConnectivityService connService, bool isDark) {
    if (connService.discoveredPeers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.radar_rounded,
              size: 40,
              color: isDark ? Colors.white12 : Colors.black12,
            ),
            const SizedBox(height: 12),
            Text(
              connService.isScanning || connService.isAdvertising
                  ? 'Scanne nach Spielern...'
                  : 'Starte Suche oder erstelle eine Lobby,\num mit anderen zu spielen.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white30 : Colors.black38,
              ),
            ),
          ],
        ),
      ).animate().fadeIn();
    }

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      itemCount: connService.discoveredPeers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final peer = connService.discoveredPeers[index];
        final isKnown = connService.knownPlayers.any((p) => p['id'] == peer.id);

        return GestureDetector(
          onTap: () => _showPeerOptions(connService, peer),
          child: GlassContainer(
            borderRadius: 16,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            border: isKnown ? Border.all(color: const Color(0xFF39FF14), width: 1.5) : null,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
                  ),
                  child: Icon(
                    Icons.phone_iphone_rounded,
                    color: isDark ? Colors.white70 : Colors.black87,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              peer.name,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isKnown) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF39FF14).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Bekannt',
                                style: TextStyle(color: Color(0xFF39FF14), fontSize: 9, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        peer.state == PeerState.connecting
                            ? 'Verbinde...'
                            : 'Bereit zum Verbinden',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildPeerActionButton(connService, peer),
              ],
            ),
          ).animate().fadeIn().slideY(begin: 0.1, end: 0),
        );
      },
    );
  }

  Widget _buildPeerActionButton(ConnectivityService service, AppPeer peer) {
    if (peer.state == PeerState.connecting) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00F2FE)),
      );
    }

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF00F2FE).withOpacity(0.15),
        foregroundColor: const Color(0xFF00F2FE),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      onPressed: () => _showPeerOptions(service, peer),
      child: const Text(
        'Verbinden',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildVerificationOverlay(ConnectivityService connService, bool isDark) {
    final theme = Theme.of(context);
    final pinCode = connService.verificationPin;

    return Container(
      color: Colors.black.withOpacity(0.85),
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: GlassContainer(
              padding: const EdgeInsets.all(28),
              borderRadius: 24,
              child: connService.isHost
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.security_rounded,
                          size: 56,
                          color: Color(0xFF00F2FE),
                        ).animate().scaleXY(begin: 0.8, end: 1.2, duration: 1000.ms, curve: Curves.easeInOutBack),
                        const SizedBox(height: 16),
                        Text(
                          'Sicherheits-Verifizierung',
                          style: theme.textTheme.titleLarge?.copyWith(fontSize: 22, color: Colors.white),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Gib diesen Code deinem Spielpartner. Er muss ihn auf seinem Gerät eingeben.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Text(
                            pinCode != null ? pinCode.toString() : '----',
                            style: const TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 8,
                              color: Color(0xFF00F2FE),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white60,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Warte auf Partner...',
                          style: TextStyle(color: Colors.white54, fontSize: 11, fontStyle: FontStyle.italic),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () => connService.disconnect(),
                          child: const Text('Abbrechen', style: TextStyle(color: Colors.redAccent)),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.pin_rounded,
                          size: 56,
                          color: Color(0xFFFF007F),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'PIN Eingeben',
                          style: theme.textTheme.titleLarge?.copyWith(fontSize: 22, color: Colors.white),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Gib den 4-stelligen Verifizierungscode ein, der auf dem Gerät des Hosts angezeigt wird.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(4, (index) {
                            String char = '';
                            if (_enteredPin.length > index) {
                              char = _enteredPin[index];
                            }
                            return Container(
                              width: 50,
                              height: 60,
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _enteredPin.length == index
                                      ? const Color(0xFFFF007F)
                                      : (char.isNotEmpty ? Colors.white38 : Colors.white10),
                                  width: 2,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  char,
                                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              ),
                            );
                          }),
                        ),
                        if (connService.pinError) ...[
                          const SizedBox(height: 12),
                          Text(
                            connService.pinErrorMessage ?? 'Falscher PIN.',
                            style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                        const SizedBox(height: 24),
                        Column(
                          children: [
                            for (var row in [
                              ['1', '2', '3'],
                              ['4', '5', '6'],
                              ['7', '8', '9'],
                              ['clear', '0', 'backspace']
                            ])
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    for (var val in row)
                                      SizedBox(
                                        width: 70,
                                        height: 50,
                                        child: val == 'clear'
                                            ? IconButton(
                                                icon: const Icon(Icons.clear_rounded, color: Colors.white54),
                                                onPressed: () {
                                                  setState(() {
                                                    _enteredPin = '';
                                                  });
                                                  connService.clearPinError();
                                                },
                                              )
                                            : val == 'backspace'
                                                ? IconButton(
                                                    icon: const Icon(Icons.backspace_rounded, color: Colors.white54),
                                                    onPressed: () {
                                                      if (_enteredPin.isNotEmpty) {
                                                        setState(() {
                                                          _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
                                                        });
                                                        connService.clearPinError();
                                                      }
                                                    },
                                                  )
                                                : ElevatedButton(
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: Colors.white.withOpacity(0.08),
                                                      foregroundColor: Colors.white,
                                                      elevation: 0,
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                    ),
                                                    onPressed: () {
                                                      if (_enteredPin.length < 4) {
                                                        setState(() {
                                                          _enteredPin += val;
                                                        });
                                                        connService.clearPinError();
                                                        if (_enteredPin.length == 4) {
                                                          connService.verifyCode(int.parse(_enteredPin));
                                                        }
                                                      }
                                                    },
                                                    child: Text(
                                                      val,
                                                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _enteredPin = '';
                            });
                            connService.disconnect();
                          },
                          child: const Text('Verbindung trennen', style: TextStyle(color: Colors.redAccent)),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
