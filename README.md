# BallisticCV ⚡

> A high-speed, on-device mobile computer vision app built with Flutter and native C++ (`opencv-mobile`) for real-time 60 FPS ping-pong ball tracking and rebound detection. It pairs zero-copy camera frame processing with a dynamic cyberpunk HUD and neon trajectory overlays.

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
  * iOS (iPhone AVFoundation 60 FPS).

---

## 🏗️ Architecture

```
┌────────────────────────────────────────────────────────┐
│        Camera Capture (CameraX / AVFoundation)         │
│   • Sensor Preset: Low (360p / 480p)                   │
│   • Locked high frame rate                             │
└──────────────────────────┬─────────────────────────────┘
                           │ Raw Plane Pointer (Zero-Copy)
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
* Flutter SDK (`>=3.16.0`)
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

### Build on iOS (Mac)
```bash
cd ios
open Runner.xcworkspace
# Select your Personal Team under Signing & Capabilities, then:
flutter run -d <iphone-device-id>
```
