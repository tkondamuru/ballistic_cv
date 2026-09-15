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

class ThudPainter extends CustomPainter {
  final DetectionResult? detection;
  final List<TrackingPoint> trail;
  final List<ThudHit> recordedHits;
  final List<ActiveSplash> activeSplashes;
  final int sensorOrientation;

  ThudPainter({
    required this.detection,
    required this.trail,
    required this.recordedHits,
    required this.activeSplashes,
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
      if (sensorOrientation == 90) {
        final screenX = (1.0 - (camY / frameH)) * size.width;
        final screenY = (camX / frameW) * size.height;
        return Offset(screenX, screenY);
      } else {
        final screenX = (camX / frameW) * size.width;
        final screenY = (camY / frameH) * size.height;
        return Offset(screenX, screenY);
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
          ..strokeWidth = 2.0 + 3.5 * t
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;

        canvas.drawLine(p1, p2, trailPaint);
      }
    }

    // 2. Draw Live Ball Target Reticle
    if (detection != null && detection!.detected) {
      final center = toScreenOffset(detection!.x, detection!.y);
      final radius = max(18.0, detection!.radius * (size.width / frameH));
      final mainColor = detection!.isPredicted ? Colors.orangeAccent : const Color(0xFF00FF66);

      // Target ring
      final ringPaint = Paint()
        ..color = mainColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      canvas.drawCircle(center, radius, ringPaint);

      // Center crosshair
      final crossPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, 3.0, crossPaint);
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
      canvas.drawCircle(sCenter, rad * 1.5, shockwavePaint2);

      // Impact Callout Text Banner
      final bannerSpan = TextSpan(
        text: 'THUD #${splash.hitNumber}! (${splash.deflectionDegrees.toStringAsFixed(0)}°)',
        style: const TextStyle(
          color: Colors.yellowAccent,
          fontSize: 16,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
          shadows: [
            Shadow(color: Colors.black, blurRadius: 6),
          ],
        ),
      );
      final btp = TextPainter(
        text: bannerSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      btp.paint(canvas, sCenter + Offset(-btp.width / 2, -rad - 24));
    }
  }

  @override
  bool shouldRepaint(covariant ThudPainter oldDelegate) => true;
}
