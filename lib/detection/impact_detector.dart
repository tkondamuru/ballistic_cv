import 'dart:math' as math;
import 'dart:ui';

class ImpactCandidate {
  final Offset position;
  final DateTime timestamp;
  final double angleDegrees;
  const ImpactCandidate(this.position, this.timestamp, this.angleDegrees);
}

class _Sample {
  final Offset position;
  final DateTime time;
  const _Sample(this.position, this.time);
}

/// Finds abrupt turns in consecutive measured positions, not contact with the
/// perimeter of the board. These are 2D impact candidates, not proof of contact.
class ImpactDetector {
  // Session replay recovered two 30–32° rebounds missed by the 35° gate.
  static const minAngleDegrees = 30.0;
  final List<_Sample> _samples = [];
  DateTime? _lastHit;

  void reset() {
    _samples.clear();
    _lastHit = null;
  }

  ImpactCandidate? add({
    required Offset position,
    required DateTime timestamp,
    required bool measured,
    required List<Offset> board,
  }) {
    // Never bridge a prediction/lost frame: reacquisition can look like a bounce.
    if (!measured || !position.dx.isFinite || !position.dy.isFinite) {
      _samples.clear();
      return null;
    }
    if (_samples.isNotEmpty) {
      final gap = timestamp.difference(_samples.last.time).inMicroseconds;
      if (gap <= 0 || gap > 80000) _samples.clear();
    }
    _samples.add(_Sample(position, timestamp));
    if (_samples.length > 3) _samples.removeAt(0);
    if (_samples.length < 3) return null;

    // A -> B -> C: decide as soon as C arrives and mark B. Only B must be
    // inside the board; the ball can approach or rebound outside its outline.
    final pivot = _samples[1];
    if (_lastHit != null &&
        pivot.time.difference(_lastHit!).inMilliseconds < 180) {
      return null;
    }
    if (!insideBoard(pivot.position, board)) return null;
    final incoming = pivot.position - _samples[0].position;
    final outgoing = _samples[2].position - pivot.position;
    // Ignore sub-pixel jitter and very slow turns. These are image-space
    // thresholds, so zoom and resolution still influence detection sensitivity.
    if (incoming.distance < 3 || outgoing.distance < 3) return null;
    final inSeconds =
        pivot.time.difference(_samples[0].time).inMicroseconds / 1e6;
    final outSeconds =
        _samples[2].time.difference(pivot.time).inMicroseconds / 1e6;
    if (incoming.distance / inSeconds < 60 ||
        outgoing.distance / outSeconds < 60) {
      return null;
    }
    final angle = _angle(incoming, outgoing);
    if (angle < minAngleDegrees) return null;

    _lastHit = pivot.time;
    // Consume this window so it cannot be rediscovered after a cooldown.
    _samples.clear();
    return ImpactCandidate(pivot.position, pivot.time, angle);
  }

  static double _angle(Offset a, Offset b) {
    final length = a.distance * b.distance;
    if (length < 1e-6) return 180;
    return math.acos(((a.dx * b.dx + a.dy * b.dy) / length).clamp(-1.0, 1.0)) *
        180 /
        math.pi;
  }

  /// The ordered convex quad is an allowed surface region, not four walls.
  /// Reject crossed/degenerate handles rather than accepting arbitrary points.
  static bool insideBoard(Offset point, List<Offset> board) {
    if (board.length != 4 ||
        board.any((p) => !p.dx.isFinite || !p.dy.isFinite)) {
      return false;
    }
    double cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;
    final turns = List.generate(
      4,
      (i) => cross(
        board[(i + 1) % 4] - board[i],
        board[(i + 2) % 4] - board[(i + 1) % 4],
      ),
    );
    if (turns.any((v) => v.abs() < 1e-6) ||
        turns.any((v) => (v > 0) != (turns.first > 0))) {
      return false;
    }
    for (var i = 0; i < 4; i++) {
      final side = cross(board[(i + 1) % 4] - board[i], point - board[i]);
      if (side.abs() > 1e-6 && (side > 0) != (turns.first > 0)) return false;
    }
    return true;
  }
}
