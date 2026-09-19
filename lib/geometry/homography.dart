import 'dart:ui';

/// Provides perspective and bilinear quad normalization mapping camera coordinates (x, y)
/// relative to 4 boundary pin handles (TL, TR, BR, BL) into unit coordinates (u, v) in [0, 1].
class Homography {
  /// Map camera position [p] within [quad] (TL, TR, BR, BL) to normalized (u, v).
  static Offset normalize(Offset p, List<Offset> quad) {
    if (quad.length != 4) return Offset.zero;

    final p0 = quad[0]; // TL
    final p1 = quad[1]; // TR
    final p2 = quad[2]; // BR
    final p3 = quad[3]; // BL

    final normalized = _invertQuad(p, p0, p1, p2, p3);
    return Offset(
      normalized.dx.clamp(-0.2, 1.2),
      normalized.dy.clamp(-0.2, 1.2),
    );
  }

  static Offset _invertQuad(
    Offset p,
    Offset p0,
    Offset p1,
    Offset p2,
    Offset p3,
  ) {
    double u = 0.5;
    double v = 0.5;

    for (int i = 0; i < 8; i++) {
      final cur = _eval(u, v, p0, p1, p2, p3);
      final f = cur - p;

      // Partial derivatives
      final du = (p1 - p0) * (1.0 - v) + (p2 - p3) * v;
      final dv = (p3 - p0) * (1.0 - u) + (p2 - p1) * u;

      final det = du.dx * dv.dy - du.dy * dv.dx;
      if (det.abs() < 1e-9) break;

      final deltaU = (f.dx * dv.dy - f.dy * dv.dx) / det;
      final deltaV = (du.dx * f.dy - du.dy * f.dx) / det;

      u -= deltaU;
      v -= deltaV;

      if (deltaU.abs() < 1e-6 && deltaV.abs() < 1e-6) break;
    }

    return Offset(u, v);
  }

  static Offset _eval(
    double u,
    double v,
    Offset p0,
    Offset p1,
    Offset p2,
    Offset p3,
  ) {
    return Offset(
      (1.0 - u) * (1.0 - v) * p0.dx + u * (1.0 - v) * p1.dx + u * v * p2.dx + (1.0 - u) * v * p3.dx,
      (1.0 - u) * (1.0 - v) * p0.dy + u * (1.0 - v) * p1.dy + u * v * p2.dy + (1.0 - u) * v * p3.dy,
    );
  }
}
