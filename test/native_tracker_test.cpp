#include "../ios/Runner/native_tracker.h"
#include <cassert>
#include <cmath>
#include <cstdio>
#include <vector>

// Run against the macOS OpenCV framework; see README.md.
int main() {
    constexpr int width = 96, height = 80;
    constexpr int packedStride = width * 4, paddedStride = packedStride + 64;
    std::vector<uint8_t> packed(packedStride * height, 0);
    std::vector<uint8_t> padded(paddedStride * height, 255);
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const bool green = (x - 48) * (x - 48) + (y - 40) * (y - 40) <= 12 * 12;
            for (int c = 0; c < 4; ++c) {
                const uint8_t value = (c == 3 || (c == 1 && green)) ? 255 : 0;
                packed[y * packedStride + x * 4 + c] = value;
                padded[y * paddedStride + x * 4 + c] = value;
            }
        }
    }
    const auto detect = [&](const uint8_t* bytes, int stride) {
        return detect_ball_rgba(bytes, width, height, 1, stride, 35, 85, 70, 255, 60, 255, 0, 0.35f);
    };
    const auto a = detect(packed.data(), packedStride);
    const auto b = detect(padded.data(), paddedStride);
    assert(get_tracker_version() == 4130);
    assert(a.detected == 1 && b.detected == 1);
    assert(std::abs(b.x - 48) < 1 && std::abs(b.y - 40) < 1);
    assert(std::abs(a.x - b.x) < 0.001 && std::abs(a.y - b.y) < 0.001);
    assert(std::abs(a.radius - b.radius) < 0.001);
    assert(b.frame_width == width && b.frame_height == height);
    assert(detect(padded.data(), packedStride - 1).detected == 0);
    assert(detect(nullptr, paddedStride).detected == 0);
    std::vector<uint8_t> black(packedStride * height, 0);
    reset_kalman_tracker();
    assert(detect(black.data(), packedStride).detected == 0);
    // Reject a larger same-color table patch before scoring/Kalman correction.
    auto competing = black;
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            if ((x-48)*(x-48)+(y-20)*(y-20) <= 8*8 ||
                (x-48)*(x-48)+(y-60)*(y-60) <= 13*13) {
                competing[y*packedStride+x*4+1] = 255;
                competing[y*packedStride+x*4+3] = 255;
            }
        }
    }
    reset_kalman_tracker();
    set_tracking_cutoff(0, -1, 35); // Accept centers above y=35.
    const auto upper = detect(competing.data(), packedStride);
    assert(upper.detected && !upper.is_predicted && std::abs(upper.y-20) < 1);
    reset_kalman_tracker();
    assert(!detect(padded.data(), paddedStride).detected); // only y=40 ball
    set_tracking_cutoff(0, 0, 0);
    reset_kalman_tracker();
    const auto lower = detect(competing.data(), packedStride);
    assert(lower.detected && std::abs(lower.y-60) < 1);
    // Change the synthetic green ball to red and verify wrapped hue limits.
    for (size_t i = 0; i < packed.size(); i += 4) {
        packed[i + 2] = packed[i + 1];
        packed[i + 1] = 0;
    }
    reset_kalman_tracker();
    const auto red = detect_ball_rgba(packed.data(), width, height, 1, packedStride,
        174, 6, 100, 255, 80, 255, 0, 0.35f);
    assert(red.detected == 1);
    reset_kalman_tracker();
    assert(detect(packed.data(), packedStride).detected == 0);
    std::puts("Native tracker: packed/padded BGRA, invalid stride, null and empty frames passed.");
}
