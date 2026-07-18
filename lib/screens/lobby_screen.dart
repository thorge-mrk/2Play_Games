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
  StreamSubscription? _msgSub;
  bool   _hasNavigated = false;
  String _enteredPin   = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupMessageListener();
    });
  }

  void _setupMessageListener() {
    final svc = Provider.of<ConnectivityService>(context, listen: false);
    _msgSub = svc.messageStream.listen((payload) {
      if (!mounted) return;
      final type = payload['type'] as String?;

      switch (type) {
        case 'simulated_invite_request':
          final peerData = payload['peer'] as Map<String, dynamic>;
          _showInviteDialog(AppPeer(
            id:     peerData['id']   as String,
            name:   peerData['name'] as String,
            state:  PeerState.connecting,
            isMock: true,
          ));
          break;

        case 'invite_declined':
          _showSnack('Anfrage wurde abgelehnt.', const Color(0xFF444444), Icons.person_off_rounded);
          break;

        case 'invite_blocked':
          _showSnack('Du wurdest blockiert.', const Color(0xFFB00020), Icons.block_rounded);
          break;
      }
    });
  }

  void _showSnack(String msg, Color bg, IconData icon) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(icon, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(msg, style: const TextStyle(color: Colors.white))),
      ]),
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Dialogs
  // ───────────────────────────────────────────────────────────────────────────

  /// Shown on the HOST/ADVERTISER side.
  /// Real peers  → Spielen / Blockieren / Ablehnen
  /// Mock bot    → Spielen / Ablehnen
  void _showInviteDialog(AppPeer peer) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _InviteDialog(
        peer: peer,
        onAccept: () {
          Navigator.of(ctx).pop();
          Provider.of<ConnectivityService>(context, listen: false).acceptInvite(peer);
        },
        onBlock: peer.isMock
            ? null
            : () {
                Navigator.of(ctx).pop();
                Provider.of<ConnectivityService>(context, listen: false).blockInvitingPeer(peer);
                _showSnack('${peer.name} für 10 Minuten blockiert.', const Color(0xFFB00020), Icons.block_rounded);
              },
        onDecline: () {
          Navigator.of(ctx).pop();
          if (!peer.isMock) {
            Provider.of<ConnectivityService>(context, listen: false).declineInvite(peer);
          }
        },
      ),
    );
  }

  /// Shown on the SCANNER (client) side before inviting a peer.
  void _showConnectDialog(ConnectivityService svc, AppPeer peer) {
    showDialog(
      context: context,
      builder: (ctx) => _ConnectConfirmDialog(
        peer: peer,
        onConfirm: () {
          Navigator.of(ctx).pop();
          svc.invitePeer(peer);
        },
        onCancel: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  void _showStatsDialog(ConnectivityService svc) {
    showDialog(
      context: context,
      builder: (ctx) => _StatsDialog(svc: svc),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Build
  // ───────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final svc    = Provider.of<ConnectivityService>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Clear PIN when verification ends
    if (!svc.isVerifying && _enteredPin.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _enteredPin = '');
      });
    }

    // Navigate to game selection once connected + verified
    if (svc.isConnected && !svc.isVerifying && !_hasNavigated) {
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

    final landscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: isDark
                  ? const LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [Color(0xFF0F0B1E), Color(0xFF160E2C), Color(0xFF0F0B1E)],
                    )
                  : const LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [Color(0xFFF0F4FA), Color(0xFFE2E9F3), Color(0xFFF7F8FC)],
                    ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: landscape
                    ? _buildLandscape(svc, isDark)
                    : _buildPortrait(svc, isDark),
              ),
            ),
          ),
          if (svc.isVerifying)
            _VerificationOverlay(
              svc:         svc,
              enteredPin:  _enteredPin,
              onPinDigit:  _onPinDigit,
              onPinClear:  _onPinClear,
              onPinBack:   _onPinBack,
              onDisconnect: () {
                setState(() => _enteredPin = '');
                svc.disconnect();
              },
            ),
        ],
      ),
    );
  }

  void _onPinDigit(String d, ConnectivityService svc) {
    if (_enteredPin.length >= 4) return;
    svc.clearPinError();
    setState(() => _enteredPin += d);
    if (_enteredPin.length == 4) {
      final pin = int.tryParse(_enteredPin) ?? -1;
      svc.verifyCode(pin);
      // Auto-clear on wrong PIN after a short pause
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted && svc.pinError) setState(() => _enteredPin = '');
      });
    }
  }

  void _onPinClear(ConnectivityService svc) {
    svc.clearPinError();
    setState(() => _enteredPin = '');
  }

  void _onPinBack(ConnectivityService svc) {
    if (_enteredPin.isEmpty) return;
    svc.clearPinError();
    setState(() => _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1));
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Layout builders
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildPortrait(ConnectivityService svc, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        _LobbyHeader(svc: svc, isDark: isDark, onStatsTap: () => _showStatsDialog(svc)),
        const SizedBox(height: 24),
        Text(
          'Spiel-Lobby',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontSize: 32, fontWeight: FontWeight.w900),
        ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.08, end: 0),
        const SizedBox(height: 20),
        _ActionTiles(svc: svc, isDark: isDark),
        const SizedBox(height: 20),
        _KnownPlayersRow(
          svc:      svc,
          isDark:   isDark,
          onTap:    (peer) => _showConnectDialog(svc, peer),
        ),
        const SizedBox(height: 20),
        _DevicesHeader(svc: svc, isDark: isDark),
        const SizedBox(height: 12),
        Expanded(
          child: _DevicesList(
            svc:       svc,
            isDark:    isDark,
            onConnect: (peer) => _onPeerTap(svc, peer),
          ),
        ),
      ],
    );
  }

  Widget _buildLandscape(ConnectivityService svc, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 12),
              _LobbyHeader(svc: svc, isDark: isDark, onStatsTap: () => _showStatsDialog(svc)),
              const SizedBox(height: 20),
              Text('Spiel-Lobby',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 26, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              _KnownPlayersRow(svc: svc, isDark: isDark, onTap: (peer) => _showConnectDialog(svc, peer)),
            ]),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          flex: 5,
          child: Column(children: [
            const SizedBox(height: 12),
            _ActionTiles(svc: svc, isDark: isDark),
            const SizedBox(height: 16),
            _DevicesHeader(svc: svc, isDark: isDark),
            const SizedBox(height: 8),
            Expanded(
              child: _DevicesList(
                svc:       svc,
                isDark:    isDark,
                onConnect: (peer) => _onPeerTap(svc, peer),
              ),
            ),
          ]),
        ),
      ],
    );
  }

  void _onPeerTap(ConnectivityService svc, AppPeer peer) {
    if (peer.state == PeerState.connecting) return;
    // Scanner taps → show confirm dialog
    // Advertiser side peers shouldn't appear in scanner list
    _showConnectDialog(svc, peer);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets (extracted for clarity)
// ─────────────────────────────────────────────────────────────────────────────

class _LobbyHeader extends StatelessWidget {
  final ConnectivityService svc;
  final bool isDark;
  final VoidCallback onStatsTap;

  const _LobbyHeader({required this.svc, required this.isDark, required this.onStatsTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: AppTheme.primaryGradient),
              boxShadow: isDark ? AppTheme.neonGlow(const Color(0xFFE94057)) : AppTheme.softShadow,
            ),
            child: const Icon(Icons.person_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(svc.myUsername,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87)),
            Row(children: [
              Container(width: 6, height: 6,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF39FF14))),
              const SizedBox(width: 4),
              const Text('Online', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
          ]),
        ]),
        Row(children: [
          IconButton(
            icon: Icon(Icons.analytics_rounded, color: isDark ? Colors.white70 : Colors.black87, size: 26),
            tooltip: 'Statistiken',
            onPressed: onStatsTap,
          ),
          IconButton(
            icon: Icon(Icons.settings_rounded, color: isDark ? Colors.white70 : Colors.black87, size: 26),
            tooltip: 'Einstellungen',
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ]),
      ],
    );
  }
}

