# BallisticCV implementation status

Verification: 38 Flutter tests, 4 Python replay tests, native tracker and frame
storage checks passed; signed iOS release build passed. Full analysis reports
only the existing frame_review_screen.dart null-aware-operator info lint.

Latest threshold update: minimum turn is now 30° (previously 35°). All other
impact gates are unchanged. The recorder reads the shared angle constant. Replay
of the 20-hit session recovers the two missed 30.4°/31.5° turns at 30°/3px;
historical analysis files below retain their recorded 35° settings. README now
documents navigation, zoom, board persistence, lower-edge filtering, impact
detection, console capture, coordinate export, and reusable offline analysis.

Offline trajectory recording (2026-09-18): Debug can start a coordinate-only
Thud session, stop with an optional actual-hit count, and share saved JSONL files
through the iOS share sheet (including Save to Files/AirDrop). Sessions persist
on the phone without a connected Mac and include board/zoom, measured/predicted/
lost positions, inside-board flags, timestamps, and impact candidates. Outside
samples are retained to replay entry/rebound/exit. Bounded batched writes report
drops; recording auto-saves on app inactivity or after 10 minutes. No images are
recorded by this feature. All 37 Flutter tests and changed-file analysis passed;
production Swift storage passed a native start/append/finish/list/JSON test. Signed
iOS release built and installed on the connected iPhone. Share-sheet interaction
and a physical throwing session still need user validation.

Impact correction (2026-09-18): Thud uses three consecutive measured positions
A → B → C and marks B as soon as C arrives. Only B must be inside the locked
board. Gates: turn ≥35°, each leg ≥3 image pixels and ≥60 pixels/second,
inter-sample gap ≤80 ms, and 180 ms duplicate cooldown. Prediction/loss resets
the window. The earlier seven-sample straightness/acceleration gates were removed.
Console diagnostics now forward via native stderr; timestamped startup messages
verify capture before a scan. ScanTrace logs all processed samples, board/ball
coordinates, region, sample timestamps, and stored-frame mappings.
Three additional missed-turn coordinate regressions pass at 35°/3px.
Both earlier captured turns pass replay once: first near frame 86 (~83°), second at frame
151 confirmed on 152 (~61°). All 31 Flutter tests passed; changed-file analysis
passed. Native tracking is unchanged. Three-point turns remain impact candidates,
not proof of contact, and may admit more noise or fast arc false positives.
Zoom changes invalidate the board alignment. Full analysis has a pre-existing
null-aware-operator lint in frame_review_screen.dart.

Latest UI update (2026-09-14): Activities has a single “Your activities” header.
Play uses fixed-width zoom arrows, with 0.1× steps, long-press repetition, and
persisted zoom restored within the camera's supported range. Repetition stops on
release, zoom limit, app inactivity, or widget disposal. The update was installed
and launched on the iPhone. Source comments explain zoom-dependent pixel gates;
no detector thresholds were changed. Current changes are being checked in on
`codex/iphone-native-build`; earlier commit/deployment notes below are historical.

Navigation update: Objects, Activities, Play, and Debug share a bottom navigation
bar. Selected object ID and activity are persisted; a valid saved pair opens Play
on relaunch. Selected cards are green with check marks. Deleting the selected
object clears its selection. Debug owns saved-frame review and confirmed deletion;
Scan 10s remains on Play. Tracking releases its camera when leaving; switching is
blocked during capture/finalization. Calibration and frame review are separate
routes. Analysis and all 15 Flutter tests passed, including restart/selection
and deletion regression coverage.

Latest deployment update (2026-09-13): at the user's request, the pending scanned
frame workflow and reset-button removal were built, installed, and launched on
the connected iPhone 16 Pro. A subsequent update explicitly requests 60 FPS for
iOS tracking using the camera plugin's frame-rate configuration and adds delivered
FPS / average CV processing-time diagnostics. That signed release was also installed.
Static analysis and all 14 Flutter tests passed. Actual 60 FPS delivery and thrown
ball accuracy still require device observation; the plugin may choose a lower
supported rate at the selected resolution. CV remains synchronous and shutter
control remains unimplemented. The earlier deployment notes below describe the
state before these installations.

