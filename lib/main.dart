import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';

/// In-memory app state (RAM only — cleared on restart).
class FcmFeed {
  FcmFeed._();
  static final FcmFeed instance = FcmFeed._();

  final ValueNotifier<String> status = ValueNotifier('starting');
  final ValueNotifier<String?> token = ValueNotifier(null);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FirebaseMessaging.instance.onTokenRefresh.listen(
    (t) => FcmFeed.instance.token.value = t,
  );
  try {
    final token = await FirebaseMessaging.instance.getToken();
    FcmFeed.instance.token.value = token;
    FcmFeed.instance.status.value =
        token != null ? 'token loaded' : 'token unavailable (no Play services?)';
  } catch (e) {
    FcmFeed.instance.status.value = 'token error: $e';
  }

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
      body: Center(
        child: ValueListenableBuilder<String>(
          valueListenable: feed.status,
          builder: (context, status, _) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Status: $status'),
              const SizedBox(height: 12),
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
    );
  }
}
