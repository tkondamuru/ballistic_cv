import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:ballistic_cv/models/thud_hit.dart';

void main() {
  group('Thud Impact & Deflection Angle Calculation Tests', () {
    test('Calculates 180 degree direct rebound deflection', () {
      final vInX = 15.0, vInY = 0.0;
      final vOutX = -12.0, vOutY = 0.0;

      final angleInRad = math.atan2(vInY, vInX);
      final angleOutRad = math.atan2(vOutY, vOutX);

      var diffDeg = ((angleOutRad - angleInRad) * (180.0 / math.pi)).abs() % 360.0;
      if (diffDeg > 180.0) {
        diffDeg = 360.0 - diffDeg;
      }

      expect(diffDeg, closeTo(180.0, 0.1));
    });

    test('Calculates 90 degree perpendicular deflection', () {
      final vInX = 10.0, vInY = 0.0;
      final vOutX = 0.0, vOutY = 10.0;

      final angleInRad = math.atan2(vInY, vInX);
      final angleOutRad = math.atan2(vOutY, vOutX);

      var diffDeg = ((angleOutRad - angleInRad) * (180.0 / math.pi)).abs() % 360.0;
      if (diffDeg > 180.0) {
        diffDeg = 360.0 - diffDeg;
      }

      expect(diffDeg, closeTo(90.0, 0.1));
    });

    test('ThudHit model instantiation', () {
      final hit = ThudHit(
        number: 1,
        cameraPosition: const Offset(120.0, 240.0),
        deflectionDegrees: 45.0,
        timestamp: DateTime.now(),
      );

      expect(hit.number, equals(1));
      expect(hit.cameraPosition, equals(const Offset(120.0, 240.0)));
      expect(hit.deflectionDegrees, equals(45.0));
    });
  });
}
