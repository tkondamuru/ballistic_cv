import 'package:flutter/material.dart';

class ThudHit {
  final int number;
  final Offset cameraPosition; // (x, y) center in camera sensor space
  final double deflectionDegrees; // Angle of deflection in degrees
  final DateTime timestamp;

  const ThudHit({
    required this.number,
    required this.cameraPosition,
    required this.deflectionDegrees,
    required this.timestamp,
  });
}
