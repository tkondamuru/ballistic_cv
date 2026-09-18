# 20-hit session analysis

Source: thud-1789749904559-7B5074EC.jsonl, recorded September 18, 2026.

- 3,592 coordinate samples; no reported dropped samples. 486 measured,
  290 predicted, 2,816 searching. Searching time includes time between throws.
- App recorded 18 impact candidates. Offline replay reproduced all 18 exactly,
  including pivot timestamps. User reported 20 physical hits.
- 20 measured board visits separated by at least 0.5 seconds; 18 have one
  detected candidate each. Two visits have no candidate at the current 35° gate.
- At 30°/3px, replay produces one candidate in every visit, 20 total.
  The recovered candidates are sample 1032 (confirmed 1033), 19.613s,
  30.414°, legs 7.645/6.341px; and sample 2214 (confirmed 2215),
  39.314s, 31.512°, legs 11.000/6.331px. Both pass all other gates.
- Lowering the leg threshold from 3px to 2px leaves the counts unchanged.
- Lowering to 30° also moves two existing detections one sample earlier:
  1500→1499 and 2297→2296; these are not additional hits.

This supports testing 30° while retaining 3px, speed, gap, and cooldown gates.
It is evidence from one coordinate session, not proof that every candidate is
physical contact or that 30° avoids false positives in other throws. No production
thresholds were changed by this analysis.

Times are elapsed since recording started; sample numbers are coordinate sample
IDs, not scanned-image frame IDs. summary.json contains the hit lists and
sensitivity runs; turns.csv lists rejection reasons for evaluated windows.
