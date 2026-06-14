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

class _LobbyScreenState extends State<LobbyScreen> with SingleTickerProviderStateMixin {
  StreamSubscription? _msgSubscription;
  bool _hasNavigated = false;
  String _enteredPin = '';
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _listenToMessages();
  }

  void _listenToMessages() {
    final connService = Provider.of<ConnectivityService>(context, listen: false);
    _msgSubscription = connService.messageStream.listen((payload) {
      if (!mounted) return;
      final type = payload['type'] as String?;

      if (type == 'simulated_invite_request') {
        final peerData = payload['peer'] as Map<String, dynamic>;
        _showInviteDialog(
          AppPeer(
            id: peerData['id'] as String,
            name: peerData['name'] as String,
            state: PeerState.connecting,
            isMock: true,
          ),
        );
      } else if (type == 'invite_declined') {
        // The peer we invited declined our request
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.person_off_rounded, color: Colors.white),
                SizedBox(width: 8),
                Text('Anfrage wurde abgelehnt.'),
              ],
            ),
            backgroundColor: Color(0xFF444444),
            duration: Duration(seconds: 3),
          ),
        );
      } else if (type == 'invite_blocked') {
        // The peer blocked us
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.block_rounded, color: Colors.white),
                SizedBox(width: 8),
                Text('Du wurdest blockiert.'),
              ],
            ),
            backgroundColor: Color(0xFFB00020),
            duration: Duration(seconds: 3),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _msgSubscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Dialogs & Sheets
  // ---------------------------------------------------------------------------

  /// Shown on the ADVERTISER (host) side when a peer requests to connect.
  /// Real peers: Spielen / Blockieren / Ablehnen
  /// Mock bots: Spielen / Ablehnen
  void _showInviteDialog(AppPeer peer) {
    if (!mounted) return;
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
                // Bot icon vs person icon
                Icon(
                  peer.isMock ? Icons.smart_toy_rounded : Icons.sports_esports_rounded,
                  size: 52,
                  color: peer.isMock ? const Color(0xFFB44FFF) : const Color(0xFF00F2FE),
                ).animate().scaleXY(begin: 0.7, end: 1.0, duration: 500.ms, curve: Curves.elasticOut),
                const SizedBox(height: 16),
                Text(
                  'Spiel-Einladung',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 20),
                ),
                const SizedBox(height: 8),
                Text(
                  '${peer.name} möchte mit dir spielen!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black87,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                // SPIELEN button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: const Text('Spielen', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8A2387),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      Provider.of<ConnectivityService>(context, listen: false).acceptInvite(peer);
                    },
                  ),
                ),
                if (!peer.isMock) ...[
                  const SizedBox(height: 10),
                  // BLOCKIEREN button (only for real peers)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.block_rounded, size: 18, color: Color(0xFFFF4040)),
                      label: const Text(
                        'Blockieren (10 Min)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFFFF4040),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: Color(0xFFFF4040), width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        Provider.of<ConnectivityService>(context, listen: false)
                            .blockInvitingPeer(peer);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${peer.name} für 10 Minuten blockiert.'),
                            backgroundColor: const Color(0xFFB00020),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                // ABLEHNEN button
                TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    if (!peer.isMock) {
                      Provider.of<ConnectivityService>(context, listen: false).declineInvite(peer);
                    }
                  },
                  child: Text(
                    'Ablehnen',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black54,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Shown on the SCANNER (client) side – simple connect confirmation.
  void _showConnectConfirmDialog(ConnectivityService service, AppPeer peer) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: GlassContainer(
          padding: const EdgeInsets.all(24),
          borderRadius: 24,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                peer.isMock ? Icons.smart_toy_rounded : Icons.person_rounded,
                size: 48,
                color: peer.isMock ? const Color(0xFFB44FFF) : const Color(0xFF00F2FE),
              ),
              const SizedBox(height: 14),
              Text(
                'Mit ${peer.name} verbinden?',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(
                      'Abbrechen',
                      style: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00B4D8),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      service.invitePeer(peer);
                    },
                    child: const Text('Verbinden', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
                      icon: Icon(Icons.close_rounded,
                          color: isDark ? Colors.white70 : Colors.black87),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _statChip(
                      '${(connService.totalPlayTimeSeconds / 3600).toStringAsFixed(1)} Std',
                      'Online-Zeit',
                      Icons.timer_rounded,
                    ),
                    _statChip(
                      connService.favoriteGame,
                      'Lieblingsspiel',
                      Icons.favorite_rounded,
                    ),
                  ],
                ),
                const Divider(height: 32, thickness: 1),
                const Text(
                  'Spiel-Statistiken',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                for (var entry in connService.gameStats.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _gameDisplayName(entry.key),
                          style: const TextStyle(fontSize: 13),
                        ),
                        Text(
                          'S: ${(entry.value['wins_vs_bot'] ?? 0) + (entry.value['wins_vs_player'] ?? 0)}'
                          '  N: ${(entry.value['losses_vs_bot'] ?? 0) + (entry.value['losses_vs_player'] ?? 0)}',
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

  Widget _statChip(String value, String label, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(icon, size: 14, color: const Color(0xFF00F2FE)),
            const SizedBox(width: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }

  String _gameDisplayName(String key) {
    switch (key) {
      case 'tictactoe': return 'Tic-Tac-Toe';
      case 'connect4': return 'Vier Gewinnt';
      case 'battleship': return 'Schiffe Versenken';
      case 'rockpaperscissors': return 'Schere, Stein, Papier';
      case 'minigolf': return 'Minigolf';
      default: return key;
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final connService = Provider.of<ConnectivityService>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Reset PIN when verification ends
    if (!connService.isVerifying && _enteredPin.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _enteredPin = '');
      });
    }

    // Navigate to game selection when connected and verified
    if (connService.isConnected && !_hasNavigated && !connService.isVerifying) {
      _hasNavigated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const GameSelectionScreen()),
        ).then((_) {
          if (mounted) setState(() => _hasNavigated = false);
        });
      });
    }

    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      body: Stack(
        children: [
          // Background gradient
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
                    ? _buildLandscapeLayout(connService, isDark)
                    : _buildPortraitLayout(connService, isDark),
              ),
            ),
          ),

          // Verification overlay
          if (connService.isVerifying)
            _buildVerificationOverlay(connService, isDark),
        ],
      ),
    );
  }

  Widget _buildLandscapeLayout(ConnectivityService connService, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                _buildHeader(connService, isDark),
                const SizedBox(height: 20),
                Text(
                  'Spiel-Lobby',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 16),
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
              Expanded(child: _buildDevicesList(connService, isDark)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPortraitLayout(ConnectivityService connService, bool isDark) {
    return Column(
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
        ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.1, end: 0),
        const SizedBox(height: 20),
        _buildActionChoices(connService, isDark).animate().fadeIn(delay: 250.ms),
        const SizedBox(height: 20),
        _buildKnownPlayersSection(connService, isDark),
        const SizedBox(height: 20),
        _buildDevicesHeader(connService, isDark).animate().fadeIn(delay: 350.ms),
        const SizedBox(height: 12),
        Expanded(child: _buildDevicesList(connService, isDark)),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Sub-widgets
  // ---------------------------------------------------------------------------

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
                gradient: const LinearGradient(colors: AppTheme.primaryGradient),
                boxShadow: isDark
                    ? AppTheme.neonGlow(const Color(0xFFE94057))
                    : AppTheme.softShadow,
              ),
              child: const Center(
                child: Icon(Icons.person_rounded, color: Colors.white, size: 26),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connService.myUsername,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF39FF14),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text('Online', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ],
        ),
        Row(
          children: [
            IconButton(
              icon: Icon(Icons.analytics_rounded,
                  color: isDark ? Colors.white70 : Colors.black87, size: 26),
              tooltip: 'Statistiken',
              onPressed: () => _showStatsDialog(connService),
            ),
            IconButton(
              icon: Icon(Icons.settings_rounded,
                  color: isDark ? Colors.white70 : Colors.black87, size: 26),
              tooltip: 'Einstellungen',
              onPressed: () {
                Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
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
              gradientColors: connService.isAdvertising ? AppTheme.primaryGradient : null,
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
                      color: connService.isAdvertising
                          ? Colors.white
                          : (isDark ? Colors.white : Colors.black87),
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
              gradientColors: connService.isScanning ? AppTheme.neonBlueGradient : null,
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
                      color: connService.isScanning
                          ? Colors.white
                          : (isDark ? Colors.white : Colors.black87),
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
          height: 76,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: connService.knownPlayers.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final player = connService.knownPlayers[index];
              final name = player['name'] ?? 'Spieler';
              final peerId = player['id'] ?? '';

              // Check if this known player is currently visible as a discovered peer
              final onlinePeer = connService.discoveredPeers.firstWhere(
                (p) => p.id == peerId || p.name == name,
                orElse: () => AppPeer(id: '', name: '', state: PeerState.notConnected),
              );
              final isOnline = onlinePeer.id.isNotEmpty;

              return GestureDetector(
                onTap: isOnline
                    ? () {
                        if (connService.isScanning) {
                          // Scanner taps a known player → direct connect confirmation
                          _showConnectConfirmDialog(connService, onlinePeer);
                        } else {
                          // Advertiser side – shouldn't happen here normally
                          _showInviteDialog(onlinePeer);
                        }
                      }
                    : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
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
                    boxShadow: isOnline
                        ? [BoxShadow(color: const Color(0xFF39FF14).withOpacity(0.15), blurRadius: 8)]
                        : null,
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: isOnline
                            ? const Color(0xFF39FF14).withOpacity(0.2)
                            : Colors.grey.withOpacity(0.15),
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
                            const SizedBox(height: 2),
                            Text(
                              isOnline ? '● Online' : '○ Offline',
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
              size: 48,
              color: isDark ? Colors.white12 : Colors.black12,
            ),
            const SizedBox(height: 12),
            Text(
              connService.isScanning || connService.isAdvertising
                  ? 'Scanne nach Spielern...'
                  : 'Starte eine Suche oder erstelle eine Lobby,\num mit anderen zu spielen.',
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
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final peer = connService.discoveredPeers[index];
        final isKnown = connService.isKnownPlayer(peer.id);
        final isBot = peer.isMock;

        return GestureDetector(
          onTap: () {
            if (peer.state == PeerState.connecting) return;
            if (connService.isScanning) {
              _showConnectConfirmDialog(connService, peer);
            }
            // On advertiser side, the invite dialog handles the action
          },
          child: GlassContainer(
            borderRadius: 16,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: isKnown
                ? Border.all(color: const Color(0xFF39FF14), width: 1.5)
                : isBot
                    ? Border.all(color: const Color(0xFFB44FFF).withOpacity(0.5), width: 1.5)
                    : null,
            child: Row(
              children: [
                // Icon: bot vs phone
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isBot
                        ? const Color(0xFFB44FFF).withOpacity(0.12)
                        : (isDark
                            ? Colors.white.withOpacity(0.05)
                            : Colors.black.withOpacity(0.03)),
                  ),
                  child: Icon(
                    isBot ? Icons.smart_toy_rounded : Icons.phone_iphone_rounded,
                    color: isBot
                        ? const Color(0xFFB44FFF)
                        : (isDark ? Colors.white70 : Colors.black87),
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
                                color: const Color(0xFF39FF14).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle_rounded,
                                      size: 9, color: Color(0xFF39FF14)),
                                  SizedBox(width: 3),
                                  Text(
                                    'Bekannt',
                                    style: TextStyle(
                                        color: Color(0xFF39FF14),
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (isBot) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFB44FFF).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'BOT',
                                style: TextStyle(
                                    color: Color(0xFFB44FFF),
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        peer.state == PeerState.connecting
                            ? 'Verbinde...'
                            : isBot
                                ? 'KI-Gegner · Sofort spielbereit'
                                : 'Bereit zum Verbinden',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildPeerActionButton(connService, peer),
              ],
            ),
          ).animate().fadeIn(delay: (index * 80).ms).slideY(begin: 0.08, end: 0),
        );
      },
    );
  }

  Widget _buildPeerActionButton(ConnectivityService service, AppPeer peer) {
    if (peer.state == PeerState.connecting) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF00F2FE)),
      );
    }

    final isBot = peer.isMock;
    final color = isBot ? const Color(0xFFB44FFF) : const Color(0xFF00F2FE);

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.15),
        foregroundColor: color,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      onPressed: () {
        if (service.isScanning) {
          _showConnectConfirmDialog(service, peer);
        }
      },
      child: Text(
        isBot ? 'Spielen' : 'Verbinden',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PIN Verification Overlay
  // ---------------------------------------------------------------------------

  Widget _buildVerificationOverlay(ConnectivityService connService, bool isDark) {
    final pinCode = connService.verificationPin;

    return Container(
      color: Colors.black.withOpacity(0.88),
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32),
            child: GlassContainer(
              padding: const EdgeInsets.all(28),
              borderRadius: 24,
              child: connService.isHost
                  ? _buildHostVerificationView(connService, pinCode)
                  : _buildGuestVerificationView(connService),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHostVerificationView(ConnectivityService connService, int? pinCode) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.security_rounded, size: 56, color: Color(0xFF00F2FE))
            .animate()
            .scaleXY(begin: 0.7, end: 1.0, duration: 600.ms, curve: Curves.elasticOut),
        const SizedBox(height: 16),
        const Text(
          'Sicherheits-Verifizierung',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        const Text(
          'Zeige diesem Code deinem Spielpartner.\nEr muss ihn auf seinem Gerät eingeben.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60, fontSize: 13),
        ),
        const SizedBox(height: 28),
        // PIN display with individual digit boxes
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: (pinCode?.toString().padLeft(4, '0') ?? '----')
              .split('')
              .map((digit) => Container(
                    width: 56,
                    height: 68,
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00F2FE).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF00F2FE).withOpacity(0.4), width: 2),
                    ),
                    child: Center(
                      child: Text(
                        digit,
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF00F2FE),
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 28),
        const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white38),
        ),
        const SizedBox(height: 10),
        const Text(
          'Warte auf Eingabe des Partners...',
          style: TextStyle(color: Colors.white38, fontSize: 11, fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 20),
        TextButton(
          onPressed: () => connService.disconnect(),
          child: const Text('Abbrechen', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
        ),
      ],
    );
  }

  Widget _buildGuestVerificationView(ConnectivityService connService) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.pin_rounded, size: 56, color: Color(0xFFFF007F))
            .animate()
            .scaleXY(begin: 0.7, end: 1.0, duration: 600.ms, curve: Curves.elasticOut),
        const SizedBox(height: 16),
        const Text(
          'PIN Eingeben',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        const Text(
          'Gib den 4-stelligen Code ein,\nder auf dem Gerät des Hosts angezeigt wird.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60, fontSize: 13),
        ),
        const SizedBox(height: 24),
        // PIN input boxes
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (index) {
            final filled = _enteredPin.length > index;
            final active = _enteredPin.length == index;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 54,
              height: 64,
              margin: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: filled
                    ? const Color(0xFFFF007F).withOpacity(0.12)
                    : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: connService.pinError
                      ? Colors.redAccent
                      : active
                          ? const Color(0xFFFF007F)
                          : filled
                              ? Colors.white30
                              : Colors.white12,
                  width: 2,
                ),
              ),
              child: Center(
                child: Text(
                  filled ? _enteredPin[index] : '',
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            );
          }),
        ),
        if (connService.pinError) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 16),
              const SizedBox(width: 6),
              Text(
                connService.pinErrorMessage ?? 'Falscher PIN.',
                style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        // Numpad
        ...([
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['clear', '0', 'backspace'],
        ].map(
          (row) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: row.map((val) => _buildNumpadKey(val, connService)).toList(),
            ),
          ),
        )),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () {
            setState(() => _enteredPin = '');
            connService.disconnect();
          },
          child: const Text('Verbindung trennen', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
        ),
      ],
    );
  }

  Widget _buildNumpadKey(String val, ConnectivityService connService) {
    if (val == 'clear') {
      return SizedBox(
        width: 72,
        height: 52,
        child: IconButton(
          icon: const Icon(Icons.clear_rounded, color: Colors.white54),
          onPressed: () {
            setState(() => _enteredPin = '');
            connService.clearPinError();
          },
        ),
      );
    }
    if (val == 'backspace') {
      return SizedBox(
        width: 72,
        height: 52,
        child: IconButton(
          icon: const Icon(Icons.backspace_rounded, color: Colors.white54),
          onPressed: () {
            if (_enteredPin.isNotEmpty) {
              setState(() => _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1));
              connService.clearPinError();
            }
          },
        ),
      );
    }

    return SizedBox(
      width: 72,
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withOpacity(0.08),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: EdgeInsets.zero,
        ),
        onPressed: () {
          if (_enteredPin.length < 4) {
            connService.clearPinError();
            setState(() => _enteredPin += val);
            if (_enteredPin.length == 4) {
              connService.verifyCode(int.parse(_enteredPin));
              // Reset input after short delay to allow re-entry on fail
              Future.delayed(const Duration(milliseconds: 800), () {
                if (mounted && connService.pinError) {
                  setState(() => _enteredPin = '');
                }
              });
            }
          }
        },
        child: Text(val, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
