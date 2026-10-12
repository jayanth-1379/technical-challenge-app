import 'package:flutter_test/flutter_test.dart';
import 'package:technical_challenge_test/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const TechnicalChallengeApp());
    expect(find.text('Technical Challenge App'), findsOneWidget);
  });
}
