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
    expect(find.text('Choose an activity'), findsOneWidget);
    expect(find.text('Tracking'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete Gold ball'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Gold ball'), findsNothing);
    expect(await ObjectLibrary.load(), isEmpty);
  });
}
