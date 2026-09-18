# BallisticCV ⚡

> A high-speed, on-device mobile computer vision app built with Flutter and native C++ (`opencv-mobile`) for real-time ping-pong ball tracking with a 60 FPS target and rebound detection. It pairs camera frame processing with a dynamic cyberpunk HUD and neon trajectory overlays.

---

## 🎯 Features

* **Real-time Tracking (60 FPS target)**: Runs on-device with zero server latency using `opencv-mobile` linked via Dart FFI.
* **Smart Filtering**: BGR $\to$ HSV color masking with morphological opening and contour circularity gating.
* **Ball Radius Gating**: Discards large background objects, walls, and reflections ($3\text{px} \le r \le 85\text{px}$).
* **Dynamic Cyberpunk HUD**:
  * Glowing dynamic border: **Green** when `TRACKING`, **Red** when `SEARCHING`.
  * Live FPS counter (targeting 60 FPS).
  * Coordinate readouts $(x, y)$ and detected radius with active status icons (🎯 Crosshairs / 📡 Radar).
  * Neon fading comet trajectory trail.
* **Cross-Platform**:
  * Android (Poco and other ARM devices via NDK & CMake).
  * iOS (iPhone AVFoundation).

---

## Navigation and camera controls

**Objects**, **Activities**, **Play**, and **Debug** are bottom tabs. Selected
objects and activities show a selection mark and persist across restarts; a valid
saved pair opens Play directly. Activities uses a single “Your activities” header.
Debug owns frame review/deletion and coordinate recording/export.

Play's compact horizontal zoom controls step by 0.1×; holding an arrow repeats
until released or the supported limit is reached. Zoom is saved and restored.
Image-space distance thresholds vary with zoom, so keep zoom consistent when
comparing trials.

## Thud board alignment and impact detection

Drag the four initially smaller, central handles onto the board and lock it.
Locking saves normalized corners per camera and zoom, restored on return at the
same aspect ratio. A new zoom needs its own alignment; returning to a previously
saved zoom restores that calibration. Realigning is necessary if the camera or
board physically moves.

**Ignore below board** rejects native ball candidates below the board's sloping
lower edge, extended across the image, with a 5-camera-pixel allowance. The filter
runs before candidate selection and Kalman correction so an orange table patch
cannot supply a below-edge measurement. Prediction still handles missing
measurements; real ball motion below the cutoff will also be ignored. This
preference persists and applies while the board is locked.

Impact detection uses three consecutive measured positions A → B → C and marks
B when C arrives. B must be inside the locked board; A and C may be outside.
Current gates are **30° minimum turn**, **3 camera pixels per leg**, **60 pixels/s
per leg**, no more than **80 ms between measurements**, and **180 ms cooldown**.
Predicted/lost positions reset the window; accepted windows are consumed. This
avoids waiting for a seven-point window that can outlast a fast rebound. The
Kalman tracker is separate from this impact detector.

A 20-hit coordinate session yielded 18 candidates at 35°. Replaying at 30°/3px
produced one candidate in each of 20 board visits, recovering turns of 30.4° and
31.5°. Lowering the pixel gate added nothing. This supports the 30° change, but
2D turns remain contact candidates: further throws and no-contact controls are
needed to assess false positives. Historical reports retain their original 35°
settings; new recordings export the current threshold.

### Console troubleshooting

Run `flutter run --release -d <iphone-device-id>` with the phone unlocked. Native
stderr forwarding emits timestamped `ConsoleCheck` startup messages so console
capture can be verified before throwing. `ScanTrace` includes processed sample
timestamps, board/ball coordinates, region status, and saved-image mappings;
processed sample IDs and saved-image frame numbers are different. Coordinate
recording below provides the same style of offline diagnostics without a cable.

---

## 🏗️ Architecture

```
┌────────────────────────────────────────────────────────┐
│        Camera Capture (CameraX / AVFoundation)         │
│   • Sensor Preset: Low (360p / 480p)                   │
│   • Device-dependent capture rate                             │
└──────────────────────────┬─────────────────────────────┘
                           │ Camera bytes copied to native buffers
                           ▼
┌────────────────────────────────────────────────────────┐
│      Native C++ Engine (libnative_tracker.so)          │
│  [opencv-mobile 4.13.0 via Dart FFI]                   │
│   • YUV420 / NV21 / BGRA -> HSV                        │
│   • cv::inRange Binary Mask                            │
│   • cv::morphologyEx (Noise removal)                   │
│   • cv::findContours & Ball Radius Gating              │
└──────────────────────────┬─────────────────────────────┘
                           │ Lightweight Coordinate Stream: (x, y, r, detected)
                           ▼
┌────────────────────────────────────────────────────────┐
│             Flutter UI Layer (Impeller / Skia)         │
│   • CameraPreview Background                           │
│   • CustomPainter (Neon Comet Trail & Target Reticle)  │
│   • Top HUD Bar & Bottom Coordinate Readout            │
└────────────────────────────────────────────────────────┘
```

---

## 🚀 Getting Started

### Prerequisites
* Flutter SDK (`>=3.32.0`; validated with 3.41.1)
* Android Studio with **NDK (Side by side)** and **CMake** installed

### Run on Android
```bash
flutter pub get
flutter run
```

### Build APK
```bash
flutter build apk --debug
```

### Build and run on iPhone (Mac)

Requires Xcode with the iOS SDK, CocoaPods, and Flutter. If using the restored
SDK in this checkout, run `export PATH="$PWD/.tools/flutter/bin:$PATH"` first.

