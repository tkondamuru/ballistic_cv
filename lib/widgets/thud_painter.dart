import 'dart:math';
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
  final int sensorOrientation;

  ThudPainter({
    required this.detection,
    required this.trail,
    required this.recordedHits,
    required this.activeSplashes,
    this.arucoCorners,
    this.sensorOrientation = 90,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (detection == null || detection!.frameWidth == 0 || detection!.frameHeight == 0) {
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
        final p2 = toScreenOffset(trail[i + 1].position.dx, trail[i + 1].position.dy);

        final isPred = trail[i + 1].isPredicted;
        final baseColor = isPred ? Colors.orangeAccent : const Color(0xFF00FF66);

        final trailPaint = Paint()
          ..color = baseColor.withValues(alpha: (0.15 + 0.85 * t).clamp(0.0, 1.0))
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

      final mainColor = detection!.isPredicted ? Colors.orangeAccent : const Color(0xFF00FF66);

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
      canvas.drawLine(center + const Offset(-8, 0), center + const Offset(-4, 0), tickPaint);
      canvas.drawLine(center + const Offset(4, 0), center + const Offset(8, 0), tickPaint);
      canvas.drawLine(center + const Offset(0, -8), center + const Offset(0, -4), tickPaint);
      canvas.drawLine(center + const Offset(0, 4), center + const Offset(0, 8), tickPaint);
    }

    // 3. Draw Persistent Historical Hit Markers on Screen
    for (final hit in recordedHits) {
      final hitCenter = toScreenOffset(hit.cameraPosition.dx, hit.cameraPosition.dy);

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
          shadows: [
            Shadow(color: Colors.black, blurRadius: 4),
          ],
        ),
      );
      final tp = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, hitCenter + const Offset(12, -18));
    }

    // 4. Draw Active Expanding Shockwave Splash Animations
    for (final splash in activeSplashes) {
      final sCenter = toScreenOffset(splash.cameraPosition.dx, splash.cameraPosition.dy);
      final rad = splash.radius;

      // Primary Cyan Shockwave Ring
      final shockwavePaint1 = Paint()
        ..color = Colors.cyanAccent.withValues(alpha: (splash.remainingFrames / 18.0).clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5;
      canvas.drawCircle(sCenter, rad, shockwavePaint1);

      // Secondary Orange Shockwave Ring
      final shockwavePaint2 = Paint()
        ..color = Colors.orangeAccent.withValues(alpha: (splash.remainingFrames / 18.0).clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(sCenter, rad * 0.7, shockwavePaint2);
    }

    // 5. Draw ArUco Ordered Boundary Quad Overlay (bright green lines)
    if (arucoCorners != null && arucoCorners!.length == 4) {
      final ordered = orderArUcoCorners(arucoCorners!);
      final screenQuad = ordered.map((c) => toScreenOffset(c.dx, c.dy)).toList();

      final quadPath = Path()
        ..moveTo(screenQuad[0].dx, screenQuad[0].dy)
        ..lineTo(screenQuad[1].dx, screenQuad[1].dy)
        ..lineTo(screenQuad[2].dx, screenQuad[2].dy)
        ..lineTo(screenQuad[3].dx, screenQuad[3].dy)
        ..close();

      final quadPaint = Paint()
        ..color = const Color(0xFF00FF66)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;

      final fillPaint = Paint()
        ..color = const Color(0xFF00FF66).withValues(alpha: 0.12)
        ..style = PaintingStyle.fill;

      canvas.drawPath(quadPath, fillPaint);
      canvas.drawPath(quadPath, quadPaint);
    }
  }

  @override
  bool shouldRepaint(covariant ThudPainter oldDelegate) => true;
}
