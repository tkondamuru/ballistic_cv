import 'package:flutter_test/flutter_test.dart';
import 'package:ballistic_cv/geometry/homography.dart';

void main() {
  group('Homography Quad Normalization Tests', () {
    final quad = const [
      Offset(100, 100), // TL (0, 0)
      Offset(500, 120), // TR (1, 0)
      Offset(480, 450), // BR (1, 1)
      Offset(120, 400), // BL (0, 1)
    ];

    test('TL corner maps to (0, 0)', () {
      final res = Homography.normalize(const Offset(100, 100), quad);
      expect(res.dx, closeTo(0.0, 0.01));
      expect(res.dy, closeTo(0.0, 0.01));
    });

    test('TR corner maps to (1, 0)', () {
      final res = Homography.normalize(const Offset(500, 120), quad);
      expect(res.dx, closeTo(1.0, 0.01));
      expect(res.dy, closeTo(0.0, 0.01));
    });

    test('BR corner maps to (1, 1)', () {
      final res = Homography.normalize(const Offset(480, 450), quad);
      expect(res.dx, closeTo(1.0, 0.01));
      expect(res.dy, closeTo(1.0, 0.01));
    });

    test('BL corner maps to (0, 1)', () {
      final res = Homography.normalize(const Offset(120, 400), quad);
      expect(res.dx, closeTo(0.0, 0.01));
      expect(res.dy, closeTo(1.0, 0.01));
    });

    test('Quad center maps to (0.5, 0.5)', () {
      // Midpoint of diagonals
      final center = Offset(
        (100 + 500 + 480 + 120) / 4,
        (100 + 120 + 450 + 400) / 4,
      );
      final res = Homography.normalize(center, quad);
      expect(res.dx, closeTo(0.5, 0.05));
      expect(res.dy, closeTo(0.5, 0.05));
    });
  });
}
