import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../models/hsv_profile.dart';

/// HSV uses OpenCV units: H 0..179; S and V 0..255.
class HsvPixel {
  final int h, s, v;
  const HsvPixel(this.h, this.s, this.v);
}

HsvPixel pixelHsv(CameraImage image, int x, int y) {
  int r, g, b;
  if (image.format.group == ImageFormatGroup.bgra8888) {
    final p = image.planes.first;
    final i = y * p.bytesPerRow + x * 4;
    b = p.bytes[i];
    g = p.bytes[i + 1];
    r = p.bytes[i + 2];
  } else if (image.format.group == ImageFormatGroup.yuv420 &&
      image.planes.length == 3) {
    final p = image.planes;
    final yy = p[0].bytes[y * p[0].bytesPerRow + x * (p[0].bytesPerPixel ?? 1)];
    final u =
        p[1].bytes[(y ~/ 2) * p[1].bytesPerRow +
            (x ~/ 2) * (p[1].bytesPerPixel ?? 1)] -
        128;
    final v =
        p[2].bytes[(y ~/ 2) * p[2].bytesPerRow +
            (x ~/ 2) * (p[2].bytesPerPixel ?? 1)] -
        128;
    r = (1.164 * (yy - 16) + 1.596 * v).round().clamp(0, 255);
    g = (1.164 * (yy - 16) - .392 * u - .813 * v).round().clamp(0, 255);
    b = (1.164 * (yy - 16) + 2.017 * u).round().clamp(0, 255);
  } else {
    throw StateError(
      'Unsupported camera format: ${image.format.group}, ${image.planes.length} planes',
    );
  }
  final hsv = HSVColor.fromColor(Color.fromARGB(255, r, g, b));
  return HsvPixel(
    (hsv.hue / 2).round() % 180,
    (hsv.saturation * 255).round(),
    (hsv.value * 255).round(),
  );
}

const sampleRadiusFraction = .045;
List<HsvPixel> sampleCenter(CameraImage image) {
  final radius = (math.min(image.width, image.height) * sampleRadiusFraction)
      .floor();
  final cx = image.width ~/ 2, cy = image.height ~/ 2;
  final pixels = <HsvPixel>[];
  for (int dy = -radius; dy <= radius; dy++) {
    for (int dx = -radius; dx <= radius; dx++) {
      if (dx * dx + dy * dy <= radius * radius) {
        pixels.add(pixelHsv(image, cx + dx, cy + dy));
      }
    }
  }
  return pixels;
}

int percentile(List<int> values, double fraction) {
  final sorted = [...values]..sort();
  return sorted[((sorted.length - 1) * fraction).round()];
}

HsvProfile combineSamples(List<List<HsvPixel>> samples) {
  final pixels = samples.expand((s) => s).toList();
  if (pixels.isEmpty) throw StateError('No color samples');
  final achromatic = percentile(pixels.map((p) => p.s).toList(), .90) < 30;
  // Anchor circular hue at the most common hue, avoiding the red 179/0 seam.
  final histogram = List.filled(180, 0);
  for (final p in pixels) {
    histogram[p.h]++;
  }
  final anchor = histogram.indexOf(histogram.reduce(math.max));
  final hues = pixels.map((p) => ((p.h - anchor + 90) % 180) - 90).toList();
  final low = percentile(hues, .10), high = percentile(hues, .90);
  if (!achromatic && high - low > 35) {
    throw StateError(
      'Samples contain different colors. Cover the small circle and retry.',
    );
  }
  final sats = pixels.map((p) => p.s).toList();
  final vals = pixels.map((p) => p.v).toList();
  return HsvProfile(
    hMed: (anchor + percentile(hues, .5)) % 180,
    sMed: percentile(sats, .5),
    vMed: percentile(vals, .5),
    hMin: achromatic ? 0 : (anchor + low - 5) % 180,
    hMax: achromatic ? 179 : (anchor + high + 5) % 180,
    sMin: (percentile(sats, .10) - 30).clamp(0, 255),
    sMax: (percentile(sats, .90) + 30).clamp(0, 255),
    vMin: (percentile(vals, .10) - 45).clamp(0, 255),
    vMax: (percentile(vals, .90) + 45).clamp(0, 255),
  );
}

bool matchesProfile(HsvPixel p, HsvProfile profile) {
  final hue = profile.hMin <= profile.hMax
      ? p.h >= profile.hMin && p.h <= profile.hMax
      : p.h >= profile.hMin || p.h <= profile.hMax;
  return hue &&
      p.s >= profile.sMin &&
      p.s <= profile.sMax &&
      p.v >= profile.vMin &&
      p.v <= profile.vMax;
}
