import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../capture/frame_capture.dart';
import '../native/native_cv.dart';
import '../widgets/tracking_painter.dart';

class FrameReviewScreen extends StatefulWidget {
  final FrameSet capture;
  final Future<ui.Image> Function(String)? loadImage;
  const FrameReviewScreen({super.key, required this.capture, this.loadImage});
  @override
  State<FrameReviewScreen> createState() => _FrameReviewScreenState();
}

class _FrameReviewScreenState extends State<FrameReviewScreen> {
  final _pages = PageController();
  Timer? _scrub;
  int _selected = 0, _wanted = 0, _loaded = -1;
  ui.Image? _image;
  bool _loading = false, _overlay = true, _mask = false, _loadedMask = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _request(0);
  }

  void _request(int index) {
    _wanted = index;
    if (_loaded == index && _loadedMask == _mask && !_loading) return;
    if (!_loading) unawaited(_load());
  }

  Future<void> _load() async {
    _loading = true;
    while (mounted) {
      final index = _wanted, mask = _mask;
      ui.Image? next;
      try {
        if (widget.loadImage != null) {
          next = await widget.loadImage!(widget.capture.path(index));
        } else {
          final bytes = await File(widget.capture.path(index)).readAsBytes();
          final codec = await ui.instantiateImageCodec(bytes);
          next = (await codec.getNextFrame()).image;
          codec.dispose();
        }
        if (mask) {
          final original = next;
          final pixels = (await original.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
          final hsv = List<int>.from(widget.capture.data['hsv'] as List);
          for (int i = 0; i < pixels.length; i += 4) {
            final color = HSVColor.fromColor(
              Color.fromARGB(255, pixels[i], pixels[i + 1], pixels[i + 2]),
            );
            final h = (color.hue / 2).round() % 180;
            final s = (color.saturation * 255).round(),
                v = (color.value * 255).round();
            final match =
                (hsv[3] <= hsv[4]
                    ? h >= hsv[3] && h <= hsv[4]
                    : h >= hsv[3] || h <= hsv[4]) &&
                s >= hsv[5] &&
                s <= hsv[6] &&
                v >= hsv[7] &&
                v <= hsv[8];
            pixels[i] = pixels[i + 1] = pixels[i + 2] = match ? 255 : 0;
          }
          final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
          final descriptor = ui.ImageDescriptor.raw(
            buffer,
            width: original.width,
            height: original.height,
            pixelFormat: ui.PixelFormat.rgba8888,
          );
          final maskCodec = await descriptor.instantiateCodec();
          next = (await maskCodec.getNextFrame()).image;
          maskCodec.dispose();
          descriptor.dispose();
          buffer.dispose();
          original.dispose();
        }
        if (!mounted) {
          next.dispose();
          break;
        }
        if (index != _wanted || mask != _mask) {
          next.dispose();
          continue;
        }
        _image?.dispose();
        setState(() {
          _image = next;
          _loaded = index;
          _loadedMask = mask;
          _error = null;
        });
      } catch (e) {
        next?.dispose();
        if (mounted && index == _wanted && mask == _mask) {
          setState(() {
            _error = 'Could not load frame ${index + 1}: $e';
          });
        }
      }
      if (index == _wanted && mask == _mask) break;
    }
    _loading = false;
  }

  void _jump() {
    _scrub?.cancel();
    _pages.jumpToPage(_selected);
    _request(_selected);
  }

  Widget _frame(int index) {
    if (_loaded != index || _image == null || _loadedMask != _mask) {
      return Center(
        child: _error != null
            ? Text(_error!)
            : const CircularProgressIndicator(),
      );
    }
    final f = Map<String, dynamic>.from(widget.capture.frames[index] as Map);
    final d = Map<String, dynamic>.from(f['detection'] as Map);
    double n(String key) => (d[key] as num).toDouble();
    final detection = DetectionResult(
      x: n('x'),
      y: n('y'),
      vx: n('vx'),
      vy: n('vy'),
      radius: n('radius'),
      detected: d['detected'] as bool,
      isPredicted: d['predicted'] as bool,
      frameWidth: f['width'] as int,
      frameHeight: f['height'] as int,
    );
    final trail = (f['trail'] as List)
        .map(
          (p) => TrackingPoint(
            position: Offset(
              (p['x'] as num).toDouble(),
              (p['y'] as num).toDouble(),
            ),
            radius: 0,
            isPredicted: p['predicted'] as bool,
            timestamp: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        )
        .toList();
    final turns = _image!.width > _image!.height
        ? (f['orientation'] as int) ~/ 90 % 4
        : 0;
    return Center(
      child: RotatedBox(
        quarterTurns: turns,
        child: AspectRatio(
          aspectRatio: _image!.width / _image!.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              RawImage(
                image: _image,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.none,
              ),
              if (_overlay)
                CustomPaint(
                  painter: TrackingPainter(
                    detection: detection,
                    trail: trail,
                    sensorOrientation: 0,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrub?.cancel();
    _pages.dispose();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frames = widget.capture.frames;
    final f = frames[_selected] as Map;
    final d = f['detection'] as Map;
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Scanned frames'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Text(widget.capture.name),
              Text(
                'Frame ${_selected + 1} / ${frames.length} · ${((f['timeUs'] as num) / 1000000).toStringAsFixed(3)}s',
              ),
              Text(
                d['detected'] != true
                    ? 'Searching'
                    : d['predicted'] == true
                    ? 'Predicted'
                    : 'Detected',
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: frames.length,
                  onPageChanged: (index) {
                    _scrub?.cancel();
                    setState(() {
                      _selected = index;
                    });
                    _request(index);
                  },
                  itemBuilder: (context, index) => _frame(index),
                ),
              ),
              Wrap(
                spacing: 12,
                children: [
                  FilterChip(
                    label: const Text('Tracking overlay'),
                    selected: _overlay,
                    onSelected: (value) => setState(() {
                      _overlay = value;
                    }),
                  ),
                  FilterChip(
                    label: const Text('Color mask'),
                    selected: _mask,
                    onSelected: (value) {
                      setState(() {
                        _mask = value;
                      });
                      _request(_selected);
                    },
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                child: SizedBox(
                  height: 12,
                  width: double.infinity,
                  child: CustomPaint(painter: _FrameMarks(frames)),
                ),
              ),
              Slider(
                value: _selected.toDouble(),
                min: 0,
                max: (frames.length - 1).clamp(1, 599).toDouble(),
                divisions: frames.length > 1 ? frames.length - 1 : 1,
                label: 'Frame ${_selected + 1}',
                onChanged: frames.length <= 1
                    ? null
                    : (value) {
                        setState(() {
                          _selected = value.round();
                        });
                        _scrub?.cancel();
                        _scrub = Timer(
                          const Duration(milliseconds: 250),
                          _jump,
                        );
                      },
                onChangeEnd: frames.length <= 1 ? null : (_) => _jump(),
              ),
              const Text(
                'Green: detected · orange: predicted · red: searching',
                style: TextStyle(fontSize: 11),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _FrameMarks extends CustomPainter {
  final List<dynamic> frames;
  _FrameMarks(this.frames);
  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < frames.length; i++) {
      final d = frames[i]['detection'];
      final color = d['detected'] != true
          ? Colors.redAccent
          : d['predicted'] == true
          ? Colors.orange
          : Colors.greenAccent;
      canvas.drawRect(
        Rect.fromLTWH(
          i * size.width / frames.length,
          0,
          size.width / frames.length,
          size.height,
        ),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FrameMarks oldDelegate) =>
      oldDelegate.frames != frames;
}
