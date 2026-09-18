"""Independent gate checks for the standard-library trajectory replay tool."""
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from analyze_trajectory import replay

CONFIG = dict(minAngleDegrees=35, minLegPixels=3,
              minSpeedPixelsPerSecond=60, maxGapMs=80, cooldownMs=180)
BOARD = [dict(x=0, y=0), dict(x=100, y=0), dict(x=100, y=100), dict(x=0, y=100)]


def samples(points):
    return [dict(sample=i+1, timestampUs=i*16000, elapsedUs=i*16000,
                 status='measured', boardLocked=True, board=BOARD,
                 ball=dict(x=x, y=y)) for i, (x, y) in enumerate(points)]


class ReplayTests(unittest.TestCase):
    def test_marks_pivot_even_if_exit_is_outside(self):
        hits, _ = replay(samples([(90, 90), (95, 95), (90, 105)]), CONFIG)
        self.assertEqual([h['pivot_sample'] for h in hits], [2])

    def test_prediction_breaks_window(self):
        rows = samples([(10, 10), (20, 20), (10, 30)])
        rows[1]['status'] = 'predicted'
        self.assertEqual(replay(rows, CONFIG)[0], [])

    def test_angle_only_failure(self):
        rows = samples([(10, 10), (20, 10), (28.66, 15)])
        hits, turns = replay(rows, CONFIG)
        self.assertFalse(hits)
        self.assertEqual(turns[0]['rejected_by'], 'angle')
        self.assertEqual(len(replay(rows, dict(CONFIG, minAngleDegrees=29))[0]), 1)

    def test_short_leg_and_large_gap(self):
        rows = samples([(10, 10), (12, 10), (12, 20)])
        self.assertEqual(replay(rows, CONFIG)[1][0]['rejected_by'], 'short_leg')
        rows[2]['timestampUs'] = 200000
        self.assertEqual(replay(rows, CONFIG)[1], [])


if __name__ == '__main__':
    unittest.main()
