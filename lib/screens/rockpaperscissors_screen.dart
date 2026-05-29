import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_sheet.dart';

class RockPaperScissorsScreen extends StatefulWidget {
  const RockPaperScissorsScreen({super.key});

  @override
  State<RockPaperScissorsScreen> createState() => _RockPaperScissorsScreenState();
}

class _RockPaperScissorsScreenState extends State<RockPaperScissorsScreen> {
  String? _myChoice;
  String? _opponentChoice;
  
  bool _revealed = false;
  int _myScore = 0;
  int _opponentScore = 0;
  
  String _roundResult = ''; // 'win', 'lose', 'draw'
  StreamSubscription? _msgSubscription;

  @override
  void initState() {
    super.initState();
    final connService = Provider.of<ConnectivityService>(context, listen: false);

    _msgSubscription = connService.messageStream.listen((payload) {
      if (payload['type'] == 'game_move' && payload['gameId'] == 'rockpaperscissors') {
        final data = payload['data'] as Map<String, dynamic>;
        
        setState(() {
          // If we receive the AI/Opponent choice
          _opponentChoice = data['aiChoice'] as String?;
          // If it is a real opponent, they might send their choice first, or we wait till both are set
          if (connService.mode == AppConnectivityMode.real) {
            _opponentChoice = data['userChoice'] as String?;
          }
          
          _checkReveal();
        });
      } else if (payload['type'] == 'game_reset' && payload['gameId'] == 'rockpaperscissors') {
        connService.sendPayload({
          'type': 'game_reset_accept',
          'gameId': 'rockpaperscissors',
        });
        _resetRound();
      } else if (payload['type'] == 'game_reset_accept' && payload['gameId'] == 'rockpaperscissors') {
        _resetRound();
      } else if (payload['type'] == 'game_exit') {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _msgSubscription?.cancel();
    super.dispose();
  }

  void _choose(String choice) {
    if (_myChoice != null) return; // Choice already locked

    setState(() {
      _myChoice = choice;
    });

    final connService = Provider.of<ConnectivityService>(context, listen: false);
    
    // Send choice to opponent
    connService.sendPayload({
      'type': 'game_move',
      'gameId': 'rockpaperscissors',
      'data': {
        'userChoice': choice,
      }
    });

    _checkReveal();
  }

  void _checkReveal() {
    if (_myChoice != null && _opponentChoice != null) {
      setState(() {
        _revealed = true;
        _evaluateRound();
      });
    }
  }

  void _evaluateRound() {
    if (_myChoice == _opponentChoice) {
      _roundResult = 'draw';
    } else if ((_myChoice == 'rock' && _opponentChoice == 'scissors') ||
        (_myChoice == 'paper' && _opponentChoice == 'rock') ||
        (_myChoice == 'scissors' && _opponentChoice == 'paper')) {
      _roundResult = 'win';
      _myScore++;
    } else {
      _roundResult = 'lose';
      _opponentScore++;
    }
  }

  void _resetRound() {
    setState(() {
      _myChoice = null;
      _opponentChoice = null;
      _revealed = false;
      _roundResult = '';
    });
  }

  void _requestReset() {
    Provider.of<ConnectivityService>(context, listen: false).sendPayload({
      'type': 'game_reset',
      'gameId': 'rockpaperscissors',
    });
  }

  void _exitGame() {
    Provider.of<ConnectivityService>(context, listen: false).exitGame();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final connService = Provider.of<ConnectivityService>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Guard dropped connection
    if (!connService.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      });
      return const SizedBox();
    }

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
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_ios_new_rounded, color: isDark ? Colors.white70 : Colors.black87),
                      onPressed: _exitGame,
                    ),
                    Text(
                      'Schere, Stein, Papier',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    IconButton(
                      icon: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(Icons.chat_bubble_rounded, color: isDark ? Colors.white70 : Colors.black87, size: 24),
                          if (connService.unreadChatCount > 0)
                            Positioned(
                              right: -4,
                              top: -4,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF007F),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: isDark ? const Color(0xFF0F0B1E) : Colors.white, width: 1.5),
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 16,
                                  minHeight: 16,
                                ),
                                child: Text(
                                  '${connService.unreadChatCount}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
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
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Scoreboard Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: GlassContainer(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  borderRadius: 20,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        children: [
                          const Text('DU', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                          const SizedBox(height: 4),
                          Text(
                            '$_myScore',
                            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF00F2FE)),
                          ),
                        ],
                      ),
                      Text(
                        'PUNKTE',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                          color: isDark ? Colors.white24 : Colors.black26,
                        ),
                      ),
                      Column(
                        children: [
                          Text(
                            (connService.connectedPeer?.name ?? 'GEGNER').toUpperCase(),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$_opponentScore',
                            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFFFF007F)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(flex: 2),

              // Reveal / Hand Animations Area
              if (_revealed)
                _buildRevealArea(isDark)
              else
                _buildWaitingArea(isDark, connService),

              const Spacer(flex: 3),

              // Buttons Choice Selector / Reset Buttons
              if (!_revealed)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildChoiceCard(context, 'rock', '✊', 'Stein'),
                      _buildChoiceCard(context, 'paper', '✋', 'Papier'),
                      _buildChoiceCard(context, 'scissors', '✌️', 'Schere'),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8A2387),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(200, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                    ),
                    onPressed: _requestReset,
                    icon: const Icon(Icons.replay_rounded),
                    label: const Text('Nächste Runde', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ).animate().scaleXY(begin: 0.8, end: 1.0, duration: 250.ms, curve: Curves.bounceOut),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRevealArea(bool isDark) {
    String emoji(String? choice) {
      if (choice == 'rock') return '✊';
      if (choice == 'paper') return '✋';
      if (choice == 'scissors') return '✌️';
      return '❓';
    }

    final winColor = _roundResult == 'win'
        ? Colors.greenAccent[400]
        : (_roundResult == 'lose' ? Colors.redAccent[400] : Colors.amberAccent[400]);

    final winText = _roundResult == 'win'
        ? 'Rundensieg!'
        : (_roundResult == 'lose' ? 'Gegner gewinnt Runde!' : 'Unentschieden!');

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // My choice
            Column(
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.02),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF00F2FE), width: 2),
                  ),
                  child: Center(
                    child: Text(emoji(_myChoice), style: const TextStyle(fontSize: 48)),
                  ),
                ).animate().scaleXY(begin: 0.2, end: 1.0, duration: 400.ms, curve: Curves.bounceOut),
                const SizedBox(height: 12),
                const Text('Du', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),

            Text(
              'VS',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white24 : Colors.black26,
              ),
            ),

            // Opponent choice
            Column(
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.02),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFFF007F), width: 2),
                  ),
                  child: Center(
                    child: Text(emoji(_opponentChoice), style: const TextStyle(fontSize: 48)),
                  ),
                ).animate().scaleXY(begin: 0.2, end: 1.0, duration: 400.ms, curve: Curves.bounceOut),
                const SizedBox(height: 12),
                const Text('Gegner', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
        
        const SizedBox(height: 32),

        Text(
          winText,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: winColor),
        ).animate().fadeIn(duration: 300.ms).shimmer(duration: 1000.ms),
      ],
    );
  }

  Widget _buildWaitingArea(bool isDark, ConnectivityService service) {
    final locked = _myChoice != null;
    final opponentLocked = _opponentChoice != null;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: locked ? const Color(0xFF00F2FE).withOpacity(0.15) : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: locked ? const Color(0xFF00F2FE) : (isDark ? Colors.white24 : Colors.black26),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                      color: locked ? const Color(0xFF00F2FE) : Colors.grey,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Du', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  locked ? 'Eingeloggt' : 'Wählt...',
                  style: TextStyle(fontSize: 11, color: locked ? const Color(0xFF00F2FE) : Colors.grey),
                ),
              ],
            ),
            
            Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: opponentLocked ? const Color(0xFFFF007F).withOpacity(0.15) : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: opponentLocked ? const Color(0xFFFF007F) : (isDark ? Colors.white24 : Colors.black26),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      opponentLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                      color: opponentLocked ? const Color(0xFFFF007F) : Colors.grey,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(service.connectedPeer?.name ?? 'Gegner', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  opponentLocked ? 'Eingeloggt' : 'Wählt...',
                  style: TextStyle(fontSize: 11, color: opponentLocked ? const Color(0xFFFF007F) : Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChoiceCard(BuildContext context, String value, String emoji, String label) {
    final isSelected = _myChoice == value;
    final hasChosen = _myChoice != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: hasChosen ? null : () => _choose(value),
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        borderRadius: 20,
        gradientColors: isSelected
            ? AppTheme.primaryGradient
            : (hasChosen
                ? [Colors.grey.withOpacity(0.1), Colors.grey.withOpacity(0.05)]
                : null),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 36)),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
