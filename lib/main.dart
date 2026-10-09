import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'firebase_options.dart';

const kTopic = 'fcm-test';
const kChannelId = 'fcm_demo';
const kChannelName = 'FCM Demo';

class PushEntry {
  PushEntry({
    required this.title,
    required this.body,
    required this.source,
    Map<String, dynamic>? data,
  }) : data = data ?? <String, dynamic>{},
       receivedAt = DateTime.now();

  final String title;
  final String body;
  final String source;
  final Map<String, dynamic> data;
  final DateTime receivedAt;
}

/// In-memory app state (RAM only — cleared on restart).
class FcmFeed {
  FcmFeed._();
  static final FcmFeed instance = FcmFeed._();

  final ValueNotifier<String> status = ValueNotifier('starting');
  final ValueNotifier<String?> token = ValueNotifier(null);
  final ValueNotifier<String> permission = ValueNotifier('unknown');
  final ValueNotifier<String> topicStatus = ValueNotifier('pending');
  final ValueNotifier<List<PushEntry>> messages = ValueNotifier(<PushEntry>[]);

  void add(PushEntry entry) {
    messages.value = <PushEntry>[entry, ...messages.value];
  }

  void clear() {
    messages.value = <PushEntry>[];
  }
}

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

/// Creates the fcm_demo channel at importance MAX — both renderers
/// (our code in foreground, Play services in background) post to it.
Future<void> _initLocalNotifications() async {
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  await _localNotifications.initialize(
    settings: InitializationSettings(android: androidSettings),
  );
  await _localNotifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(
        const AndroidNotificationChannel(
          kChannelId,
          kChannelName,
          description: 'Push messages from the FCM harness',
          importance: Importance.max,
        ),
      );
}

PushEntry _toEntry(RemoteMessage message, {required String source}) {
  final data = message.data;
  return PushEntry(
    title:
        message.notification?.title ??
        data['title']?.toString() ??
        '(no title)',
    body: message.notification?.body ?? data['body']?.toString() ?? '',
    source: source,
    data: data,
  );
}

/// Permission → channel → token → topic → foreground listener.
/// Runs before runApp.
Future<void> startFcm() async {
  final feed = FcmFeed.instance;

  final settings = await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );
  feed.permission.value = settings.authorizationStatus.name;

  await _initLocalNotifications();

  try {
    feed.token.value = await FirebaseMessaging.instance.getToken();
  } catch (e) {
    feed.status.value = 'token error: $e';
  }
  FirebaseMessaging.instance.onTokenRefresh.listen(
    (t) => feed.token.value = t,
  );

  try {
    await FirebaseMessaging.instance.subscribeToTopic(kTopic);
    feed.topicStatus.value = 'subscribed ($kTopic)';
  } catch (e) {
    feed.topicStatus.value = 'error: $e';
  }

  FirebaseMessaging.onMessage.listen((message) {
    feed.add(_toEntry(message, source: 'foreground'));
  });

  feed.status.value = 'listening';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await startFcm();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FCM Push Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'FCM Push Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    final feed = FcmFeed.instance;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _InfoRow(label: 'Status', listenable: feed.status),
                    _InfoRow(label: 'Permission', listenable: feed.permission),
                    _InfoRow(label: 'Topic', listenable: feed.topicStatus),
                    const SizedBox(height: 8),
                    ValueListenableBuilder<String?>(
                      valueListenable: feed.token,
                      builder: (context, token, _) => SelectableText(
                        token ?? '(no token yet)',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ValueListenableBuilder<List<PushEntry>>(
              valueListenable: feed.messages,
              builder: (context, entries, _) => Row(
                children: [
                  Text(
                    'Received messages (${entries.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: entries.isEmpty ? null : feed.clear,
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ValueListenableBuilder<List<PushEntry>>(
              valueListenable: feed.messages,
              builder: (context, entries, _) {
                if (entries.isEmpty) {
                  return const Center(
                    child: Text(
                      'No messages yet.\nSend one from the Firebase console.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final t = entry.receivedAt.toLocal();
                    final ts =
                        '${t.hour.toString().padLeft(2, '0')}:'
                        '${t.minute.toString().padLeft(2, '0')}:'
                        '${t.second.toString().padLeft(2, '0')}';
                    return ListTile(
                      title: Text(entry.title),
                      subtitle: Text('${entry.body}\n${entry.source} · $ts'),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.listenable});

  final String label;
  final ValueListenable<String> listenable;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: listenable,
      builder: (context, value, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$label: ',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Flexible(child: Text(value, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}
