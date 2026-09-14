import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/hsv_profile.dart';
import '../calibration/color_samples.dart';
import '../native/native_cv.dart';
import '../widgets/tracking_painter.dart';
import '../widgets/zoom_button.dart';
import '../capture/frame_capture.dart';

class TrackerScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final HsvProfile hsvProfile;
  final String objectName;
  final String objectId;
  final bool embedded;

  const TrackerScreen({
    super.key,
    required this.cameras,
    required this.hsvProfile,
    this.objectName = 'Object',
    this.objectId = '',
    this.embedded = false,
  });

  @override
  State<TrackerScreen> createState() => TrackerScreenState();
}

class TrackerScreenState extends State<TrackerScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  final FrameCapture _capture = FrameCapture();
  double _minZoom = 1, _maxZoom = 1, _zoom = 1;
  bool _zoomBusy = false;
  SharedPreferences? _zoomPreferences;
  bool _paused = false;
  bool _isProcessing = false;
  bool _loggedFirstLock = false;
  DetectionResult? _lastDetection;
  final List<TrackingPoint> _trail = [];

  // Frame timing & FPS
  int _frameCount = 0;
  int _receivedFrames = 0;
  int _processingMicros = 0;
  double _cameraFps = 0;
  double _cvMilliseconds = 0;
  double _fps = 0.0;
  DateTime _lastFpsCheck = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _capture.addListener(_captureChanged);
    if (Platform.isIOS) unawaited(_capture.load());
    if (widget.cameras.isNotEmpty) NativeTracker.instance.resetKalmanTracker();
    final p = widget.hsvProfile;
    debugPrint(
      '[Tracking] Target HSV median=${p.hMed},${p.sMed},${p.vMed}; '
      'H=${p.hMin}..${p.hMax}, S=${p.sMin}..${p.sMax}, V=${p.vMin}..${p.vMax}',
    );
    _initCamera();
  }

  void _captureChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _startCapture() async {
    final p = widget.hsvProfile;
    await _capture.start({
      'objectId': widget.objectId,
      'objectName': widget.objectName,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'hsv': [
        p.hMed,
        p.sMed,
        p.vMed,
        p.hMin,
        p.hMax,
        p.sMin,
        p.sMax,
        p.vMin,
        p.vMax,
      ],
    });
  }

  Future<void> _initCamera() async {
    if (widget.cameras.isEmpty) return;

    final camera = widget.cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => widget.cameras.first,
    );

    final controller = CameraController(
      camera,
      ResolutionPreset.low,
      // Request 60 FPS explicitly; the selected device format can still limit it.
      fps: Platform.isIOS ? 60 : null,
      enableAudio: false,
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420,
    );

    try {
      await controller.initialize();
      try {
        _minZoom = await controller.getMinZoomLevel();
        _maxZoom = await controller.getMaxZoomLevel();
        _zoomPreferences = await SharedPreferences.getInstance();
        // Restore before streaming, clamping for the active camera's capabilities.
        _zoom = (_zoomPreferences!.getDouble('play_zoom') ?? 1.0).clamp(
          _minZoom,
          _maxZoom,
        );
        await controller.setZoomLevel(_zoom);
      } catch (e) {
        _minZoom = _maxZoom = _zoom = 1;
        debugPrint('Zoom unavailable: $e');
      }
      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
      });

      _frameCount = 0;
      _receivedFrames = 0;
      _processingMicros = 0;
      _lastFpsCheck = DateTime.now();
      debugPrint(
        '[Tracking] Requested ${controller.mediaSettings.fps} FPS; '
        'preview=${controller.value.previewSize}',
      );
      await controller.startImageStream(_processCameraFrame);
    } catch (e) {
      debugPrint('Error initializing camera controller: $e');
    }
  }

  Future<void> _stepZoom(int direction) async {
    final controller = _controller;
    // Drop repeat ticks while a camera/write operation is pending: never queue
    // zoom steps that could continue running after the user releases the arrow.
    if (_zoomBusy || controller == null) return;
    // Integer tenths avoid accumulating floating-point drift across repeated taps.
    final value = ((_zoom * 10).round() + direction) / 10;
    final next = value.clamp(_minZoom, _maxZoom);
    setState(() => _zoomBusy = true);
    try {
      await controller.setZoomLevel(next);
      if (mounted) setState(() => _zoom = next);
      final preferences =
          _zoomPreferences ?? await SharedPreferences.getInstance();
      if (!await preferences.setDouble('play_zoom', next)) {
        throw StateError('Could not save zoom');
      }
    } catch (e) {
      debugPrint('Could not set or save zoom: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not change or save zoom. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _zoomBusy = false);
    }
  }

  void _processCameraFrame(CameraImage image) {
    _receivedFrames++;
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final processingTimer = Stopwatch()..start();
      final detection = NativeTracker.instance.detectFromCameraImage(
        image,
        hMin: widget.hsvProfile.hMin,
        hMax: widget.hsvProfile.hMax,
        sMin: widget.hsvProfile.sMin,
        sMax: widget.hsvProfile.sMax,
        vMin: widget.hsvProfile.vMin,
        vMax: widget.hsvProfile.vMax,
        enableMotion: false,
      );
      processingTimer.stop();
      _processingMicros += processingTimer.elapsedMicroseconds;

      if (!_loggedFirstLock && detection.detected && !detection.isPredicted) {
        _loggedFirstLock = true;
        debugPrint(
          '[Tracking] FIRST LOCK: x=${detection.x}, y=${detection.y}, '
          'radius=${detection.radius}; frame=${image.width}x${image.height}, '
          'format=${image.format.group}, sensor=${_controller?.description.sensorOrientation}',
        );
        final pixel = pixelHsv(
          image,
          detection.x.round().clamp(0, image.width - 1),
          detection.y.round().clamp(0, image.height - 1),
        );
        debugPrint(
          '[Tracking] Pixel at filtered center: H=${pixel.h} (${pixel.h * 2}°), '
          'S=${pixel.s}, V=${pixel.v}; within target=${matchesProfile(pixel, widget.hsvProfile)}',
        );
      }

      // FPS calculation
      _frameCount++;
      final now = DateTime.now();
      final elapsed = now.difference(_lastFpsCheck).inMilliseconds;
      if (elapsed >= 500) {
        _fps = (_frameCount * 1000.0) / elapsed;
        _cameraFps = (_receivedFrames * 1000.0) / elapsed;
        _cvMilliseconds = _processingMicros / _frameCount / 1000;
        debugPrint(
          '[Tracking] Delivered=${_cameraFps.toStringAsFixed(1)} FPS, '
          'processed=${_fps.toStringAsFixed(1)} FPS, '
          'CV=${_cvMilliseconds.toStringAsFixed(2)} ms, '
          'frame=${image.width}x${image.height}',
        );
        _frameCount = 0;
        _receivedFrames = 0;
        _processingMicros = 0;
        _lastFpsCheck = now;
      }

      if (mounted) {
        setState(() {
          _lastDetection = detection;

          if (detection.detected) {
            _trail.add(
              TrackingPoint(
                position: Offset(detection.x, detection.y),
                radius: detection.radius,
                isPredicted: detection.isPredicted,
                timestamp: now,
              ),
            );
            // Keep trail up to 25 points for smooth motion curve (matching TRAIL_LENGTH in Python)
            if (_trail.length > 25) {
              _trail.removeAt(0);
            }
          } else {
            // Decay trail smoothly when ball is missing
            if (_trail.isNotEmpty) {
              _trail.removeAt(0);
            }
          }
        });
      }
      if (Platform.isIOS && image.format.group == ImageFormatGroup.bgra8888) {
        _capture.add(
          () => {
            'bytes': image.planes.first.bytes,
            'width': image.width,
            'height': image.height,
            'stride': image.planes.first.bytesPerRow,
            'orientation': _controller?.description.sensorOrientation ?? 90,
            'detection': {
              'x': detection.x,
              'y': detection.y,
              'vx': detection.vx,
              'vy': detection.vy,
              'radius': detection.radius,
              'detected': detection.detected,
              'predicted': detection.isPredicted,
            },
            'trail': _trail
                .map(
                  (p) => {
                    'x': p.position.dx,
                    'y': p.position.dy,
                    'predicted': p.isPredicted,
                  },
                )
                .toList(),
          },
        );
      }
    } catch (e) {
      debugPrint('Frame processing error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  Future<bool> leaveActivity() async {
    if (_capture.busy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Wait for the scan to finish before switching tabs.'),
        ),
      );
      return false;
    }
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
    return true;
  }

  Future<void> _recalibrate() async {
    if (_capture.busy) return;
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      if (_capture.capturing) {
        _capture.message = 'Capture interrupted; available frames were kept.';
        unawaited(_capture.finish());
      }
      final controller = _controller;
      _controller = null;
      _paused = true;
      unawaited(controller?.dispose());
    } else if (state == AppLifecycleState.resumed && _paused) {
      _paused = false;
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _capture.removeListener(_captureChanged);
    if (_capture.capturing) unawaited(_capture.finish());
    _capture.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasCamera = _controller != null && _controller!.value.isInitialized;

    return PopScope(
      canPop: !_capture.busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.objectName} · Tracking'),
          automaticallyImplyLeading: !widget.embedded,
          leading: widget.embedded ? null : BackButton(onPressed: _recalibrate),
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Camera Feed Layer
            if (hasCamera)
              CameraPreview(_controller!)
            else if (widget.cameras.isEmpty)
              const Center(child: Text('No camera available.'))
            else
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF00FF66)),
                    SizedBox(height: 16),
                    Text(
                      'Initializing High-Speed Stream...',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  ],
                ),
              ),

            // 2. CustomPainter Kalman-Smoothed Motion Trail & HUD Layer
            if (hasCamera && _lastDetection != null)
              CustomPaint(
                painter: TrackingPainter(
                  detection: _lastDetection,
                  trail: _trail,
                  sensorOrientation: _controller!.description.sensorOrientation,
                ),
              ),

            // 3. Top Cyberpunk HUD Bar
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Builder(
                  builder: (context) {
                    final isTracking = _lastDetection?.detected ?? false;
                    final isPred = _lastDetection?.isPredicted ?? false;
                    final statusColor = isTracking
                        ? (isPred
                              ? Colors.orangeAccent
                              : const Color(0xFF00FF66))
                        : Colors.redAccent;

                    return Container(
                      margin: const EdgeInsets.only(
                        top: 6,
                        left: 16,
                        right: 16,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: statusColor, width: 2.0),
                        boxShadow: [
                          BoxShadow(
                            color: statusColor.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // FPS Indicator
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_fps.toStringAsFixed(1)} FPS',
                                style: TextStyle(
                                  color: _fps >= 55
                                      ? const Color(0xFF00FF66)
                                      : (_fps >= 30
                                            ? Colors.orangeAccent
                                            : Colors.redAccent),
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Text(
                                'In: ${_cameraFps.toStringAsFixed(0)} FPS · '
                                'CV: ${_cvMilliseconds.toStringAsFixed(1)} ms',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),

                          // Engine Status & Tracking Badge
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'BallisticCV Engine',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isTracking
                                    ? (isPred
                                          ? '◐ PREDICTING'
                                          : '● KALMAN TRACKING')
                                    : '○ SEARCHING',
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),

            // 4. Zoom and target color/coordinate readout
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: 56,
                  margin: const EdgeInsets.only(
                    bottom: 24,
                    left: 16,
                    right: 16,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        key: const ValueKey('zoomControls'),
                        // Changing coordinate text must not resize the zoom controls.
                        width: 148,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            ZoomButton(
                              label: 'Decrease zoom',
                              onStep: hasCamera && _zoom > _minZoom
                                  ? () => _stepZoom(-1)
                                  : null,
                              icon: Icons.chevron_left,
                            ),
                            Expanded(
                              child: Text(
                                '${_zoom.toStringAsFixed(1)}×',
                                textAlign: TextAlign.center,
                              ),
                            ),
                            ZoomButton(
                              label: 'Increase zoom',
                              onStep: hasCamera && _zoom < _maxZoom
                                  ? () => _stepZoom(1)
                                  : null,
                              icon: Icons.chevron_right,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Center Coordinate Readout
                      Builder(
                        builder: (context) {
                          final isTracking =
                              _lastDetection != null &&
                              _lastDetection!.detected;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Tooltip(
                                  message: 'Sampled target color',
                                  child: Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white70),
                                      color: HSVColor.fromAHSV(
                                        1,
                                        widget.hsvProfile.hMed * 2.0,
                                        widget.hsvProfile.sMed / 255,
                                        widget.hsvProfile.vMed / 255,
                                      ).toColor(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  isTracking
                                      ? '(${_lastDetection!.x.toInt()}, ${_lastDetection!.y.toInt()})'
                                      : '--',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (Platform.isIOS)
              Positioned(
                right: 18,
                bottom: 112,
                child: Column(
                  children: [
                    SizedBox(
                      width: 68,
                      height: 68,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox.expand(
                            child: CircularProgressIndicator(
                              value: _capture.capturing ? _capture.progress : 0,
                              color: Colors.redAccent,
                              backgroundColor: Colors.white24,
                              strokeWidth: 5,
                            ),
                          ),
                          IconButton.filled(
                            tooltip: _capture.saved == null
                                ? 'Capture 10 seconds'
                                : 'Delete scanned frames in Debug to capture again',
                            onPressed:
                                hasCamera &&
                                    !_capture.busy &&
                                    _capture.saved == null &&
                                    _capture.message == null
                                ? _startCapture
                                : null,
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.red,
                              disabledBackgroundColor: Colors.grey.shade800,
                            ),
                            icon: const Icon(
                              Icons.fiber_manual_record,
                              color: Colors.white,
                            ),
                            iconSize: 32,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _capture.capturing
                          ? '${(10 * (1 - _capture.progress)).ceil()}s · ${_capture.count} frames'
                          : _capture.saved != null
                          ? 'Capture saved'
                          : 'Scan 10s',
                      style: const TextStyle(backgroundColor: Colors.black87),
                    ),
                  ],
                ),
              ),
            if (_capture.message != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 205,
                child: Material(
                  color: Colors.black87,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(_capture.message!),
                  ),
                ),
              ),
            if (_capture.finishing) ...[
              const ModalBarrier(dismissible: false, color: Colors.black87),
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Finishing scanned frames…'),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
