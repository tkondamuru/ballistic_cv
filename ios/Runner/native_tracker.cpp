#include "native_tracker.h"
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <cmath>
#include <vector>
#include <cstring>
#include <algorithm>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

namespace {

class SimpleKalmanFilter2D {
public:
    bool is_initialized = false;
    int missed_frames = 0;
    
    // State: [x, y, vx, vy]
    float x = 0.0f;
    float y = 0.0f;
    float vx = 0.0f;
    float vy = 0.0f;

    // Error covariance P (4x4)
    float P[4][4] = {
        {1.0f, 0.0f, 0.0f, 0.0f},
        {0.0f, 1.0f, 0.0f, 0.0f},
        {0.0f, 0.0f, 1.0f, 0.0f},
        {0.0f, 0.0f, 0.0f, 1.0f}
    };

    void reset() {
        is_initialized = false;
        missed_frames = 0;
        x = y = vx = vy = 0.0f;
        for (int r = 0; r < 4; ++r) {
            for (int c = 0; c < 4; ++c) {
                P[r][c] = (r == c) ? 1.0f : 0.0f;
            }
        }
    }

    void predict_state() {
        // State transition: x_new = x + vx, y_new = y + vy
        x += vx;
        y += vy;

        // P_new = F * P * F^T + Q
        // F = [[1,0,1,0],[0,1,0,1],[0,0,1,0],[0,0,0,1]]
        // Q process noise = 1e-2 * I
        float q = 0.01f;
        float P_temp[4][4];

        // F * P
        for (int c = 0; c < 4; ++c) {
            P_temp[0][c] = P[0][c] + P[2][c];
            P_temp[1][c] = P[1][c] + P[3][c];
            P_temp[2][c] = P[2][c];
            P_temp[3][c] = P[3][c];
        }

        // (F * P) * F^T
        for (int r = 0; r < 4; ++r) {
            float row0 = P_temp[r][0];
            float row1 = P_temp[r][1];
            float row2 = P_temp[r][2];
            float row3 = P_temp[r][3];

            P[r][0] = row0 + row2;
            P[r][1] = row1 + row3;
            P[r][2] = row2;
            P[r][3] = row3;
        }

        for (int i = 0; i < 4; ++i) {
            P[i][i] += q;
        }
    }

    void update(float mx, float my) {
        if (!is_initialized) {
            x = mx;
            y = my;
            vx = 0.0f;
            vy = 0.0f;
            is_initialized = true;
            missed_frames = 0;
            return;
        }

        predict_state();
        missed_frames = 0;

        // Innovation y_innov = z - H * x  (H = [[1,0,0,0],[0,1,0,0]])
        float yx = mx - x;
        float yy = my - y;

        // S = H * P * H^T + R  (R = 0.1 * I)
        float r_cov = 0.1f;
        float S00 = P[0][0] + r_cov;
        float S01 = P[0][1];
        float S10 = P[1][0];
        float S11 = P[1][1] + r_cov;

        // S inverse (2x2)
        float det = S00 * S11 - S01 * S10;
        if (std::abs(det) < 1e-6f) return;

        float invS00 =  S11 / det;
        float invS01 = -S01 / det;
        float invS10 = -S10 / det;
        float invS11 =  S00 / det;

        // K = P * H^T * S_inv  (P * H^T is first 2 columns of P)
        float K[4][2];
        for (int i = 0; i < 4; ++i) {
            K[i][0] = P[i][0] * invS00 + P[i][1] * invS10;
            K[i][1] = P[i][0] * invS01 + P[i][1] * invS11;
        }

        // x = x + K * y_innov
        x  += K[0][0] * yx + K[0][1] * yy;
        y  += K[1][0] * yx + K[1][1] * yy;
        vx += K[2][0] * yx + K[2][1] * yy;
        vy += K[3][0] * yx + K[3][1] * yy;

        // P = (I - K * H) * P
        float I_KH[4][4] = {
            {1.0f - K[0][0], -K[0][1],        0.0f, 0.0f},
            {-K[1][0],        1.0f - K[1][1], 0.0f, 0.0f},
            {-K[2][0],       -K[2][1],        1.0f, 0.0f},
            {-K[3][0],       -K[3][1],        0.0f, 1.0f}
        };

        float P_new[4][4] = {0};
        for (int r = 0; r < 4; ++r) {
            for (int c = 0; c < 4; ++c) {
                P_new[r][c] = I_KH[r][0] * P[0][c] +
                              I_KH[r][1] * P[1][c] +
                              I_KH[r][2] * P[2][c] +
                              I_KH[r][3] * P[3][c];
            }
        }
        std::memcpy(P, P_new, sizeof(P));
    }

    bool update_missed() {
        if (!is_initialized) return false;

        missed_frames++;
        if (missed_frames > 8) {
            reset();
            return false;
        }

        predict_state();
        return true;
    }
};

static SimpleKalmanFilter2D g_kalman;
static cv::Mat g_prev_gray;

} // namespace

