import 'dart:math';
import '../detection/impact_detector.dart';
import 'package:flutter/material.dart';
import '../models/thud_hit.dart';
import '../native/native_cv.dart';
import 'tracking_painter.dart';

class ActiveSplash {
  final int hitNumber;
  final Offset cameraPosition;
  final double deflectionDegrees;
  double radius;
  int remainingFrames;

  ActiveSplash({
    required this.hitNumber,
    required this.cameraPosition,
    required this.deflectionDegrees,
    this.radius = 16.0,
    this.remainingFrames = 18,
  });
}

class FrameHitEstimate {
  final double framesToHit;
  final double msToHit;
  final Offset intersectionPoint;

  FrameHitEstimate({
    required this.framesToHit,
    required this.msToHit,
    required this.intersectionPoint,
  });
}

/// Calculates analytical ray intersection between ball trajectory and wall boundary quad
FrameHitEstimate? calculateFramesToHit({
  required Offset ballPos,
  required Offset ballVel,
  required List<Offset> quad,
  required double fps,
}) {
  final speed = ballVel.distance;
  if (speed < 0.5 || quad.length != 4) return null;

  double? minT;
  Offset? bestIntersection;

  for (int i = 0; i < 4; i++) {
    final a = quad[i];
    final b = quad[(i + 1) % 4];

    final vx = ballVel.dx;
    final vy = ballVel.dy;
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;

    final denom = vx * dy - vy * dx;
    if (denom.abs() < 0.0001) continue;

    final t = ((a.dx - ballPos.dx) * dy - (a.dy - ballPos.dy) * dx) / denom;
    final s = ((a.dx - ballPos.dx) * vy - (a.dy - ballPos.dy) * vx) / denom;

    if (t > 0 && s >= 0.0 && s <= 1.0) {
      if (minT == null || t < minT) {
        minT = t;
        bestIntersection = Offset(ballPos.dx + t * vx, ballPos.dy + t * vy);
      }
    }
  }

  if (minT != null && bestIntersection != null) {
    final effectiveFps = fps > 0 ? fps : 60.0;
    return FrameHitEstimate(
      framesToHit: minT,
      msToHit: (minT / effectiveFps) * 1000.0,
      intersectionPoint: bestIntersection,
    );
  }
  return null;
}

/// Orders 4 detected ArUco corner points into canonical [TL, TR, BR, BL] order
/// by sorting their (x, y) coordinates regardless of detection input order.
List<Offset> orderArUcoCorners(List<Offset> points) {
  if (points.length != 4) return points;
  final sorted = List<Offset>.from(points);
  sorted.sort((a, b) => (a.dx + a.dy).compareTo(b.dx + b.dy));
  final tl = sorted[0];
  final br = sorted[3];

  final remaining = [sorted[1], sorted[2]];
  remaining.sort((a, b) => (a.dy - a.dx).compareTo(b.dy - b.dx));
  final tr = remaining[0];
  final bl = remaining[1];

  return [tl, tr, br, bl];
}

class ThudPainter extends CustomPainter {
  final DetectionResult? detection;
  final List<TrackingPoint> trail;
  final List<ThudHit> recordedHits;
  final List<ActiveSplash> activeSplashes;
  final List<Offset>? arucoCorners;
  final bool isBoundaryLocked;
  final int sensorOrientation;
  final double fps;

