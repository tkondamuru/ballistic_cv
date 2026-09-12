import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../models/hsv_profile.dart';
import '../native/native_cv.dart';
import '../widgets/camera_reticle.dart';
import 'tracker_screen.dart';

class CalibratorScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CalibratorScreen({super.key, required this.cameras});

  @override
  State<CalibratorScreen> createState() => _CalibratorScreenState();
}

class _CalibratorScreenState extends State<CalibratorScreen> {
  CameraController? _controller;
  bool _isProcessing = false;
  bool _isSampling = false;
  CameraImage? _lastFrame;

  HsvProfile _currentProfile = HsvProfile.defaultGreen;
  Color _sampledColor = const Color(0xFF00FF66);
  String _statusText = 'Hold ball inside reticle & tap sample';

  @override
  void initState() {
    super.initState();
    _loadSavedProfile();
    _initCamera();
  }

  Future<void> _loadSavedProfile() async {
    final saved = await HsvProfile.load();
    if (saved != null && mounted) {
      setState(() {
        _currentProfile = saved;
      });
    }
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
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await controller.initialize();
      if (!mounted) return;

      setState(() {
        _controller = controller;
      });

      await controller.startImageStream((image) {
        if (_isProcessing) return;
        _isProcessing = true;
        _lastFrame = image;
        _isProcessing = false;
      });
    } catch (e) {
      debugPrint('Camera init error in Calibrator: $e');
    }
  }

  void _sampleAndLockColor() {
    if (_lastFrame == null || _isSampling) return;

    setState(() {
      _isSampling = true;
      _statusText = 'Sampling median HSV color...';
    });

    try {
      final image = _lastFrame!;
      final reticleX = image.width ~/ 2;
      final reticleY = image.height ~/ 2;
      final reticleRadius = image.width ~/ 6;

      final res = NativeTracker.instance.sampleHsvColor(
        image,
        reticleX: reticleX,
        reticleY: reticleY,
        reticleRadius: reticleRadius,
      );

      // Convert sampled HSV to Flutter Color for preview
      final hsvColor = HSVColor.fromAHSV(
        1.0,
        (res.hMed * 2.0).clamp(0.0, 360.0), // OpenCV H (0..180) to HSVColor H (0..360)
        (res.sMed / 255.0).clamp(0.0, 1.0),
        (res.vMed / 255.0).clamp(0.0, 1.0),
      );

      final newProfile = HsvProfile(
        hMed: res.hMed,
        sMed: res.sMed,
        vMed: res.vMed,
        hMin: res.hMin,
        hMax: res.hMax,
        sMin: res.sMin,
        sMax: 255,
        vMin: res.vMin,
        vMax: 255,
      );

      newProfile.save();

      setState(() {
        _currentProfile = newProfile;
        _sampledColor = hsvColor.toColor();
        _statusText = 'Color locked! Dynamic H:[${res.hMin}..${res.hMax}], S:[${res.sMin}..255], V:[${res.vMin}..255]';
        _isSampling = false;
      });

      // Brief delay to display swatch, then transition to Tracker Screen
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => TrackerScreen(
              cameras: widget.cameras,
              hsvProfile: newProfile,
            ),
          ),
        );
      });
    } catch (e) {
      setState(() {
        _statusText = 'Sampling error: $e';
        _isSampling = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasCamera = _controller != null && _controller!.value.isInitialized;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Live Camera Feed
          if (hasCamera)
            CameraPreview(_controller!)
          else
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF00FF66)),
            ),

          // 2. Centered Target Reticle
          const Center(
            child: CameraReticle(
              size: 140,
              label: 'Position Ball Inside Reticle',
            ),
          ),

          // 3. Top Cyberpunk Header Bar
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.only(top: 12, left: 16, right: 16),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF00FF66), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00FF66).withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Color Swatch Circle
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _sampledColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.0),
                        boxShadow: [
                          BoxShadow(
                            color: _sampledColor.withValues(alpha: 0.6),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'SCREEN 1: COLOR PIPETTE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _statusText,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 4. Bottom Action Area
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.only(bottom: 24, left: 20, right: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Dynamic Bounds Chip
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Text(
                        'Active Bounds: H:[${_currentProfile.hMin}..${_currentProfile.hMax}] '
                        'S:[${_currentProfile.sMin}..255] V:[${_currentProfile.vMin}..255]',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Primary Button: Sample & Lock Ball Color
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: _isSampling ? null : _sampleAndLockColor,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00FF66),
                          foregroundColor: Colors.black,
                          elevation: 8,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          shadowColor: const Color(0xFF00FF66).withValues(alpha: 0.5),
                        ),
                        icon: _isSampling
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.black,
                                ),
                              )
                            : const Icon(Icons.colorize, size: 24),
                        label: Text(
                          _isSampling ? 'SAMPLING...' : 'SAMPLE & LOCK BALL COLOR',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
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
