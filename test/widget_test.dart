import 'package:flutter_test/flutter_test.dart';

import 'package:fcm_push_demo/main.dart';

void main() {
  testWidgets('shows boot status and empty token slot', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Status: starting'), findsOneWidget);
    expect(find.text('(no token yet)'), findsOneWidget);
  });
}
