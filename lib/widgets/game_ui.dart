import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';
import 'chat_sheet.dart';

/// Shared UI building blocks for all game screens.
///
/// Every game used to duplicate its header, chat button, bot difficulty
/// dropdown, exit dialog and game-over overlay. They live here now so the
/// games stay consistent and small.

/// Standard header of a game screen: back button, centered title,
/// bot difficulty (only vs. bot), chat button with unread badge and
/// optional extra actions (e.g. Minigolf reset).
class GameHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback onExit;
  final List<Widget> extraActions;

  const GameHeader({
    super.key,
    required this.title,
    this.subtitle,
    required this.onExit,
    this.extraActions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white70 : Colors.black87;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: fg),
            tooltip: 'Zurück zur Spielauswahl',
            onPressed: onExit,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
              ],
            ),
          ),
          const BotDifficultySwitcher(),
          const ChatIconButton(),
          ...extraActions,
        ],
      ),
    );
  }
}

/// Chat button with unread badge; opens the [ChatSheet].
class ChatIconButton extends StatelessWidget {
  const ChatIconButton({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<ConnectivityService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return IconButton(
      tooltip: 'Chat',
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            Icons.chat_bubble_rounded,
            color: isDark ? Colors.white70 : Colors.black87,
            size: 24,
          ),
          if (svc.unreadChatCount > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: AppTheme.accentNeonPink,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? AppTheme.darkBg : Colors.white,
                    width: 1.5,
                  ),
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  '${svc.unreadChatCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      onPressed: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const ChatSheet(),
        );
      },
    );
  }
}

/// Dropdown to change the bot difficulty – only visible when playing vs. bot.
class BotDifficultySwitcher extends StatelessWidget {
  const BotDifficultySwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<ConnectivityService>();
    if (svc.connectedPeer?.isMock != true) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? Colors.white12
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: svc.botDifficulty,
          dropdownColor: isDark ? AppTheme.darkCard : Colors.white,
          icon: Icon(Icons.arrow_drop_down,
              color: isDark ? Colors.white70 : Colors.black54, size: 18),
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
          onChanged: (val) {
            if (val != null) svc.setBotDifficulty(val);
          },
          items: const [
            DropdownMenuItem(value: 'einfach', child: Text('🤖 Einfach')),
            DropdownMenuItem(value: 'mittel', child: Text('🤖 Mittel')),
            DropdownMenuItem(value: 'schwer', child: Text('🤖 Schwer')),
          ],
        ),
      ),
    );
  }
}

/// Confirmation dialog shown before leaving a running game.
///
/// Leaving a game returns BOTH players to the game selection – the
/// connection stays alive.
Future<bool> showExitGameDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
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
                color: Colors.amberAccent,
              ),
              const SizedBox(height: 16),
              Text(
                'Spiel verlassen?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(ctx).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ihr kehrt beide zur Spielauswahl zurück. '
                'Die Verbindung bleibt bestehen.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(ctx).brightness == Brightness.dark
                      ? Colors.white70
                      : Colors.black54,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Weiterspielen'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Ja, verlassen'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  return result ?? false;
}

/// Full-screen result overlay (win / lose / draw) with "Beenden" and
/// "Revanche" actions, shared by all games.
class GameResultOverlay extends StatelessWidget {
  final String title;
  final String description;
  final Color color;
  final IconData icon;
  final Widget? extra;
  final VoidCallback onExit;
  final VoidCallback onRematch;
  final bool waitingForRematch;
  final String rematchLabel;

  const GameResultOverlay({
    super.key,
    required this.title,
    required this.description,
    required this.color,
    required this.icon,
    this.extra,
    required this.onExit,
    required this.onRematch,
    this.waitingForRematch = false,
    this.rematchLabel = 'Revanche',
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.75),
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 380),
              padding: const EdgeInsets.all(24),
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: color.withValues(alpha: 0.6),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.2),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 64, color: color)
                      .animate()
                      .scaleXY(
                          begin: 0.6,
                          end: 1.0,
                          duration: 500.ms,
                          curve: Curves.elasticOut),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  if (extra != null) ...[
                    const SizedBox(height: 8),
                    extra!,
                  ],
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color:
                                    isDark ? Colors.white24 : Colors.black26),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: onExit,
                          child: Text(
                            'Beenden',
                            style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryPurple,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: waitingForRematch ? null : onRematch,
                          child: waitingForRematch
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : Text(rematchLabel,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
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

/// Gradient page background shared by all screens.
class AppBackground extends StatelessWidget {
  final Widget child;
  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0F0B1E), Color(0xFF130A29), Color(0xFF0F0B1E)],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF4F6FB), Color(0xFFE9EEF6), Color(0xFFF7F8FC)],
              ),
      ),
      child: child,
    );
  }
}
