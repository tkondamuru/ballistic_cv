import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ballistic_cv/models/board_alignment.dart';

void main() {
  test('cutoff follows tilted lower edge and keeps a five pixel margin', () {
    final line = BoardAlignment.cutoff([
      const Offset(10, 10),
      const Offset(90, 10),
      const Offset(90, 70),
      const Offset(10, 50),
    ])!;
    double side(double x, double y) => line[0] * x + line[1] * y + line[2];
    expect(side(50, 30), greaterThan(0));
    expect(side(50, 63), greaterThan(0));
    expect(side(50, 80), lessThan(0));
    expect(side(0, 30), greaterThan(0));
  });
  test(
    'restores saved corners per zoom/camera and scales matching frames',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final points = BoardAlignment.initial(288, 352);
      await BoardAlignment.save(prefs, 'back', 1.2, 288, 352, points);
      await prefs.reload();
      expect(BoardAlignment.load(prefs, 'back', 1.2, 288, 352), points);
      expect(BoardAlignment.load(prefs, 'back', 1.3, 288, 352), isNull);
      expect(BoardAlignment.load(prefs, 'front', 1.2, 288, 352), isNull);
      expect(BoardAlignment.load(prefs, 'back', 1.2, 352, 288), isNull);
      expect(
        BoardAlignment.load(prefs, 'back', 1.2, 576, 704),
        points.map((p) => p * 2).toList(),
      );
    },
  );
  test('rejects crossed corners and starts clear of lower controls', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final points = BoardAlignment.initial(288, 352);
    expect(points.every((p) => p.dy <= 352 * .62), isTrue);
    await expectLater(
      BoardAlignment.save(prefs, 'back', 1, 288, 352, [
        points[0],
        points[2],
        points[1],
        points[3],
      ]),
      throwsStateError,
    );
  });
}
