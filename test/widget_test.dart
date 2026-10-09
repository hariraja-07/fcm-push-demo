import 'package:flutter_test/flutter_test.dart';

import 'package:fcm_push_demo/main.dart';

void main() {
  testWidgets('shows FCM status before controller starts', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('starting'), findsOneWidget);
    expect(find.text('unknown'), findsOneWidget);
    expect(find.text('pending'), findsOneWidget);
    expect(find.text('(no token yet)'), findsOneWidget);
  });
}