```bash
flutter pub get
flutter build ios --release --no-codesign
open ios/Runner.xcworkspace
```

In Xcode, select Runner → Signing & Capabilities and choose your Apple development
team. Connect and unlock the iPhone, trust the Mac, and enable Developer Mode.
Then, from the project root:

```bash
flutter devices
flutter run --release -d <iphone-device-id>
```

CocoaPods downloads the pinned OpenCV 4.13.0 iOS framework and verifies its SHA-256
using `ios/OpenCVMobile.podspec`. This dependency targets physical iOS devices;
it does not include an iOS Simulator slice. Runner compiles the C++ tracker and
exports its C entry points for Dart FFI. iOS uses BGRA camera frames with explicit
row strides; Android uses YUV420. Both native implementations must keep the same
FFI signature when changing the shared Dart bindings.

The current pipeline copies camera bytes into reusable native buffers and runs
tracking synchronously. Camera FPS and tracking throughput must be measured on
the device; iOS requests 60 FPS, but the camera may select a lower supported rate. The HUD
reports delivered FPS; resolution, exposure, and synchronous CV can limit throughput.

### Native regression test (Mac)

Download and extract the matching `opencv-mobile-4.13.0-macos.zip` from the
[opencv-mobile v36 release](https://github.com/nihui/opencv-mobile/releases/tag/v36).
With `opencv2.framework` in `/tmp/ballistic-opencv-macos`, run:

```bash
clang++ -std=c++17 -F/tmp/ballistic-opencv-macos \
  test/native_tracker_test.cpp ios/Runner/native_tracker.cpp \
  -framework opencv2 -framework Accelerate -framework Foundation \
  -framework CoreGraphics -framework CoreVideo -framework AVFoundation \
  -lz -o /tmp/ballistic-native-test
/tmp/ballistic-native-test
```

This verifies packed and padded BGRA frames produce matching detections and
checks invalid row strides, null input, and frames without a ball.

### Scanned frames (iPhone)

Use **Scan 10s** on the Play screen to capture up to 600 lossless PNG frames
with their relative processing timestamps, selected HSV profile, detections,
and displayed trails. Capture stops after 10 seconds, on interruption, or if a
write fails. A single outstanding disk write bounds memory; frames arriving
while the writer is busy are skipped and counted. This diagnostic mode records
the delivered/processed stream, not guaranteed 60 FPS or sensor timestamps.

The single saved set appears as **Scanned frames** on **Debug**. Capture
is disabled until that set is explicitly deleted. It is stored privately in
Application Support, excluded from backup, and is not exported to Photos.
Interrupted unfinished sets are cleaned up on the next load; finalized partial
captures remain reviewable. No free-space precheck is performed; write errors
are handled and reported.

Swipe between numbered frames, or use the ruler: while moving it, only the
selection number changes. The frame loads after 250 ms of inactivity or on
release. Review uses one decoded display image plus an in-flight replacement,
without a thumbnail cache. **Close** preserves the set; **Delete scanned frames**
requires confirmation. Tracking overlays can be toggled, and **Color mask** shows
pixels passing the captured HSV bounds (before morphology and shape filtering).

Local checks (no device installation):

```bash
flutter test
python3 test/run_frame_capture_native_test.py  # macOS: PNG and file lifecycle checks
flutter build ios --release --no-codesign
```

Capture/write throughput and ruler responsiveness still need validation on a
physical iPhone. Frame capture is currently implemented for iOS only.

### Offline coordinate recordings

On iPhone, open **Debug → Start tracking recording**, then **Play → Thud**.
Return to Debug and select **Stop and save recording**; optionally enter your
actual hit count. Each session is saved privately as a `.jsonl` file. Use its
share icon for AirDrop or **Save to Files**. No Mac, network, or image capture is
required. The session stops after 10 minutes or when the app becomes inactive.

The JSON Lines file contains a schema/settings header, timestamped samples in
camera pixels (board, zoom, cutoff state, object, measured/predicted/searching,
inside-board flag, ball position/velocity, and new hit events), and a summary
with detected/actual counts and dropped-write samples. Outside-board and lost
samples are included so replay does not accidentally join unrelated trajectories.
Unfinished files after a terminated app may lack the final summary; earlier
complete lines remain available. This is diagnostic telemetry, not video.

### Replay an exported tracking recording

Run from the project root (Python 3, no extra packages):

```bash
python3 scripts/analyze_trajectory.py ~/Downloads/thud-1789749904559-7B5074EC.jsonl --actual-hits 20 --output-dir reports/thud-2026-09-18
```

Replace the input filename and output folder for each session. `--actual-hits`
overrides the optional count saved by the phone. The tool replays the schema-1
three-point detector using the exported thresholds, checks app/replay hit
timestamps, lists candidates and board visits, and compares angle/pixel thresholds.
It saves `summary.json` (including sensitivity candidates) and `turns.csv` (each
evaluated window and rejection gates). Sample numbers refer to coordinate samples,
not saved image frame numbers. Predicted/lost samples break the window, matching
the app. Board visits grouped within 0.5 seconds are diagnostic, not confirmed
physical throws; matching a total count alone does not prove detection accuracy.
The replay assumes uninterrupted detector state; changing alignment or other
settings mid-session can reset app state and cause a reported mismatch.

Regression checks: `python3 -m unittest discover -s test -p test_analyze_trajectory.py`.
