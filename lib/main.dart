import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'firebase_options.dart';

const kTopic = 'fcm-test';
const kChannelId = 'fcm_demo';
const kChannelName = 'Tomato Delivery Alerts';
const kBrandRed = Color(0xFFE23744);
const kBrandSurface = Color(0xFFFFF5F5);

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
    settings: const InitializationSettings(android: androidSettings),
  );
  await _localNotifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(
        const AndroidNotificationChannel(
          kChannelId,
          kChannelName,
          description: 'Real-time order & delivery updates for Tomato',
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

int _notificationId = 0;

/// Foreground renderer — FCM stays silent while the app is open,
/// so we draw the tray notification ourselves on channel fcm_demo.
Future<void> _showLocalNotification(String title, String body) async {
  final id = _notificationId++ % 2147483647;
  await _localNotifications.show(
    id: id,
    title: title,
    body: body,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        kChannelId,
        kChannelName,
        channelDescription: 'Real-time order & delivery updates for Tomato',
        importance: Importance.max,
        priority: Priority.high,
        icon: 'ic_stat_tomato',
        color: kBrandRed,
        styleInformation: BigTextStyleInformation(''),
      ),
    ),
  );
}

/// Runs in a background isolate for data-only messages (no notification
/// key): Play services won't render those, so we do it ourselves.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  if (message.notification == null) {
    final data = message.data;
    final title = data['title']?.toString() ?? '(no title)';
    final body = data['body']?.toString() ?? '';
    await _initLocalNotifications();
    await _showLocalNotification(title, body);
  }
}

/// Permission → channel → token → topic → foreground listener.
/// Runs before runApp.
Future<void> startFcm() async {
  final feed = FcmFeed.instance;

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

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
    final entry = _toEntry(message, source: 'foreground');
    feed.add(entry);
    _showLocalNotification(entry.title, entry.body);
  });

  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    feed.add(_toEntry(message, source: 'notification tap'));
  });

  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    feed.add(_toEntry(initialMessage, source: 'notification tap'));
  }

  feed.status.value = 'listening';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await startFcm();
  runApp(const TomatoApp());
}

class TomatoApp extends StatelessWidget {
  const TomatoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tomato',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kBrandRed,
          primary: kBrandRed,
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: kBrandRed,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: const TomatoHomePage(title: 'Tomato'),
    );
  }
}

class TomatoHomePage extends StatefulWidget {
  const TomatoHomePage({super.key, required this.title});

  final String title;

  @override
  State<TomatoHomePage> createState() => _TomatoHomePageState();
}

