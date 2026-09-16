import 'dart:ffi';
import 'dart:io';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:ffi/ffi.dart';

final class DetectionResultStruct extends Struct {
  @Float()
  external double x;

  @Float()
  external double y;

  @Float()
  external double vx;

  @Float()
  external double vy;

  @Float()
  external double radius;

  @Int32()
  external int detected;

  @Int32()
  external int isPredicted;

  @Int32()
  external int frameWidth;

  @Int32()
  external int frameHeight;
}

final class CalibratedHsvResultStruct extends Struct {
  @Int32()
  external int hMed;
  @Int32()
  external int sMed;
  @Int32()
  external int vMed;

  @Int32()
  external int hMin;
  @Int32()
  external int hMax;
  @Int32()
  external int sMin;
  @Int32()
  external int sMax;
  @Int32()
  external int vMin;
  @Int32()
  external int vMax;
}

class DetectionResult {
  final double x;
  final double y;
  final double vx;
  final double vy;
  final double radius;
  final bool detected;
  final bool isPredicted;
  final int frameWidth;
  final int frameHeight;

  const DetectionResult({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.radius,
    required this.detected,
    required this.isPredicted,
    required this.frameWidth,
    required this.frameHeight,
  });

  factory DetectionResult.empty([int width = 0, int height = 0]) {
    return DetectionResult(
      x: 0,
      y: 0,
      vx: 0,
      vy: 0,
      radius: 0,
      detected: false,
      isPredicted: false,
      frameWidth: width,
      frameHeight: height,
    );
  }

  @override
  String toString() =>
      'DetectionResult(detected: $detected, isPredicted: $isPredicted, x: ${x.toStringAsFixed(1)}, y: ${y.toStringAsFixed(1)}, v: (${vx.toStringAsFixed(1)}, ${vy.toStringAsFixed(1)}), r: ${radius.toStringAsFixed(1)})';
}

class CalibratedHsvResult {
  final int hMed;
  final int sMed;
  final int vMed;
  final int hMin;
  final int hMax;
  final int sMin;
  final int sMax;
  final int vMin;
  final int vMax;

  const CalibratedHsvResult({
    required this.hMed,
    required this.sMed,
    required this.vMed,
    required this.hMin,
    required this.hMax,
    required this.sMin,
    required this.sMax,
    required this.vMin,
    required this.vMax,
  });
}

typedef _GetVersionC = Int32 Function();
typedef _GetVersionDart = int Function();

typedef _ResetKalmanTrackerC = Void Function();
typedef _ResetKalmanTrackerDart = void Function();

typedef _DetectBallYuv420C = DetectionResultStruct Function(
  Pointer<Uint8> yPlane,
  Pointer<Uint8> uPlane,
  Pointer<Uint8> vPlane,
  Int32 width,
  Int32 height,
  Int32 yRowStride,
  Int32 uvRowStride,
  Int32 uvPixelStride,
  Int32 hMin,
  Int32 hMax,
  Int32 sMin,
  Int32 sMax,
  Int32 vMin,
  Int32 vMax,
  Int32 enableMotion,
);

typedef _DetectBallYuv420Dart = DetectionResultStruct Function(
  Pointer<Uint8> yPlane,
  Pointer<Uint8> uPlane,
  Pointer<Uint8> vPlane,
  int width,
  int height,
  int yRowStride,
  int uvRowStride,
  int uvPixelStride,
  int hMin,
  int hMax,
  int sMin,
  int sMax,
  int vMin,
  int vMax,
  int enableMotion,
);

typedef _DetectBallRgbaC = DetectionResultStruct Function(
  Pointer<Uint8> rgbaBytes,
  Int32 width,
  Int32 height,
  Int32 isBgra,
  Int32 rowStride,
  Int32 hMin,
  Int32 hMax,
  Int32 sMin,
  Int32 sMax,
  Int32 vMin,
  Int32 vMax,
  Int32 enableMotion,
);