class _ActionTiles extends StatelessWidget {
  final ConnectivityService svc;
  final bool isDark;
  const _ActionTiles({required this.svc, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: _tile(
        context,
        icon: Icons.wifi_tethering_rounded,
        title: 'Lobby erstellen',
        subtitle: svc.isAdvertising ? 'Sichtbar...' : 'Anderen beitreten lassen',
        active: svc.isAdvertising,
        gradient: AppTheme.primaryGradient,
        accentColor: const Color(0xFF8A2387),
        onTap: () {
          if (svc.isAdvertising) {
            svc.stopAdvertising();
          } else {
            svc.stopScanning();
            svc.startAdvertising();
          }
        },
      )),
      const SizedBox(width: 12),
      Expanded(child: _tile(
        context,
        icon: Icons.youtube_searched_for_rounded,
        title: 'Lobby suchen',
        subtitle: svc.isScanning ? 'Suche läuft...' : 'Finde Lobbys in der Nähe',
        active: svc.isScanning,
        gradient: AppTheme.neonBlueGradient,
        accentColor: const Color(0xFF00F2FE),
        onTap: () {
          if (svc.isScanning) {
            svc.stopScanning();
          } else {
            svc.stopAdvertising();
            svc.startScanning();
          }
        },
      )),
    ]);
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool active,
    required List<Color> gradient,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        borderRadius: 20,
        gradientColors: active ? gradient : null,
        child: Column(children: [
          Icon(icon, size: 32,
              color: active ? Colors.white : (isDark ? accentColor : Colors.black54)),
          const SizedBox(height: 8),
          Text(title,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13,
                  color: active ? Colors.white : (isDark ? Colors.white : Colors.black87)),
              textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(subtitle,
              style: TextStyle(fontSize: 10,
                  color: active ? Colors.white70 : Colors.grey),
              textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}

class _KnownPlayersRow extends StatelessWidget {
  final ConnectivityService svc;
  final bool isDark;
  final void Function(AppPeer) onTap;

  const _KnownPlayersRow({required this.svc, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (svc.knownPlayers.isEmpty) return const SizedBox();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('BEKANNTE SPIELER',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
              letterSpacing: 2, color: isDark ? Colors.white60 : Colors.grey[700])),
      const SizedBox(height: 8),
      SizedBox(
        height: 76,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: svc.knownPlayers.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (ctx, i) {
            final player  = svc.knownPlayers[i];
            final name    = player['name'] ?? 'Spieler';
            final peerId  = player['id']   ?? '';

            // Check if this known player is currently visible in discovered peers
            AppPeer? onlinePeer;
            for (final p in svc.discoveredPeers) {
              if (p.id == peerId) { onlinePeer = p; break; }
            }
            final online = onlinePeer != null;

            return GestureDetector(
              onTap: online ? () => onTap(onlinePeer!) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 136,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: online ? const Color(0xFF39FF14) : (isDark ? const Color(0xFF1F2937) : const Color(0xFFE5E7EB)),
                    width: 1.5,
                  ),
                  boxShadow: online
                      ? [BoxShadow(color: const Color(0xFF39FF14).withValues(alpha: 0.15), blurRadius: 8)]
                      : null,
                ),
                child: Row(children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: online
                        ? const Color(0xFF39FF14).withValues(alpha: 0.2)
                        : Colors.grey.withValues(alpha: 0.15),
                    child: Icon(Icons.person_rounded, size: 14,
                        color: online ? const Color(0xFF39FF14) : Colors.grey),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(name,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87),
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(online ? '● Online' : '○ Offline',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold,
                              color: online ? const Color(0xFF39FF14) : Colors.grey)),
                    ],
                  )),
                ]),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 8),
    ]);
  }
}

