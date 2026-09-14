import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ballistic_cv/capture/frame_capture.dart';
import 'package:ballistic_cv/screens/frame_review_screen.dart';

void main() {
  testWidgets(
    'ruler skips intermediate decodes and loads on pause or release',
    (tester) async {
      final loaded = <String>[];
      final capture = FrameSet({
        'directory': '/scan',
        'objectName': 'Ball',
        'frames': List.generate(
          10,
          (i) => {
            'file': '$i.png',
            'width': 2,
            'height': 2,
            'orientation': 0,
            'timeUs': i * 33333,
            'detection': {
              'x': 0,
              'y': 0,
              'vx': 0,
              'vy': 0,
              'radius': 1,
              'detected': false,
              'predicted': false,
            },
            'trail': [],
          },
        ),
      });
      await tester.pumpWidget(
        MaterialApp(
          home: FrameReviewScreen(
            capture: capture,
            loadImage: (path) async {
              loaded.add(path);
              final recorder = ui.PictureRecorder();
              Canvas(recorder).drawColor(Colors.black, BlendMode.src);
              final picture = recorder.endRecording();
              final image = picture.toImageSync(2, 2);
              picture.dispose();
              return image;
            },
          ),
        ),
      );
      await tester.pump();
      expect(loaded, ['/scan/0.png']);
      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged!(2);
      slider.onChanged!(5);
      slider.onChanged!(8);
      await tester.pump(const Duration(milliseconds: 200));
      expect(loaded.length, 1);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();
      expect(loaded, ['/scan/0.png', '/scan/8.png']);
      tester.widget<Slider>(find.byType(Slider)).onChanged!(3);
      tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(3);
      await tester.pump();
      await tester.pump();
      expect(loaded.last, '/scan/3.png');
      expect(find.text('Close'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
