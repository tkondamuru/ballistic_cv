# Flutter Mobile Ball Tracker Specification (iOS & Android)

A self-contained, high-speed mobile computer vision application built with **Flutter** and **native C++ (`opencv-mobile`)**. It replaces external webcams and laptop tethering with the smartphone's camera optics, internal GPU, and on-device processing.

---

## 1. Executive Summary & Goals

* **Single Standalone App**: All vision processing, HSV filtering, Kalman tracking, hit detection, and telemetry recording are packaged entirely within the mobile app.
* **No Server Required for Real-Time Play**: Ball tracking at 60 FPS runs 100% on-device to eliminate network latency (which would cause live tracking overlays to lag behind a high-speed ball).
* **Cross-Platform**:
  * **Primary Target (Mandatory)**: iPhone (iOS) running at a locked **60 FPS** with hardware shutter control.
  * **Secondary Target**: Android (Poco device) for rapid development, desk testing, and debugging directly from Windows over USB.
* **Lightweight Native Core**: Powered by **`opencv-mobile`** via Dart FFI (~5 MB footprint vs 50+ MB standard OpenCV), with ready extension hooks for **ArUco marker detection** and **YOLO (`ncnn`)**.
* **Eliminates Room Lighting / Wall False Positives**: An interactive **Color Pipette (Screen 1)** samples the exact ball hue in ambient light before tracking begins.

---

## 2. Mandatory iPhone Compilation & Deployment Guide

Compiling and deploying to a physical iPhone is **mandatory** for production testing. You **do not** need a paid ($99/year) Apple Developer Program membership.

### 2.1 Prerequisites on Mac
1. **Mac Hardware**: Any Mac running macOS Monterey, Ventura, Sonoma, or Sequoia.
2. **Xcode**: Free from the Mac App Store.
3. **Flutter SDK**: Installed and configured (`flutter doctor`).
4. **Free Apple ID**: Used for personal code signing.

### 2.2 Free Provisioning in Xcode (Personal Team)
1. Open the generated iOS project in Xcode:
   ```bash
   cd flutter_ball_tracker/ios
   open Runner.xcworkspace
   ```
2. In Xcode's left sidebar, click **Runner** (top-level project).
3. Select the **Signing & Capabilities** tab.
4. Check **"Automatically manage signing"**.
5. Under **Team**, sign in with your free Apple ID and select **"Your Name (Personal Team)"**.
6. Set a unique **Bundle Identifier** (e.g., `com.yourname.balltracker`).
7. Connect your iPhone via USB cable to the Mac.
8. Unlock your iPhone, select it as the target device in Xcode's top toolbar, and click **Run** (or `flutter run -d <iphone-device-id>`).
9. *First run only on iPhone*: Go to **Settings > General > VPN & Device Management**, tap your Apple ID under Developer App, and tap **"Trust"**.

### 2.3 Required iOS Permissions (`ios/Runner/Info.plist`)
```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is required for real-time ping-pong ball tracking at 60 FPS.</string>

<key>NSPhotoLibraryAddUsageDescription</key>
<string>Permission is required to save tracked game data and videos to your Camera Roll.</string>

<key>NSMicrophoneUsageDescription</key>
<string>Microphone access is optional for video recording.</string>
```

---

## 3. High-Performance Architecture (60 FPS on Mobile)

Processing raw pixel streams at 60 FPS (a strict **16.6ms per-frame budget**) requires zero-copy pointer passing and offloading computer vision to a background worker:

```
┌────────────────────────────────────────────────────────┐
│        Camera Capture (AVFoundation / CameraX)         │
│   • Sensor Preset: 360p / 480p (Low bandwidth)         │
│   • Locked 60 FPS capture mode                         │
└──────────────────────────┬─────────────────────────────┘
                           │ Raw Plane Pointer (Zero-Copy)
                           ▼
┌────────────────────────────────────────────────────────┐
│     Background Worker Isolate / Native C++ Thread      │
│  [opencv-mobile Engine via Dart FFI]                   │
│   • YUV/BGRA -> HSV conversion                         │
│   • inRange Binary Mask Segmentation                   │
│   • Contour Extraction & Elliptical Gating (circ>=0.18)│
│   • State Estimation & Kalman Filter (X, Y, Vx, Vy)    │
│   • Directional Inflection & Hit Reversal Detection    │
└──────────────────────────┬─────────────────────────────┘
                           │ Lightweight Coordinate Stream: (x, y, vx, vy, hit)
                           ▼
┌────────────────────────────────────────────────────────┐
│             Flutter UI Layer (Impeller / Skia)         │
│   • CameraPreview (Edge-to-edge)                       │
│   • CustomPainter (Neon Comet Trail, Bullseye Rings)   │
│   • Top HUD: Real-Time FPS, Hit Counter, Speedometer   │
│   • Telemetry Logger (JSON session export)             │
└────────────────────────────────────────────────────────┘
```