class _DevicesHeader extends StatelessWidget {
  final ConnectivityService svc;
  final bool isDark;
  const _DevicesHeader({required this.svc, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text('GERÄTE IN DER NÄHE',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
              letterSpacing: 2, color: isDark ? Colors.white60 : Colors.grey[700])),
      if (svc.isScanning || svc.isAdvertising)
        SizedBox(
          width: 14, height: 14,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: isDark ? Colors.white70 : Colors.black54),
        ),
    ]);
  }
}

class _DevicesList extends StatelessWidget {
  final ConnectivityService svc;
  final bool isDark;
  final void Function(AppPeer) onConnect;

  const _DevicesList({required this.svc, required this.isDark, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    final peers = svc.discoveredPeers;

    if (peers.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.radar_rounded, size: 48,
              color: isDark ? Colors.white12 : Colors.black12),
          const SizedBox(height: 12),
          Text(
            svc.isScanning || svc.isAdvertising
                ? 'Scanne nach Spielern...'
                : 'Starte eine Suche oder erstelle eine Lobby\num mit anderen zu spielen.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12,
                color: isDark ? Colors.white30 : Colors.black38),
          ),
        ]).animate().fadeIn(),
      );
    }

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      itemCount: peers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) {
        final peer    = peers[i];
        final isBot   = peer.isMock;
        final isKnown = svc.isKnownPlayer(peer.id);

        return GestureDetector(
          onTap: peer.state == PeerState.connecting ? null : () => onConnect(peer),
          child: GlassContainer(
            borderRadius: 16,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: isKnown
                ? Border.all(color: const Color(0xFF39FF14), width: 1.5)
                : isBot
                    ? Border.all(color: const Color(0xFFB44FFF).withValues(alpha: 0.5), width: 1.5)
                    : null,
            child: Row(children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isBot
                      ? const Color(0xFFB44FFF).withValues(alpha: 0.12)
                      : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03)),
                ),
                child: Icon(
                  isBot ? Icons.smart_toy_rounded : Icons.phone_iphone_rounded,
                  color: isBot ? const Color(0xFFB44FFF) : (isDark ? Colors.white70 : Colors.black87),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(peer.name,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14,
                            color: isDark ? Colors.white : Colors.black87),
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (isKnown) _badge('Bekannt', const Color(0xFF39FF14), Icons.check_circle_rounded),
                  if (isBot)   _badge('BOT', const Color(0xFFB44FFF), null),
                ]),
                const SizedBox(height: 2),
                Text(
                  peer.state == PeerState.connecting ? 'Verbinde...' : (isBot ? 'KI-Gegner · Sofort spielbereit' : 'Bereit zum Verbinden'),
                  style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black54),
                ),
              ])),
              const SizedBox(width: 8),
              _PeerButton(peer: peer, isBot: isBot, onTap: () => onConnect(peer)),
            ]),
          ).animate().fadeIn(delay: (i * 80).ms).slideY(begin: 0.08, end: 0),
        );
      },
    );
  }

  Widget _badge(String label, Color color, IconData? icon) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 9, color: color), const SizedBox(width: 3)],
        Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

