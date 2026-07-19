import 'dart:math';
import 'package:flutter/material.dart';

class MovingObstacle {
  final String id;
  final Rect initialRect;
  final double dx; // Speed X
  final double dy; // Speed Y
  final double range; // Slide range
  final bool isRotating;
  final double rotationSpeed; // Radians per frame

  // Runtime tracking variables
  double currentOffset = 0;
  int direction = 1;
  double currentAngle = 0;

  MovingObstacle({
    required this.id,
    required this.initialRect,
    this.dx = 0,
    this.dy = 0,
    this.range = 0,
    this.isRotating = false,
    this.rotationSpeed = 0,
  });

  Rect get currentRect {
    if (isRotating) return initialRect;
    final offsetMultiplier = currentOffset;
    return initialRect.translate(dx * offsetMultiplier, dy * offsetMultiplier);
  }

  void update(double dt) {
    if (isRotating) {
      currentAngle = (currentAngle + rotationSpeed * dt) % (2 * pi);
    } else if (range > 0) {
      currentOffset += direction * dt * 60; // 60 units per second scale
      if (currentOffset.abs() >= range) {
        currentOffset = range * direction;
        direction *= -1; // Reverse direction
      }
    }
  }
}

class GolfLevel {
  final int id;
  final String name;
  final int par;
  final Offset startPos;
  final Offset holePos;
  final List<Rect> walls;
  final List<Rect> sandTraps;
  final List<Rect> iceSheets;
  final List<Rect> waterHazards;
  final List<MovingObstacle> movingObstacles;

  GolfLevel({
    required this.id,
    required this.name,
    required this.par,
    required this.startPos,
    required this.holePos,
    this.walls = const [],
    this.sandTraps = const [],
    this.iceSheets = const [],
    this.waterHazards = const [],
    this.movingObstacles = const [],
  });

