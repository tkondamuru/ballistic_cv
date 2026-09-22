# iPhone LiDAR Depth Stream, 3D Ball Velocity & Time-of-Flight Roadmap

This document outlines the step-by-step technical implementation roadmap for expanding the `cvthudwave` / `ballistic_cv` computer vision engine to utilize iPhone LiDAR hardware depth sensing for 3D ball trajectory estimation, live depth heatmap rendering, and predictive time-of-flight impact calculation.

---

## 📌 Phase 1: iOS LiDAR Depth Buffer Stream Integration
**Goal**: Access the raw iPhone LiDAR depth map alongside your RGB camera frames.

- **Task 1.1**: Update iOS `ARSession` configuration in `Runner` to enable `.sceneDepth`:
  ```swift
  let config = ARWorldTrackingConfiguration()
  if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
      config.frameSemantics.insert(.sceneDepth)
  }
  session.run(config)
  ```
- **Task 1.2**: In `session(_:didUpdate:)`, extract `frame.sceneDepth?.depthMap` (a 32-bit float buffer where each pixel holds distance in meters).
- **Task 1.3**: Pass the depth buffer pointer alongside the RGB image pointer into your C++ native tracker (`native_tracker.cpp`).

---

## 📌 Phase 2: Live LiDAR Depth Heatmap Overlay
**Goal**: Render the Predator-style thermal depth overlay over camera frames.

- **Task 2.1**: In `native_tracker.cpp`, convert the 32-bit float depth map (0.5m to 5.0m) to an 8-bit grayscale image (`CV_8UC1`).
- **Task 2.2**: Apply OpenCV’s Jet/Turbo colormap:
  ```cpp
  cv::applyColorMap(depth8bit, depthColorMap, cv::COLORMAP_JET);
  ```
- **Task 2.3**: Blend 40% of the colored depth heatmap onto the camera frame using `cv::addWeighted`.
- **Task 2.4**: Add a toggle switch in Flutter UI: `Show Depth Heatmap: ON / OFF`.

---

## 📌 Phase 3: 3D Ball Sampling (2D Pixels -> 3D World Coordinates)
**Goal**: Calculate exact `(X, Y, Z)` physical location of the ball.

- **Task 3.1**: Use your existing HSV color segmentation to find the 2D ball centroid `(pixel_x, pixel_y)`.
- **Task 3.2**: Sample the LiDAR depth array at `(pixel_x, pixel_y)` to get `Z_ball` in meters.
- **Task 3.3**: Convert 2D pixel `(pixel_x, pixel_y, Z_ball)` to 3D world coordinates `(X_ball, Y_ball, Z_ball)` using camera focal length:
  - `X_ball = (pixel_x - cx) * Z_ball / fx`
  - `Y_ball = (pixel_y - cy) * Z_ball / fy`

---

## 📌 Phase 4: 3D Kalman Filter & Time-of-Flight (ToF) Kinematics
**Goal**: Estimate 3D velocity (MPH) and predict wall arrival time.

- **Task 4.1**: Expand your C++ Kalman Filter state vector to 3D: `[X, Y, Z, Vx, Vy, Vz, Ax, Ay, Az]`.
- **Task 4.2**: Compute 3D velocity in meters/second and convert to MPH:
  - `Speed_MPH = sqrt(Vx^2 + Vy^2 + Vz^2) * 2.237`
- **Task 4.3**: Calculate the screen wall plane equation `(Ax + By + Cz + D = 0)` using the 4 corner calibration pins.
- **Task 4.4**: Calculate predicted Time of Flight remaining before collision:
  - `Time_To_Impact_Seconds = (Z_ball - Z_wall) / Vz`

---

## 📌 Phase 5: AR HUD Display & WebSocket Payload
**Goal**: Broadcast 3D metrics to your web browser monitor and render 3D trajectory HUD.

- **Task 5.1**: Expand WebSocket JSON payload sent to Cloudflare:
  ```json
  {
    "type": "hit",
    "u": 0.45,
    "v": 0.32,
    "zMeters": 1.85,
    "speedMph": 44.2,
    "timeOfFlightMs": 120
  }
  ```
- **Task 5.2**: Render 3D trajectory ribbon line connecting historical `(X, Y, Z)` points on mobile preview and HTML5 web canvas.
- **Task 5.3**: Render floating AR HUD badges: `3D DEPTH`, `SPEED (MPH)`, and `TIME TO FLIGHT (ms)`.
