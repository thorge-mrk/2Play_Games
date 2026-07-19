import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';

class RockPaperScissorsScreen extends StatefulWidget {
  const RockPaperScissorsScreen({super.key});

  @override
  State<RockPaperScissorsScreen> createState() =>
      _RockPaperScissorsScreenState();
}

class _RockPaperScissorsScreenState extends State<RockPaperScissorsScreen> {
  String? _myChoice;
  String? _opponentChoice;

  bool _revealed = false;
  int _myScore = 0;
  int _opponentScore = 0;

  String _roundResult = ''; // 'win', 'lose', 'draw'
  StreamSubscription? _msgSubscription;
  bool _isGameOver = false;
  String _winner = '';
  bool _waitingForResetAccept = false;
  bool _statsUpdated = false;
  Timer? _autoProgressTimer;

  @override
  void initState() {
    super.initState();
    final connService =
        Provider.of<ConnectivityService>(context, listen: false);

    _msgSubscription = connService.messageStream.listen((payload) {
      if (!mounted) return;
      if (payload['type'] == 'game_move' &&
          payload['gameId'] == 'rockpaperscissors') {
        final data = payload['data'] as Map<String, dynamic>;
        setState(() {
          if (connService.connectedPeer?.isMock == true) {
            _opponentChoice = data['aiChoice'] as String?;
          } else {
            _opponentChoice = data['userChoice'] as String?;
          }
          _checkReveal();
        });
      } else if (payload['type'] == 'game_reset' &&
          payload['gameId'] == 'rockpaperscissors') {
        connService.sendPayload({
          'type': 'game_reset_accept',
          'gameId': 'rockpaperscissors',
        });
        _resetRound();
      } else if (payload['type'] == 'game_reset_accept' &&
          payload['gameId'] == 'rockpaperscissors') {
        _resetRound();
      } else if (payload['type'] == 'game_exit') {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _msgSubscription?.cancel();
    _autoProgressTimer?.cancel();
    super.dispose();
  }

  void _choose(String choice) {
    if (_myChoice != null) return;

    setState(() => _myChoice = choice);

    Provider.of<ConnectivityService>(context, listen: false).sendPayload({
      'type': 'game_move',
      'gameId': 'rockpaperscissors',
      'data': {'userChoice': choice},
    });

    _checkReveal();
  }

  void _checkReveal() {
    if (_myChoice == null || _opponentChoice == null || _revealed) return;

    setState(() {
      _revealed = true;
      _evaluateRound();
    });
    _updateStats();

    if (!_isGameOver) {
      _autoProgressTimer?.cancel();
      _autoProgressTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        final connService =
            Provider.of<ConnectivityService>(context, listen: false);
        // One side drives the round progression to avoid double resets.
        if (connService.isHost ||
            (connService.connectedPeer?.isMock ?? false)) {
          _requestReset();
        }
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

    if (_myScore >= 3) {
      _isGameOver = true;
      _winner = 'Du';
    } else if (_opponentScore >= 3) {
      _isGameOver = true;
      _winner = 'Gegner';
    }
  }

  void _updateStats() {
    if (_statsUpdated || !_isGameOver) return;
    final connService =
        Provider.of<ConnectivityService>(context, listen: false);
    if (_winner == 'Du') {
      connService.incrementWin('rockpaperscissors');
      _statsUpdated = true;
    } else if (_winner == 'Gegner') {
      connService.incrementLoss('rockpaperscissors');
      _statsUpdated = true;
    }
  }

  void _resetRound() {
    setState(() {
      _myChoice = null;
      _opponentChoice = null;
      _revealed = false;
      _roundResult = '';
      _waitingForResetAccept = false;
      if (_isGameOver) {
        _myScore = 0;
        _opponentScore = 0;
        _isGameOver = false;
        _winner = '';
        _statsUpdated = false;
      }
    });
  }

  void _requestReset() {
    setState(() => _waitingForResetAccept = true);
    Provider.of<ConnectivityService>(context, listen: false).sendPayload({
      'type': 'game_reset',
      'gameId': 'rockpaperscissors',
    });
  }

  Future<void> _exitGame() async {
    final shouldExit = await showExitGameDialog(context);
    if (!shouldExit || !mounted) return;
    Provider.of<ConnectivityService>(context, listen: false).exitGame();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final connService = Provider.of<ConnectivityService>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!connService.hasSession) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      });
      return const SizedBox();
    }

    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _exitGame();
      },
      child: Scaffold(
        body: AppBackground(
          child: Stack(
            children: [
              SafeArea(
                child: isLandscape
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 4,
                            child: SingleChildScrollView(
                              child: Column(
                                children: [
                                  GameHeader(
                                      title: 'Schere, Stein, Papier',
                                      onExit: _exitGame),
                                  const SizedBox(height: 12),
                                  _buildScoreboard(isDark, connService),
                                  const SizedBox(height: 24),
                                  if (_revealed && !_isGameOver)
                                    const _AutoNextHint(),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 5,
                            child: Center(
                              child: _revealed
                                  ? _buildRevealArea(isDark)
                                  : Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        _buildWaitingArea(isDark, connService),
                                        const SizedBox(height: 24),
                                        _buildChoicesRow(context),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          GameHeader(
                              title: 'Schere, Stein, Papier',
                              onExit: _exitGame),
                          const SizedBox(height: 12),
                          _buildScoreboard(isDark, connService),
                          const Spacer(flex: 2),
                          if (_revealed)
                            _buildRevealArea(isDark)
                          else
                            _buildWaitingArea(isDark, connService),
                          const Spacer(flex: 3),
                          if (!_revealed)
                            _buildChoicesRow(context)
                          else
                            const _AutoNextHint(),
                          const Spacer(),
                        ],
                      ),
              ),
              if (_isGameOver) _buildGameOverOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScoreboard(bool isDark, ConnectivityService connService) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        borderRadius: 20,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              children: [
                const Text('DU',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey)),
                const SizedBox(height: 4),
                Text(
                  '$_myScore',
                  style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF00F2FE)),
                ),
              ],
            ),
            Text(
              'PUNKTE (Ziel: 3)',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                color: isDark ? Colors.white24 : Colors.black26,
              ),
            ),
            Column(
              children: [
                Text(
                  (connService.connectedPeer?.name ?? 'GEGNER').toUpperCase(),
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  '$_opponentScore',
                  style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.accentNeonPink),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChoicesRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildChoiceCard(context, 'rock', '✊', 'Stein'),
          _buildChoiceCard(context, 'paper', '✋', 'Papier'),
          _buildChoiceCard(context, 'scissors', '✌️', 'Schere'),
        ],
      ),
    );
  }

  Widget _buildRevealArea(bool isDark) {
    String emoji(String? choice) {
      switch (choice) {
        case 'rock':
          return '✊';
        case 'paper':
          return '✋';
        case 'scissors':
          return '✌️';
        default:
          return '❓';
      }
    }

    final winColor = _roundResult == 'win'
        ? Colors.greenAccent[400]
        : (_roundResult == 'lose'
            ? Colors.redAccent[400]
            : Colors.amberAccent[400]);
    final winText = _roundResult == 'win'
        ? 'Rundensieg!'
        : (_roundResult == 'lose' ? 'Gegner gewinnt Runde!' : 'Unentschieden!');

    Widget bubble(String? choice, Color borderColor, String label) => Column(
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.black.withValues(alpha: 0.02),
                shape: BoxShape.circle,
                border: Border.all(color: borderColor, width: 2),
              ),
              child: Center(
                child:
                    Text(emoji(choice), style: const TextStyle(fontSize: 48)),
              ),
            ).animate().scaleXY(
                begin: 0.2, end: 1.0, duration: 400.ms, curve: Curves.bounceOut),
            const SizedBox(height: 12),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            bubble(_myChoice, const Color(0xFF00F2FE), 'Du'),
            Text(
              'VS',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white24 : Colors.black26,
              ),
            ),
            bubble(_opponentChoice, AppTheme.accentNeonPink, 'Gegner'),
          ],
        ),
        const SizedBox(height: 32),
        Text(
          winText,
          style: TextStyle(
              fontSize: 24, fontWeight: FontWeight.w900, color: winColor),
        ).animate().fadeIn(duration: 300.ms),
      ],
    );
  }

  Widget _buildWaitingArea(bool isDark, ConnectivityService service) {
    final locked = _myChoice != null;
    final opponentLocked = _opponentChoice != null;

    Widget lockIndicator(bool isLocked, Color color, String name) => Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: isLocked
                    ? color.withValues(alpha: 0.15)
                    : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isLocked
                      ? color
                      : (isDark ? Colors.white24 : Colors.black26),
                  width: 2,
                ),
              ),
              child: Center(
                child: Icon(
                  isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                  color: isLocked ? color : Colors.grey,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              isLocked ? 'Eingeloggt' : 'Wählt...',
              style: TextStyle(
                  fontSize: 11, color: isLocked ? color : Colors.grey),
            ),
          ],
        );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        lockIndicator(locked, const Color(0xFF00F2FE), 'Du'),
        lockIndicator(opponentLocked, AppTheme.accentNeonPink,
            service.connectedPeer?.name ?? 'Gegner'),
      ],
    );
  }

  Widget _buildChoiceCard(
      BuildContext context, String value, String emoji, String label) {
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
                ? [
                    Colors.grey.withValues(alpha: 0.1),
                    Colors.grey.withValues(alpha: 0.05)
                  ]
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
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameOverOverlay() {
    final isWin = _winner == 'Du';
    return GameResultOverlay(
      title: isWin ? 'SIEG!' : 'NIEDERLAGE!',
      description: isWin
          ? 'Herzlichen Glückwunsch, du hast das Match gewonnen!'
          : 'Schade, dein Gegner hat das Match gewonnen!',
      color: isWin ? Colors.greenAccent : Colors.redAccent,
      icon: isWin
          ? Icons.emoji_events_rounded
          : Icons.sentiment_very_dissatisfied_rounded,
      extra: Text(
        'Endstand: $_myScore - $_opponentScore',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.amber,
        ),
      ),
      onExit: _exitGame,
      onRematch: _requestReset,
      waitingForRematch: _waitingForResetAccept,
    );
  }
}

class _AutoNextHint extends StatelessWidget {
  const _AutoNextHint();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.0),
      child: Center(
        child: Text(
          'Nächste Runde startet automatisch...',
          style: TextStyle(
              fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey),
        ),
      ),
    );
  }
}
