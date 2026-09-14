import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ballistic_cv/widgets/zoom_button.dart';

void main() {
  testWidgets('tap steps once; hold repeats and stops on release or disable', (
    tester,
  ) async {
    var steps = 0;
    Widget button(bool enabled) => MaterialApp(
      home: Scaffold(
        body: ZoomButton(
          label: 'Increase zoom',
          icon: Icons.chevron_right,
          onStep: enabled ? () => steps++ : null,
        ),
      ),
    );
    await tester.pumpWidget(button(true));
    await tester.tap(find.byType(IconButton));
    expect(steps, 1);
    final hold = await tester.startGesture(
      tester.getCenter(find.byType(IconButton)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 360));
    expect(steps, greaterThan(2));
    await hold.up();
    final released = steps;
    await tester.pump(const Duration(seconds: 1));
    expect(steps, released);
    final second = await tester.startGesture(
      tester.getCenter(find.byType(IconButton)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(button(false));
    final disabled = steps;
    await tester.pump(const Duration(seconds: 1));
    expect(steps, disabled);
    await second.up();
    expect(find.byType(Tooltip), findsNothing);
  });
}
