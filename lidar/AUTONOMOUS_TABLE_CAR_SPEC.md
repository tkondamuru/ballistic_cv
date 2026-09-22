# Autonomous Mini-City Table Car System Architecture (God-View Navigation)

## 1. Executive Summary

This specification defines a low-cost, centralized "God-View" autonomous vehicle and mini-city navigation architecture. Instead of mounting complex onboard sensors on toy vehicles, a single overhead tripod-mounted smartphone (iPhone) equipped with Computer Vision (CV) and LiDAR handles 100% of spatial perception, obstacle detection, pathfinding, and vehicle motor control.

---

## 2. System Architecture & Component Flow

```
[ Overhead Smartphone (Tripod Table View) ]
           │
           ├── 1. Table Homography (Transforms camera view into 2D Top-Down Grid)
           ├── 2. Car Pose Estimation (ArUco marker on car roof -> X, Y, Heading Theta)
           ├── 3. Obstacle Detection (Lego Blocks / City Buildings -> Occupancy Grid)
           ├── 4. Target Detection (Passenger Figurine -> Destination Coordinates)
           │
           ▼
[ A* (A-Star) Grid Pathfinding Engine ] (Runs in C++ / JS < 2ms)
           │
           ├── Computes shortest collision-free path around buildings
           │
           ▼
[ PID Motor Controller ]
           │
           └── Sends Bluetooth LE / WebSocket Commands to Micro-Car (ESP32):
               { "motorL": 180, "motorR": 120, "steeringDeg": -15 }
```

---

## 3. Hardware Requirements (~$20 Total Cost)

1. **Micro Autonomous Vehicle**: Small RC chassis fitted with an ESP32-BLE / Wi-Fi microcontroller + DRV8833 motor driver (~$15).
2. **Roof Tracking Marker**: Small high-contrast ArUco tag or dual-color LED pair on the car roof for sub-millimeter position and heading orientation (`theta`).
3. **City Environment**: Lego blocks (buildings/houses), passenger figurines, 4 corner table markers.
4. **Overhead Camera**: iPhone mounted on a tripod facing down at the table surface.

---

## 4. Algorithmic Stack

### A. Table Top-Down Homography
Warps the angled camera perspective into a clean top-down $20 \times 20$ grid representation:

$$H_{\text{table}} = \text{cv::findHomography}(\text{CameraCorners}, \text{GridCorners})$$

### B. Occupancy Grid Map
Houses and Lego structures generate a 2D boolean matrix `Grid[Row][Col]` where `0 = Open Street` and `1 = Blocked Building`.

### C. A* (A-Star) Pathfinding
Calculates the optimal street navigation route:

$$f(n) = g(n) + h(n)$$

Where $g(n)$ is the distance from start to node $n$, and $h(n)$ is the estimated Euclidean distance from node $n$ to destination.

### D. Steering PID Control Loop
Compares car heading angle $\theta_{\text{car}}$ with desired path vector $\theta_{\text{target}}$:

$$\text{SteeringError} = \theta_{\text{target}} - \theta_{\text{car}}$$

Sends differential motor speed commands to turn left or right.

---

## 5. Development Milestones

1. **Milestone 1**: Single Car Point-to-Point Driving on open table.
2. **Milestone 2**: Lego City Obstacle Avoidance via A* Pathfinding.
3. **Milestone 3**: Dynamic Re-routing (Placing/moving Lego houses live while car is driving).
4. **Milestone 4**: Multi-Car Fleet Management (2 Cars, 2 Passengers with inter-vehicle collision avoidance).
