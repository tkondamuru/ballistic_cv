import 'dart:ffi';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:ffi/ffi.dart';

final class DetectionResultStruct extends Struct {
  @Float()
  external double x;

  @Float()
  external double y;

  @Float()
  external double radius;

  @Int32()
  external int detected;

  @Int32()
  external int frameWidth;

  @Int32()
  external int frameHeight;
}

class DetectionResult {
  final double x;
  final double y;
  final double radius;
  final bool detected;
  final int frameWidth;
  final int frameHeight;

  const DetectionResult({
    required this.x,
    required this.y,
    required this.radius,
    required this.detected,
    required this.frameWidth,
    required this.frameHeight,
  });

  factory DetectionResult.empty([int width = 0, int height = 0]) {
    return DetectionResult(
      x: 0,
      y: 0,
      radius: 0,
      detected: false,
      frameWidth: width,
      frameHeight: height,
    );
  }

  @override
  String toString() =>
      'DetectionResult(detected: $detected, x: ${x.toStringAsFixed(1)}, y: ${y.toStringAsFixed(1)}, r: ${radius.toStringAsFixed(1)}, size: ${frameWidth}x$frameHeight)';
}

typedef _GetVersionC = Int32 Function();
typedef _GetVersionDart = int Function();

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
);

typedef _DetectBallRgbaC = DetectionResultStruct Function(
  Pointer<Uint8> rgbaBytes,
  Int32 width,
  Int32 height,
  Int32 isBgra,
  Int32 hMin,
  Int32 hMax,
  Int32 sMin,
  Int32 sMax,
  Int32 vMin,
  Int32 vMax,
);

typedef _DetectBallRgbaDart = DetectionResultStruct Function(
  Pointer<Uint8> rgbaBytes,
  int width,
  int height,
  int isBgra,
  int hMin,
  int hMax,
  int sMin,
  int sMax,
  int vMin,
  int vMax,
);

class NativeTracker {
  static final NativeTracker instance = NativeTracker._internal();

  late final DynamicLibrary _lib;
  late final _GetVersionDart _getVersion;
  late final _DetectBallYuv420Dart _detectBallYuv420;
  late final _DetectBallRgbaDart _detectBallRgba;

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

    _detectBallYuv420 = _lib
        .lookup<NativeFunction<_DetectBallYuv420C>>('detect_ball_yuv420')
        .asFunction<_DetectBallYuv420Dart>();

    _detectBallRgba = _lib
        .lookup<NativeFunction<_DetectBallRgbaC>>('detect_ball_rgba')
        .asFunction<_DetectBallRgbaDart>();

    _initialized = true;
  }

  int getVersion() {
    initialize();
    return _getVersion();
  }

  DetectionResult detectFromCameraImage(
    CameraImage image, {
    int hMin = 35, // Default green lower bound
    int hMax = 85, // Default green upper bound
    int sMin = 70,
    int sMax = 255,
    int vMin = 60,
    int vMax = 255,
  }) {
    initialize();

    if (image.format.group == ImageFormatGroup.yuv420 && image.planes.length >= 3) {
      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];

      // Ensure reusable buffers are large enough
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
      );

      return DetectionResult(
        x: struct.x,
        y: struct.y,
        radius: struct.radius,
        detected: struct.detected == 1,
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
        hMin, hMax,
        sMin, sMax,
        vMin, vMax,
      );

      return DetectionResult(
        x: struct.x,
        y: struct.y,
        radius: struct.radius,
        detected: struct.detected == 1,
        frameWidth: struct.frameWidth,
        frameHeight: struct.frameHeight,
      );
    }

    return DetectionResult.empty(image.width, image.height);
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
