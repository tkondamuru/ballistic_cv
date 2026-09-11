import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'native/native_cv.dart';
import 'widgets/tracking_painter.dart';

List<CameraDescription> _cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  try {
    _cameras = await availableCameras();
  } catch (e) {
    debugPrint('Error getting cameras: $e');
  }

  runApp(const BallisticCvApp());
}

class BallisticCvApp extends StatelessWidget {
  const BallisticCvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BallisticCV',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        primaryColor: const Color(0xFF00FF66),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FF66),
          secondary: Colors.cyanAccent,
        ),
      ),
      home: const TrackerHomeScreen(),
    );
  }
}

class TrackerHomeScreen extends StatefulWidget {
  const TrackerHomeScreen({super.key});

  @override
  State<TrackerHomeScreen> createState() => _TrackerHomeScreenState();
}

class _TrackerHomeScreenState extends State<TrackerHomeScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isProcessing = false;
  DetectionResult? _lastDetection;
  final List<TrackingPoint> _trail = [];

  // Frame timing & FPS
  int _frameCount = 0;
  double _fps = 0.0;
  DateTime _lastFpsCheck = DateTime.now();

  // Calibrated HSV bounds for Green Ball
  final int _hMin = 35;
  final int _hMax = 85;
  final int _sMin = 70;
  final int _sMax = 255;
  final int _vMin = 60;
  final int _vMax = 255;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initNativeTracker();
    _initCamera();
  }

  void _initNativeTracker() {
    try {
      final version = NativeTracker.instance.getVersion();
      debugPrint('Native tracker initialized: v$version (OpenCV 4.13.0)');
    } catch (e) {
      debugPrint('Native tracker init error: $e');
    }
  }

  Future<void> _initCamera() async {
    if (_cameras.isEmpty) {
      debugPrint('No cameras available.');
      return;
    }

    // Select primary back camera
    final camera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );

    final controller = CameraController(
      camera,
      ResolutionPreset.low, // 360p / 480p for 60 FPS throughput
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

      // Start zero-copy camera frame processing stream
      await controller.startImageStream(_processCameraFrame);
    } catch (e) {
      debugPrint('Error initializing camera controller: $e');
    }
  }

  void _processCameraFrame(CameraImage image) {
    // Drop frame if previous frame is still being processed
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final detection = NativeTracker.instance.detectFromCameraImage(
        image,
        hMin: _hMin,
        hMax: _hMax,
        sMin: _sMin,
        sMax: _sMax,
        vMin: _vMin,
        vMax: _vMax,
      );

      // FPS tracking
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
            _trail.add(TrackingPoint(
              position: Offset(detection.x, detection.y),
              radius: detection.radius,
              timestamp: now,
            ));
            if (_trail.length > 12) {
              _trail.removeAt(0);
            }
          } else {
            // Gradually decay trail when ball is momentarily occluded
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }

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
    NativeTracker.instance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasCamera = _controller != null && _controller!.value.isInitialized;

    return Scaffold(
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
                    'Initializing Camera Stream...',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ],
              ),
            ),

          // 2. CustomPainter Real-Time Tracking HUD Layer
          if (hasCamera && _lastDetection != null)
            CustomPaint(
              painter: TrackingPainter(
                detection: _lastDetection,
                trail: _trail,
                sensorOrientation: _controller!.description.sensorOrientation,
              ),
            ),

          // 3. Top Cyberpunk HUD Bar with dynamic Red/Green tracking border
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Builder(
                builder: (context) {
                  final isTracking = _lastDetection?.detected ?? false;
                  final statusColor = isTracking ? const Color(0xFF00FF66) : Colors.redAccent;

                  return Container(
                    margin: const EdgeInsets.only(top: 6, left: 16, right: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: statusColor,
                        width: 2.0,
                      ),
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
                                    : (_fps >= 30 ? Colors.orangeAccent : Colors.redAccent),
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              'Target: 60 FPS',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
                            ),
                          ],
                        ),

                        // Engine Info & Status Text
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'BallisticCV',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isTracking ? '● TRACKING' : '○ SEARCHING',
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

          // 4. Bottom Coordinate Readout with Tracking / Searching Icon
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Builder(
                builder: (context) {
                  final isTracking = _lastDetection != null && _lastDetection!.detected;
                  final statusColor = isTracking ? const Color(0xFF00FF66) : Colors.redAccent;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isTracking ? statusColor.withValues(alpha: 0.5) : Colors.white12,
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        // Status Icon: Crosshair when tracking, Radar when searching
                        Icon(
                          isTracking ? Icons.gps_fixed : Icons.radar,
                          color: statusColor,
                          size: 20,
                        ),
                        Text(
                          'X: ${isTracking ? _lastDetection!.x.toStringAsFixed(1) : "--"}',
                          style: const TextStyle(color: Colors.white70, fontSize: 13, fontFamily: 'monospace'),
                        ),
                        Text(
                          'Y: ${isTracking ? _lastDetection!.y.toStringAsFixed(1) : "--"}',
                          style: const TextStyle(color: Colors.white70, fontSize: 13, fontFamily: 'monospace'),
                        ),
                        Text(
                          'Radius: ${isTracking ? _lastDetection!.radius.toStringAsFixed(1) : "--"}px',
                          style: const TextStyle(color: Colors.white70, fontSize: 13, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
