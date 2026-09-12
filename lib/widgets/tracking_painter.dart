import 'dart:math';
import 'package:flutter/material.dart';
import '../native/native_cv.dart';

class TrackingPoint {
  final Offset position;
  final double radius;
  final bool isPredicted;
  final DateTime timestamp;

  TrackingPoint({
    required this.position,
    required this.radius,
    required this.isPredicted,
    required this.timestamp,
  });
}

class TrackingPainter extends CustomPainter {
  final DetectionResult? detection;
  final List<TrackingPoint> trail;
  final int sensorOrientation;

  TrackingPainter({
    required this.detection,
    required this.trail,
    this.sensorOrientation = 90,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (detection == null || detection!.frameWidth == 0 || detection!.frameHeight == 0) {
      return;
    }

    final double frameW = detection!.frameWidth.toDouble();
    final double frameH = detection!.frameHeight.toDouble();

    // Sensor to screen coordinate transformation
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

    // Velocity vector transformation
    Offset toScreenVector(double vx, double vy) {
      if (sensorOrientation == 90) {
        final screenVx = -vy * (size.width / frameH);
        final screenVy = vx * (size.height / frameW);
        return Offset(screenVx, screenVy);
      } else {
        final screenVx = vx * (size.width / frameW);
        final screenVy = vy * (size.height / frameH);
        return Offset(screenVx, screenVy);
      }
    }

    // 1. Draw Fading Comet Trail (matching track_video.py)
    if (trail.length > 1) {
      for (int i = 0; i < trail.length - 1; i++) {
        final t = (i + 1) / trail.length; // 0.0 -> 1.0 (head)
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

    // 2. Draw Detected Ball Reticle & Target Rings
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
  }

  @override
  bool shouldRepaint(covariant TrackingPainter oldDelegate) => true;
}
