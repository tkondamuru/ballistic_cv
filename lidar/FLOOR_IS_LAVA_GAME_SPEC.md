# Virtual "Floor is Lava" & Grid Stepper Game Architecture

## 1. Executive Summary

Commercial interactive tile arcades (e.g., *Activate Games*) require $50,000+ in hardware for hundreds of physical pressure-sensitive LED floor tiles. 

This specification defines a zero-extra-hardware camera-based alternative. A single smartphone mounted in a room tracks multi-person 3D floor positions via Apple Vision / MediaPipe Pose skeleton tracking, mapping player foot positions onto a virtual TV grid streamed over WebSockets via Cloudflare Durable Objects.

---

## 2. System Architecture & Component Flow

```
[ Smartphone Camera (Room Angle) ]
           │
           ├── 1. Multi-Person Foot Detection (Apple Vision / MediaPipe Pose)
           ├── 2. Floor Planar Homography Mapping (Room Floor -> Grid Columns/Rows)
           │
           ▼
[ Cloudflare Durable Object WebSocket Relay ]
           │
           ▼
[ TV Monitor / Laptop Browser Canvas Engine ]
           ├── 1. Renders 6x6 (or 8x8) Tile Grid (Green Safe, Red Lava, Coin Bonus)
           ├── 2. Renders Real-time Player Avatars & Footprints
           └── 3. Evaluates Win/Loss Collision States
```

---

## 3. Real-Time WebSocket Payload Format

The smartphone streams player floor positions at 30–60 FPS to the browser:

```json
{
  "type": "players_update",
  "timestamp": 1726798000123,
  "room": "lava-room-1",
  "players": [
    {
      "id": 1,
      "name": "Player 1",
      "gridCol": 2,
      "gridRow": 4,
      "color": "#00E5FF",
      "isJumping": false
    },
    {
      "id": 2,
      "name": "Player 2",
      "gridCol": 5,
      "gridRow": 1,
      "color": "#FF00AA",
      "isJumping": true
    }
  ]
}
```

---

## 4. Game Modes

### A. Classic Lava Invasion
- **Objective**: Survive as long as possible without stepping on spreading red tiles.
- **Mechanics**: Red tiles spread dynamically from room edges. Safe green tiles open up randomly. Players must physically jump across their room floor to land on the safe green tiles.

### B. Memory Tile Stepper
- **Objective**: Memorize and step out tile sequences.
- **Mechanics**: TV displays a 4-step tile pattern (e.g., A2 -> B3 -> C1 -> D4). Players must jump across the sequence in order from memory.

### C. Speed Coin Rush
- **Objective**: Collect the highest number of coins in 60 seconds.
- **Mechanics**: Golden coins spawn on random grid tiles for 3 seconds. Multiple players race across the room floor to step on the coin tile first.

---

## 5. Technical Implementation Steps

1. **Foot Centroid Tracking**: Track ankle/foot 2D keypoints for up to 4 simultaneous players.
2. **Floor Quad Calibration**: Tap 4 corners of the living room rug/play area to compute planar homography matrix $H_{\text{floor}}$.
3. **Collision Detection**: Evaluate player grid cell indices against target grid state map.