  ThudPainter({
    required this.detection,
    required this.trail,
    required this.recordedHits,
    required this.activeSplashes,
    this.arucoCorners,
    this.isBoundaryLocked = false,
    this.sensorOrientation = 90,
    this.fps = 60.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (detection == null ||
        detection!.frameWidth == 0 ||
        detection!.frameHeight == 0) {
      return;
    }

    final double frameW = detection!.frameWidth.toDouble();
    final double frameH = detection!.frameHeight.toDouble();

    Offset toScreenOffset(double camX, double camY) {
      if (sensorOrientation == 90 && frameW > frameH) {
        final screenX = (1.0 - (camY / frameH)) * size.width;
        final screenY = (camX / frameW) * size.height;
        return Offset(screenX, screenY);
      } else {
        final screenX = (camX / frameW) * size.width;
        final screenY = (camY / frameH) * size.height;
        return Offset(screenX, screenY);
      }
    }

    Offset toScreenVector(double vx, double vy) {
      if (sensorOrientation == 90 && frameW > frameH) {
        final screenVx = -vy * (size.width / frameH);
        final screenVy = vx * (size.height / frameW);
        return Offset(screenVx, screenVy);
      } else {
        final screenVx = vx * (size.width / frameW);
        final screenVy = vy * (size.height / frameH);
        return Offset(screenVx, screenVy);
      }
    }

    // 1. Draw Fading Comet Trail
    if (trail.length > 1) {
      for (int i = 0; i < trail.length - 1; i++) {
        final t = (i + 1) / trail.length;
        final p1 = toScreenOffset(trail[i].position.dx, trail[i].position.dy);
        final p2 = toScreenOffset(
          trail[i + 1].position.dx,
          trail[i + 1].position.dy,
        );

        final isPred = trail[i + 1].isPredicted;
        final baseColor = isPred
            ? Colors.orangeAccent
            : const Color(0xFF00FF66);

        final trailPaint = Paint()
          ..color = baseColor.withValues(
            alpha: (0.15 + 0.85 * t).clamp(0.0, 1.0),
          )
          ..strokeWidth = 2.0 + 4.0 * t
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;

        canvas.drawLine(p1, p2, trailPaint);
      }
    }

    // 2. Draw Live Ball Target Reticle (identically matched to TrackingPainter)
    if (detection != null && detection!.detected) {
      final center = toScreenOffset(detection!.x, detection!.y);
      final radius = max(18.0, detection!.radius * (size.width / frameH));

      final mainColor = detection!.isPredicted
          ? Colors.orangeAccent
          : const Color(0xFF00FF66);

      // Outer glow
      final glowPaint = Paint()
        ..color = mainColor.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(center, radius + 4, glowPaint);

      // Main target circle
      final ringPaint = Paint()
        ..color = mainColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      canvas.drawCircle(center, radius, ringPaint);

      // Velocity direction arrow
      final vVector = toScreenVector(detection!.vx, detection!.vy);
      final speed = vVector.distance;
      if (speed > 2.0) {
        final arrowEnd = center + vVector * 0.4;
        final arrowPaint = Paint()
          ..color = Colors.cyanAccent
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round;

        canvas.drawLine(center, arrowEnd, arrowPaint);
        canvas.drawCircle(arrowEnd, 3.5, Paint()..color = Colors.cyanAccent);
      }

      // Center crosshair dot
      final crossPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, 3.0, crossPaint);

      // Crosshair tick marks
      final tickPaint = Paint()
        ..color = mainColor
        ..strokeWidth = 2.0;
      canvas.drawLine(
        center + const Offset(-8, 0),
        center + const Offset(-4, 0),
        tickPaint,
      );
      canvas.drawLine(
        center + const Offset(4, 0),
        center + const Offset(8, 0),
        tickPaint,
      );
      canvas.drawLine(
        center + const Offset(0, -8),
        center + const Offset(0, -4),
        tickPaint,
      );
      canvas.drawLine(
        center + const Offset(0, 4),
        center + const Offset(0, 8),
        tickPaint,
      );
    }

    // 3. Draw Persistent Historical Hit Markers on Screen
    for (final hit in recordedHits) {
      final hitCenter = toScreenOffset(
        hit.cameraPosition.dx,
        hit.cameraPosition.dy,
      );

      // Outer Red Bullseye Ring
      final hitRingPaint = Paint()
        ..color = Colors.redAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawCircle(hitCenter, 18.0, hitRingPaint);

      // Inner Red Dot
      final hitDotPaint = Paint()
        ..color = Colors.redAccent
        ..style = PaintingStyle.fill;
      canvas.drawCircle(hitCenter, 5.0, hitDotPaint);

      // Number & Angle Badge
      final textSpan = TextSpan(
        text: '#${hit.number} (${hit.deflectionDegrees.toStringAsFixed(0)}°)',
        style: const TextStyle(
          color: Colors.redAccent,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      );
      final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, hitCenter + const Offset(12, -18));
    }

    // 4. Draw Active Expanding Shockwave Splash Animations
    for (final splash in activeSplashes) {
      final sCenter = toScreenOffset(
        splash.cameraPosition.dx,
        splash.cameraPosition.dy,
      );
      final rad = splash.radius;

      // Primary Cyan Shockwave Ring
      final shockwavePaint1 = Paint()
        ..color = Colors.cyanAccent.withValues(
          alpha: (splash.remainingFrames / 18.0).clamp(0.0, 1.0),
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5;
      canvas.drawCircle(sCenter, rad, shockwavePaint1);

      // Secondary Orange Shockwave Ring
      final shockwavePaint2 = Paint()
        ..color = Colors.orangeAccent.withValues(
          alpha: (splash.remainingFrames / 18.0).clamp(0.0, 1.0),
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(sCenter, rad * 0.7, shockwavePaint2);
    }

    // 5. Draw Ordered Boundary Quad Overlay & Wall Center Crosshair
    if (arucoCorners != null && arucoCorners!.length == 4) {
      final ordered = orderArUcoCorners(arucoCorners!);
      final screenQuad = ordered
          .map((c) => toScreenOffset(c.dx, c.dy))
          .toList();

      final quadPath = Path()
        ..moveTo(screenQuad[0].dx, screenQuad[0].dy)
        ..lineTo(screenQuad[1].dx, screenQuad[1].dy)
        ..lineTo(screenQuad[2].dx, screenQuad[2].dy)
        ..lineTo(screenQuad[3].dx, screenQuad[3].dy)
        ..close();

      bool inWallZone = false;
      if (isBoundaryLocked && detection != null && detection!.detected) {
        final pos = Offset(detection!.x, detection!.y);
        inWallZone = ImpactDetector.insideBoard(pos, arucoCorners!);
      }

      final Color baseQuadColor = isBoundaryLocked
          ? (inWallZone ? const Color(0xFFFFCC00) : const Color(0xFF00FF66))
          : Colors.orangeAccent;

      if (inWallZone) {
        // Outer Glow when ball is in wall zone
        final glowPaint = Paint()
          ..color = baseQuadColor.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10.0
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
        canvas.drawPath(quadPath, glowPaint);
      }

      final quadPaint = Paint()
        ..color = baseQuadColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = isBoundaryLocked ? (inWallZone ? 4.5 : 3.0) : 2.5;

      final fillPaint = Paint()
        ..color = baseQuadColor.withValues(
          alpha: isBoundaryLocked ? (inWallZone ? 0.22 : 0.12) : 0.06,
        )
        ..style = PaintingStyle.fill;

      canvas.drawPath(quadPath, fillPaint);
      canvas.drawPath(quadPath, quadPaint);

      // Draw Wall Center Crosshair
      final wallCenterScreen = Offset(
        (screenQuad[0].dx + screenQuad[1].dx + screenQuad[2].dx + screenQuad[3].dx) / 4,
        (screenQuad[0].dy + screenQuad[1].dy + screenQuad[2].dy + screenQuad[3].dy) / 4,
      );

      final centerCrossPaint = Paint()
        ..color = const Color(0xFF00E5FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(wallCenterScreen, 6.0, centerCrossPaint);
      canvas.drawLine(
        wallCenterScreen + const Offset(-10, 0),
        wallCenterScreen + const Offset(10, 0),
        centerCrossPaint,
      );
      canvas.drawLine(
        wallCenterScreen + const Offset(0, -10),
        wallCenterScreen + const Offset(0, 10),
        centerCrossPaint,
      );

      final centerTextSpan = const TextSpan(
        text: 'WALL CENTER',
        style: TextStyle(
          color: Color(0xFF00E5FF),
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      );
      final centerTp = TextPainter(text: centerTextSpan, textDirection: TextDirection.ltr)
        ..layout();
      centerTp.paint(canvas, wallCenterScreen + const Offset(12, -6));

      // On-screen Status Badge when in Wall Contact Zone
      if (inWallZone) {
        final textSpan = TextSpan(
          text: 'BALL IN BOARD AREA',
          style: TextStyle(
            color: const Color(0xFFFFCC00),
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
          ),
        );
        final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)
          ..layout();
        tp.paint(canvas, Offset((size.width - tp.width) / 2, 45.0));
      }

      // 6. Live Trajectory & Impact Frame Countdown Badge
      if (detection != null && detection!.detected && (detection!.vx.abs() > 0.5 || detection!.vy.abs() > 0.5)) {
        final ballPos = Offset(detection!.x, detection!.y);
        final ballVel = Offset(detection!.vx, detection!.vy);

        final estimate = calculateFramesToHit(
          ballPos: ballPos,
          ballVel: ballVel,
          quad: arucoCorners!,
          fps: fps,
        );

        if (estimate != null) {
          final impactScreen = toScreenOffset(
            estimate.intersectionPoint.dx,
            estimate.intersectionPoint.dy,
          );
          final ballScreen = toScreenOffset(ballPos.dx, ballPos.dy);

          // Ray line to wall impact point
          final rayPaint = Paint()
            ..color = Colors.orangeAccent
            ..strokeWidth = 2.0
            ..style = PaintingStyle.stroke;
          canvas.drawLine(ballScreen, impactScreen, rayPaint);

          // Impact Reticle
          canvas.drawCircle(
            impactScreen,
            8.0,
            Paint()
              ..color = Colors.orangeAccent
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5,
          );

          // Countdown Badge HUD
          final badgeText =
              'EST. HIT IN: ${estimate.framesToHit.toStringAsFixed(1)} FRAMES (${estimate.msToHit.toStringAsFixed(0)}ms)';
          final badgeSpan = TextSpan(
            text: badgeText,
            style: const TextStyle(
              color: Colors.orangeAccent,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
              shadows: [Shadow(color: Colors.black, blurRadius: 6)],
            ),
          );
          final badgeTp = TextPainter(text: badgeSpan, textDirection: TextDirection.ltr)
            ..layout();
          badgeTp.paint(canvas, Offset((size.width - badgeTp.width) / 2, 70.0));
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant ThudPainter oldDelegate) => true;
}
