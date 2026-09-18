import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ballistic_cv/detection/impact_detector.dart';

void main() {
  const board = [
    Offset(0, 0),
    Offset(200, 0),
    Offset(200, 200),
    Offset(0, 200),
  ];
  final start = DateTime(2026);
  List<ImpactCandidate> run(
    List<Offset> points, {
    int frameMs = 16,
    int? missing,
    int? gap,
  }) {
    final detector = ImpactDetector();
    final hits = <ImpactCandidate>[];
    for (var i = 0; i < points.length; i++) {
      final hit = detector.add(
        position: points[i],
        timestamp: start.add(
          Duration(
            milliseconds: i * frameMs + (gap != null && i >= gap ? 200 : 0),
          ),
        ),
        measured: i != missing,
        board: board,
      );
      if (hit != null) hits.add(hit);
    }
    return hits;
  }

  const rebound = [
    Offset(70, 100),
    Offset(80, 100),
    Offset(90, 100),
    Offset(100, 100),
    Offset(90, 100),
    Offset(80, 100),
    Offset(70, 100),
  ];
  test('finds central rebound at the turn, not an edge, at 30 and 60 FPS', () {
    for (final ms in [16, 33]) {
      final hits = run(rebound, frameMs: ms);
      expect(hits, hasLength(1));
      expect(hits.single.position, const Offset(100, 100));
      expect(hits.single.angleDegrees, closeTo(180, 0.01));
      expect(hits.single.timestamp, start.add(Duration(milliseconds: 3 * ms)));
    }
  });
  test('saved frames 82–91 detect the smoothed turn near frame 86 once', () {
    final data =
        jsonDecode(
              File('test/fixtures/thud_smoothed_turn.json').readAsStringSync(),
            )
            as Map;
    final quad = (data['board'] as List)
        .map(
          (p) => Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()),
        )
        .toList();
    final detector = ImpactDetector();
    final hits = <ImpactCandidate>[];
    for (final f in data['frames'] as List) {
      final hit = detector.add(
        position: Offset(
          (f['x'] as num).toDouble(),
          (f['y'] as num).toDouble(),
        ),
        timestamp: start.add(Duration(microseconds: f['timeUs'] as int)),
        measured: f['measured'] as bool,
        board: quad,
      );
      if (hit != null) hits.add(hit);
    }
    expect(hits, hasLength(1));
    expect(
      (hits.single.position - const Offset(120.6884, 78.8871)).distance,
      lessThan(1),
    );
    expect(hits.single.angleDegrees, inInclusiveRange(80, 90));
  });
  test(
    'short saved turn is detected on third frame, even with little approach',
    () {
      final data =
          jsonDecode(
                File('test/fixtures/thud_short_turn.json').readAsStringSync(),
              )
              as Map;
      final quad = (data['board'] as List)
          .map(
            (p) =>
                Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()),
          )
          .toList();
      final detector = ImpactDetector();
      final hits = <ImpactCandidate>[];
      int? confirmation;
      for (final f in data['frames'] as List) {
        final hit = detector.add(
          position: Offset(
            (f['x'] as num).toDouble(),
            (f['y'] as num).toDouble(),
          ),
          timestamp: start.add(Duration(microseconds: f['timeUs'] as int)),
          measured: f['measured'] as bool,
          board: quad,
        );
        if (hit != null) {
          hits.add(hit);
          confirmation = f['number'] as int;
        }
      }
      expect(hits, hasLength(1));
      expect(confirmation, 152);
      expect(hits.single.angleDegrees, inInclusiveRange(60, 63));
    },
  );
  test('three points suffice and approach/departure may be outside board', () {
    final hits = run([
      const Offset(-10, 100),
      const Offset(10, 100),
      const Offset(-10, 120),
    ]);
    expect(hits, hasLength(1));
    expect(hits.single.position, const Offset(10, 100));
    expect(run([const Offset(90, 100), const Offset(100, 100)]), isEmpty);
  });
  test('timed cooldown suppresses distinct repeated turns', () {
    expect(
      run([
        const Offset(80, 100),
        const Offset(100, 100),
        const Offset(80, 100),
        const Offset(60, 100),
        const Offset(40, 100),
        const Offset(60, 100),
      ]),
      hasLength(1),
    );
  });
  test('30 degrees and 3 pixels accept all three reported missed turns', () {
    final data =
        jsonDecode(
              File(
                'test/fixtures/thud_three_missed_turns.json',
              ).readAsStringSync(),
            )
            as Map;
    final quad = (data['board'] as List)
        .map(
          (p) => Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()),
        )
        .toList();
    for (final turn in data['turns'] as List) {
      final detector = ImpactDetector();
      ImpactCandidate? hit;
      final points = turn['points'] as List;
      for (var i = 0; i < points.length; i++) {
        hit = detector.add(
          position: Offset(
            (points[i]['x'] as num).toDouble(),
            (points[i]['y'] as num).toDouble(),
          ),
          timestamp: start.add(Duration(milliseconds: i * 17)),
          measured: true,
          board: quad,
        );
      }
      expect(hit, isNotNull, reason: 'turn at saved frame ${turn['frame']}');
    }
  });
  test(
    'accepts the two measured 30–32 degree rebounds from the 20-hit session',
    () {
      for (final points in [
        [
          const Offset(103.6983, 95.9709),
          const Offset(104.7873, 103.5379),
          const Offset(102.3889, 109.4075),
        ],
        [
          const Offset(111.9388, 79.4845),
          const Offset(117.7568, 88.8201),
          const Offset(117.8031, 95.1512),
        ],
      ]) {
        final hits = run(points);
        expect(hits, hasLength(1));
        expect(hits.single.angleDegrees, inInclusiveRange(30, 32));
      }
      // A shallower turn must still fail the angle gate.
      expect(
        run([const Offset(20, 20), const Offset(30, 20), const Offset(40, 25)]),
        isEmpty,
      );
    },
  );
  test('reports a real 90 degree turn', () {
    final hits = run([
      ...rebound.take(4),
      const Offset(100, 110),
      const Offset(100, 120),
      const Offset(100, 130),
    ]);
    expect(hits.single.angleDegrees, closeTo(90, 0.01));
  });
  test(
    'rejects smooth ballistic arcs, including vertical apex near top edge',
    () {
      for (final dx in [0.0, 2.0, 8.0]) {
        final arc = List.generate(21, (i) {
          final t = i - 10;
          return Offset(100 + dx * t, 10 + 0.8 * t * t);
        });
        expect(run(arc), isEmpty);
      }
    },
  );
  test('rejects straight travel near border and small jitter', () {
    expect(run(List.generate(12, (i) => Offset(20.0 + i * 10, 10))), isEmpty);
    expect(run(List.generate(20, (i) => Offset(100.0 + i % 2, 100))), isEmpty);
  });
  test('does not bridge predicted frames or time gaps', () {
    expect(run(rebound, missing: 3), isEmpty);
    expect(run(rebound, gap: 4), isEmpty);
  });
  test('rejects outside hits and consumes accepted candidates', () {
    expect(
      run(rebound.map((p) => p + const Offset(0, -150)).toList()),
      isEmpty,
    );
    final continued = [
      ...rebound,
      ...List.generate(20, (i) => Offset(60.0 - i * 3, 100)),
    ];
    expect(run(continued), hasLength(1));
  });
  test('reset discards pre-calibration history', () {
    final detector = ImpactDetector();
    for (var i = 0; i < 4; i++) {
      detector.add(
        position: rebound[i],
        timestamp: start.add(Duration(milliseconds: i * 16)),
        measured: true,
        board: board,
      );
    }
    detector.reset();
    for (var i = 4; i < 7; i++) {
      expect(
        detector.add(
          position: rebound[i],
          timestamp: start.add(Duration(milliseconds: i * 16)),
          measured: true,
          board: board,
        ),
        isNull,
      );
    }
  });
  test(
    'accepts reversed corner order; rejects crossed or degenerate boards',
    () {
      expect(
        ImpactDetector.insideBoard(
          const Offset(100, 100),
          board.reversed.toList(),
        ),
        isTrue,
      );
      expect(
        ImpactDetector.insideBoard(const Offset(100, 100), [
          board[0],
          board[2],
          board[1],
          board[3],
        ]),
        isFalse,
      );
      expect(
        ImpactDetector.insideBoard(
          const Offset(100, 100),
          List.filled(4, Offset.zero),
        ),
        isFalse,
      );
    },
  );
}
