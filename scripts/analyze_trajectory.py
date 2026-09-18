#!/usr/bin/env python3
"""Offline replay of Thud schema-1 JSONL. Standard library only.

Mirrors lib/detection/impact_detector.dart; candidates are not proven contacts.
Retain missing/predicted samples: they reset the three-measurement window.
Example: python3 scripts/analyze_trajectory.py capture.jsonl --actual-hits 20
"""
import argparse
import collections
import csv
import json
import math
from pathlib import Path


def inside(point, board):
    if len(board) != 4:
        return False
    def sub(a, b):
        return (a['x'] - b['x'], a['y'] - b['y'])
    def cross(a, b):
        return a[0] * b[1] - a[1] * b[0]
    turns = [cross(sub(board[(i+1)%4], board[i]),
                   sub(board[(i+2)%4], board[(i+1)%4])) for i in range(4)]
    if any(not math.isfinite(v) or abs(v) < 1e-6 or (v > 0) != (turns[0] > 0) for v in turns):
        return False
    return all(abs(v) <= 1e-6 or (v > 0) == (turns[0] > 0)
               for v in [cross(sub(board[(i+1)%4], board[i]), sub(point, board[i])) for i in range(4)])


def replay(samples, config):
    window, hits, candidates = [], [], []
    last_hit = None
    for s in samples:
        ball = s.get('ball')
        if (s['status'] != 'measured' or not s['boardLocked'] or not ball
                or not all(math.isfinite(ball[k]) for k in ('x', 'y'))):
            window.clear()
            continue
        if window and not 0 < s['timestampUs'] - window[-1]['timestampUs'] <= config['maxGapMs'] * 1000:
            window.clear()
        window.append(s)
        window = window[-3:]
        if len(window) != 3:
            continue
        a, b, c = window
        u = [b['ball'][k] - a['ball'][k] for k in ('x', 'y')]
        v = [c['ball'][k] - b['ball'][k] for k in ('x', 'y')]
        d1, d2 = math.hypot(*u), math.hypot(*v)
        cosine = sum(x*y for x, y in zip(u, v)) / (d1*d2) if d1*d2 >= 1e-6 else -1
        angle = math.degrees(math.acos(max(-1, min(1, cosine))))
        speeds = [d1 * 1e6 / (b['timestampUs'] - a['timestampUs']), d2 * 1e6 / (c['timestampUs'] - b['timestampUs'])]
        reasons = []
        if last_hit is not None and b['timestampUs'] - last_hit < config['cooldownMs'] * 1000:
            reasons.append('cooldown')
        if not inside(b['ball'], c['board']):
            reasons.append('outside_board')
        if min(d1, d2) < config['minLegPixels']:
            reasons.append('short_leg')
        if min(speeds) < config['minSpeedPixelsPerSecond']:
            reasons.append('slow')
        if angle < config['minAngleDegrees']:
            reasons.append('angle')
        row = dict(pivot_sample=b['sample'], confirmation_sample=c['sample'],
                   elapsed_seconds=b['elapsedUs']/1e6, timestampUs=b['timestampUs'],
                   x=b['ball']['x'], y=b['ball']['y'], angle=angle,
                   incoming_pixels=d1, outgoing_pixels=d2,
                   incoming_speed=speeds[0], outgoing_speed=speeds[1],
                   rejected_by=','.join(reasons))
        candidates.append(row)
        if not reasons:
            hits.append(row)
            last_hit = b['timestampUs']
            window.clear()
    return hits, candidates