class _TomatoHomePageState extends State<TomatoHomePage> {
  void _copyToken(String? token) {
    if (token == null || token.isEmpty) return;
    Clipboard.setData(ClipboardData(text: token));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('FCM Registration Token copied to clipboard!'),
        duration: Duration(seconds: 2),
        backgroundColor: kBrandRed,
      ),
    );
  }

  void _showSamplePayloads() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: ListView(
                controller: scrollController,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Icon(Icons.code, color: kBrandRed),
                      SizedBox(width: 8),
                      Text(
                        'Sample Test Payloads',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Use these realistic food delivery notification templates in the Firebase Console or HTTP v1 API:',
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                  const SizedBox(height: 16),
                  _PayloadCard(
                    title: '1. Order Confirmed (Standard Display)',
                    jsonText:
                        '{\n  "notification": {\n    "title": "Order Placed 🍕",\n    "body": "Pizzaria Uno confirmed your order #402. Chef is firing up the oven!"\n  },\n  "topic": "fcm-test"\n}',
                  ),
                  const SizedBox(height: 12),
                  _PayloadCard(
                    title: '2. Out for Delivery (High Priority)',
                    jsonText:
                        '{\n  "notification": {\n    "title": "Out for Delivery 🛵",\n    "body": "Your order is with delivery partner Alex. Arriving in ~12 mins."\n  },\n  "topic": "fcm-test"\n}',
                  ),
                  const SizedBox(height: 12),
                  _PayloadCard(
                    title: '3. Data-Only Silent Tracking (Custom Tray)',
                    jsonText:
                        '{\n  "data": {\n    "title": "Delivered 🎉",\n    "body": "Enjoy your hot meal! Don\'t forget to rate your experience.",\n    "orderId": "402"\n  },\n  "topic": "fcm-test"\n}',
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final feed = FcmFeed.instance;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Sample Payloads',
            icon: const Icon(Icons.code),
            onPressed: _showSamplePayloads,
          ),
        ],
      ),
      body: Column(
        children: [
          // Disclaimer & Subtitle banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: kBrandSurface,
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.grey.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Fictional FCM Delivery Test Harness • Not affiliated with commercial brands',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Card(
              elevation: 1.5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _InfoRow(
                      label: 'Status',
                      icon: Icons.sync,
                      listenable: feed.status,
                      accentColor: Colors.blue,
                    ),
                    _InfoRow(
                      label: 'Permission',
                      icon: Icons.security,
                      listenable: feed.permission,
                      accentColor: Colors.teal,
                    ),
                    _InfoRow(
                      label: 'Topic',
                      icon: Icons.tag,
                      listenable: feed.topicStatus,
                      accentColor: kBrandRed,
                    ),
                    const Divider(height: 16),
                    ValueListenableBuilder<String?>(
                      valueListenable: feed.token,
                      builder: (context, token, _) {
                        return Row(
                          children: [
                            const Icon(Icons.vpn_key, size: 16, color: Colors.grey),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SelectableText(
                                token ?? '(retrieving token...)',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                ),
                                maxLines: 1,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 18),
                              tooltip: 'Copy Token',
                              onPressed: token == null ? null : () => _copyToken(token),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ValueListenableBuilder<List<PushEntry>>(
              valueListenable: feed.messages,
              builder: (context, entries, _) => Row(
                children: [
                  const Icon(Icons.notifications_active, size: 18, color: kBrandRed),
                  const SizedBox(width: 6),
                  Text(
                    'Delivery Push Log (${entries.length})',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: entries.isEmpty ? null : feed.clear,
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text('Clear'),
                    style: TextButton.styleFrom(foregroundColor: Colors.grey.shade700),
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
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fastfood_outlined, size: 54, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        const Text(
                          'No push messages received yet.',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Publish a campaign to topic "$kTopic"\nor send a test message to this device token.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final t = entry.receivedAt.toLocal();
                    final ts =
                        '${t.hour.toString().padLeft(2, '0')}:'
                        '${t.minute.toString().padLeft(2, '0')}:'
                        '${t.second.toString().padLeft(2, '0')}';
                    return _PushEntryCard(entry: entry, timestamp: ts);
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

class _PushEntryCard extends StatelessWidget {
  const _PushEntryCard({required this.entry, required this.timestamp});

  final PushEntry entry;
  final String timestamp;

  IconData _getIcon() {
    final lower = '${entry.title} ${entry.body}'.toLowerCase();
    if (lower.contains('order') || lower.contains('placed') || lower.contains('pizza')) {
      return Icons.receipt_long;
    }
    if (lower.contains('cooking') || lower.contains('prep') || lower.contains('chef')) {
      return Icons.restaurant;
    }
    if (lower.contains('delivery') || lower.contains('rider') || lower.contains('way')) {
      return Icons.delivery_dining;
    }
    if (lower.contains('deliver') || lower.contains('enjoy') || lower.contains('arrived')) {
      return Icons.check_circle_outline;
    }
    return Icons.notifications;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: kBrandSurface,
              foregroundColor: kBrandRed,
              radius: 20,
              child: Icon(_getIcon(), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          entry.source,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.body,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    timestamp,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PayloadCard extends StatelessWidget {
  const _PayloadCard({required this.title, required this.jsonText});

  final String title;
  final String jsonText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 16),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: jsonText));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Payload copied!'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            jsonText,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.icon,
    required this.listenable,
    required this.accentColor,
  });

  final String label;
  final IconData icon;
  final ValueListenable<String> listenable;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: listenable,
      builder: (context, value, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Icon(icon, size: 16, color: accentColor),
            const SizedBox(width: 8),
            Text(
              '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            Flexible(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
