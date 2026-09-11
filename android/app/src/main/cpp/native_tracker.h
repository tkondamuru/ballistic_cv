#ifndef NATIVE_TRACKER_H
#define NATIVE_TRACKER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    float x;          // Normalized or pixel X coordinate (center of ball)
    float y;          // Normalized or pixel Y coordinate (center of ball)
    float radius;     // Detected radius in pixels
    int detected;     // 1 if ball detected, 0 if lost
    int frame_width;  // Processed width
    int frame_height; // Processed height
} DetectionResult;

// Test function to verify FFI link
int get_tracker_version();

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
    int v_min, int v_max
);

// BGRA/RGBA frame detection (for iOS or test bitmaps)
DetectionResult detect_ball_rgba(
    const uint8_t* rgba_bytes,
    int width,
    int height,
    int is_bgra,
    int row_stride,
    int h_min, int h_max,
    int s_min, int s_max,
    int v_min, int v_max
);

#ifdef __cplusplus
}
#endif

#endif // NATIVE_TRACKER_H
