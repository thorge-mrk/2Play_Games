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
                        // Reject invite in simulated is just doing nothing
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

  @override
  Widget build(BuildContext context) {
    final connService = Provider.of<ConnectivityService>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Auto navigate to game selection screen when connected
    if (connService.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const GameSelectionScreen()),
        );
      });
    }

    final primaryGlow = isDark ? const Color(0xFF8A2387) : Colors.transparent;

    return Scaffold(
      body: Container(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        // User Avatar
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
                ).animate().fadeIn(duration: 500.ms),

                const SizedBox(height: 24),

                // Mode Indicator Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        connService.mode == AppConnectivityMode.real
                            ? Icons.bluetooth_audio_rounded
                            : Icons.auto_awesome_rounded,
                        size: 16,
                        color: connService.mode == AppConnectivityMode.real
                            ? const Color(0xFF00F2FE)
                            : const Color(0xFFFF007F),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        connService.mode == AppConnectivityMode.real
                            ? 'Real-P2P (Bluetooth & Wi-Fi)'
                            : 'Demo-Modus (Gegen Offline-KI)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 150.ms),

                const SizedBox(height: 16),

                // Title
                Text(
                  'Spiel-Lobby',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                      ),
                ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1, end: 0),

                const SizedBox(height: 24),

                // Action choices: Host vs Scan
                Row(
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
                          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                          borderRadius: 20,
                          gradientColors: connService.isAdvertising
                              ? AppTheme.primaryGradient
                              : null,
                          child: Column(
                            children: [
                              Icon(
                                Icons.wifi_tethering_rounded,
                                size: 36,
                                color: connService.isAdvertising
                                    ? Colors.white
                                    : (isDark ? const Color(0xFF8A2387) : Colors.black54),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Lobby erstellen',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: connService.isAdvertising ? Colors.white : (isDark ? Colors.white : Colors.black87),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                connService.isAdvertising ? 'Sichtbar...' : 'Lasse andere dich finden',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: connService.isAdvertising ? Colors.white70 : Colors.grey,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
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
                          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                          borderRadius: 20,
                          gradientColors: connService.isScanning
                              ? AppTheme.neonBlueGradient
                              : null,
                          child: Column(
                            children: [
                              Icon(
                                Icons.youtube_searched_for_rounded,
                                size: 36,
                                color: connService.isScanning
                                    ? Colors.white
                                    : (isDark ? const Color(0xFF00F2FE) : Colors.black54),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Lobby suchen',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: connService.isScanning ? Colors.white : (isDark ? Colors.white : Colors.black87),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                connService.isScanning ? 'Suche läuft...' : 'Finde Lobbys in der Nähe',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: connService.isScanning ? Colors.white70 : Colors.grey,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ).animate().fadeIn(delay: 300.ms),

                const SizedBox(height: 32),

                // Peers List Title / Searching animation
                Row(
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
                ).animate().fadeIn(delay: 400.ms),

                const SizedBox(height: 16),

                // Device List View
                Expanded(
                  child: connService.discoveredPeers.isEmpty
                      ? Center(
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
                                    : 'Starte Suche oder erstelle eine Lobby,\num mit anderen zu spielen.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark ? Colors.white30 : Colors.black38,
                                ),
                              ),
                            ],
                          ),
                        ).animate().fadeIn()
                      : ListView.separated(
                          physics: const BouncingScrollPhysics(),
                          itemCount: connService.discoveredPeers.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final peer = connService.discoveredPeers[index];
                            return GlassContainer(
                              borderRadius: 16,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
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
                                        Text(
                                          peer.name,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: isDark ? Colors.white : Colors.black87,
                                          ),
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
                            ).animate().fadeIn().slideY(begin: 0.1, end: 0);
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
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
    
    // In real mode, if we are browsing and we find someone, we invite them
    // If they are advertising, they wait for invite
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
      onPressed: () {
        if (service.isScanning) {
          service.invitePeer(peer);
        } else {
          // If we are advertising, we can accept their request or trigger accepting logic
          service.acceptInvite(peer);
        }
      },
      child: const Text(
        'Verbinden',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}
