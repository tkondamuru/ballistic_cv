import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/hsv_profile.dart';
import '../models/thud_hit.dart';
import '../native/native_cv.dart';
import '../widgets/thud_painter.dart';
import '../widgets/tracking_painter.dart';

class ThudScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final HsvProfile hsvProfile;
  final String objectName;
  final String objectId;
  final bool embedded;

  const ThudScreen({
    super.key,
    required this.cameras,
    required this.hsvProfile,
    this.objectName = 'Object',
    this.objectId = '',
    this.embedded = false,
  });

  @override
  State<ThudScreen> createState() => ThudScreenState();
}

class ThudScreenState extends State<ThudScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isProcessing = false;
  DetectionResult? _lastDetection;

  // Trajectory & Detection State
  final List<TrackingPoint> _trail = [];
  final List<ThudHit> _recordedHits = [];
  final List<ActiveSplash> _activeSplashes = [];
  final List<Offset> _recentVelocities = [];

  int _cooldownFrames = 0;

  // Frame timing & FPS
  int _frameCount = 0;
  double _fps = 0.0;
  DateTime _lastFpsCheck = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NativeTracker.instance.resetKalmanTracker();
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
      fps: Platform.isIOS ? 60 : null,
      enableAudio: false,
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420,
    );

    try {
      await controller.initialize();
      try {
        final minZoom = await controller.getMinZoomLevel();
        final maxZoom = await controller.getMaxZoomLevel();
        final preferences = await SharedPreferences.getInstance();
        final zoom = (preferences.getDouble('play_zoom') ?? 1.0).clamp(
          minZoom,
          maxZoom,
        );
        await controller.setZoomLevel(zoom);
      } catch (e) {
        debugPrint('Zoom setup error in ThudScreen: $e');
      }

      if (!mounted) {
        await controller.dispose();
        return;
      }

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

      // FPS Calculation
      _frameCount++;
      final now = DateTime.now();
      final elapsed = now.difference(_lastFpsCheck).inMilliseconds;
      if (elapsed >= 500) {
        _fps = (_frameCount * 1000.0) / elapsed;
        _frameCount = 0;
        _lastFpsCheck = now;
      }

      if (_cooldownFrames > 0) {
        _cooldownFrames--;
      }

      // Update Active Shockwave Animations
      for (int i = _activeSplashes.length - 1; i >= 0; i--) {
        _activeSplashes[i].radius += 3.5;
        _activeSplashes[i].remainingFrames--;
        if (_activeSplashes[i].remainingFrames <= 0) {
          _activeSplashes.removeAt(i);
        }
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
            if (_trail.length > 25) {
              _trail.removeAt(0);
            }

            // Track recent velocity vectors for rebound / impact detection
            final currentVel = Offset(detection.vx, detection.vy);
            _recentVelocities.add(currentVel);
            if (_recentVelocities.length > 6) {
              _recentVelocities.removeAt(0);
            }

            // Rebound & Impact Detection Logic
            if (_recentVelocities.length >= 4 &&
                _cooldownFrames == 0 &&
                !detection.isPredicted) {
              // Approach velocity (first 2 entries) vs Rebound velocity (last 2 entries)
              final vInX =
                  (_recentVelocities[0].dx + _recentVelocities[1].dx) / 2.0;
              final vInY =
                  (_recentVelocities[0].dy + _recentVelocities[1].dy) / 2.0;

              final len = _recentVelocities.length;
              final vOutX =
                  (_recentVelocities[len - 2].dx +
                      _recentVelocities[len - 1].dx) /
                  2.0;
              final vOutY =
                  (_recentVelocities[len - 2].dy +
                      _recentVelocities[len - 1].dy) /
                  2.0;

              final speedIn = math.sqrt(vInX * vInX + vInY * vInY);
              final speedOut = math.sqrt(vOutX * vOutX + vOutY * vOutY);

              // Require active approach flight (speedIn >= 7.0 px/f) and active rebound (speedOut >= 3.5 px/f)
              if (speedIn >= 7.0 && speedOut >= 3.5) {
                final dotProd = (vInX * vOutX + vInY * vOutY);
                final cosTheta = dotProd / (speedIn * speedOut);

                // Rebound inflection threshold: cos(theta) < 0.45 (direction reversal > 63 degrees)
                if (cosTheta < 0.45) {
                  // Calculate approach & rebound angles
                  final angleInRad = math.atan2(vInY, vInX);
                  final angleOutRad = math.atan2(vOutY, vOutX);

                  var diffDeg =
                      ((angleOutRad - angleInRad) * (180.0 / math.pi)).abs() %
                      360.0;
                  if (diffDeg > 180.0) {
                    diffDeg = 360.0 - diffDeg;
                  }

                  final hitNum = _recordedHits.length + 1;
                  final hitPos = Offset(detection.x, detection.y);

                  final newHit = ThudHit(
                    number: hitNum,
                    cameraPosition: hitPos,
                    deflectionDegrees: diffDeg,
                    timestamp: now,
                  );

                  _recordedHits.add(newHit);
                  _activeSplashes.add(
                    ActiveSplash(
                      hitNumber: hitNum,
                      cameraPosition: hitPos,
                      deflectionDegrees: diffDeg,
                    ),
                  );

                  _cooldownFrames = 14; // Debounce ~250ms
                  _recentVelocities.clear();
                  debugPrint(
                    '[Thud] PHYSICAL IMPACT #$hitNum detected at (${detection.x.toInt()}, ${detection.y.toInt()}); '
                    'Deflection angle=${diffDeg.toStringAsFixed(1)}°, cosTheta=${cosTheta.toStringAsFixed(2)}',
                  );
                }
              }
            }
          } else {
            // Decay trail smoothly when ball is lost
            if (_trail.isNotEmpty) {
              _trail.removeAt(0);
            }
            _recentVelocities.clear();
          }
        });
      }
    } catch (e) {
      debugPrint('Thud frame processing error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  Future<bool> leaveActivity() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
    return true;
  }

  Future<void> _navigateBack() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _clearHits() {
    setState(() {
      _recordedHits.clear();
      _activeSplashes.clear();
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
    final isTracking = _lastDetection != null && _lastDetection!.detected;

    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.objectName} · Thud (Impacts)'),
          automaticallyImplyLeading: !widget.embedded,
          leading: widget.embedded ? null : BackButton(onPressed: _navigateBack),
          actions: [
            if (_recordedHits.isNotEmpty)
              IconButton(
                tooltip: 'Clear hit markers',
                icon: const Icon(Icons.delete_sweep),
                onPressed: _clearHits,
              ),
          ],
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
                      'Initializing Thud Stream...',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  ],
                ),
              ),

            // 2. CustomPainter Thud Impact & Motion Layer
            if (hasCamera && _lastDetection != null)
              CustomPaint(
                painter: ThudPainter(
                  detection: _lastDetection,
                  trail: _trail,
                  recordedHits: _recordedHits,
                  activeSplashes: _activeSplashes,
                  sensorOrientation:
                      _controller!.description.sensorOrientation,
                ),
              ),

            // 3. Bottom Stats Bar (Hit & FPS Stats, Target Swatch & Coordinates)
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
                      // Hit & FPS Readout Box
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'HITS: ${_recordedHits.length}',
                              style: const TextStyle(
                                color: Colors.yellowAccent,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              '${_fps.toStringAsFixed(1)} FPS',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Target Color Swatch & Center Coordinate Readout
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Tooltip(
                              message: 'Sampled target color',
                              child: Container(
                                width: 16,
                                height: 16,
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
                            const SizedBox(width: 8),
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
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
