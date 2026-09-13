import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../calibration/color_samples.dart';
import '../models/hsv_profile.dart';

class CalibratorScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const CalibratorScreen({super.key, required this.cameras});
  @override
  State<CalibratorScreen> createState() => _CalibratorScreenState();
}

class _CalibratorScreenState extends State<CalibratorScreen> {
  CameraController? _controller;
  CameraImage? _lastFrame;
  final _samples = <List<HsvPixel>>[];
  final _readings = <String>[];
  HsvProfile? _profile;
  ui.Image? _preview;
  bool _busy = false;
  bool _closed = false;
  String? _error;
  static const _instructions = [
    'Cover the small circle with a normally lit area of the ball.',
    'Move to a slightly shaded area. Keep the circle covered.',
    'Turn the ball slightly and sample another angle. Avoid glare.',
  ];

  @override
  void initState() {
    super.initState();
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
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420,
    );
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted || _closed) {
        await controller.dispose();
        return;
      }
      await controller.startImageStream((image) {
        if (!mounted || _closed) return;
        final first = _lastFrame == null;
        _lastFrame = image;
        if (first) setState(() {});
      });
      if (mounted) setState(() {});
    } catch (e, stack) {
      _report('Camera error', e, stack);
    }
  }

  void _report(String label, Object error, StackTrace stack) {
    debugPrint('$label: $error');
    final image = _lastFrame;
    if (image != null) {
      debugPrint(
        'Frame ${image.width}x${image.height}, ${image.format.group}, '
        '${image.planes.length} planes, strides=${image.planes.map((p) => p.bytesPerRow).toList()}',
      );
    }
    debugPrint(stack.toString());
    if (mounted) {
      setState(() {
        _error = '$label: $error';
        _busy = false;
      });
    }
  }

  Future<void> _sample() async {
    final frame = _lastFrame;
    if (frame == null || _busy || _samples.length >= 3) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final pixels = sampleCenter(frame);
      final individual = combineSamples([pixels]);
      final reading =
          'Sample ${_samples.length + 1}: H=${individual.hMed} '
          '(${individual.hMed * 2}°), S=${individual.sMed}, V=${individual.vMed}';
      debugPrint(
        '[Calibration] $reading; pixels=${pixels.length}; '
        'H range=${individual.hMin}..${individual.hMax} (OpenCV H 0..179, S/V 0..255)',
      );
      final candidate = [..._samples, pixels];
      final combined = combineSamples(candidate);
      _samples.add(pixels);
      _readings.add(reading);
      if (_samples.length == 3) {
        _profile = combined;
        debugPrint(
          '[Calibration] Combined H=${combined.hMin}..${combined.hMax}, '
          'S=${combined.sMin}..${combined.sMax}, V=${combined.vMin}..${combined.vMax}',
        );
        await _makePreview(frame, combined);
      }
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    } catch (e, stack) {
      _report('Sampling error', e, stack);
    }
  }

  Future<void> _makePreview(CameraImage frame, HsvProfile profile) async {
    final bytes = Uint8List(frame.width * frame.height * 4);
    for (int y = 0; y < frame.height; y++) {
      for (int x = 0; x < frame.width; x++) {
        final p = pixelHsv(frame, x, y);
        final color = HSVColor.fromAHSV(
          1,
          p.h * 2.0,
          p.s / 255,
          p.v / 255,
        ).toColor();
        final match = matchesProfile(p, profile);
        final i = (y * frame.width + x) * 4;
        bytes[i] = match ? 255 : (color.r * 90).round();
        bytes[i + 1] = match ? 0 : (color.g * 90).round();
        bytes[i + 2] = match ? 255 : (color.b * 90).round();
        bytes[i + 3] = 255;
      }
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: frame.width,
      height: frame.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    if (!mounted) {
      image.dispose();
      return;
    }
    _preview?.dispose();
    setState(() {
      _preview = image;
    });
  }

  void _reset() {
    _preview?.dispose();
    setState(() {
      _preview = null;
      _profile = null;
      _samples.clear();
      _readings.clear();
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_profile == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Release the camera before the tracker opens it.
      _closed = true;
      await _controller?.dispose();
      _controller = null;
      if (!mounted) return;
      Navigator.of(context).pop(_profile);
    } catch (e, stack) {
      _report('Save error', e, stack);
    }
  }

  @override
  void dispose() {
    _closed = true;
    _controller?.dispose();
    _preview?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _controller?.value.isInitialized ?? false;
    final reviewing = _samples.length == 3;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          reviewing
              ? 'Review color match'
              : 'Sample ball color (${_samples.length}/3)',
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                reviewing
                    ? 'Frozen preview: magenta pixels match. Check the ball and background before saving.'
                    : _instructions[_samples.length],
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (!ready) {
                    return const Center(child: Text('Waiting for camera…'));
                  }
                  // Contain the entire portrait preview; sample and target share its center and scale.
                  final aspect = 1 / _controller!.value.aspectRatio;
                  final width = math.min(
                    constraints.maxWidth,
                    constraints.maxHeight * aspect,
                  );
                  final height = width / aspect;
                  final diameter =
                      math.min(width, height) * sampleRadiusFraction * 2;
                  return Center(
                    child: SizedBox(
                      width: width,
                      height: height,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_preview != null)
                            RotatedBox(
                              quarterTurns: _preview!.width > _preview!.height
                                  ? (_controller!
                                                .description
                                                .sensorOrientation ~/
                                            90) %
                                        4
                                  : 0,
                              child: RawImage(
                                image: _preview,
                                fit: BoxFit.fill,
                              ),
                            )
                          else
                            CameraPreview(_controller!),
                          if (!reviewing)
                            Center(
                              child: Container(
                                width: diameter,
                                height: diameter,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.greenAccent,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final reading in _readings)
                    Text(reading, style: const TextStyle(fontSize: 12)),
                  if (_error != null)
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  const SizedBox(height: 8),
                  if (reviewing)
                    ElevatedButton(
                      onPressed: _busy || _preview == null ? null : _save,
                      child: const Text('Save object'),
                    )
                  else
                    ElevatedButton(
                      onPressed: _busy || _lastFrame == null ? null : _sample,
                      child: Text(
                        _busy
                            ? 'Sampling…'
                            : 'Take sample ${_samples.length + 1}',
                      ),
                    ),
                  if (_samples.isNotEmpty)
                    TextButton(
                      onPressed: _busy ? null : _reset,
                      child: const Text('Retake all samples'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
