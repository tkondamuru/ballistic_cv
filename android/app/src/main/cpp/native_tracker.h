#ifndef NATIVE_TRACKER_H
#define NATIVE_TRACKER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    float x;           // Kalman-smoothed X coordinate
    float y;           // Kalman-smoothed Y coordinate
    float vx;          // Estimated velocity X (pixels/frame)
    float vy;          // Estimated velocity Y (pixels/frame)
    float radius;      // Detected radius in pixels
    int detected;      // 1 if valid state, 0 if lost
    int is_predicted;  // 1 if bridged by Kalman prediction during occlusion
    int frame_width;   // Processed width
    int frame_height;  // Processed height
} DetectionResult;

typedef struct {
    int h_med;
    int s_med;
    int v_med;
    int h_min;
    int h_max;
    int s_min;
    int s_max;
    int v_min;
    int v_max;
} CalibratedHsvResult;

// Version check
int get_tracker_version();

// Reset Kalman filter and motion tracking history
void reset_kalman_tracker();

// Android CameraImage YUV420_888 frame detection
DetectionResult detect_ball_yuv420(
    const uint8_t* y_plane,
    const uint8_t* u_plane,
    const uint8_t* v_plane,
    int width,
    int height,
    int y_row_stride,
    int uv_row_stride,
    int uv_pixel_stride,
    int h_min, int h_max,
    int s_min, int s_max,
    int v_min, int v_max,
    int enable_motion,
    float min_circularity
);

// BGRA/RGBA frame detection (for iOS)
DetectionResult detect_ball_rgba(
    const uint8_t* rgba_bytes,
    int width,
    int height,
    int is_bgra,
    int row_stride,
    int h_min, int h_max,
    int s_min, int s_max,
    int v_min, int v_max,
    int enable_motion,
    float min_circularity
);

// Reticle Color Sampling for Screen 1 Pipette Calibrator
CalibratedHsvResult sample_hsv_color_rgba(
    const uint8_t* rgba_bytes,
    int width,
    int height,
    int is_bgra,
    int row_stride,
    int reticle_x,
    int reticle_y,
    int reticle_radius
);

CalibratedHsvResult sample_hsv_color_yuv420(
    const uint8_t* y_plane,
    const uint8_t* u_plane,
    const uint8_t* v_plane,
    int width,
    int height,
    int y_row_stride,
    int uv_row_stride,
    int uv_pixel_stride,
    int reticle_x,
    int reticle_y,
    int reticle_radius
);

#ifdef __cplusplus
}
#endif

#endif // NATIVE_TRACKER_H