class _PeerButton extends StatelessWidget {
  final AppPeer peer;
  final bool isBot;
  final VoidCallback onTap;
  const _PeerButton({required this.peer, required this.isBot, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (peer.state == PeerState.connecting) {
      return const SizedBox(
        width: 22, height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF00F2FE)),
      );
    }
    final color = isBot ? const Color(0xFFB44FFF) : const Color(0xFF00F2FE);
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.15),
        foregroundColor: color,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      onPressed: onTap,
      child: Text(isBot ? 'Spielen' : 'Verbinden',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Invite Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _InviteDialog extends StatelessWidget {
  final AppPeer peer;
  final VoidCallback onAccept;
  final VoidCallback? onBlock;
  final VoidCallback onDecline;

  const _InviteDialog({
    required this.peer,
    required this.onAccept,
    required this.onBlock,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: GlassContainer(
        padding: const EdgeInsets.all(24),
        borderRadius: 24,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            peer.isMock ? Icons.smart_toy_rounded : Icons.sports_esports_rounded,
            size: 52,
            color: peer.isMock ? const Color(0xFFB44FFF) : const Color(0xFF00F2FE),
          ).animate().scaleXY(begin: 0.7, end: 1.0, duration: 500.ms, curve: Curves.elasticOut),
          const SizedBox(height: 16),
          Text('Spiel-Einladung',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 20)),
          const SizedBox(height: 8),
          Text('${peer.name} möchte mit dir spielen!',
              textAlign: TextAlign.center,
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14)),
          const SizedBox(height: 24),

          // Spielen
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
              onPressed: onAccept,
            ),
          ),

          // Blockieren (real peers only)
          if (onBlock != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.block_rounded, size: 18, color: Color(0xFFFF4040)),
                label: const Text('Blockieren (10 Min)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFFFF4040))),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(color: Color(0xFFFF4040), width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: onBlock,
              ),
            ),
          ],

          const SizedBox(height: 10),
          TextButton(
            onPressed: onDecline,
            child: Text('Ablehnen',
                style: TextStyle(color: isDark ? Colors.white54 : Colors.black54,
                    fontWeight: FontWeight.bold)),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Connect Confirm Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _ConnectConfirmDialog extends StatelessWidget {
  final AppPeer peer;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  const _ConnectConfirmDialog({required this.peer, required this.onConfirm, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(40),
      child: GlassContainer(
        padding: const EdgeInsets.all(24),
        borderRadius: 24,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            peer.isMock ? Icons.smart_toy_rounded : Icons.person_rounded,
            size: 48,
            color: peer.isMock ? const Color(0xFFB44FFF) : const Color(0xFF00F2FE),
          ),
          const SizedBox(height: 14),
          Text('Mit ${peer.name} verbinden?',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            peer.isMock
                ? 'KI-Gegner · Schwierigkeit aus Einstellungen'
                : 'Der andere Spieler muss die Anfrage akzeptieren.',
            style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            TextButton(
              onPressed: onCancel,
              child: Text('Abbrechen',
                  style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: peer.isMock ? const Color(0xFFB44FFF) : const Color(0xFF00B4D8),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: onConfirm,
              child: Text(peer.isMock ? 'Spielen' : 'Verbinden',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _StatsDialog extends StatelessWidget {
  final ConnectivityService svc;
  const _StatsDialog({required this.svc});

  String _gameName(String key) {
    const m = {
      'tictactoe': 'Tic-Tac-Toe', 'connect4': 'Vier Gewinnt',
      'battleship': 'Schiffe Versenken', 'rockpaperscissors': 'Schere, Stein, Papier',
      'minigolf': 'Minigolf',
    };
    return m[key] ?? key;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: GlassContainer(
        padding: const EdgeInsets.all(24),
        borderRadius: 24,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Statistiken',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 22)),
            IconButton(
              icon: Icon(Icons.close_rounded, color: isDark ? Colors.white70 : Colors.black87),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ]),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _statItem('${(svc.totalPlayTimeSeconds / 3600).toStringAsFixed(1)} Std', 'Online-Zeit', Icons.timer_rounded),
            _statItem(svc.favoriteGame, 'Lieblingsspiel', Icons.favorite_rounded),
          ]),
          const Divider(height: 28, thickness: 1),
          const Text('Spiel-Statistiken', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...svc.gameStats.entries.map((e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(_gameName(e.key), style: const TextStyle(fontSize: 13)),
              Text(
                'S: ${(e.value['wins_vs_bot'] ?? 0) + (e.value['wins_vs_player'] ?? 0)}'
                '  N: ${(e.value['losses_vs_bot'] ?? 0) + (e.value['losses_vs_player'] ?? 0)}',
                style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54),
              ),
            ]),
          )),
        ]),
      ),
    );
  }

  Widget _statItem(String val, String label, IconData icon) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      const SizedBox(height: 4),
      Row(children: [
        Icon(icon, size: 14, color: const Color(0xFF00F2FE)),
        const SizedBox(width: 4),
        Text(val, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      ]),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Verification Overlay
// ─────────────────────────────────────────────────────────────────────────────

class _VerificationOverlay extends StatelessWidget {
  final ConnectivityService svc;
  final String enteredPin;
  final void Function(String, ConnectivityService) onPinDigit;
  final void Function(ConnectivityService) onPinClear;
  final void Function(ConnectivityService) onPinBack;
  final VoidCallback onDisconnect;

  const _VerificationOverlay({
    required this.svc,
    required this.enteredPin,
    required this.onPinDigit,
    required this.onPinClear,
    required this.onPinBack,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.90),
      width: double.infinity,
      height: double.infinity,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: svc.isHost
                ? _HostView(svc: svc, onDisconnect: onDisconnect)
                : _GuestView(
                    svc:         svc,
                    enteredPin:  enteredPin,
                    onDigit:     (d) => onPinDigit(d, svc),
                    onClear:     ()  => onPinClear(svc),
                    onBack:      ()  => onPinBack(svc),
                    onDisconnect: onDisconnect,
                  ),
          ),
        ),
      ),
    );
  }
}

