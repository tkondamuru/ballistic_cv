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
import '../widgets/zoom_button.dart';

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
  double _minZoom = 1, _maxZoom = 1, _zoom = 1;
  bool _zoomBusy = false;
  SharedPreferences? _zoomPreferences;
  bool _isProcessing = false;
  DetectionResult? _lastDetection;

  // Interactive Boundary Quad State
  List<Offset>? _arucoBoundary;
  bool _isBoundaryLocked = false;

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
      'boundary': _arucoBoundary?.map((pt) => {'x': pt.dx, 'y': pt.dy}).toList(),
      'isBoundaryLocked': _isBoundaryLocked,
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
        _minZoom = await controller.getMinZoomLevel();
        _maxZoom = await controller.getMaxZoomLevel();
        _zoomPreferences = await SharedPreferences.getInstance();
        _zoom = (_zoomPreferences!.getDouble('play_zoom') ?? 1.0).clamp(
          _minZoom,
          _maxZoom,
        );
        await controller.setZoomLevel(_zoom);
      } catch (e) {
        _minZoom = _maxZoom = _zoom = 1;
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

  Future<void> _stepZoom(int direction) async {
    final controller = _controller;
    if (_zoomBusy || controller == null) return;
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

  double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final ap = p - a;
    final lengthSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lengthSq == 0) return ap.distance;
    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / lengthSq).clamp(0.0, 1.0);
    final projection = a + ab * t;
    return (p - projection).distance;
  }

  double _distanceToQuadEdge(Offset p, List<Offset> quad) {
    if (quad.length != 4) return 0.0;
    double minDistance = double.infinity;
    for (int i = 0; i < 4; i++) {
      final a = quad[i];
      final b = quad[(i + 1) % 4];
      final d = _distanceToSegment(p, a, b);
      if (d < minDistance) {
        minDistance = d;
      }
    }
    return minDistance;
  }

  bool _isNearOrOutsideWall(Offset p, List<Offset> quad, double thresholdPx) {
    if (quad.length != 4) return false;
    final isInside = _isPointInsideQuad(p, quad);
    if (!isInside) return true; // Ball went outside boundary line (in/past wall)
    final edgeDist = _distanceToQuadEdge(p, quad);
    return edgeDist <= thresholdPx;
  }

  void _onToggleBoundaryPressed() {
    if (_capture.busy) return;
    setState(() {
      if (_isBoundaryLocked) {
        _isBoundaryLocked = false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Boundary unlocked. Drag corner handles to align.'),
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        _isBoundaryLocked = true;
        if (_arucoBoundary == null || _arucoBoundary!.length != 4) {
          final w = _lastDetection?.frameWidth.toDouble() ?? 480.0;
          final h = _lastDetection?.frameHeight.toDouble() ?? 360.0;
          _arucoBoundary = [
            Offset(w * 0.15, h * 0.15),
            Offset(w * 0.85, h * 0.15),
            Offset(w * 0.85, h * 0.85),
            Offset(w * 0.15, h * 0.85),
          ];
        }
        // Clear all previous hit points when boundary is locked
        _recordedHits.clear();
        _activeSplashes.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Boundary locked. Hits inside quad will be tracked.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    });
  }

  void _processCameraFrame(CameraImage image) {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final imgW = image.width.toDouble();
      final imgH = image.height.toDouble();
      final currentQuad = _arucoBoundary ?? [
        Offset(imgW * 0.15, imgH * 0.15),
        Offset(imgW * 0.85, imgH * 0.15),
        Offset(imgW * 0.85, imgH * 0.85),
        Offset(imgW * 0.15, imgH * 0.85),
      ];
      final bool inOrNearBoard = _trail.isNotEmpty &&
          _isNearOrOutsideWall(_trail.last.position, currentQuad, 40.0);
      final double circularityThreshold = inOrNearBoard ? 0.0 : 0.35;

      final detection = NativeTracker.instance.detectFromCameraImage(
        image,
        hMin: widget.hsvProfile.hMin,
        hMax: widget.hsvProfile.hMax,
        sMin: widget.hsvProfile.sMin,
        sMax: widget.hsvProfile.sMax,
        vMin: widget.hsvProfile.vMin,
        vMax: widget.hsvProfile.vMax,
        enableMotion: false,
        minCircularity: circularityThreshold,
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

          final frameW = detection.frameWidth.toDouble();
          final frameH = detection.frameHeight.toDouble();
          final currentQuad = _arucoBoundary ?? [
            Offset(frameW * 0.15, frameH * 0.15),
            Offset(frameW * 0.85, frameH * 0.15),
            Offset(frameW * 0.85, frameH * 0.85),
            Offset(frameW * 0.15, frameH * 0.85),
          ];

          if (detection.detected) {
            final currentPos = Offset(detection.x, detection.y);
            final trackingPoint = TrackingPoint(
              position: currentPos,
              radius: detection.radius,
              isPredicted: detection.isPredicted,
              timestamp: now,
            );

            _trail.add(trackingPoint);
            if (_trail.length > 25) {
              _trail.removeAt(0);
            }

            // Wall Collision & Displacement Gated Impact Detection on _trail Directly
            if (_isBoundaryLocked && _cooldownFrames == 0) {
              final validTrail =
                  _trail.where((p) => !p.isPredicted).toList();

              if (validTrail.length >= 3) {
                final bool currentlyNearWall =
                    _isNearOrOutsideWall(currentPos, currentQuad, 20.0);

                if (!currentlyNearWall && validTrail.length >= 4) {
                  final pLast = validTrail.last.position;

                  int bestIdx = -1;
                  double minEdgeDist = double.infinity;

                  // Search full validTrail history for the point closest to the wall edge
                  for (int i = 0; i < validTrail.length - 1; i++) {
                    final pt = validTrail[i];
                    if (_isNearOrOutsideWall(pt.position, currentQuad, 20.0)) {
                      final d = _distanceToQuadEdge(pt.position, currentQuad);
                      if (d < minEdgeDist) {
                        minEdgeDist = d;
                        bestIdx = i;
                      }
                    }
                  }

                  if (bestIdx > 0) {
                    final pFirst =
                        validTrail[math.max(0, bestIdx - 3)].position;
                    final pPeak = validTrail[bestIdx].position;

                    final dFirst = _distanceToQuadEdge(pFirst, currentQuad);
                    final dPeak = _distanceToQuadEdge(pPeak, currentQuad);
                    final dLast = _distanceToQuadEdge(pLast, currentQuad);

                    final dApproach = dFirst - dPeak;
                    final dRebound = dLast - dPeak;

                    final vIn = Offset(pPeak.dx - pFirst.dx, pPeak.dy - pFirst.dy);
                    final vOut = Offset(pLast.dx - pPeak.dx, pLast.dy - pPeak.dy);

                    if ((dApproach >= 4.0 || vIn.distance >= 8.0) &&
                        (dRebound >= 3.0 || vOut.distance >= 5.0)) {
                      final hitPos = pPeak;
                      final hitNum = _recordedHits.length + 1;

                      _recordedHits.add(
                        ThudHit(
                          number: hitNum,
                          cameraPosition: hitPos,
                          deflectionDegrees: 45.0,
                          timestamp: now,
                        ),
                      );
                      _activeSplashes.add(
                        ActiveSplash(
                          hitNumber: hitNum,
                          cameraPosition: hitPos,
                          deflectionDegrees: 45.0,
                        ),
                      );

                      _cooldownFrames = 12;
                      debugPrint(
                        '[Thud] DIRECT TRAIL IMPACT #$hitNum at (${hitPos.dx.toInt()}, ${hitPos.dy.toInt()}); '
                        'Approach=${dApproach.toStringAsFixed(1)}px, Rebound=${dRebound.toStringAsFixed(1)}px',
                      );
                    }
                  }
                }
              }
            }
          } else {
            // Ball lost
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
            'boundary':
                _arucoBoundary?.map((pt) => {'x': pt.dx, 'y': pt.dy}).toList(),
            'isBoundaryLocked': _isBoundaryLocked,
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

            // 2. CustomPainter Thud Impact, Motion Layer & Interactive Drag Handles
            if (hasCamera && _lastDetection != null)
              LayoutBuilder(
                builder: (context, constraints) {
                  final screenSize = constraints.biggest;
                  final frameW = _lastDetection!.frameWidth > 0
                      ? _lastDetection!.frameWidth.toDouble()
                      : 480.0;
                  final frameH = _lastDetection!.frameHeight > 0
                      ? _lastDetection!.frameHeight.toDouble()
                      : 360.0;
                  final orientation =
                      _controller?.description.sensorOrientation ?? 90;

                  Offset toScreen(double camX, double camY) {
                    if (orientation == 90 && frameW > frameH) {
                      final screenX = (1.0 - (camY / frameH)) * screenSize.width;
                      final screenY = (camX / frameW) * screenSize.height;
                      return Offset(screenX, screenY);
                    } else {
                      final screenX = (camX / frameW) * screenSize.width;
                      final screenY = (camY / frameH) * screenSize.height;
                      return Offset(screenX, screenY);
                    }
                  }

                  Offset toCamera(Offset screen) {
                    if (orientation == 90 && frameW > frameH) {
                      final camX = (screen.dy / screenSize.height) * frameW;
                      final camY = (1.0 - (screen.dx / screenSize.width)) * frameH;
                      return Offset(camX.clamp(0.0, frameW), camY.clamp(0.0, frameH));
                    } else {
                      final camX = (screen.dx / screenSize.width) * frameW;
                      final camY = (screen.dy / screenSize.height) * frameH;
                      return Offset(camX.clamp(0.0, frameW), camY.clamp(0.0, frameH));
                    }
                  }

                  final currentBoundary = _arucoBoundary ?? [
                    Offset(frameW * 0.15, frameH * 0.15),
                    Offset(frameW * 0.85, frameH * 0.15),
                    Offset(frameW * 0.85, frameH * 0.85),
                    Offset(frameW * 0.15, frameH * 0.85),
                  ];

                  final labels = ['TL', 'TR', 'BR', 'BL'];

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(
                        painter: ThudPainter(
                          detection: _lastDetection,
                          trail: _trail,
                          recordedHits: _recordedHits,
                          activeSplashes: _activeSplashes,
                          arucoCorners: currentBoundary,
                          isBoundaryLocked: _isBoundaryLocked,
                          sensorOrientation: orientation,
                        ),
                      ),
                      if (!_isBoundaryLocked)
                        ...List.generate(4, (i) {
                          final screenPos = toScreen(
                            currentBoundary[i].dx,
                            currentBoundary[i].dy,
                          );
                          return Positioned(
                            left: screenPos.dx - 22,
                            top: screenPos.dy - 22,
                            child: GestureDetector(
                              onPanUpdate: (details) {
                                final newScreen = screenPos + details.delta;
                                final newCam = toCamera(newScreen);
                                setState(() {
                                  _arucoBoundary ??= List<Offset>.from(currentBoundary);
                                  _arucoBoundary![i] = newCam;
                                });
                              },
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00FF66).withValues(alpha: 0.90),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.black, width: 2.5),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black54,
                                      blurRadius: 6,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    labels[i],
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                    ],
                  );
                },
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
                      // Hit & FPS Readout Box with Lock/Unlock Boundary Icon
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _isBoundaryLocked
                                ? const Color(0xFF00FF66)
                                : Colors.orangeAccent,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: _isBoundaryLocked
                                  ? 'Boundary locked. Tap to unlock and drag corner handles.'
                                  : 'Boundary unlocked (Editing pins). Tap to lock boundary.',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 30,
                                minHeight: 30,
                              ),
                              icon: Icon(
                                _isBoundaryLocked ? Icons.lock : Icons.lock_open,
                                color: _isBoundaryLocked
                                    ? const Color(0xFF00FF66)
                                    : Colors.orangeAccent,
                                size: 20,
                              ),
                              onPressed: _onToggleBoundaryPressed,
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

            // 4. Zoom Controls Floating Widget (Bottom-Left)
            Positioned(
              left: 16,
              bottom: 90,
              child: Container(
                key: const ValueKey('thudZoomControls'),
                width: 140,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
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
            ),

            // 5. 10-Second Frame Capture Floating Button
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
