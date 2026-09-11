# BallisticCV ⚡

> A high-speed, on-device mobile computer vision app built with Flutter and native C++ (`opencv-mobile`) for real-time 60 FPS ping-pong ball tracking and rebound detection. It pairs camera frame processing with a dynamic cyberpunk HUD and neon trajectory overlays.

---

## 🎯 Features

* **Real-time 60 FPS Tracking**: Runs on-device with zero server latency using `opencv-mobile` linked via Dart FFI.
* **Smart Filtering**: BGR $\to$ HSV color masking with morphological opening and contour circularity gating.
* **Ball Radius Gating**: Discards large background objects, walls, and reflections ($6\text{px} \le r \le 85\text{px}$).
* **Dynamic Cyberpunk HUD**:
  * Glowing dynamic border: **Green** when `TRACKING`, **Red** when `SEARCHING`.
  * Live FPS counter (targeting 60 FPS).
  * Coordinate readouts $(x, y)$ and detected radius with active status icons (🎯 Crosshairs / 📡 Radar).
  * Neon fading comet trajectory trail.
* **Cross-Platform**:
  * Android (Poco and other ARM devices via NDK & CMake).
  * iOS (iPhone AVFoundation).

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
the device; 60 FPS is a target, not currently enforced by the camera configuration.

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
