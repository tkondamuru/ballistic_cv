import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../models/hsv_profile.dart';
import '../calibration/color_samples.dart';
import '../native/native_cv.dart';
import '../widgets/tracking_painter.dart';

class TrackerScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final HsvProfile hsvProfile;
  final String objectName;

  const TrackerScreen({
    super.key,
    required this.cameras,
    required this.hsvProfile,
    this.objectName = 'Object',
  });

  @override
  State<TrackerScreen> createState() => _TrackerScreenState();
}

class _TrackerScreenState extends State<TrackerScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isProcessing = false;
  bool _loggedFirstLock = false;
  DetectionResult? _lastDetection;
  final List<TrackingPoint> _trail = [];

  // Frame timing & FPS
  int _frameCount = 0;
  double _fps = 0.0;
  DateTime _lastFpsCheck = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NativeTracker.instance.resetKalmanTracker();
    final p = widget.hsvProfile;
    debugPrint(
      '[Tracking] Target HSV median=${p.hMed},${p.sMed},${p.vMed}; '
      'H=${p.hMin}..${p.hMax}, S=${p.sMin}..${p.sMax}, V=${p.vMin}..${p.vMax}',
    );
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (widget.cameras.isEmpty) return;

    final camera = widget.cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => widget.cameras.first,
    );

    final controller = CameraController(
      camera,
      ResolutionPreset.low, // 360p / 480p for locked high throughput
      enableAudio: false,
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420,
    );

    try {
      await controller.initialize();
      if (!mounted) return;

      setState(() {
        _controller = controller;
      });

      await controller.startImageStream(_processCameraFrame);
    } catch (e) {
      debugPrint('Error initializing camera controller: $e');
    }
  }

  void _processCameraFrame(CameraImage image) {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
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
        _frameCount = 0;
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
    } catch (e) {
      debugPrint('Frame processing error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _recalibrate() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _resetTrackerState() {
    _loggedFirstLock = false;
    NativeTracker.instance.resetKalmanTracker();
    setState(() {
      _trail.clear();
      _lastDetection = null;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasCamera = _controller != null && _controller!.value.isInitialized;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.objectName} · Tracking'),
        leading: BackButton(onPressed: _recalibrate),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Camera Feed Layer
          if (hasCamera)
            CameraPreview(_controller!)
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
                      ? (isPred ? Colors.orangeAccent : const Color(0xFF00FF66))
                      : Colors.redAccent;

                  return Container(
                    margin: const EdgeInsets.only(top: 6, left: 16, right: 16),
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
                              'Target: 60 FPS',
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

          // 4. Bottom Controls: Eyedropper Recalibrate & Reset Buttons
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Recalibrate Button (Eyedropper)
                    FloatingActionButton.extended(
                      heroTag: 'recalibrate',
                      onPressed: _recalibrate,
                      backgroundColor: Colors.black.withValues(alpha: 0.85),
                      foregroundColor: const Color(0xFF00FF66),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(
                          color: Color(0xFF00FF66),
                          width: 1.5,
                        ),
                      ),
                      icon: const Icon(Icons.arrow_back, size: 20),
                      label: const Text(
                        'ACTIVITIES',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    // Center Coordinate Readout
                    Builder(
                      builder: (context) {
                        final isTracking =
                            _lastDetection != null && _lastDetection!.detected;
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

                    // Reset Trail & Kalman Filter
                    FloatingActionButton(
                      heroTag: 'reset',
                      onPressed: _resetTrackerState,
                      backgroundColor: Colors.black.withValues(alpha: 0.85),
                      foregroundColor: Colors.white70,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(
                          color: Colors.white24,
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(Icons.refresh, size: 22),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