  static List<GolfLevel> generate50Levels() {
    final List<GolfLevel> levels = [];

    // Let's programmatically define 50 distinct levels on a 360 x 500 playing field
    for (int i = 1; i <= 50; i++) {
      String name = '';
      int par = 3;
      Offset start = const Offset(180, 440);
      Offset hole = const Offset(180, 80);
      List<Rect> levelWalls = [];
      List<Rect> sand = [];
      List<Rect> ice = [];
      List<Rect> water = [];
      List<MovingObstacle> movers = [];

      // Add default field boundary walls to all levels
      // left, right, top, bottom
      levelWalls.addAll([
        const Rect.fromLTWH(0, 0, 12, 500),
        const Rect.fromLTWH(348, 0, 12, 500),
        const Rect.fromLTWH(0, 0, 360, 12),
        const Rect.fromLTWH(0, 488, 360, 12),
      ]);

      if (i == 1) {
        name = 'Erster Abschlag';
        par = 2;
        // Simple straight shot, no obstacles
      } else if (i == 2) {
        name = 'Sandkiste';
        par = 3;
        sand.add(const Rect.fromLTWH(100, 200, 160, 100)); // Sand trap in the middle
      } else if (i == 3) {
        name = 'Gleitbahn';
        par = 3;
        ice.add(const Rect.fromLTWH(60, 180, 240, 140)); // Ice sheet in the middle
      } else if (i == 4) {
        name = 'Teichüberquerung';
        par = 3;
        water.add(const Rect.fromLTWH(60, 200, 240, 80)); // Water hazard in the middle
      } else if (i == 5) {
        name = 'Die Wand';
        par = 3;
        levelWalls.add(const Rect.fromLTWH(60, 240, 240, 20)); // Wall in center block
      } else if (i == 6) {
        name = 'L-Kurve';
        par = 3;
        hole = const Offset(60, 80);
        levelWalls.add(const Rect.fromLTWH(120, 0, 20, 350)); // Vertical wall forming L
      } else if (i == 7) {
        name = 'Nadelöhr';
        par = 4;
        levelWalls.add(const Rect.fromLTWH(0, 240, 140, 20));
        levelWalls.add(const Rect.fromLTWH(220, 240, 140, 20)); // Narrow gap in middle (gap = 80 wide)
      } else if (i == 8) {
        name = 'Das Windrad';
        par = 4;
        movers.add(MovingObstacle(
          id: 'windmill_8',
          initialRect: const Rect.fromLTWH(150, 220, 60, 60),
          isRotating: true,
          rotationSpeed: 1.5,
        ));
      } else if (i == 9) {
        name = 'Schiebetür';
        par = 4;
        movers.add(MovingObstacle(
          id: 'slider_9',
          initialRect: const Rect.fromLTWH(120, 240, 120, 20),
          dx: 0.8,
          range: 80,
        ));
      } else if (i == 10) {
        name = 'Zick-Zack';
        par = 4;
        levelWalls.add(const Rect.fromLTWH(0, 160, 260, 20));
        levelWalls.add(const Rect.fromLTWH(100, 320, 260, 20));
      }

      // programmatically generate levels 11 to 50
      else {
        // Varying difficulty patterns
        if (i % 5 == 1) {
          name = 'Eiskorridor $i';
          par = 3 + (i % 3);
          start = Offset(60.0 + (i % 4) * 60, 440);
          hole = Offset(300.0 - (i % 4) * 60, 80);
          ice.add(Rect.fromLTWH(40, 150, 280, 200));
          levelWalls.add(Rect.fromLTWH(100, 120, 20, 260));
          levelWalls.add(Rect.fromLTWH(240, 120, 20, 260));
        } else if (i % 5 == 2) {
          name = 'Wasser-Slalom $i';
          par = 4 + (i % 2);
          water.add(Rect.fromLTWH(20, 150, 140, 60));
          water.add(Rect.fromLTWH(200, 290, 140, 60));
          sand.add(Rect.fromLTWH(120, 220, 120, 50));
          levelWalls.add(Rect.fromLTWH(120, 120, 120, 20));
        } else if (i % 5 == 3) {
          name = 'Doppel-Windrad $i';
          par = 5;
          movers.add(MovingObstacle(
            id: 'windmill_${i}_a',
            initialRect: const Rect.fromLTWH(80, 220, 50, 50),
            isRotating: true,
            rotationSpeed: 2.0,
          ));
          movers.add(MovingObstacle(
            id: 'windmill_${i}_b',
            initialRect: const Rect.fromLTWH(230, 220, 50, 50),
            isRotating: true,
            rotationSpeed: -2.0,
          ));
          levelWalls.add(Rect.fromLTWH(170, 180, 20, 140));
        } else if (i % 5 == 4) {
          name = 'Bewegliche Wache $i';
          par = 4;
          movers.add(MovingObstacle(
            id: 'slider_$i',
            initialRect: const Rect.fromLTWH(80, 220, 100, 20),
            dx: 1.2,
            range: 100,
          ));
          sand.add(Rect.fromLTWH(120, 100, 120, 80));
        } else {
          // Hard / Boss level configurations
          name = 'Das Labyrinth $i';
          par = 5;
          if (i == 50) {
            name = 'Das Grosse Finale';
            par = 6;
          }
          
          // Generate a programmatic maze
          levelWalls.add(const Rect.fromLTWH(0, 150, 200, 20));
          levelWalls.add(const Rect.fromLTWH(160, 270, 200, 20));
          levelWalls.add(const Rect.fromLTWH(0, 380, 240, 20));
          
          // Add a windmill and a slider to final boss levels
          if (i >= 40) {
            movers.add(MovingObstacle(
              id: 'windmill_$i',
              initialRect: const Rect.fromLTWH(80, 80, 40, 40),
              isRotating: true,
              rotationSpeed: 2.5,
            ));
            movers.add(MovingObstacle(
              id: 'slider_$i',
              initialRect: const Rect.fromLTWH(100, 310, 80, 20),
              dx: 1.5,
              range: 80,
            ));
            water.add(const Rect.fromLTWH(100, 180, 160, 60));
          }
        }
      }

      levels.add(GolfLevel(
        id: i,
        name: name,
        par: par,
        startPos: start,
        holePos: hole,
        walls: levelWalls,
        sandTraps: sand,
        iceSheets: ice,
        waterHazards: water,
        movingObstacles: movers,
      ));
    }

    return levels;
  }
}
