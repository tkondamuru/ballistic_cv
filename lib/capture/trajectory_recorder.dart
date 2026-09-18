import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../detection/impact_detector.dart';

/// Coordinate-only JSON Lines sessions. Bounded batches keep slow storage from
/// accumulating an unlimited queue; dropped samples are reported in the footer.
class TrajectoryRecorder extends ChangeNotifier with WidgetsBindingObserver {
  static final instance = TrajectoryRecorder();
  TrajectoryRecorder({MethodChannel? channel})
    : channel = channel ?? const MethodChannel('ballistic/trajectory') {
    WidgetsBinding.instance.addObserver(this);
  }
  final MethodChannel channel;
  bool recording = false, busy = false;
  String? error;
  String? session;
  int samples = 0, dropped = 0, hits = 0;
  List<Map<String, dynamic>> files = [];
  final List<String> _batch = [];
  Future<void>? _pending;
  Timer? _timer;
  final Stopwatch _clock = Stopwatch();

  Future<void> refresh() async {
    try {
      final result = await channel.invokeListMethod<dynamic>('list') ?? [];
      files = result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      error = 'Could not load recordings: $e';
    }
    notifyListeners();
  }

  Future<void> start() async {
    if (recording || busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      session = await channel.invokeMethod<String>(
        'start',
        jsonEncode({
          'event': 'start',
          'schema': 1,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'coordinateSpace': 'cameraPixels',
          'activity': 'thud',
          'detector': {
            'minAngleDegrees': ImpactDetector.minAngleDegrees,
            'minLegPixels': 3,
            'minSpeedPixelsPerSecond': 60,
            'maxGapMs': 80,
            'cooldownMs': 180,
          },
        }),
      );
      samples = 0;
      dropped = 0;
      hits = 0;
      _batch.clear();
      _clock.reset();
      _clock.start();
      recording = true;
      _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        _flush();
        if (_clock.elapsed >= const Duration(minutes: 10)) {
          unawaited(stop(reason: 'timeLimit'));
        }
      });
    } catch (e) {
      error = 'Could not start recording: $e';
    }
    busy = false;
    notifyListeners();
  }

  void add(Map<String, Object?> data) {
    if (!recording) return;
    samples++;
    if (data['hit'] != null) hits++;
    if (_batch.length >= 200) {
      dropped++;
      return;
    }
    _batch.add(
      jsonEncode({
        'event': 'sample',
        'sample': samples,
        'elapsedUs': _clock.elapsedMicroseconds,
        ...data,
      }),
    );
    if (_batch.length >= 30) _flush();
  }

  void _flush() {
    if (_pending != null || _batch.isEmpty) return;
    final text = '${_batch.join('\n')}\n';
    final count = _batch.length;
    _batch.clear();
    final write = channel.invokeMethod<void>('append', text).catchError((
      Object e,
    ) {
      dropped += count;
      error = 'Recording write failed: $e';
      recording = false;
      _timer?.cancel();
      notifyListeners();
    });
    _pending = write;
    unawaited(
      write.whenComplete(() {
        _pending = null;
      }),
    );
  }

  Future<void> stop({int? actualHits, String reason = 'user'}) async {
    if (busy || session == null) return;
    busy = true;
    recording = false;
    _timer?.cancel();
    _clock.stop();
    notifyListeners();
    try {
      await _pending;
      _flush();
      await _pending;
      await channel.invokeMethod<void>(
        'finish',
        jsonEncode({
          'event': 'end',
          'reason': reason,
          'samples': samples,
          'dropped': dropped,
          'detectedHits': hits,
          'actualHits': actualHits,
          'elapsedUs': _clock.elapsedMicroseconds,
          'error': error,
        }),
      );
      session = null;
    } catch (e) {
      error = 'Could not finalize recording: $e';
    }
    busy = false;
    await refresh();
  }

  Future<void> share(String name) async {
    try {
      await channel.invokeMethod<void>('share', name);
    } catch (e) {
      error = 'Could not share recording: $e';
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive && recording) {
      unawaited(stop(reason: 'appInactive'));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }
}
