import 'package:flutter_test/flutter_test.dart';

import 'package:fcm_push_demo/main.dart';

void main() {
  setUp(FcmFeed.instance.clear);

  testWidgets('renders status card and empty message log', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('FCM Push Demo'), findsOneWidget);
    expect(find.textContaining('No messages yet'), findsOneWidget);
    expect(find.text('starting'), findsOneWidget);
    expect(find.text('unknown'), findsOneWidget);
    expect(find.text('pending'), findsOneWidget);
    expect(find.text('(no token yet)'), findsOneWidget);
  });

  testWidgets('renders a received push message', (WidgetTester tester) async {
    FcmFeed.instance.add(
      PushEntry(title: 'Hello', body: 'world', source: 'test'),
    );

    await tester.pumpWidget(const MyApp());

    expect(find.text('Hello'), findsOneWidget);
    expect(find.textContaining('world'), findsOneWidget);
    expect(find.textContaining('test'), findsOneWidget);
    expect(find.text('Received messages (1)'), findsOneWidget);
  });

  testWidgets('clear empties the message log', (WidgetTester tester) async {
    FcmFeed.instance.add(
      PushEntry(title: 'Hello', body: 'world', source: 'test'),
    );
    FcmFeed.instance.clear();

    await tester.pumpWidget(const MyApp());

    expect(find.textContaining('No messages yet'), findsOneWidget);
    expect(find.text('Received messages (0)'), findsOneWidget);
  });
}
