import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:two_play/main.dart';
import 'package:two_play/models/minigolf_levels.dart';
import 'package:two_play/services/connectivity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('splash shows brand and navigates to the lobby',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ConnectivityService(),
        child: const MyApp(),
      ),
    );

    expect(find.text('2Play'), findsOneWidget);

    // Let the splash loading animation finish and the lobby settle in.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Spiel-Lobby'), findsOneWidget);
  });

  group('Minigolf levels', () {
    test('generates 50 unique, bounded levels', () {
      final levels = GolfLevel.generate50Levels();

      expect(levels, hasLength(50));
      expect(levels.map((l) => l.id).toSet(), hasLength(50));

      const field = Rect.fromLTWH(0, 0, 360, 500);
      for (final level in levels) {
        expect(field.contains(level.startPos), isTrue,
            reason: 'start of level ${level.id} outside the field');
        expect(field.contains(level.holePos), isTrue,
            reason: 'hole of level ${level.id} outside the field');
        expect(level.par, greaterThan(0));
        // Every level has the four boundary walls.
        expect(level.walls.length, greaterThanOrEqualTo(4));
      }
    });

    test('moving obstacles animate over time', () {
      final windmill = MovingObstacle(
        id: 'w',
        initialRect: const Rect.fromLTWH(100, 100, 60, 60),
        isRotating: true,
        rotationSpeed: 2.0,
      );
      windmill.update(0.5);
      expect(windmill.currentAngle, closeTo(1.0, 0.0001));

      final slider = MovingObstacle(
        id: 's',
        initialRect: const Rect.fromLTWH(100, 100, 60, 20),
        dx: 1.0,
        range: 30,
      );
      slider.update(0.25);
      expect(slider.currentRect.left, isNot(100.0));
    });
  });
}