### Architectural Key Rules:
1. **Sensor Resolution**: The camera is configured at `ResolutionPreset.low` ($480\text{p} / 360\text{p}$) directly on the sensor level. Downscaling $1080\text{p}$ in software burns battery and causes thermal throttling.
2. **Main Thread Isolation**: OpenCV operations **never run on the Flutter UI thread**. They execute in a long-lived Dart background isolate (`Isolate.spawn`) or native C++ thread to guarantee a solid 60 FPS UI rendering loop.

---

## 4. Detailed Screen Specifications

The app consists of two dedicated screens:

```
[Screen 1: Pipette Calibrator] ──(Color Locked)──> [Screen 2: Live Tracking & Arena]
         ▲                                                            │
         └────────────────────(Recalibrate Button)────────────────────┘
```

---

### Screen 1: Color Pipette & Lighting Calibrator

#### Purpose:
Solves the color-drift problem permanently. Instead of hardcoding HSV values that break when room lights change or when a wall has a similar hue, the user samples the exact ball color in 2 seconds.

#### Visual Elements:
1. **Live Camera Feed**: Real-time view of the room.
2. **Target Reticle**: A centered circular ring ($120\text{px}$ diameter) indicating where to position the ball.
3. **Color Swatch Preview**: A small circle displaying the active sampled color in real time.
4. **Lighting Indicator**: A chip showing `Lux: Optimal` / `Too Dark`.
5. **Primary Action Button**: `"Sample & Lock Ball Color"` (Large rounded button at bottom).
6. **Manual Fine-Tuning Drawer (Optional)**: Sliders for Hue Tolerance ($\pm 5\text{ to } \pm 15$), Min Saturation ($80\text{--}180$), and Min Value ($60\text{--}150$).

#### User Flow:
1. Hold the ping-pong ball inside the circular reticle.
2. Tap **"Sample & Lock Ball Color"**.
3. The app crops the reticle pixels, converts to HSV, computes the median Hue ($H_{med}$), Saturation ($S_{med}$), and Value ($V_{med}$).
4. Dynamic bounds are calculated:
   * $H \in [H_{med} - 10, H_{med} + 10]$
   * $S \in [\max(70, S_{med} - 45), 255]$
   * $V \in [\max(60, V_{med} - 50), 255]$
5. Persists these values to `SharedPreferences` so calibration is remembered across app launches.
6. Automatically navigates to **Screen 2: Live Tracking Arena**.

---

### Screen 2: Live Tracking Arena & Telemetry Recorder

#### Purpose:
The primary tracking surface. Displays the high-speed camera stream with trajectory overlays, detects physical rebounds/hits in real time, and logs complete match telemetry.

#### Visual Elements & Overlay Stack:
1. **Camera Preview**: Edge-to-edge 60 FPS live feed.
2. **CustomPainter Layer**:
   * **Target Green Ring**: Surrounds the detected ball center $(x, y)$ with radius $r$.
   * **Neon Comet Trail**: Fading trajectory line representing the last 8–10 frames. The tail is thin and translucent ($1\text{px}, \alpha=0.2$); the head is vibrant and thick ($4\text{px}, \alpha=1.0$).
   * **Hit Bullseyes**: Permanent or pulsing impact rings plotted at the exact coordinates of detected bounces/screen hits with label `HIT #1`, `HIT #2`.
3. **Top HUD Bar**:
   * **FPS Counter**: e.g., `60.2 FPS` (Green = $\ge 58$, Orange = dropping frames).
   * **Hit Counter**: Big bold badge (e.g., `HITS: 7`).
   * **Tracking Indicator**: Green dot `TRACKING` / Red dot `LOST`.
4. **Bottom Floating Controls**:
   * **Record / Stop Button**:
     * Red circle (`● REC`) when idle.
     * Flashing red square (`■ STOP [00:14]`) while recording.
   * **Recalibrate Button**: Eyedropper icon in bottom-left to return to Screen 1 if lighting shifts.
   * **Clear Hits Button**: Trash icon in bottom-right to reset the hit counter and clear bullseye rings.

#### Recording Architecture (Telemetry & Post-Compositing):
* **Live Recording (Zero Overhead)**: When **REC** is tapped, the app streams timestamps, ball coordinates $(x, y)$, estimated velocity, and hit events into a lightweight `.json` session telemetry file. This adds **$<0.1\%$ CPU overhead**, ensuring zero dropped frames during fast action.
* **Raw Video Capture (Optional)**: If full video archiving is needed, raw camera video is saved independently via standard hardware encoding.
* **Overlay Compositing**: If an `.mp4` with burned-in HUD/trail graphics is requested, it is rendered **post-session asynchronously** in the background, avoiding real-time camera stream contention.

