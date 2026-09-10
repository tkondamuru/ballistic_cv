import 'dart:math';
import 'package:flutter/material.dart';
import '../native/native_cv.dart';

class TrackingPoint {
  final Offset position;
  final double radius;
  final DateTime timestamp;

  TrackingPoint({
    required this.position,
    required this.radius,
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

    // Transform camera sensor coordinates to Flutter screen coordinates
    // On Android/iOS in portrait, sensor coordinates are rotated 90 degrees:
    // camera X -> screen Y, camera Y -> screen (width - X)
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
        final t = (i + 1) / trail.length; // 0.0 -> 1.0 (head)
        final p1 = toScreenOffset(trail[i].position.dx, trail[i].position.dy);
        final p2 = toScreenOffset(trail[i + 1].position.dx, trail[i + 1].position.dy);

        final trailPaint = Paint()
          ..color = Colors.cyanAccent.withValues(alpha: 0.15 + 0.85 * t)
          ..strokeWidth = 1.5 + 3.5 * t
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;

        canvas.drawLine(p1, p2, trailPaint);
      }
    }

    // 2. Draw Detected Ball Reticle & Target Rings
    if (detection != null && detection!.detected) {
      final center = toScreenOffset(detection!.x, detection!.y);
      final radius = max(18.0, detection!.radius * (size.width / frameH));

      // Outer glow
      final glowPaint = Paint()
        ..color = const Color(0xFF00FF66).withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(center, radius + 4, glowPaint);

      // Main neon green target circle
      final ringPaint = Paint()
        ..color = const Color(0xFF00FF66)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      canvas.drawCircle(center, radius, ringPaint);

      // Center crosshair
      final crossPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, 3.0, crossPaint);

      // Crosshair tick marks
      final tickPaint = Paint()
        ..color = const Color(0xFF00FF66)
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
