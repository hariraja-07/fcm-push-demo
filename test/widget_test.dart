import 'package:flutter_test/flutter_test.dart';

import 'package:fcm_push_demo/main.dart';

void main() {
  setUp(FcmFeed.instance.clear);

  testWidgets('renders status card and empty push log', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TomatoApp());

    expect(find.text('Tomato'), findsOneWidget);
    expect(find.textContaining('No push messages received yet'), findsOneWidget);
    expect(find.text('starting'), findsOneWidget);
    expect(find.text('unknown'), findsOneWidget);
    expect(find.text('pending'), findsOneWidget);
    expect(find.text('(retrieving token...)'), findsOneWidget);
    expect(find.text('Delivery Push Log (0)'), findsOneWidget);
  });

  testWidgets('renders a received push message', (WidgetTester tester) async {
    FcmFeed.instance.add(
      PushEntry(title: 'Hello', body: 'world', source: 'test'),
    );

    await tester.pumpWidget(const TomatoApp());

    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('world'), findsOneWidget);
    expect(find.text('test'), findsOneWidget);
    expect(find.text('Delivery Push Log (1)'), findsOneWidget);
  });

  testWidgets('clear empties the push log', (WidgetTester tester) async {
    FcmFeed.instance.add(
      PushEntry(title: 'Hello', body: 'world', source: 'test'),
    );
    FcmFeed.instance.clear();

    await tester.pumpWidget(const TomatoApp());

    expect(find.textContaining('No push messages received yet'), findsOneWidget);
    expect(find.text('Delivery Push Log (0)'), findsOneWidget);
  });
}
