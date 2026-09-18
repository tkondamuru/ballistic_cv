import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ballistic_cv/capture/trajectory_recorder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/trajectory');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test(
    'session exports measured/outside/lost samples and actual hit count',
    () async {
      final lines = <Map>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'start') {
          lines.add(jsonDecode(call.arguments as String) as Map);
          return 'test.jsonl';
        }
        if (call.method == 'append' || call.method == 'finish') {
          lines.addAll(
            (call.arguments as String)
                .trim()
                .split('\n')
                .map((s) => jsonDecode(s) as Map),
          );
        }
        if (call.method == 'list') {
          return [
            {'name': 'test.jsonl', 'bytes': 123},
          ];
        }
        return null;
      });
      final recorder = TrajectoryRecorder(channel: channel);
      await recorder.start();
      recorder.add({
        'status': 'measured',
        'insideBoard': true,
        'ball': {'x': 12, 'y': 20},
        'hit': {'angleDegrees': 40},
      });
      recorder.add({'status': 'measured', 'insideBoard': false});
      recorder.add({'status': 'searching', 'ball': null});
      await recorder.stop(actualHits: 2);
      expect(lines.where((e) => e['event'] == 'sample').length, 3);
      expect(lines.last['actualHits'], 2);
      expect(lines.last['detectedHits'], 1);
      expect(lines.last['dropped'], 0);
      expect(recorder.files.single['name'], 'test.jsonl');
      expect(recorder.recording, isFalse);
      recorder.dispose();
    },
  );
  test('slow disk bounds queue and stop waits for writes', () async {
    final gate = Completer<void>();
    var writes = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'start') return 'test.jsonl';
      if (call.method == 'append' && ++writes == 1) await gate.future;
      if (call.method == 'list') return [];
      return null;
    });
    final recorder = TrajectoryRecorder(channel: channel);
    await recorder.start();
    for (var i = 0; i < 250; i++) {
      recorder.add({'x': i});
    }
    expect(recorder.dropped, 20);
    final finish = recorder.stop();
    expect(recorder.busy, isTrue);
    gate.complete();
    await finish;
    expect(writes, 2);
    recorder.dispose();
  });
}
