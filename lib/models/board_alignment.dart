import 'dart:convert';
import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';
import '../detection/impact_detector.dart';

/// Store normalized camera coordinates, keyed by camera and zoom. A different
/// zoom is a different calibration; never silently reuse it as a locked board.
class BoardAlignment {
  /// Half-plane toward the board interior, extended across the image. The
  /// five-pixel margin admits centers just below the calibrated lower edge.
  static List<double>? cutoff(List<Offset>? board, {double margin = 5}) {
    if (board == null || !valid(board)) return null;
    final edge = board[3] - board[2];
    final length = edge.distance;
    var a = -edge.dy / length;
    var b = edge.dx / length;
    var c = -(a * board[2].dx + b * board[2].dy);
    final upper = (board[0] + board[1]) / 2;
    if (a * upper.dx + b * upper.dy + c < 0) {
      a = -a;
      b = -b;
      c = -c;
    }
    return [a, b, c + margin];
  }

  static String _key(String camera, double zoom) =>
      'thud_board_v1_${camera}_${zoom.toStringAsFixed(1)}';

  static List<Offset> initial(double width, double height) => [
    Offset(width * .30, height * .30),
    Offset(width * .70, height * .30),
    Offset(width * .70, height * .62),
    Offset(width * .30, height * .62),
  ];

  static List<Offset>? load(
    SharedPreferences prefs,
    String camera,
    double zoom,
    double width,
    double height,
  ) {
    try {
      final raw = prefs.getString(_key(camera, zoom));
      if (raw == null) return null;
      final data = jsonDecode(raw) as Map;
      if ((data['aspect'] as num).toDouble() != width / height) return null;
      final points = (data['points'] as List)
          .map(
            (p) => Offset(
              (p[0] as num).toDouble() * width,
              (p[1] as num).toDouble() * height,
            ),
          )
          .toList();
      return valid(points) ? points : null;
    } catch (_) {
      return null;
    }
  }

  static bool valid(List<Offset> points) {
    if (points.length != 4) return false;
    final center = points.reduce((a, b) => a + b) / 4;
    return ImpactDetector.insideBoard(center, points);
  }

  static Future<void> save(
    SharedPreferences prefs,
    String camera,
    double zoom,
    double width,
    double height,
    List<Offset> points,
  ) async {
    if (width <= 0 || height <= 0 || !valid(points)) {
      throw StateError('Align four corners into a rectangle before locking.');
    }
    if (!await prefs.setString(
      _key(camera, zoom),
      jsonEncode({
        'aspect': width / height,
        'points': points.map((p) => [p.dx / width, p.dy / height]).toList(),
      }),
    )) {
      throw StateError('Could not save board alignment.');
    }
  }
}
