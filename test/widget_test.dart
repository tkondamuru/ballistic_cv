import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ballistic_cv/main.dart';
import 'package:ballistic_cv/models/hsv_profile.dart';
import 'package:ballistic_cv/models/sampled_object.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('empty library offers new samples', (tester) async {
    await tester.pumpWidget(const BallisticCvApp(cameras: []));
    await tester.pumpAndSettle();
    expect(find.text('Your objects'), findsOneWidget);
    expect(find.text('New object'), findsOneWidget);
  });
  testWidgets('select object, view activities, return, delete', (tester) async {
    await ObjectLibrary.save([
      const SampledObject(
        id: 'ball',
        name: 'Gold ball',
        profile: HsvProfile.defaultGreen,
      ),
    ]);
    await tester.pumpWidget(const BallisticCvApp(cameras: []));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gold ball'));
    await tester.pumpAndSettle();
    expect(find.text('Your activities'), findsOneWidget);
    expect(find.text('Tracking'), findsOneWidget);
    await tester.tap(find.text('Objects'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete Gold ball'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Gold ball'), findsNothing);
    expect(await ObjectLibrary.load(), isEmpty);
    await tester.tap(find.text('Activities'));
    await tester.pumpAndSettle();
    expect(find.text('Select an object to get started.'), findsOneWidget);
  });
  testWidgets(
    'remembers selection, opens Play, marks cards and separates Debug',
    (tester) async {
      await ObjectLibrary.save([
        const SampledObject(
          id: 'ball',
          name: 'Gold ball',
          profile: HsvProfile.defaultGreen,
        ),
      ]);
      await tester.pumpWidget(const BallisticCvApp(cameras: []));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gold ball'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tracking'));
      await tester.pumpAndSettle();
      expect(find.text('Gold ball · Tracking'), findsOneWidget);
      expect(find.byType(Slider), findsNothing);
      expect(
        tester.getSize(find.byKey(const ValueKey('zoomControls'))),
        const Size(148, 48),
      );
      expect(find.bySemanticsLabel('Decrease zoom'), findsOneWidget);
      expect(find.bySemanticsLabel('Increase zoom'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('selected_object_id'), 'ball');
      expect(prefs.getString('selected_activity'), 'tracking');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(const BallisticCvApp(cameras: []));
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );
      await tester.tap(find.text('Activities'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      await tester.tap(find.text('Objects'));
      await tester.pumpAndSettle();
      expect(find.text('✓ Selected'), findsOneWidget);
      expect(find.text('Scanned frames'), findsNothing);
      await tester.tap(find.text('Debug'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        3,
      );
      await tester.tap(find.text('Objects'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete Gold ball'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(prefs.getString('selected_object_id'), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(const BallisticCvApp(cameras: []));
      await tester.pumpAndSettle();
      expect(find.text('Your objects'), findsOneWidget);
    },
  );
}