class _HostView extends StatelessWidget {
  final ConnectivityService svc;
  final VoidCallback onDisconnect;
  const _HostView({required this.svc, required this.onDisconnect});

  @override
  Widget build(BuildContext context) {
    final pin = svc.verificationPin;
    final digits = pin?.toString().padLeft(4, '0') ?? '----';

    return Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.security_rounded, size: 56, color: Color(0xFF00F2FE))
          .animate()
          .scaleXY(begin: 0.7, end: 1.0, duration: 600.ms, curve: Curves.elasticOut),
      const SizedBox(height: 16),
      const Text('Sicherheits-Verifizierung',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          textAlign: TextAlign.center),
      const SizedBox(height: 10),
      const Text('Zeige diesem Code deinem Spielpartner.\nEr muss ihn auf seinem Gerät eingeben.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60, fontSize: 13)),
      const SizedBox(height: 28),
      // PIN boxes
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: digits.split('').map((d) => Container(
          width: 58, height: 70,
          margin: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF00F2FE).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF00F2FE).withValues(alpha: 0.5), width: 2),
          ),
          child: Center(
            child: Text(d,
                style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900,
                    color: Color(0xFF00F2FE))),
          ),
        )).toList(),
      ),
      const SizedBox(height: 28),
      const SizedBox(
        width: 22, height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white38),
      ),
      const SizedBox(height: 10),
      const Text('Warte auf Eingabe des Partners...',
          style: TextStyle(color: Colors.white38, fontSize: 11, fontStyle: FontStyle.italic)),
      const SizedBox(height: 20),
      TextButton(
        onPressed: onDisconnect,
        child: const Text('Abbrechen', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
      ),
    ]);
  }
}

