import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../capture/frame_capture.dart';
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
  final FrameCapture _capture = FrameCapture();
  bool _isProcessing = false;
  DetectionResult? _lastDetection;

  // ArUco Boundary State (null = unlocked/all deflections marked in real-time)
  List<Offset>? _arucoBoundary;
  bool _scanArucoRequested = false;

  // Trajectory & Detection State
  final List<TrackingPoint> _trail = [];
  final List<ThudHit> _recordedHits = [];
  final List<ActiveSplash> _activeSplashes = [];

  int _cooldownFrames = 0;

  // Frame timing & FPS
  int _frameCount = 0;
  double _fps = 0.0;
  DateTime _lastFpsCheck = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _capture.addListener(_captureChanged);
    if (Platform.isIOS) unawaited(_capture.load());
    NativeTracker.instance.resetKalmanTracker();
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
      'activity': 'thud',
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

  bool _isPointInsideQuad(Offset p, List<Offset> quad) {
    if (quad.length != 4) return true;
    bool? positive;
    for (int i = 0; i < 4; i++) {
      final a = quad[i];
      final b = quad[(i + 1) % 4];
      final crossProduct =
          (b.dx - a.dx) * (p.dy - a.dy) - (b.dy - a.dy) * (p.dx - a.dx);
      if (crossProduct == 0) continue;
      if (positive == null) {
        positive = crossProduct > 0;
      } else if ((crossProduct > 0) != positive) {
        return false;
      }
    }
    return true;
  }

  void _onScanArucoPressed() {
    if (_capture.busy) return;
    if (_arucoBoundary != null) {
      setState(() {
        _arucoBoundary = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ArUco boundary unlocked.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _scanArucoRequested = true;
    });
  }

  void _performArucoScan(CameraImage image) {
    _scanArucoRequested = false;

    // Detect real ArUco / square quad marker centroids from OpenCV
    final detectedCorners =
        NativeTracker.instance.detectArucoCornersFromCameraImage(image);

    if (detectedCorners.length == 4) {
      final ordered = orderArUcoCorners(detectedCorners);
      setState(() {
        _arucoBoundary = ordered;
        // Clear all previous hit points when boundary is locked
        _recordedHits.clear();
        _activeSplashes.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('4 ArUco codes identified. Boundary locked.'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      final count = detectedCorners.length;
      setState(() {
        _arucoBoundary = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Identified $count ArUco code(s) (4 required). Move camera to focus.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
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

      if (_scanArucoRequested) {
        _performArucoScan(image);
      }

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

          final bool validLocation = detection.detected &&
              (_arucoBoundary == null ||
                  _isPointInsideQuad(
                    Offset(detection.x, detection.y),
                    _arucoBoundary!,
                  ));

          if (validLocation) {
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

            // Geometric Deflection & Impact Detection Logic (Real-Time Peak Detection)
            if (_trail.length >= 5 &&
                _cooldownFrames == 0 &&
                !detection.isPredicted) {
              final idxK = _trail.length - 3; // Candidate vertex index
              final pA = _trail[idxK - 2].position;
              final pK = _trail[idxK].position; // Candidate corner vertex
              final pB = _trail[idxK + 2].position;

              final vIn = Offset(pK.dx - pA.dx, pK.dy - pA.dy);
              final vOut = Offset(pB.dx - pK.dx, pB.dy - pK.dy);

              final sIn = vIn.distance;
              final sOut = vOut.distance;

              // Require active motion into and out of candidate vertex (at least 3.5px over 2 frames)
              if (sIn >= 3.5 && sOut >= 3.5) {
                final dot = vIn.dx * vOut.dx + vIn.dy * vOut.dy;
                final cosTheta = (dot / (sIn * sOut)).clamp(-1.0, 1.0);
                final deflectionAngleDeg =
                    math.acos(cosTheta) * (180.0 / math.pi);

                // Compare with previous adjacent candidate angle to confirm local peak curvature
                final pA0 = _trail[idxK - 3].position;
                final pK0 = _trail[idxK - 1].position;
                final pB0 = _trail[idxK + 1].position;
                final vIn0 = Offset(pK0.dx - pA0.dx, pK0.dy - pA0.dy);
                final vOut0 = Offset(pB0.dx - pK0.dx, pB0.dy - pK0.dy);
                final sIn0 = vIn0.distance;
                final sOut0 = vOut0.distance;
                double anglePrev = 0.0;
                if (sIn0 >= 3.5 && sOut0 >= 3.5) {
                  final dot0 = vIn0.dx * vOut0.dx + vIn0.dy * vOut0.dy;
                  final cosTheta0 = (dot0 / (sIn0 * sOut0)).clamp(-1.0, 1.0);
                  anglePrev = math.acos(cosTheta0) * (180.0 / math.pi);
                }

                // Mark real-time as soon as deflection angle >= 30° and reaches local peak
                if (deflectionAngleDeg >= 30.0 &&
                    deflectionAngleDeg >= anglePrev) {
                  final hitNum = _recordedHits.length + 1;
                  final hitPos = pK; // Exact corner vertex position

                  final newHit = ThudHit(
                    number: hitNum,
                    cameraPosition: hitPos,
                    deflectionDegrees: deflectionAngleDeg,
                    timestamp: now,
                  );

                  _recordedHits.add(newHit);
                  _activeSplashes.add(
                    ActiveSplash(
                      hitNumber: hitNum,
                      cameraPosition: hitPos,
                      deflectionDegrees: deflectionAngleDeg,
                    ),
                  );

                  _cooldownFrames = 10; // Debounce ~160ms
                  debugPrint(
                    '[Thud] REALTIME DEFLECTION VERTEX #$hitNum detected at (${pK.dx.toInt()}, ${pK.dy.toInt()}); '
                    'Deflection angle=${deflectionAngleDeg.toStringAsFixed(1)}°',
                  );
                }
              }
            }
          } else {
            // Decay trail smoothly when ball is lost or outside boundary
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
            'hits': _recordedHits
                .map(
                  (h) => {
                    'number': h.number,
                    'x': h.cameraPosition.dx,
                    'y': h.cameraPosition.dy,
                    'deflectionDegrees': h.deflectionDegrees,
                  },
                )
                .toList(),
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
      debugPrint('Thud frame processing error: $e');
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

  Future<void> _navigateBack() async {
    if (_capture.busy) return;
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _clearHits() {
    if (_capture.busy) return;
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
    _capture.removeListener(_captureChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasCamera = _controller != null && _controller!.value.isInitialized;
    final isTracking = _lastDetection != null && _lastDetection!.detected;

    return PopScope(
      canPop: !_capture.busy,
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
                  arucoCorners: _arucoBoundary,
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
                      // Hit & FPS Readout Box with ArUco Scan Icon
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _arucoBoundary != null
                                ? const Color(0xFF00FF66)
                                : Colors.white12,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: _arucoBoundary != null
                                  ? 'ArUco boundary locked. Tap to unlock.'
                                  : 'Scan for ArUco boundary (4 markers)',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 30,
                                minHeight: 30,
                              ),
                              icon: Icon(
                                _arucoBoundary != null
                                    ? Icons.crop_free
                                    : Icons.qr_code_scanner,
                                color: _arucoBoundary != null
                                    ? const Color(0xFF00FF66)
                                    : Colors.white70,
                                size: 20,
                              ),
                              onPressed: _onScanArucoPressed,
                            ),
                            const SizedBox(width: 6),
                            Column(
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

            // 4. 10-Second Frame Capture Floating Button
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
