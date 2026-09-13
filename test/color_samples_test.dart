import 'package:flutter_test/flutter_test.dart';
import 'package:ballistic_cv/calibration/color_samples.dart';

void main() {
  test('white ball uses saturation and brightness, not unstable hue', () {
    final p = combineSamples([
      List.filled(100, const HsvPixel(25, 5, 220)),
      List.filled(100, const HsvPixel(100, 10, 170)),
    ]);
    expect(p.hMin, 0);
    expect(p.hMax, 179);
    expect(matchesProfile(const HsvPixel(150, 10, 200), p), isTrue);
    expect(matchesProfile(const HsvPixel(25, 200, 200), p), isFalse);
  });
  test('combines lighting changes without accepting unrelated hues', () {
    final p = combineSamples([
      List.filled(100, const HsvPixel(60, 180, 210)),
      List.filled(100, const HsvPixel(62, 160, 120)),
      List.filled(100, const HsvPixel(59, 170, 180)),
    ]);
    expect(matchesProfile(const HsvPixel(61, 170, 130), p), isTrue);
    expect(matchesProfile(const HsvPixel(110, 170, 130), p), isFalse);
  });
  test('trims isolated glare and background pixels', () {
    final p = combineSamples([
      [
        ...List.filled(95, const HsvPixel(60, 180, 180)),
        ...List.filled(5, const HsvPixel(110, 0, 255)),
      ],
    ]);
    expect(p.hMin, 55);
    expect(p.hMax, 65);
    expect(p.sMin, 150);
  });
  test('red samples cross the hue seam without matching green', () {
    final p = combineSamples([
      List.filled(100, const HsvPixel(179, 200, 200)),
      List.filled(100, const HsvPixel(1, 200, 150)),
      List.filled(100, const HsvPixel(0, 200, 180)),
    ]);
    expect(p.hMin, greaterThan(p.hMax));
    expect(matchesProfile(const HsvPixel(179, 200, 180), p), isTrue);
    expect(matchesProfile(const HsvPixel(1, 200, 180), p), isTrue);
    expect(matchesProfile(const HsvPixel(60, 200, 180), p), isFalse);
  });
  test('rejects incompatible samples instead of broadening to all colors', () {
    expect(
      () => combineSamples([
        List.filled(100, const HsvPixel(30, 200, 200)),
        List.filled(100, const HsvPixel(100, 200, 200)),
      ]),
      throwsStateError,
    );
  });
}