This document describes implemented behavior, not a guarantee that every goal in
SPEC.md has been met. Later product decisions expanded the navigation and replaced
the proposed video recorder with diagnostic frame capture.

## Current delivery state

- **Installed and exercised on iPhone:** native OpenCV tracking, three-sample color
  calibration, saved objects, activity selection, tracking overlays and console
  diagnostics, and light object/activity cards. The user reported that sampling
  and tracking were working well after the fixes.
- **Implemented locally, not installed yet:** removal of the bottom-right reset
  button and the 10-second scanned-frame capture/review workflow.
- **Repository:** current branch is `codex/iphone-native-build`; last committed
  and pushed change is `148ac8d`. Frame capture/review and this status document
  are working-tree changes at the time of this update.
- **Deployment constraint:** do not install the pending changes on the iPhone
  until the user requests it.
- **Platforms:** physical iPhone builds/deployment have been verified. Android
  native code and build configuration exist, but the latest changes have not
  been built or tested on Android in this session. No macOS desktop app target.

## Implemented product flow

```text
Your objects
  ├─ New object → Name → Three color samples → Match preview → Save object
  ├─ Select object → Activities → Tracking / play screen
  └─ Scanned frames → Swipe / ruler review → Close (keep set)
                     └─ Explicit deletion from Your objects
```

### Saved objects and navigation

- Named objects with a sampled-color swatch and persisted HSV profile.
- Create, select, and delete objects; object deletion requires confirmation.
- Existing single-profile storage migrates once to an object named “Saved ball.”
- A separate Activities screen currently offers **Tracking** only.
- Tracking includes navigation back to Activities and then Your objects.
- Light gray cards, near-black text, and dark icons improve readability.
- The saved object contains the combined HSV profile, not the original three
  calibration images or their individual pixel arrays.

Sources: [sampled_object.dart](lib/models/sampled_object.dart),
[objects_screen.dart](lib/screens/objects_screen.dart),
[activities_screen.dart](lib/screens/activities_screen.dart).

### Three-sample calibration

- Small center sampling circle sized relative to the camera preview/frame.
- Three captures: normally lit, slightly shaded, and another angle of the ball.
- Each sample displays and logs median hue (OpenCV units and degrees), saturation,
  and brightness. Combined thresholds are also logged.
- Combined thresholds use the 10th/90th percentiles with margins; incompatible
  color samples are rejected rather than widening the range indefinitely.
- Circular hue handling supports red across the 179/0 seam.
- Low-saturation white/gray samples use saturation and brightness with a full
  hue range, since their hue is unreliable.
- Frozen magenta match preview before saving; retake-all action.
- BGRA frames on iPhone; Android's three-plane YUV path is implemented.
- Sampling errors and stack traces are printed to the console.

Sources: [color_samples.dart](lib/calibration/color_samples.dart),
[calibrator_screen.dart](lib/screens/calibrator_screen.dart).

### Native tracking and play screen

- OpenCV 4.13.0 linked through Dart FFI; iPhone builds compile the C++ tracker
  and retain all six native entry points in release builds.
- BGRA/YUV conversion, HSV thresholding including wrapped hue ranges,
  morphology, contour filtering, and area × circularity candidate scoring.
- Constant-velocity 2D Kalman filter estimates position and velocity and bridges
  missed detections. Velocity is in pixels per frame, not calibrated physical units.
- Live camera preview, target ring, fading trail, velocity arrow, FPS readout,
  tracking/searching status, coordinates, and sampled-color swatch.
- Predicted trail/marker segments are distinguished with orange coloring.
- First measured lock logs coordinates, radius, frame format/orientation, and
  pixel HSV at the filtered center. Target HSV limits are logged at startup.