typedef _DetectBallRgbaDart = DetectionResultStruct Function(
  Pointer<Uint8> rgbaBytes,
  int width,
  int height,
  int isBgra,
  int rowStride,
  int hMin,
  int hMax,
  int sMin,
  int sMax,
  int vMin,
  int vMax,
  int enableMotion,
);

typedef _SampleHsvRgbaC = CalibratedHsvResultStruct Function(
  Pointer<Uint8> rgbaBytes,
  Int32 width,
  Int32 height,
  Int32 isBgra,
  Int32 rowStride,
  Int32 reticleX,
  Int32 reticleY,
  Int32 reticleRadius,
);

typedef _SampleHsvRgbaDart = CalibratedHsvResultStruct Function(
  Pointer<Uint8> rgbaBytes,
  int width,
  int height,
  int isBgra,
  int rowStride,
  int reticleX,
  int reticleY,
  int reticleRadius,
);

typedef _SampleHsvYuv420C = CalibratedHsvResultStruct Function(
  Pointer<Uint8> yPlane,
  Pointer<Uint8> uPlane,
  Pointer<Uint8> vPlane,
  Int32 width,
  Int32 height,
  Int32 yRowStride,
  Int32 uvRowStride,
  Int32 uvPixelStride,
  Int32 reticleX,
  Int32 reticleY,
  Int32 reticleRadius,
);

typedef _SampleHsvYuv420Dart = CalibratedHsvResultStruct Function(
  Pointer<Uint8> yPlane,
  Pointer<Uint8> uPlane,
  Pointer<Uint8> vPlane,
  int width,
  int height,
  int yRowStride,
  int uvRowStride,
  int uvPixelStride,
  int reticleX,
  int reticleY,
  int reticleRadius,
);

class NativeTracker {
  static final NativeTracker instance = NativeTracker._internal();

  late final DynamicLibrary _lib;
  late final _GetVersionDart _getVersion;
  late final _ResetKalmanTrackerDart _resetKalman;
  late final _DetectBallYuv420Dart _detectBallYuv420;
  late final _DetectBallRgbaDart _detectBallRgba;
  late final _SampleHsvRgbaDart _sampleHsvRgba;
  late final _SampleHsvYuv420Dart _sampleHsvYuv420;

  // Reusable native buffers for zero GC churn
  Pointer<Uint8>? _yBuffer;
  int _yBufferSize = 0;
  Pointer<Uint8>? _uBuffer;
  int _uBufferSize = 0;
  Pointer<Uint8>? _vBuffer;
  int _vBufferSize = 0;

  Pointer<Uint8>? _rgbaBuffer;
  int _rgbaBufferSize = 0;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  NativeTracker._internal();

  void initialize() {
    if (_initialized) return;

    if (Platform.isAndroid) {
      _lib = DynamicLibrary.open('libnative_tracker.so');
    } else if (Platform.isIOS) {
      _lib = DynamicLibrary.process();
    } else {
      throw UnsupportedError('NativeTracker is only supported on Android and iOS.');
    }

    _getVersion = _lib
        .lookup<NativeFunction<_GetVersionC>>('get_tracker_version')
        .asFunction<_GetVersionDart>();

    _resetKalman = _lib
        .lookup<NativeFunction<_ResetKalmanTrackerC>>('reset_kalman_tracker')
        .asFunction<_ResetKalmanTrackerDart>();

    _detectBallYuv420 = _lib
        .lookup<NativeFunction<_DetectBallYuv420C>>('detect_ball_yuv420')
        .asFunction<_DetectBallYuv420Dart>();

    _detectBallRgba = _lib
        .lookup<NativeFunction<_DetectBallRgbaC>>('detect_ball_rgba')
        .asFunction<_DetectBallRgbaDart>();

    _sampleHsvRgba = _lib
        .lookup<NativeFunction<_SampleHsvRgbaC>>('sample_hsv_color_rgba')
        .asFunction<_SampleHsvRgbaDart>();

    _sampleHsvYuv420 = _lib
        .lookup<NativeFunction<_SampleHsvYuv420C>>('sample_hsv_color_yuv420')
        .asFunction<_SampleHsvYuv420Dart>();

    _initialized = true;
  }