extern "C" {

int get_tracker_version() {
    return 4130; // OpenCV 4.13.0
}

void reset_kalman_tracker() {
    g_kalman.reset();
    g_prev_gray.release();
}

static DetectionResult process_bgr(
    const cv::Mat& bgr,
    int width,
    int height,
    int h_min, int h_max,
    int s_min, int s_max,
    int v_min, int v_max,
    int enable_motion
) {
    DetectionResult result;
    result.frame_width = width;
    result.frame_height = height;
    result.detected = 0;
    result.is_predicted = 0;
    result.x = 0.0f;
    result.y = 0.0f;
    result.vx = 0.0f;
    result.vy = 0.0f;
    result.radius = 0.0f;

    if (bgr.empty()) {
        return result;
    }

    // 1. Convert to HSV
    cv::Mat hsv;
    cv::cvtColor(bgr, hsv, cv::COLOR_BGR2HSV);

    // 2. Color thresholding
    cv::Mat color_mask;
    cv::Scalar lower(h_min, s_min, v_min);
    cv::Scalar upper(h_max, s_max, v_max);
    if (h_min <= h_max) {
        cv::inRange(hsv, lower, upper, color_mask);
    } else {
        // Hue wraps around red at 179 -> 0.
        cv::Mat other;
        cv::inRange(hsv, cv::Scalar(h_min, s_min, v_min), cv::Scalar(179, s_max, v_max), color_mask);
        cv::inRange(hsv, cv::Scalar(0, s_min, v_min), cv::Scalar(h_max, s_max, v_max), other);
        cv::bitwise_or(color_mask, other, color_mask);
    }

    // 3. Motion Differencing Mask (optional)
    cv::Mat gray, gray_blurred, mask;
    cv::cvtColor(bgr, gray, cv::COLOR_BGR2GRAY);
    cv::GaussianBlur(gray, gray_blurred, cv::Size(5, 5), 0);

    if (enable_motion && !g_prev_gray.empty() && g_prev_gray.size() == gray_blurred.size()) {
        cv::Mat frame_diff, motion_mask;
        cv::absdiff(gray_blurred, g_prev_gray, frame_diff);
        cv::threshold(frame_diff, motion_mask, 8, 255, cv::THRESH_BINARY);

        cv::Mat dilate_kernel = cv::getStructuringElement(cv::MORPH_ELLIPSE, cv::Size(7, 7));
        cv::dilate(motion_mask, motion_mask, dilate_kernel);
        cv::bitwise_and(color_mask, motion_mask, mask);
    } else {
        mask = color_mask.clone();
    }
    g_prev_gray = gray_blurred.clone();

    // 4. Morphological OPEN and CLOSE (matching hsv_detector.py).
    // This fixed pixel kernel can remove small/fragmented ball masks. Zoom changes
    // the mask's apparent size, so borderline detections can vary with zoom.
    cv::Mat kernel = cv::getStructuringElement(cv::MORPH_ELLIPSE, cv::Size(5, 5));
    cv::morphologyEx(mask, mask, cv::MORPH_OPEN, kernel);
    cv::morphologyEx(mask, mask, cv::MORPH_CLOSE, kernel);

    // 5. Contour Extraction & Weighted Scoring (score = area * circularity).
    // Area and radius gates below use image pixels, not physical ball dimensions.
    std::vector<std::vector<cv::Point>> contours;
    cv::findContours(mask, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);

    double best_score = 0.0;
    cv::Point2f best_center(0.0f, 0.0f);
    float best_radius = 0.0f;
    bool found_candidate = false;

    for (const auto& c : contours) {
        double area = cv::contourArea(c);
        if (area < 25.0 || area > 12000.0) {
            continue;
        }

        double perimeter = cv::arcLength(c, true);
        if (perimeter <= 0.0) {
            continue;
        }

        // Circularity check (4 * pi * Area / Perimeter^2 >= 0.35, matching config.MIN_CIRCULARITY)
        double circularity = (4.0 * M_PI * area) / (perimeter * perimeter);
        if (circularity >= 0.35) {
            cv::Point2f center(0.0f, 0.0f);
            float radius = 0.0f;
            cv::minEnclosingCircle(c, center, radius);

            double score = area * circularity;
            if (radius >= 5.0f && radius <= 85.0f && score > best_score) {
                best_score = score;
                best_center = center;
                best_radius = radius;
                found_candidate = true;
            }
        }
    }

    // 6. Both UI states use Kalman: green incorporates a fresh accepted contour;
    // orange extrapolates because no contour passed the detection gates this frame.
    bool active = false;
    if (found_candidate) {
        g_kalman.update(best_center.x, best_center.y);
        active = true;
        result.is_predicted = 0;
    } else {
        active = g_kalman.update_missed();
        result.is_predicted = 1;
    }

    if (active) {
        result.detected = 1;
        result.x = g_kalman.x;
        result.y = g_kalman.y;
        result.vx = g_kalman.vx;
        result.vy = g_kalman.vy;
        result.radius = found_candidate ? best_radius : 18.0f;
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
    int v_min, int v_max,
    int enable_motion
) {
    DetectionResult fallback;
    fallback.frame_width = width;
    fallback.frame_height = height;
    fallback.detected = 0;
    fallback.is_predicted = 0;

    if (!y_plane || !u_plane || !v_plane || width <= 0 || height <= 0) {
        return fallback;
    }

    cv::Mat yuv_nv21(height + height / 2, width, CV_8UC1);
    uint8_t* nv21_data = yuv_nv21.data;

    for (int r = 0; r < height; ++r) {
        std::memcpy(nv21_data + (r * width), y_plane + (r * y_row_stride), width);
    }

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

    return process_bgr(bgr, width, height, h_min, h_max, s_min, s_max, v_min, v_max, enable_motion);
}

DetectionResult detect_ball_rgba(
    const uint8_t* rgba_bytes,
    int width,
    int height,
    int is_bgra,
    int row_stride,
    int h_min, int h_max,
    int s_min, int s_max,
    int v_min, int v_max,
    int enable_motion
) {
    DetectionResult fallback;
    fallback.frame_width = width;
    fallback.frame_height = height;
    fallback.detected = 0;
    fallback.is_predicted = 0;

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

    return process_bgr(bgr, width, height, h_min, h_max, s_min, s_max, v_min, v_max, enable_motion);
}

static CalibratedHsvResult compute_hsv_calibration(const cv::Mat& bgr, int rx, int ry, int r_radius) {
    CalibratedHsvResult res;
    std::memset(&res, 0, sizeof(res));

    if (bgr.empty()) return res;

    cv::Mat hsv;
    cv::cvtColor(bgr, hsv, cv::COLOR_BGR2HSV);

    int min_x = std::max(0, rx - r_radius);
    int max_x = std::min(bgr.cols - 1, rx + r_radius);
    int min_y = std::max(0, ry - r_radius);
    int max_y = std::min(bgr.rows - 1, ry + r_radius);

    std::vector<int> h_vals, s_vals, v_vals;

    for (int y = min_y; y <= max_y; ++y) {
        for (int x = min_x; x <= max_x; ++x) {
            int dx = x - rx;
            int dy = y - ry;
            if (dx * dx + dy * dy <= r_radius * r_radius) {
                cv::Vec3b pixel = hsv.at<cv::Vec3b>(y, x);
                h_vals.push_back(pixel[0]);
                s_vals.push_back(pixel[1]);
                v_vals.push_back(pixel[2]);
            }
        }
    }

    if (h_vals.empty()) return res;

    std::sort(h_vals.begin(), h_vals.end());
    std::sort(s_vals.begin(), s_vals.end());
    std::sort(v_vals.begin(), v_vals.end());

    size_t mid = h_vals.size() / 2;
    res.h_med = h_vals[mid];
    res.s_med = s_vals[mid];
    res.v_med = v_vals[mid];

    res.h_min = std::max(0, res.h_med - 10);
    res.h_max = std::min(180, res.h_med + 10);
    res.s_min = std::max(70, res.s_med - 45);
    res.s_max = 255;
    res.v_min = std::max(60, res.v_med - 50);
    res.v_max = 255;

    return res;
}

CalibratedHsvResult sample_hsv_color_rgba(
    const uint8_t* rgba_bytes,
    int width,
    int height,
    int is_bgra,
    int row_stride,
    int reticle_x,
    int reticle_y,
    int reticle_radius
) {
    if (!rgba_bytes || width <= 0 || height <= 0 || row_stride < static_cast<int64_t>(width) * 4) {
        CalibratedHsvResult empty;
        std::memset(&empty, 0, sizeof(empty));
        return empty;
    }

    cv::Mat img(height, width, CV_8UC4, const_cast<uint8_t*>(rgba_bytes), row_stride);
    cv::Mat bgr;
    if (is_bgra) {
        cv::cvtColor(img, bgr, cv::COLOR_BGRA2BGR);
    } else {
        cv::cvtColor(img, bgr, cv::COLOR_RGBA2BGR);
    }

    return compute_hsv_calibration(bgr, reticle_x, reticle_y, reticle_radius);
}

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
) {
    if (!y_plane || !u_plane || !v_plane || width <= 0 || height <= 0) {
        CalibratedHsvResult empty;
        std::memset(&empty, 0, sizeof(empty));
        return empty;
    }

    cv::Mat yuv_nv21(height + height / 2, width, CV_8UC1);
    uint8_t* nv21_data = yuv_nv21.data;

    for (int r = 0; r < height; ++r) {
        std::memcpy(nv21_data + (r * width), y_plane + (r * y_row_stride), width);
    }

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

    return compute_hsv_calibration(bgr, reticle_x, reticle_y, reticle_radius);
}

} // extern "C"

