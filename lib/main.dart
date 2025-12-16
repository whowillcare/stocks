import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'ui/home_provider.dart';
import 'ui/home_screen.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';
import 'ui/event_log_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackgroundService.init();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    // Initialize notifications
    NotificationService().init();

    // Listen for notification clicks
    NotificationService().onNotificationClick.addListener(() {
      final payload = NotificationService().onNotificationClick.value;
      if (payload == 'events') {
        navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (context) => const EventLogScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => HomeProvider())],
      child: MaterialApp(
        title: 'Stock Analyzer',
        navigatorKey: navigatorKey,
        theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
        home: const HomeScreen(),
      ),
    );
  }
}
