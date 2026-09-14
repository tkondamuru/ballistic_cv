import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ballistic_cv/capture/frame_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/frames');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'one outstanding frame, finish waits for it, saved set blocks recapture',
    () async {
      final gate = Completer<int>();
      final calls = <String>[];
      Map<String, dynamic>? saved;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'frame':
            return gate.future;
          case 'finish':
            saved = {
              'objectName': 'Ball',
              'directory': '/scan',
              'frames': [
                {'file': '0001.png'},
              ],
            };
            return 1;
          case 'load':
            return saved;
          case 'delete':
            saved = null;
            return null;
          default:
            return null;
        }
      });
      final capture = FrameCapture(channel: channel);
      await capture.load();
      await capture.start({'objectName': 'Ball'});
      capture.add(() => {'width': 2});
      capture.add(() => throw StateError('Queued a second raw frame'));
      final finish = capture.finish();
      await Future<void>.delayed(Duration.zero);
      expect(calls.where((e) => e == 'finish'), isEmpty);
      gate.complete(1);
      await finish;
      expect(capture.count, 1);
      expect(capture.skipped, 1);
      expect(capture.saved!.frames.length, 1);
      await capture.start({});
      expect(calls.where((e) => e == 'start').length, 1);
      await capture.delete();
      expect(capture.saved, isNull);
      await capture.start({});
      expect(calls.where((e) => e == 'start').length, 2);
      await capture.finish();
      capture.dispose();
    },
  );

  test(
    'time limit finishes automatically even when no new frame arrives',
    () async {
      final done = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'finish') {
          done.complete();
          return 0;
        }
        return null;
      });
      final capture = FrameCapture(
        channel: channel,
        duration: const Duration(milliseconds: 20),
      );
      await capture.start({});
      await done.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);
      expect(capture.capturing, isFalse);
      capture.dispose();
    },
  );

  test(
    'write failure finalizes accepted frames without an unbounded retry loop',
    () async {
      final done = Completer<void>();
      int writes = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'frame') {
          writes++;
          throw PlatformException(code: 'full');
        }
        if (call.method == 'finish') {
          done.complete();
          return 1;
        }
        if (call.method == 'load') {
          return {
            'objectName': 'Ball',
            'directory': '/scan',
            'frames': [
              {'file': '0001.png'},
            ],
          };
        }
        return null;
      });
      final capture = FrameCapture(channel: channel);
      await capture.start({});
      capture.add(() => {});
      await done.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);
      expect(capture.capturing, isFalse);
      expect(capture.message, contains('Capture stopped'));
      expect(writes, 1);
      capture.dispose();
    },
  );

  test('hard cap finalizes rather than accepting frame 601', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, isNot('frame'));
      return null;
    });
    final capture = FrameCapture(channel: channel);
    await capture.start({});
    capture.count = 600;
    capture.add(() => throw StateError('Frame cap exceeded'));
    await Future<void>.delayed(Duration.zero);
    expect(capture.capturing, isFalse);
    capture.dispose();
  });
}
