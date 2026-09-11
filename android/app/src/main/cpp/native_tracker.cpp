#include "native_tracker.h"
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <cmath>
#include <vector>
#include <cstring>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

extern "C" {

// OpenMP runtime cleanup stub required by NDK 27 toolchain
void __kmpc_dispatch_deinit(void* loc, int32_t gtid) {
    (void)loc;
    (void)gtid;
}

int get_tracker_version() {
    return 4130; // OpenCV 4.13.0
}

static DetectionResult process_bgr(
    const cv::Mat& bgr,
    int width,
    int height,
    int h_min, int h_max,
    int s_min, int s_max,
    int v_min, int v_max
) {
    DetectionResult result;
    result.frame_width = width;
    result.frame_height = height;
    result.detected = 0;
    result.x = 0.0f;
    result.y = 0.0f;
    result.radius = 0.0f;

    if (bgr.empty()) {
        return result;
    }

    // 1. Convert to HSV
    cv::Mat hsv;
    cv::cvtColor(bgr, hsv, cv::COLOR_BGR2HSV);

    // 2. Thresholding via inRange
    cv::Mat mask;
    cv::Scalar lower(h_min, s_min, v_min);
    cv::Scalar upper(h_max, s_max, v_max);
    cv::inRange(hsv, lower, upper, mask);

    // 3. Morphological Opening (clean 1-pixel salt-and-pepper noise)
    cv::Mat kernel = cv::getStructuringElement(cv::MORPH_ELLIPSE, cv::Size(3, 3));
    cv::morphologyEx(mask, mask, cv::MORPH_OPEN, kernel);

    // 4. Contour extraction
    std::vector<std::vector<cv::Point>> contours;
    cv::findContours(mask, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);

    double best_area = 0.0;
    cv::Point2f best_center(0.0f, 0.0f);
    float best_radius = 0.0f;
    bool found = false;

    for (const auto& c : contours) {
        double area = cv::contourArea(c);
        if (area < 25.0 || area > 12000.0) {
            continue;
        }

        double perimeter = cv::arcLength(c, true);
        if (perimeter <= 0.0) {
            continue;
        }

        // Circularity check (4 * pi * Area / Perimeter^2 >= 0.18)
        double circularity = (4.0 * M_PI * area) / (perimeter * perimeter);
        if (circularity >= 0.18) {
            cv::Point2f center(0.0f, 0.0f);
            float radius = 0.0f;
            cv::minEnclosingCircle(c, center, radius);

            // Ball radius gate: A ping-pong ball at play distance is 6px to 85px
            // This immediately discards large walls, tables, or background surfaces
            if (radius >= 6.0f && radius <= 85.0f && area > best_area) {
                best_area = area;
                best_center = center;
                best_radius = radius;
                found = true;
            }
        }
    }

    if (found) {
        result.detected = 1;
        result.x = best_center.x;
        result.y = best_center.y;
        result.radius = best_radius;
    }

    return result;
}

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
) {
    DetectionResult fallback;
    fallback.frame_width = width;
    fallback.frame_height = height;
    fallback.detected = 0;
    fallback.x = 0;
    fallback.y = 0;
    fallback.radius = 0;

    if (!y_plane || !u_plane || !v_plane || width <= 0 || height <= 0) {
        return fallback;
    }

    // Build contiguous NV21 image: Y plane + interleaved VU
    cv::Mat yuv_nv21(height + height / 2, width, CV_8UC1);
    uint8_t* nv21_data = yuv_nv21.data;

    // Copy Y rows handling row_stride
    for (int r = 0; r < height; ++r) {
        std::memcpy(nv21_data + (r * width), y_plane + (r * y_row_stride), width);
    }

    // Interleave V and U rows into NV21 format (VU order)
    uint8_t* uv_dest = nv21_data + (width * height);
    int uv_height = height / 2;
    int uv_width = width / 2;

    for (int r = 0; r < uv_height; ++r) {
        const uint8_t* u_row = u_plane + (r * uv_row_stride);
        const uint8_t* v_row = v_plane + (r * uv_row_stride);
        uint8_t* dest_row = uv_dest + (r * width);

        for (int c = 0; c < uv_width; ++c) {
            dest_row[2 * c]     = v_row[c * uv_pixel_stride];
            dest_row[2 * c + 1] = u_row[c * uv_pixel_stride];
        }
    }

    cv::Mat bgr;
    cv::cvtColor(yuv_nv21, bgr, cv::COLOR_YUV2BGR_NV21);

    return process_bgr(bgr, width, height, h_min, h_max, s_min, s_max, v_min, v_max);
}

DetectionResult detect_ball_rgba(
    const uint8_t* rgba_bytes,
    int width,
    int height,
    int is_bgra,
    int row_stride,
    int h_min, int h_max,
    int s_min, int s_max,
    int v_min, int v_max
) {
    DetectionResult fallback;
    fallback.frame_width = width;
    fallback.frame_height = height;
    fallback.detected = 0;
    fallback.x = 0;
    fallback.y = 0;
    fallback.radius = 0;

    if (!rgba_bytes || width <= 0 || height <= 0 || row_stride < static_cast<int64_t>(width) * 4) {
        return fallback;
    }

    cv::Mat img(height, width, CV_8UC4, const_cast<uint8_t*>(rgba_bytes), row_stride);
    cv::Mat bgr;
    if (is_bgra) {
        cv::cvtColor(img, bgr, cv::COLOR_BGRA2BGR);
    } else {
        cv::cvtColor(img, bgr, cv::COLOR_RGBA2BGR);
    }

    return process_bgr(bgr, width, height, h_min, h_max, s_min, s_max, v_min, v_max);
}

} // extern "C"