---

## 5. Computer Vision Engine (`opencv-mobile` via C++ FFI)

The native engine is built on **`opencv-mobile`** (Nihui's minimal ~5 MB build) linked via `dart:ffi`.

### 5.1 Ball Detection Pipeline
1. **Format Conversion**: Convert incoming YUV420_888 (Android) or BGRA (iOS) buffer to BGR/HSV natively in C++.
2. **Color Masking**: Apply dynamically calibrated HSV lower and upper bounds using `cv::inRange`.
3. **Morphological Opening**: $3 \times 3$ elliptical kernel (`cv::morphologyEx`) to strip single-pixel background noise without eroding thin motion streaks.
4. **Contour Filtering**:
   * Area: $25 \le \text{Area} \le 8000$ pixels.
   * Circularity Gating: $\text{Circularity} = \frac{4\pi \cdot \text{Area}}{\text{Perimeter}^2} \ge 0.18$.
   *(Lower circularity threshold allows oblong motion-blurred ball streaks at high velocity to be tracked).*

### 5.2 2D Kalman Filter
* **State Vector**: $X = [x, y, v_x, v_y]^T$
* **Constant-Velocity Motion Model**: Bridges momentary 1–3 frame occlusions or high-speed blurs.
* **Trail Drain**: If no measurement is detected for 4 consecutive frames, clear trajectory history immediately so ghost lines never linger.

### 5.3 Physical Rebound & Hit Detection
Maintains a rolling buffer of recent trajectory vectors:
1. **Directional Inflection**:
   $$\cos(\theta) = \frac{\vec{v}_{prev} \cdot \vec{v}_{curr}}{\|\vec{v}_{prev}\| \|\vec{v}_{curr}\|} < 0.45$$
2. **Vertical / Horizontal Reversals**:
   $$\text{Reversal} = (v_{y, prev} > 1.2 \land v_{y, curr} < -0.8) \lor (v_{x, prev} \cdot v_{x, curr} < -1.5)$$
3. **Cooldown Window**: 3–4 frames debounce to prevent duplicate hit triggers from a single contact.

### 5.4 Extension Roadmap: ArUco Markers & YOLO

#### A. ArUco Marker Detection (Included via `objdetect`)
* `opencv-mobile` includes the OpenCV 4.x `objdetect` module containing `cv::aruco::ArucoDetector`.
* **Use Case**: Table calibration and cup tracking.
* **Operation**: Executed as a 1-shot snapshot on Screen 1 to compute the $3 \times 3$ table perspective homography matrix. 60 FPS ball coordinates are mapped into true table inches with zero runtime overhead during active play.

#### B. YOLO Object Detection (Via `ncnn`)
* `opencv-mobile` pairs directly with **Tencent NCNN** (Nihui's high-performance mobile neural network inference engine).
* **Capabilities**: Can run quantized YOLOv8n / YOLOv11n models at 30–60 FPS using ARM NEON and Vulkan GPU acceleration.
* **Footprint**: Adds only ~3 MB to the app binary.

---

## 6. Progressive Testing Protocol (Poco & iPhone)

```
┌────────────────────────────────────────────────────────┐
│  Test 1: Pipette Calibration & Color Lock (Sanity)     │
└──────────────────────────┬─────────────────────────────┘
                           ▼
┌────────────────────────────────────────────────────────┐
│  Test 2: Desk Roll & Book Rebound (Poco Low-Speed)     │
└──────────────────────────┬─────────────────────────────┘
                           ▼
┌────────────────────────────────────────────────────────┐
│  Test 3: Gravity Drop & Table Bounce (Vertical Check)  │
└──────────────────────────┬─────────────────────────────┘
                           ▼
┌────────────────────────────────────────────────────────┐
│  Test 4: Wall Toss & Screen Rebound (iPhone 60 FPS)    │
└────────────────────────────────────────────────────────┘
```

### Test 1: Pipette Calibration (Sanity Check)
* **Goal**: Verify color isolation against the room background.
* **Procedure**: Hold the ball in the reticle on Screen 1, tap lock, move to Screen 2. Move your hand in circles with the ball.
* **Pass Criteria**: Green circle sticks to the ball; hand skin and background walls produce zero false contours.

### Test 2: Desk Roll & Book Rebound (Poco / Low-Power Friendly)
* **Goal**: Validate tracking and horizontal rebound detection at gentle velocities ($1\text{--}2\text{ m/s}$).
* **Procedure**: Prop phone on desk. Place a heavy book 3 feet away. Roll the ball into the book so it bounces backward.
* **Pass Criteria**: Trajectory trail smoothly tracks the ball across the desk; hit marker appears instantly on rebound.

### Test 3: Gravity Drop & Vertical Bounce
* **Goal**: Verify vertical inflection ($+V_y \to -V_y$) and gravitational parabola rendering.
* **Procedure**: Hold the ball 1.5 feet above the desk and drop it.
* **Pass Criteria**: Each table contact triggers `Bounce #1`, `Bounce #2`, and plots a parabolic curve.

### Test 4: Wall Toss at 60 FPS (Full iPhone Validation)
* **Goal**: Validate high-speed flight tracking and motion-blur immunity.
* **Procedure**: Stand 4–6 feet from a wall, tap **REC**, throw the ping-pong ball 5 times against the wall, tap **STOP**.
* **Pass Criteria**: All 5 wall impacts register in real time; telemetry session JSON logs complete trajectory coordinates without frame drops.

---

## 7. Project Structure & Dependencies

### 7.1 `pubspec.yaml`
```yaml
name: flutter_ball_tracker
description: High-speed mobile ping-pong ball tracker

environment:
  sdk: '>=3.2.0 <4.0.0'
  flutter: '>=3.16.0'

dependencies:
  flutter:
    sdk: flutter
  camera: ^0.10.5+9          # High-speed camera preview & frame stream
  ffi: ^2.1.2                # Dart FFI for native C++ calls
  shared_preferences: ^2.2.2 # Persist calibrated HSV parameters
  path_provider: ^2.1.2      # Local storage for telemetry logs
  gal: ^2.1.3                # Save media/exports to Photos & Gallery

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
```

### 7.2 Directory Structure
```
flutter_ball_tracker/
├── lib/
│   ├── main.dart                      # App entry & theme setup
│   ├── native/
│   │   ├── native_cv_bindings.dart    # Dart FFI bindings & structs
│   │   └── vision_worker_isolate.dart # Background frame processing isolate
│   ├── models/
│   │   ├── hsv_profile.dart           # Calibrated HSV parameters model
│   │   ├── tracking_point.dart        # (x, y, timestamp, velocity)
│   │   └── hit_event.dart             # Hit coordinate, frame & index
│   ├── screens/
│   │   ├── calibrator_screen.dart     # Screen 1: Pipette & reticle
│   │   └── tracker_screen.dart        # Screen 2: 60 FPS arena & telemetry
│   └── widgets/
│       ├── camera_reticle.dart        # Target circle for color pipette
│       ├── tracking_painter.dart      # CustomPainter for comet trail & bullseyes
│       └── hud_overlay.dart           # FPS, hit counter & recording status
├── android/
│   ├── app/
│   │   ├── CMakeLists.txt             # Native build configuration
│   │   └── src/main/cpp/
│   │       ├── native_tracker.h       # C++ tracking interface
│   │       ├── native_tracker.cpp     # opencv-mobile HSV & contour logic
│   │       └── opencv-mobile-android/ # Precompiled opencv-mobile headers & libs
│   └── app/src/main/AndroidManifest.xml
└── ios/
    ├── Runner/
    │   ├── native_tracker.cpp         # Shared C++ implementation
    │   ├── native_tracker.h
    │   ├── opencv2.framework          # Precompiled opencv-mobile iOS framework
    │   └── Info.plist                 # Camera & Photos permissions
    └── Runner.xcworkspace
```

---

## 8. Rapid Development Roadmap (Day 1: "Hello World" in 2–3 Hours)

| Phase | Est. Time | Tasks |
| :--- | :---: | :--- |
| **Phase 1: Pre-Built Binaries** | **15 min** | Download `opencv-mobile-4.10.0-android.zip` and `opencv-mobile-4.10.0-ios.zip`, extract into `android/.../cpp/` and `ios/Runner/`. |
| **Phase 2: Android FFI Bridge (Windows)** | **45–60 min** | Configure `CMakeLists.txt`, implement `native_tracker.cpp`, write `native_cv_bindings.dart`, run `flutter run` on connected Poco device over USB, verify green ball coordinates print in console. |
| **Phase 3: iOS Setup (Mac with Co-Pilot)** | **45–60 min** | Open `Runner.xcworkspace` in Xcode, link `opencv2.framework`, set Personal Team signing profile, run on physical iPhone. |
| **Phase 4: Flutter Camera Hookup** | **30 min** | Stream `CameraImage` planes to background isolate, render green target ring at detected $(x, y)$ in `CustomPainter`. |