class _GuestView extends StatelessWidget {
  final ConnectivityService svc;
  final String enteredPin;
  final void Function(String) onDigit;
  final VoidCallback onClear;
  final VoidCallback onBack;
  final VoidCallback onDisconnect;

  const _GuestView({
    required this.svc,
    required this.enteredPin,
    required this.onDigit,
    required this.onClear,
    required this.onBack,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.pin_rounded, size: 56, color: Color(0xFFFF007F))
          .animate()
          .scaleXY(begin: 0.7, end: 1.0, duration: 600.ms, curve: Curves.elasticOut),
      const SizedBox(height: 16),
      const Text('PIN Eingeben',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          textAlign: TextAlign.center),
      const SizedBox(height: 10),
      const Text('Gib den 4-stelligen Code ein,\nder auf dem Gerät des Hosts angezeigt wird.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60, fontSize: 13)),
      const SizedBox(height: 24),

      // PIN input boxes
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (i) {
          final filled = enteredPin.length > i;
          final active = enteredPin.length == i;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 56, height: 66,
            margin: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: filled
                  ? const Color(0xFFFF007F).withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: svc.pinError
                    ? Colors.redAccent
                    : active
                        ? const Color(0xFFFF007F)
                        : filled ? Colors.white38 : Colors.white24,
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                filled ? enteredPin[i] : (active ? '|' : ''),
                style: TextStyle(
                  fontSize: filled ? 30 : 20,
                  fontWeight: FontWeight.bold,
                  color: filled ? Colors.white : Colors.white38,
                ),
              ),
            ),
          );
        }),
      ),

      if (svc.pinError) ...[
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              svc.pinErrorMessage ?? 'Falscher PIN.',
              style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
        ]),
      ],

      const SizedBox(height: 28),
      // Numpad
      for (final row in [['1','2','3'], ['4','5','6'], ['7','8','9'], ['C','0','⌫']]) ...[
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: row.map((v) => _NumpadKey(
            label: v,
            onTap: () {
              if (v == 'C') { onClear(); }
              else if (v == '⌫') { onBack(); }
              else { onDigit(v); }
            },
          )).toList(),
        ),
        const SizedBox(height: 10),
      ],

      const SizedBox(height: 4),
      TextButton(
        onPressed: onDisconnect,
        child: const Text('Verbindung trennen',
            style: TextStyle(color: Colors.redAccent, fontSize: 13)),
      ),
    ]);
  }
}

class _NumpadKey extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _NumpadKey({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isIcon = label == 'C' || label == '⌫';
    return Container(
      width: 80, height: 58,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      child: Material(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Center(
            child: isIcon
                ? Icon(
                    label == 'C' ? Icons.clear_rounded : Icons.backspace_rounded,
                    color: Colors.white70, size: 22,
                  )
                : Text(label,
                    style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white,
                    )),
          ),
        ),
      ),
    );
  }
}
