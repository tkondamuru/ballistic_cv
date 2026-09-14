import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FrameSet {
  final Map<String, dynamic> data;
  FrameSet(Map data) : data = Map<String, dynamic>.from(data);
  String get name => data['objectName'] as String;
  List<dynamic> get frames => data['frames'] as List;
  String path(int index) => '${data['directory']}/${frames[index]['file']}';
}

class FrameCapture extends ChangeNotifier {
  FrameCapture({
    MethodChannel? channel,
    this.duration = const Duration(seconds: 10),
  }) : channel = channel ?? const MethodChannel('ballistic/frames');
  final MethodChannel channel;
  final Duration duration;
  FrameSet? saved;
  bool loading = false, capturing = false, finishing = false;
  bool _disposed = false;
  String? message;
  int count = 0, skipped = 0;
  final Stopwatch _clock = Stopwatch();
  Timer? _timer;
  Future<void>? _pending;
  int _lastTime = -100000;
  bool get busy => loading || capturing || finishing;
  double get progress =>
      (_clock.elapsedMicroseconds / duration.inMicroseconds).clamp(0, 1);
  void changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    loading = true;
    changed();
    try {
      final data = await channel.invokeMapMethod<String, dynamic>('load');
      saved = data == null ? null : FrameSet(data);
      message = null;
    } catch (e) {
      message = 'Could not load scanned frames: $e';
    }
    loading = false;
    changed();
  }

  Future<void> start(Map<String, Object?> object) async {
    if (busy || saved != null || message != null) return;
    loading = true;
    changed();
    try {
      await channel.invokeMethod<void>('start', object);
      count = 0;
      skipped = 0;
      _lastTime = -100000;
      capturing = true;
      _clock.reset();
      _clock.start();
      _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (_clock.elapsed >= duration) unawaited(finish());
        changed();
      });
    } catch (e) {
      message = 'Could not start capture: $e';
    }
    loading = false;
    changed();
  }

  void add(Map<String, Object?> Function() payload) {
    if (!capturing) return;
    final time = _clock.elapsedMicroseconds;
    if (time >= duration.inMicroseconds || count >= 600) {
      unawaited(finish());
      return;
    }
    if (_pending != null || time - _lastTime < 16666) {
      skipped++;
      return;
    }
    _lastTime = time;
    final task = _write(payload()..['timeUs'] = time);
    _pending = task;
    unawaited(
      task.whenComplete(() {
        if (identical(_pending, task)) _pending = null;
      }),
    );
  }

  Future<void> _write(Map<String, Object?> frame) async {
    try {
      count = await channel.invokeMethod<int>('frame', frame) ?? count;
    } catch (e, stack) {
      debugPrint('[Capture] Write failed: $e\n$stack');
      message = 'Capture stopped after $count frames: $e';
      // Defer finalization until this frame future completes.
      scheduleMicrotask(() => unawaited(finish()));
    }
    changed();
  }

  Future<void> finish() async {
    if (!capturing) return;
    capturing = false;
    finishing = true;
    _timer?.cancel();
    _clock.stop();
    changed();
    await _pending;
    try {
      await channel.invokeMethod<Object?>('finish', {
        'skipped': skipped,
        'elapsedUs': _clock.elapsedMicroseconds,
        'warning': message,
      });
      final data = await channel.invokeMapMethod<String, dynamic>('load');
      saved = data == null ? null : FrameSet(data);
      message ??= 'Saved $count scanned frames. Open them from Debug.';
    } catch (e) {
      message = 'Could not save scanned frames: $e';
    }
    finishing = false;
    changed();
  }

  Future<void> delete() async {
    if (busy) return;
    loading = true;
    changed();
    try {
      await channel.invokeMethod<void>('delete');
      saved = null;
      message = null;
    } catch (e) {
      message = 'Could not delete scanned frames: $e';
    }
    loading = false;
    changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _clock.stop();
    super.dispose();
  }
}