def analyze(path, actual=None):
    records = []
    for line_no, line in enumerate(path.read_text().splitlines(), 1):
        if line.strip():
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError as exc:
                raise ValueError(f'Invalid JSON at line {line_no}: {exc}') from exc
    header = next(r for r in records if r.get('event') == 'start')
    if header.get('schema') != 1:
        raise ValueError('Only trajectory schema 1 is supported')
    footer = next((r for r in reversed(records) if r.get('event') == 'end'), {})
    samples = [r for r in records if r.get('event') == 'sample']
    config = header['detector']
    hits, candidates = replay(samples, config)
    logged = [s['hit'] for s in samples if s.get('hit')]
    actual = actual if actual is not None else footer.get('actualHits')
    # Separate measured board visits by 0.5 s. This is a diagnostic grouping,
    # not ground truth: one physical throw may split into multiple visits.
    visits = []
    for s in samples:
        if s['status'] == 'measured' and s.get('insideBoard'):
            if not visits or s['timestampUs'] - visits[-1][-1]['timestampUs'] > 500000:
                visits.append([])
            visits[-1].append(s)
    sweep = []
    for angle in (25, 30, 35, 40):
        for leg in (2, 3):
            changed = dict(config, minAngleDegrees=angle, minLegPixels=leg)
            changed_hits = replay(samples, changed)[0]
            sweep.append(dict(angle=angle, min_leg=leg, hits=len(changed_hits),
                              candidates=changed_hits))
    report = dict(source=str(path.resolve()), actual_hits=actual, footer=footer,
                  sample_count=len(samples), status_counts=dict(collections.Counter(s['status'] for s in samples)),
                  recorded_hits=len(logged), replayed_hits=len(hits),
                  replay_matches_recorded_timestamps=[h['timestampUs'] for h in hits] == [h['timestampUs'] for h in logged],
                  config=config, hits=hits, sensitivity=sweep,
                  board_visits=[dict(start_sample=v[0]['sample'], end_sample=v[-1]['sample'],
                                     start_seconds=v[0]['elapsedUs']/1e6, end_seconds=v[-1]['elapsedUs']/1e6,
                                     measured_samples=len(v), hits=sum(v[0]['timestampUs'] <= h['timestampUs'] <= v[-1]['timestampUs'] for h in hits)) for v in visits])
    return report, candidates


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('recording', type=Path)
    parser.add_argument('--actual-hits', type=int)
    parser.add_argument('--output-dir', type=Path, help='Save summary JSON and all evaluated three-point windows as CSV')
    args = parser.parse_args()
    report, candidates = analyze(args.recording, args.actual_hits)
    print(f"Samples: {report['sample_count']} | states: {report['status_counts']}")
    print(f"Actual hits: {report['actual_hits']} | recorded: {report['recorded_hits']} | replay: {report['replayed_hits']}")
    print(f"Replay timestamps match app: {report['replay_matches_recorded_timestamps']} | dropped: {report['footer'].get('dropped', 'unknown (no footer)')}")
    print('Hit  Pivot  Confirm  Time(s)  Angle   Legs(px)')
    for i, h in enumerate(report['hits'], 1):
        print(f"{i:3} {h['pivot_sample']:6} {h['confirmation_sample']:8} {h['elapsed_seconds']:8.3f} {h['angle']:6.1f} {h['incoming_pixels']:5.1f}/{h['outgoing_pixels']:.1f}")
    print('Sensitivity (counts alone do not establish accuracy):')
    for row in report['sensitivity']:
        print(f"  {row['angle']} degrees / {row['min_leg']} px: {row['hits']} candidates")
    print('Board visits without a detected hit (not necessarily missed throws):')
    for v in report['board_visits']:
        if not v['hits']:
            print(f"  samples {v['start_sample']}–{v['end_sample']} / {v['start_seconds']:.2f}–{v['end_seconds']:.2f}s / {v['measured_samples']} measured")
    if args.output_dir:
        args.output_dir.mkdir(parents=True, exist_ok=True)
        (args.output_dir / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
        if candidates:
            with (args.output_dir / 'turns.csv').open('w', newline='') as f:
                writer = csv.DictWriter(f, fieldnames=list(candidates[0]), lineterminator="\n")
                writer.writeheader()
                writer.writerows(candidates)
        print(f'Reports: {args.output_dir.resolve()}')


if __name__ == '__main__':
    main()