  int getVersion() {
    initialize();
    return _getVersion();
  }

  void resetKalmanTracker() {
    initialize();
    _resetKalman();
  }

  DetectionResult detectFromCameraImage(
    CameraImage image, {
    int hMin = 35,
    int hMax = 85,
    int sMin = 70,
    int sMax = 255,
    int vMin = 60,
    int vMax = 255,
    bool enableMotion = false,
  }) {
    initialize();

    if (image.format.group == ImageFormatGroup.yuv420 && image.planes.length >= 3) {
      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];

      if (_yBuffer == null || _yBufferSize < yPlane.bytes.length) {
        if (_yBuffer != null) malloc.free(_yBuffer!);
        _yBufferSize = yPlane.bytes.length;
        _yBuffer = malloc.allocate<Uint8>(_yBufferSize);
      }
      if (_uBuffer == null || _uBufferSize < uPlane.bytes.length) {
        if (_uBuffer != null) malloc.free(_uBuffer!);
        _uBufferSize = uPlane.bytes.length;
        _uBuffer = malloc.allocate<Uint8>(_uBufferSize);
      }
      if (_vBuffer == null || _vBufferSize < vPlane.bytes.length) {
        if (_vBuffer != null) malloc.free(_vBuffer!);
        _vBufferSize = vPlane.bytes.length;
        _vBuffer = malloc.allocate<Uint8>(_vBufferSize);
      }

      _yBuffer!.asTypedList(yPlane.bytes.length).setAll(0, yPlane.bytes);
      _uBuffer!.asTypedList(uPlane.bytes.length).setAll(0, uPlane.bytes);
      _vBuffer!.asTypedList(vPlane.bytes.length).setAll(0, vPlane.bytes);

      final struct = _detectBallYuv420(
        _yBuffer!,
        _uBuffer!,
        _vBuffer!,
        image.width,
        image.height,
        yPlane.bytesPerRow,
        uPlane.bytesPerRow,
        uPlane.bytesPerPixel ?? 1,
        hMin, hMax,
        sMin, sMax,
        vMin, vMax,
        enableMotion ? 1 : 0,
      );

      return DetectionResult(
        x: struct.x,
        y: struct.y,
        vx: struct.vx,
        vy: struct.vy,
        radius: struct.radius,
        detected: struct.detected == 1,
        isPredicted: struct.isPredicted == 1,
        frameWidth: struct.frameWidth,
        frameHeight: struct.frameHeight,
      );
    } else if (image.format.group == ImageFormatGroup.bgra8888 || image.planes.length == 1) {
      final plane = image.planes[0];
      if (_rgbaBuffer == null || _rgbaBufferSize < plane.bytes.length) {
        if (_rgbaBuffer != null) malloc.free(_rgbaBuffer!);
        _rgbaBufferSize = plane.bytes.length;
        _rgbaBuffer = malloc.allocate<Uint8>(_rgbaBufferSize);
      }
      _rgbaBuffer!.asTypedList(plane.bytes.length).setAll(0, plane.bytes);

      final isBgra = image.format.group == ImageFormatGroup.bgra8888 ? 1 : 0;
      final struct = _detectBallRgba(
        _rgbaBuffer!,
        image.width,
        image.height,
        isBgra,
        plane.bytesPerRow,
        hMin, hMax,
        sMin, sMax,
        vMin, vMax,
        enableMotion ? 1 : 0,
      );

      return DetectionResult(
        x: struct.x,
        y: struct.y,
        vx: struct.vx,
        vy: struct.vy,
        radius: struct.radius,
        detected: struct.detected == 1,
        isPredicted: struct.isPredicted == 1,
        frameWidth: struct.frameWidth,
        frameHeight: struct.frameHeight,
      );
    }

