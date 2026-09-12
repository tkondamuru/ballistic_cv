import 'package:flutter_test/flutter_test.dart';
import 'package:ballistic_cv/main.dart';

void main() {
  testWidgets('BallisticCvApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const BallisticCvApp(cameras: []));
    expect(find.byType(BallisticCvApp), findsOneWidget);
  });
}