- Corrected unnecessary coordinate rotation for already-portrait frames.
- Optional native motion masking exists but is **disabled** in the current UI.
- The user-requested reset button removal is implemented locally. Native tracker
  state still resets when a tracking screen opens.

Sources: [native_tracker.cpp](ios/Runner/native_tracker.cpp),
[native_cv.dart](lib/native/native_cv.dart),
[tracker_screen.dart](lib/screens/tracker_screen.dart),
[tracking_painter.dart](lib/widgets/tracking_painter.dart).

### Scanned frames — local implementation, awaiting device validation

- iPhone-only **Scan 10s** control with circular countdown and captured-frame count.
- Up to 10 seconds and a hard cap of 600 stored frames; input is throttled to at
  most approximately 60 submissions/second. Actual stored FPS may be lower.
- One outstanding frame write at a time; incoming frames are skipped/countable
  while the writer is busy. No unbounded raw-frame queue.
- Lossless PNGs plus a JSON manifest: object identity/name, profile snapshot,
  numbered frames, relative processing timestamps, frame dimensions/orientation,
  detection/velocity/prediction data, displayed trail, and capture summary.
- One capture set **across the app**, not one per object. A saved set disables
  further capture until it is explicitly deleted.
- Private Application Support storage, excluded from backup; no Photos export.
- Serial native PNG/disk work runs off the UI thread. Frame transfer still copies
  bytes through the Flutter platform channel.
- Finalized partial captures can be retained on interruption/write failure.
  Unfinished staging files from a terminated app are cleaned up on a later load.
- No free-space precheck or disk-byte quota. Writes are checked and failures
  reported; frame count/duration and bounded in-memory work limit resource use.
- Your objects shows a **Scanned frames** card with object name, count, and skips.
- Review supports numbered swiping, timestamps, detection status, and a ruler
  marked for detected/predicted/searching frames.
- Ruler movement changes the number immediately, but loads an image only after
  250 ms of inactivity or on release; intermediate frame images are not decoded.
- Review keeps one decoded display image plus an in-flight replacement, with no
  thumbnail cache. Color-mask generation briefly requires additional image data.
- Tracking overlay toggle and an HSV mask view (before morphology/shape gating).
- Explicit **Close** preserves the set; swipe-back is blocked. Separate confirmed
  deletion removes the capture and enables another scan. Object deletion does not
  implicitly remove the capture snapshot.

Sources: [FrameCapture.swift](ios/Runner/FrameCapture.swift),
[frame_capture.dart](lib/capture/frame_capture.dart),
[frame_review_screen.dart](lib/screens/frame_review_screen.dart).

## Comparison with the original specification

