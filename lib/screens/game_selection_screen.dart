import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';
import 'tictactoe_screen.dart';
import 'connectfour_screen.dart';
import 'battleship_screen.dart';
import 'rockpaperscissors_screen.dart';
import 'minigolf_screen.dart';
import 'memory_screen.dart';
import 'dotsboxes_screen.dart';
import 'nim_screen.dart';
import 'reaction_screen.dart';
import 'pig_screen.dart';
import '../widgets/game_ui.dart';

class GameSelectionScreen extends StatefulWidget {
  const GameSelectionScreen({super.key});

  @override
  State<GameSelectionScreen> createState() => _GameSelectionScreenState();
}

class _GameSelectionScreenState extends State<GameSelectionScreen> {
  StreamSubscription? _msgSubscription;
  final Set<int> _animatedIndexes = {};

  @override
  void initState() {
    super.initState();
    final connService = Provider.of<ConnectivityService>(context, listen: false);
    
    // Listen to incoming messages for game selection triggers (needed for client)
    _msgSubscription = connService.messageStream.listen((payload) {
      if (payload['type'] == 'game_select') {
        final gameId = payload['gameId'] as String;
        if (!connService.isHost) {
          _navigateToGame(gameId);
        }
      }
    });
  }

  @override
  void dispose() {
    _msgSubscription?.cancel();
    super.dispose();
  }

