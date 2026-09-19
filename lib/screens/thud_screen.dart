import 'dart:async';
import 'dart:io';
import '../detection/impact_detector.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../capture/frame_capture.dart';
import '../capture/trajectory_recorder.dart';
import '../models/hsv_profile.dart';
import '../models/board_alignment.dart';
import '../models/thud_hit.dart';
import '../native/native_cv.dart';
import '../geometry/homography.dart';
import '../services/thud_relay_service.dart';
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
  bool _restoreBoard = true;
  bool _savingBoard = false;
  bool _ignoreBelowBoard = false;

  // Trajectory & Detection State
  final List<TrackingPoint> _trail = [];
  final List<ThudHit> _recordedHits = [];
  final List<ActiveSplash> _activeSplashes = [];

  final ImpactDetector _impactDetector = ImpactDetector();

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
      'boundary': _arucoBoundary
          ?.map((pt) => {'x': pt.dx, 'y': pt.dy})
          .toList(),
      'ignoreBelowBoard': _ignoreBelowBoard,
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
        _ignoreBelowBoard =
            _zoomPreferences!.getBool('thud_ignore_below_board') ?? false;
        final relayUrl =
            _zoomPreferences!.getString('thud_relay_url') ?? 'wss://mcp.agility-maint.net';
        final relayRoom =
            _zoomPreferences!.getString('thud_relay_room') ?? 'thud-room-1';
        if (!ThudRelayService.instance.isConnected) {
          unawaited(
            ThudRelayService.instance.connect(relayUrl, room: relayRoom).then((_) {
              if (mounted) setState(() {});
            }),
          );
        }
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

      _restoreBoard = true;
      await controller.startImageStream(_processCameraFrame);
    } catch (e) {
      debugPrint('Error initializing camera controller: $e');
    }
  }

  Future<void> _stepZoom(int direction) async {
    final controller = _controller;
    if (_zoomBusy || _savingBoard || _capture.busy || controller == null) {
      return;
    }
    final value = ((_zoom * 10).round() + direction) / 10;
    final next = value.clamp(_minZoom, _maxZoom);
    setState(() => _zoomBusy = true);
    try {
      await controller.setZoomLevel(next);
      if (mounted) {
        setState(() {
          _zoom = next;
          // A zoom change invalidates the board's camera-space coordinates.
          _isBoundaryLocked = false;
          _restoreBoard = true;
          _impactDetector.reset();
          _trail.clear();
          _recordedHits.clear();
          _activeSplashes.clear();
        });
      }
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

  Future<void> _onToggleBoundaryPressed() async {
    if (_capture.busy || _savingBoard || _lastDetection == null) return;
    _impactDetector.reset();
    _trail.clear();
    if (_isBoundaryLocked) {
      setState(() => _isBoundaryLocked = false);
      return;
    }
    final width = _lastDetection!.frameWidth.toDouble();
    final height = _lastDetection!.frameHeight.toDouble();
    final points = List<Offset>.from(
      _arucoBoundary ?? BoardAlignment.initial(width, height),
    );
    _savingBoard = true;
    try {
      final prefs = _zoomPreferences ?? await SharedPreferences.getInstance();
      await BoardAlignment.save(
        prefs,
        _controller!.description.name,
        _zoom,
        width,
        height,
        points,
      );
      if (!mounted) return;
      setState(() {
        _arucoBoundary = points;
        _isBoundaryLocked = true;
        _recordedHits.clear();
        _activeSplashes.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Board locked and saved for this zoom.'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      _savingBoard = false;
    }
  }

  Future<void> _showRelaySettingsDialog() async {
    final prefs = _zoomPreferences ?? await SharedPreferences.getInstance();
    final urlController = TextEditingController(
      text: prefs.getString('thud_relay_url') ?? 'wss://mcp.agility-maint.net',
    );
    final roomController = TextEditingController(
      text: prefs.getString('thud_relay_room') ?? 'thud-room-1',
    );

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isConnected = ThudRelayService.instance.isConnected;
          return AlertDialog(
            backgroundColor: const Color(0xFF141824),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFF00FF66), width: 1.5),
            ),
            title: Row(
              children: [
                Icon(
                  isConnected ? Icons.cloud_done : Icons.cloud_off,
                  color: isConnected
                      ? const Color(0xFF00FF66)
                      : Colors.orangeAccent,
                ),
                const SizedBox(width: 10),
                const Text(
                  'Cloud Relay Settings',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: urlController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'WebSocket Relay URL',
                    labelStyle: TextStyle(color: Colors.white70),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF00FF66)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: roomController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Room ID',
                    labelStyle: TextStyle(color: Colors.white70),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF00FF66)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () {
                    urlController.text = 'wss://mcp.agility-maint.net';
                    roomController.text = 'thud-room-1';
                  },
                  icon: const Icon(
                    Icons.refresh,
                    size: 16,
                    color: Color(0xFF00FF66),
                  ),
                  label: const Text(
                    'Reset to Default Preset',
                    style: TextStyle(color: Color(0xFF00FF66), fontSize: 12),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white60),
                ),
              ),
              if (isConnected)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                  ),
                  onPressed: () async {
                    await ThudRelayService.instance.disconnect();
                    if (mounted) setState(() {});
                    setDialogState(() {});
                  },
                  child: const Text(
                    'Disconnect',
                    style: TextStyle(color: Colors.white),
                  ),
                )
              else
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00FF66),
                  ),
                  onPressed: () async {
                    final u = urlController.text.trim();
                    final r = roomController.text.trim();
                    await prefs.setString('thud_relay_url', u);
                    await prefs.setString('thud_relay_room', r);
                    await ThudRelayService.instance.connect(u, room: r);
                    if (mounted) setState(() {});
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                  child: const Text(
                    'Connect',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }

  void _processCameraFrame(CameraImage image) {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      if (_restoreBoard) {
        final prefs = _zoomPreferences;
        final restored = prefs == null || _controller == null
            ? null
            : BoardAlignment.load(
                prefs,
                _controller!.description.name,
                _zoom,
                image.width.toDouble(),
                image.height.toDouble(),
              );
        _arucoBoundary =
            restored ??
            _arucoBoundary ??
            BoardAlignment.initial(
              image.width.toDouble(),
              image.height.toDouble(),
            );
        _isBoundaryLocked = restored != null;
        _restoreBoard = false;
        _impactDetector.reset();
      }
      final double circularityThreshold = _isBoundaryLocked ? 0.08 : 0.35;

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
        cutoff: _ignoreBelowBoard && _isBoundaryLocked
            ? BoardAlignment.cutoff(_arucoBoundary)
            : null,
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
          final currentQuad =
              _arucoBoundary ?? BoardAlignment.initial(frameW, frameH);

          final impact = _impactDetector.add(
            position: Offset(detection.x, detection.y),
            timestamp: now,
            measured:
                _isBoundaryLocked &&
                detection.detected &&
                !detection.isPredicted,
            board: currentQuad,
          );
          if (TrajectoryRecorder.instance.recording) {
            TrajectoryRecorder.instance.add({
              'timestampUs': now.microsecondsSinceEpoch,
              'objectId': widget.objectId,
              'objectName': widget.objectName,
              'width': image.width,
              'height': image.height,
              'zoom': _zoom,
              'ignoreBelowBoard': _ignoreBelowBoard,
              'boardLocked': _isBoundaryLocked,
              'board': currentQuad.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
              'status': !detection.detected
                  ? 'searching'
                  : detection.isPredicted
                  ? 'predicted'
                  : 'measured',
              'insideBoard': detection.detected
                  ? ImpactDetector.insideBoard(
                      Offset(detection.x, detection.y),
                      currentQuad,
                    )
                  : null,
              'ball': detection.detected
                  ? {
                      'x': detection.x,
                      'y': detection.y,
                      'vx': detection.vx,
                      'vy': detection.vy,
                      'radius': detection.radius,
                    }
                  : null,
              'hit': impact == null
                  ? null
                  : {
                      'x': impact.position.dx,
                      'y': impact.position.dy,
                      'angleDegrees': impact.angleDegrees,
                      'timestampUs': impact.timestamp.microsecondsSinceEpoch,
                    },
            });
          }
          if (impact != null) {
            final hitNum = _recordedHits.length + 1;
            _recordedHits.add(
              ThudHit(
                number: hitNum,
                cameraPosition: impact.position,
                deflectionDegrees: impact.angleDegrees,
                timestamp: impact.timestamp,
              ),
            );
            _activeSplashes.add(
              ActiveSplash(
                hitNumber: hitNum,
                cameraPosition: impact.position,
                deflectionDegrees: impact.angleDegrees,
              ),
            );

            // Compute normalized (u, v) relative to 4 corner pins and broadcast over Cloudflare Relay
            final normalized = Homography.normalize(impact.position, currentQuad);
            ThudRelayService.instance.sendHit(
              normalizedPos: normalized,
              deflectionDegrees: impact.angleDegrees,
              hitNumber: hitNum,
            );

            debugPrint(
              '[Thud] IMPACT CANDIDATE #$hitNum at '
              '(${impact.position.dx.toStringAsFixed(1)}, ${impact.position.dy.toStringAsFixed(1)}); '
              'normalized=(${normalized.dx.toStringAsFixed(3)}, ${normalized.dy.toStringAsFixed(3)}); '
              'angle=${impact.angleDegrees.toStringAsFixed(1)}°, '
              'confirmationDelay=${now.difference(impact.timestamp).inMilliseconds}ms',
            );
          }

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
          } else {
            // Ball lost
            if (_trail.isNotEmpty) {
              _trail.removeAt(0);
            }
          }
        });
      }

      if (Platform.isIOS && image.format.group == ImageFormatGroup.bgra8888) {
        // Trace all processed samples while scanning, not only written PNGs.
        final board = _arucoBoundary;
        final sample = _capture.capturing
            ? _capture.traceSample({
                'timestampUs': now.microsecondsSinceEpoch,
                'width': image.width,
                'height': image.height,
                'orientation': _controller?.description.sensorOrientation ?? 90,
                'board': board?.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
                'boardLocked': _isBoundaryLocked,
                'ignoreBelowBoard': _ignoreBelowBoard,
                'ball': detection.detected
                    ? {
                        'x': detection.x,
                        'y': detection.y,
                        'vx': detection.vx,
                        'vy': detection.vy,
                        'radius': detection.radius,
                      }
                    : null,
                'status': !detection.detected
                    ? 'searching'
                    : detection.isPredicted
                    ? 'predicted'
                    : 'measured',
                'region': !detection.detected || board == null
                    ? 'unknown'
                    : ImpactDetector.insideBoard(
                        Offset(detection.x, detection.y),
                        board,
                      )
                    ? 'inside'
                    : 'outside',
                'hitCount': _recordedHits.length,
                'lastHit': _recordedHits.isEmpty
                    ? null
                    : {
                        'number': _recordedHits.last.number,
                        'x': _recordedHits.last.cameraPosition.dx,
                        'y': _recordedHits.last.cameraPosition.dy,
                        'angleDegrees': _recordedHits.last.deflectionDegrees,
                        'timestampUs':
                            _recordedHits.last.timestamp.microsecondsSinceEpoch,
                      },
              })
            : null;
        _capture.add(
          () => {
            'sample': sample,
            'timestampUs': now.microsecondsSinceEpoch,
            'bytes': image.planes.first.bytes,
            'width': image.width,
            'height': image.height,
            'stride': image.planes.first.bytesPerRow,
            'orientation': _controller?.description.sensorOrientation ?? 90,
            'boundary': _arucoBoundary
                ?.map((pt) => {'x': pt.dx, 'y': pt.dy})
                .toList(),
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
    _impactDetector.reset();
    setState(() {
      _recordedHits.clear();
      _activeSplashes.clear();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      _impactDetector.reset();
      _trail.clear();
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
          leading: widget.embedded
              ? null
              : BackButton(onPressed: _navigateBack),
          actions: [
            PopupMenuButton<bool>(
              tooltip: 'Tracking options',
              onSelected: (value) async {
                setState(() => _ignoreBelowBoard = value);
                NativeTracker.instance.resetKalmanTracker();
                _impactDetector.reset();
                _trail.clear();
                final prefs =
                    _zoomPreferences ?? await SharedPreferences.getInstance();
                await prefs.setBool('thud_ignore_below_board', value);
              },
              itemBuilder: (_) => [
                CheckedPopupMenuItem<bool>(
                  value: !_ignoreBelowBoard,
                  checked: _ignoreBelowBoard,
                  child: const Text('Ignore below board (when locked)'),
                ),
              ],
            ),
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
                      final screenX =
                          (1.0 - (camY / frameH)) * screenSize.width;
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
                      final camY =
                          (1.0 - (screen.dx / screenSize.width)) * frameH;
                      return Offset(
                        camX.clamp(0.0, frameW),
                        camY.clamp(0.0, frameH),
                      );
                    } else {
                      final camX = (screen.dx / screenSize.width) * frameW;
                      final camY = (screen.dy / screenSize.height) * frameH;
                      return Offset(
                        camX.clamp(0.0, frameW),
                        camY.clamp(0.0, frameH),
                      );
                    }
                  }

                  final currentBoundary =
                      _arucoBoundary ?? BoardAlignment.initial(frameW, frameH);

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
                                if (_savingBoard) return;
                                final newScreen = screenPos + details.delta;
                                final newCam = toCamera(newScreen);
                                setState(() {
                                  _arucoBoundary ??= List<Offset>.from(
                                    currentBoundary,
                                  );
                                  _arucoBoundary![i] = newCam;
                                });
                              },
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF00FF66,
                                  ).withValues(alpha: 0.90),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.black,
                                    width: 2.5,
                                  ),
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
                                _isBoundaryLocked
                                    ? Icons.lock
                                    : Icons.lock_open,
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

            // 4.5. Cloud Relay Socket Toggle Button (Floating right side above Record)
            Positioned(
              right: 18,
              bottom: 195,
              child: Column(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.85),
                      border: Border.all(
                        color: ThudRelayService.instance.isConnected
                            ? const Color(0xFF00FF66)
                            : Colors.white24,
                        width: 2,
                      ),
                      boxShadow: [
                        if (ThudRelayService.instance.isConnected)
                          const BoxShadow(
                            color: Color(0xFF00FF66),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                      ],
                    ),
                    child: IconButton(
                      tooltip: ThudRelayService.instance.isConnected
                          ? 'Cloud Relay Connected (${ThudRelayService.instance.roomId}). Tap to configure.'
                          : 'Cloud Relay Disconnected. Tap to connect to mcp.agility-maint.net',
                      icon: Icon(
                        ThudRelayService.instance.isConnected
                            ? Icons.cloud_done
                            : Icons.cloud_off,
                        color: ThudRelayService.instance.isConnected
                            ? const Color(0xFF00FF66)
                            : Colors.white54,
                        size: 24,
                      ),
                      onPressed: _showRelaySettingsDialog,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ThudRelayService.instance.isConnected
                        ? 'Relay ON'
                        : 'Relay OFF',
                    style: TextStyle(
                      color: ThudRelayService.instance.isConnected
                          ? const Color(0xFF00FF66)
                          : Colors.white60,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      backgroundColor: Colors.black87,
                    ),
                  ),
                ],
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
