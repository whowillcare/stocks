import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'ui/home_provider.dart';
import 'ui/home_screen.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';
import 'ui/event_log_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

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
  final _routeObserver = CurrentRouteObserver();

  @override
  void initState() {
    super.initState();
    // Initialize notifications
    NotificationService().init();

    // Listen for notification clicks
    NotificationService().onNotificationClick.addListener(() {
      final payload = NotificationService().onNotificationClick.value;
      if (payload == 'events') {
        if (_routeObserver.currentRouteName != '/event_log') {
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (context) => const EventLogScreen(),
              settings: const RouteSettings(name: '/event_log'),
            ),
          );
        }
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
        navigatorObservers: [_routeObserver],
        theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
        home: const HomeScreen(),
      ),
    );
  }
}

class CurrentRouteObserver extends NavigatorObserver {
  String? currentRouteName;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route is ModalRoute) {
      currentRouteName = route.settings.name;
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute is ModalRoute) {
      currentRouteName = previousRoute.settings.name;
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute is ModalRoute) {
      currentRouteName = newRoute.settings.name;
    }
  }
}