  void _navigateToGame(String gameId) {
    Widget gameScreen;
    switch (gameId) {
      case 'tictactoe':
        gameScreen = const TicTacToeScreen();
        break;
      case 'connect4':
        gameScreen = const ConnectFourScreen();
        break;
      case 'battleship':
        gameScreen = const BattleshipScreen();
        break;
      case 'rockpaperscissors':
        gameScreen = const RockPaperScissorsScreen();
        break;
      case 'minigolf':
        gameScreen = const MinigolfScreen();
        break;
      case 'memory':
        gameScreen = const MemoryScreen();
        break;
      case 'dotsboxes':
        gameScreen = const DotsBoxesScreen();
        break;
      case 'nim':
        gameScreen = const NimScreen();
        break;
      case 'reaction':
        gameScreen = const ReactionScreen();
        break;
      case 'pig':
        gameScreen = const PigScreen();
        break;
      default:
        return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => gameScreen),
    ).then((_) {
      // When popping back from a game, let the connection service know we exited
      if (!mounted) return;
      final connService = Provider.of<ConnectivityService>(context, listen: false);
      if (connService.activeGameId != null && connService.isHost) {
        connService.exitGame();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final connService = Provider.of<ConnectivityService>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Guard: Return to lobby if connection is lost
    if (!connService.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      });
      return const SizedBox();
    }

    final games = [
      {
        'id': 'tictactoe',
        'title': 'Tic-Tac-Toe',
        'desc': 'Klassisches 3x3 Raster. Bringe 3 deiner Symbole in eine Reihe!',
        'icon': Icons.grid_3x3_rounded,
        'colors': AppTheme.primaryGradient,
      },
      {
        'id': 'connect4',
        'title': 'Vier Gewinnt',
        'desc': 'Lasse deine Chips in das Gitter fallen und bilde eine 4er-Reihe!',
        'icon': Icons.view_column_rounded,
        'colors': AppTheme.neonBlueGradient,
      },
      {
        'id': 'battleship',
        'title': 'Schiffe Versenken',
        'desc': 'Platziere deine Flotte geheim und vernichte die gegnerischen Schiffe!',
        'icon': Icons.directions_boat_rounded,
        'colors': AppTheme.neonPurpleGradient,
      },
      {
        'id': 'rockpaperscissors',
        'title': 'Schere, Stein, Papier',
        'desc': 'Ein schnelles Duell. Wähle deine Geste und besiege den Gegner!',
        'icon': Icons.sports_handball_rounded,
        'colors': [const Color(0xFFFF8C00), const Color(0xFFFF007F)],
      },
      {
        'id': 'minigolf',
        'title': 'Mini-Golf',
        'desc': 'Bringe den Ball mit möglichst wenigen Schlägen ins Loch! 50 Levels & Turnier-Modus.',
        'icon': Icons.flag_rounded,
        'colors': [Colors.green[600]!, Colors.teal],
      },
      {
        'id': 'memory',
        'title': 'Memory',
        'desc': 'Finde mehr Paare als dein Gegner! Ein Treffer bringt einen Extrazug.',
        'icon': Icons.style_rounded,
        'colors': [const Color(0xFF9C27B0), const Color(0xFFE91E63)],
      },
      {
        'id': 'dotsboxes',
        'title': 'Käsekästchen',
        'desc': 'Schließe Kästchen mit cleveren Linien – wer mehr Kästchen holt, gewinnt!',
        'icon': Icons.grid_on_rounded,
        'colors': [const Color(0xFF00897B), const Color(0xFF43A047)],
      },
      {
        'id': 'nim',
        'title': 'Streichholz-Duell',
        'desc': 'Nimm 1-3 Streichhölzer. Wer das letzte nehmen muss, verliert!',
        'icon': Icons.local_fire_department_rounded,
        'colors': [const Color(0xFFFF7043), const Color(0xFFD84315)],
      },
      {
        'id': 'reaction',
        'title': 'Reaktionsduell',
        'desc': 'Warte auf Grün und tippe blitzschnell – wer zuerst 3 Runden holt, gewinnt!',
        'icon': Icons.flash_on_rounded,
        'colors': [const Color(0xFFFFB300), const Color(0xFFF57C00)],
      },
      {
        'id': 'pig',
        'title': 'Würfelduell',
        'desc': 'Würfle und sammle Punkte – aber Vorsicht: Eine 1 kostet die ganze Runde!',
        'icon': Icons.casino_rounded,
        'colors': [const Color(0xFF3949AB), const Color(0xFF00ACC1)],
      },
    ];

    return Scaffold(
      body: Container(
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
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Custom Navigation Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.sports_esports_rounded,
                          color: Color(0xFF00F2FE),
                          size: 32,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '2Play Spiele',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const ChatIconButton(),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.withValues(alpha: 0.1),
                            foregroundColor: Colors.redAccent,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          onPressed: () => connService.disconnect(),
                          icon: const Icon(Icons.power_settings_new_rounded, size: 16),
                          label: const Text('Trennen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Sub-info: Who are we connected with?
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 14,
                      color: Colors.greenAccent[400],
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Verbunden mit: ${connService.connectedPeer?.name}',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Host vs Client instructions banner
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: GlassContainer(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  borderRadius: 16,
                  child: Row(
                    children: [
                      Icon(
                        connService.isHost ? Icons.vpn_key_rounded : Icons.hourglass_empty_rounded,
                        color: const Color(0xFF00F2FE),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          connService.isHost
                              ? 'Du bist der Host. Wähle ein Spiel aus, um die Runde für beide zu starten!'
                              : 'Warte darauf, dass der Host ein Spiel auswählt, um das Duell zu beginnen...',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ).animate().fadeIn(delay: 150.ms),

              if (!connService.isHost && connService.activeGameId != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: GestureDetector(
                    onTap: () {
                      _navigateToGame(connService.activeGameId!);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF007F), Color(0xFF8A2387)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF007F).withValues(alpha: 0.4),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.play_circle_fill_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Laufendes Spiel!',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  'Tippe hier, um das Spiel fortzusetzen.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withValues(alpha: 0.9),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                ).animate(onPlay: (c) => c.repeat(reverse: true))
                 .scaleXY(begin: 0.98, end: 1.02, duration: 1000.ms, curve: Curves.easeInOut),

              const SizedBox(height: 24),

              // Games List (width-limited so it stays readable on tablets)
              Expanded(
                child: ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    bottom: 20 + MediaQuery.of(context).padding.bottom,
                  ),
                  itemCount: games.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final game = games[index];
                    final isHost = connService.isHost;
                    final isSuggested = connService.suggestedGameId == game['id'];

                    Widget card = GlassContainer(
                      borderRadius: 24,
                      padding: const EdgeInsets.all(20),
                      border: isSuggested
                          ? Border.all(
                              color: isHost ? const Color(0xFF00F2FE) : const Color(0xFF8A2387),
                              width: 2.5,
                            )
                          : null,
                      child: Row(
                        children: [
                          // Icon block
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: game['colors'] as List<Color>,
                              ),
                              boxShadow: isDark
                                  ? AppTheme.neonGlow((game['colors'] as List<Color>)[0])
                                  : AppTheme.softShadow,
                            ),
                            child: Icon(
                              game['icon'] as IconData,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Info text block
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        game['title'] as String,
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.white : Colors.black87,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isSuggested) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isHost ? const Color(0xFF00F2FE).withValues(alpha: 0.15) : const Color(0xFF8A2387).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: isHost ? const Color(0xFF00F2FE) : const Color(0xFF8A2387),
                                            width: 1.2,
                                          ),
                                        ),
                                        child: Text(
                                          isHost ? 'Gegner schlägt vor!' : 'Vorgeschlagen',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: isHost ? const Color(0xFF00F2FE) : const Color(0xFF8A2387),
                                          ),
                                        ),
                                      ).animate(onPlay: (c) => c.repeat(reverse: true))
                                       .scaleXY(begin: 0.95, end: 1.05, duration: 800.ms, curve: Curves.easeInOut),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  game['desc'] as String,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? Colors.white60 : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Play arrow if Host, suggestion status indicator if guest
                          if (isHost)
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: Color(0xFF00F2FE),
                              size: 16,
                            )
                          else
                            Icon(
                              isSuggested ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                              color: isSuggested ? const Color(0xFF8A2387) : Colors.grey,
                              size: 20,
                            ),
                        ],
                      ),
                    );

                    if (isSuggested) {
                      card = card.animate(onPlay: (c) => c.repeat(reverse: true))
                          .boxShadow(
                            begin: const BoxShadow(color: Colors.transparent, blurRadius: 0),
                            end: BoxShadow(
                              color: isHost ? const Color(0xFF00F2FE).withValues(alpha: 0.4) : const Color(0xFF8A2387).withValues(alpha: 0.4),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                            duration: 1000.ms,
                            curve: Curves.easeInOut,
                          );
                    }

                    final isFirstTime = !_animatedIndexes.contains(index);
                    if (isFirstTime) {
                      _animatedIndexes.add(index);
                    }

                    Widget finalWidget = GestureDetector(
                      onTap: () {
                        if (isHost) {
                          connService.selectGame(game['id'] as String);
                          _navigateToGame(game['id'] as String);
                        } else {
                          if (connService.activeGameId == game['id']) {
                            _navigateToGame(game['id'] as String);
                          } else {
                            connService.suggestGame(game['id'] as String);
                          }
                        }
                      },
                      child: card,
                    );

                    if (isFirstTime) {
                      finalWidget = finalWidget
                          .animate()
                          .fadeIn(delay: Duration(milliseconds: 200 + index * 100))
                          .slideX(begin: 0.1, end: 0);
                    }

                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: finalWidget,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