    return DetectionResult.empty(image.width, image.height);
  }

  CalibratedHsvResult sampleHsvColor(
    CameraImage image, {
    required int reticleX,
    required int reticleY,
    required int reticleRadius,
  }) {
    initialize();

    if (image.format.group == ImageFormatGroup.yuv420 && image.planes.length >= 3) {
      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];

      if (_yBuffer == null || _yBufferSize < yPlane.bytes.length) {
        if (_yBuffer != null) malloc.free(_yBuffer!);
        _yBufferSize = yPlane.bytes.length;
        _yBuffer = malloc.allocate<Uint8>(_yBufferSize);
      }
      if (_uBuffer == null || _uBufferSize < uPlane.bytes.length) {
        if (_uBuffer != null) malloc.free(_uBuffer!);
        _uBufferSize = uPlane.bytes.length;
        _uBuffer = malloc.allocate<Uint8>(_uBufferSize);
      }
      if (_vBuffer == null || _vBufferSize < vPlane.bytes.length) {
        if (_vBuffer != null) malloc.free(_vBuffer!);
        _vBufferSize = vPlane.bytes.length;
        _vBuffer = malloc.allocate<Uint8>(_vBufferSize);
      }

      _yBuffer!.asTypedList(yPlane.bytes.length).setAll(0, yPlane.bytes);
      _uBuffer!.asTypedList(uPlane.bytes.length).setAll(0, uPlane.bytes);
      _vBuffer!.asTypedList(vPlane.bytes.length).setAll(0, vPlane.bytes);

      final res = _sampleHsvYuv420(
        _yBuffer!,
        _uBuffer!,
        _vBuffer!,
        image.width,
        image.height,
        yPlane.bytesPerRow,
        uPlane.bytesPerRow,
        uPlane.bytesPerPixel ?? 1,
        reticleX,
        reticleY,
        reticleRadius,
      );

      return CalibratedHsvResult(
        hMed: res.hMed, sMed: res.sMed, vMed: res.vMed,
        hMin: res.hMin, hMax: res.hMax,
        sMin: res.sMin, sMax: res.sMax,
        vMin: res.vMin, vMax: res.vMax,
      );
    } else if (image.format.group == ImageFormatGroup.bgra8888 || image.planes.length == 1) {
      final plane = image.planes[0];
      if (_rgbaBuffer == null || _rgbaBufferSize < plane.bytes.length) {
        if (_rgbaBuffer != null) malloc.free(_rgbaBuffer!);
        _rgbaBufferSize = plane.bytes.length;
        _rgbaBuffer = malloc.allocate<Uint8>(_rgbaBufferSize);
      }
      _rgbaBuffer!.asTypedList(plane.bytes.length).setAll(0, plane.bytes);

      final isBgra = image.format.group == ImageFormatGroup.bgra8888 ? 1 : 0;
      final res = _sampleHsvRgba(
        _rgbaBuffer!,
        image.width,
        image.height,
        isBgra,
        plane.bytesPerRow,
        reticleX,
        reticleY,
        reticleRadius,
      );

      return CalibratedHsvResult(
        hMed: res.hMed, sMed: res.sMed, vMed: res.vMed,
        hMin: res.hMin, hMax: res.hMax,
        sMin: res.sMin, sMax: res.sMax,
        vMin: res.vMin, vMax: res.vMax,
      );
    }

    return const CalibratedHsvResult(
      hMed: 0, sMed: 0, vMed: 0,
      hMin: 35, hMax: 85,
      sMin: 70, sMax: 255,
      vMin: 60, vMax: 255,
    );
  }

  void dispose() {
    if (_yBuffer != null) {
      malloc.free(_yBuffer!);
      _yBuffer = null;
    }
    if (_uBuffer != null) {
      malloc.free(_uBuffer!);
      _uBuffer = null;
    }
    if (_vBuffer != null) {
      malloc.free(_vBuffer!);
      _vBuffer = null;
    }
    if (_rgbaBuffer != null) {
      malloc.free(_rgbaBuffer!);
      _rgbaBuffer = null;
    }
  }
}