| SPEC area | Status | Actual behavior / remaining work |
| --- | --- | --- |
| §1–2 Standalone iPhone app, compilation and deployment | Implemented / device exercised | Signed builds installed and launched on physical iPhone. |
| §1, §3 Locked 60 FPS and hardware shutter | Not implemented | Low camera preset; no explicit FPS lock or shutter control. FPS label is measured processing throughput, not a guarantee. |
| §3 Zero-copy frames | Not implemented | Dart copies camera bytes into reusable native buffers; capture also transfers frame bytes to Swift. |
| §3 Background CV worker | Not implemented | Tracking FFI runs synchronously from the Flutter camera callback. Only diagnostic frame encoding/writes use a background native queue. |
| §4 Original two-screen navigation | Superseded by user-approved flow | Objects → Activities → Tracking, plus calibration and scanned-frame review. |
| §4 One-tap median pipette and specified bounds | Superseded | Three samples, percentile bounds, hue wraparound, white-ball handling, explicit preview/save. |
| §4 Lux indicator / manual HSV sliders | Not implemented | Guided sampling and preview exist; no light meter or manual tuning drawer. |
| §4 Live sampled-color preview | Partial | Saved target swatches and per-sample readings exist; no continuously updating center-color swatch. |
| §4 Tracking ring, trail, status and FPS | Implemented | Trail holds up to 25 points, rather than the specified 8–10. |
| §4 Hit counter, bullseyes, clear hits | Not implemented | No hit events or hit UI. Removed reset button reset tracking state, not hits. |
| §4 Telemetry recorder / session export | Partial diagnostic substitute | Scanned-frame manifest records tracking data; no general match telemetry recorder, export/share action, or hit records. |
| §4 Raw video / burned-in MP4 / Photos saving | Deferred | Unfinished video recorder was replaced by diagnostic frame capture; no video encoder or gallery-save flow remains. |
| §5.1 HSV and contour detection | Implemented with different tuning | Current code uses 5×5 opening and closing, area 25–12000, circularity ≥0.35, radius 5–85; spec calls for 3×3 opening, area ≤8000, circularity ≥0.18. |
| §5.2 Kalman and occlusion bridging | Partial match | Predicts through eight misses and resets on the ninth; not the specified 1–3-frame bridge/clear-after-four behavior. Trail drains gradually. |
| §5.3 Rebound/hit detection | Not implemented | No directional inflection, reversal threshold, or hit cooldown logic. |
| §5.4 ArUco / homography / YOLO / NCNN | Not implemented | Roadmap only; no marker calibration, perspective mapping, model integration, or physical-unit speed measurement. |
| §6 Formal progressive test protocol | Not completed | User confirmed successful sampling/tracking; no recorded formal results for desk rebound, gravity bounce, or five-wall-impact tests. |
| §7 Dependencies and structure | Adapted | Actual package is `ballistic_cv`; Flutter 3.41.1 used locally, pinned OpenCV 4.13.0 via CocoaPods. No added `gal` or `path_provider` dependency; small native bridge manages frame storage. |
| §8 Rapid development phases | Partially complete | iOS linking and camera/FFI integration complete; background processing and current Android/Poco validation remain. |

The spec's claims of eliminating all false positives, guaranteed 60 FPS,
zero dropped frames, negligible recording overhead, and fixed native footprint
are goals/claims, **not established measurements** of the current implementation.

## Validation recorded so far

- Flutter static analysis: latest run passed with no issues.
- Flutter tests: **14 passed**, covering calibration, object persistence/migration,
  navigation/deletion, frame-write backpressure, timer/cap behavior, write failure,
  and deferred ruler image loading.
- Native C++ tests passed for packed/padded BGRA detection, invalid inputs, hue
  wraparound, and tracker reset between independent cases.
- Native PNG/storage harness passed on Mac using the production Swift file with
  transport stubs: pixel colors/row padding, manifest creation, exclusive saved
  set, deletion, invalid frames, and empty capture handling.
- Latest local unsigned iPhone release build passed (reported size **18.9 MB**).
- Earlier signed releases were installed and run successfully on iPhone. Latest
  scanned-frame changes have **not** been installed or device-tested.
- Native harness tests do not establish iPhone capture throughput, memory usage,
  temperature behavior, actual 600-frame storage size, or UI responsiveness.

Reproducible commands from the project root (use `.tools/flutter/bin/` if Flutter
is not on PATH):

```bash
flutter analyze
flutter test
python3 test/run_frame_capture_native_test.py
flutter build ios --release --no-codesign
```

For the separate C++ regression command and OpenCV framework prerequisite, see
[README.md](README.md#native-regression-test-mac).

## Next validation and implementation priorities

1. When authorized, install and exercise scanned-frame capture on iPhone: repeat
   review, fast ruler movement, close/reopen, delete/re-record, interrupted capture,
   overlay orientation, and color-mask comparison.
2. Measure actual capture rate, skipped frames, resident memory, storage usage,
   and write latency; use captured failures to investigate tracking accuracy.
3. Decide/tune motion gating, contour thresholds, and occlusion/trail behavior
   against representative captures before claiming high-speed robustness.
4. Implement background CV processing and explicit camera FPS/shutter controls
   if the original 60 FPS target remains mandatory.
5. Add rebound/hit detection and complete the formal physical test protocol.
6. Validate current Android behavior. Video/Photos export and additional activities
   remain separate future scope rather than part of the scanned-frame feature.
