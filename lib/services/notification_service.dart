import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  // Stream for notification payload
  final ValueNotifier<String?> onNotificationClick = ValueNotifier<String?>(
    null,
  );

  Future<void> init() async {
    if (_isInitialized) return;

    // Android Config
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS/macOS Config
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    // Linux Config
    final LinuxInitializationSettings initializationSettingsLinux =
        LinuxInitializationSettings(defaultActionName: 'Open notification');

    // Initialization Logic
    final InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
          linux: initializationSettingsLinux,
        );

    try {
      await flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse details) {
          debugPrint('Notification clicked: ${details.payload}');
          if (details.payload != null) {
            onNotificationClick.value = details.payload;
          }
        },
      );

      // Request Android 13+ Permissions explicitly
      if (!kIsWeb && Platform.isAndroid) {
        final androidImplementation = flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        await androidImplementation?.requestNotificationsPermission();
      }

      _isInitialized = true;
    } catch (e) {
      debugPrint('Error initializing notifications: $e');
    }
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_isInitialized) await init();

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'stock_alerts_channel',
          'Stock Alerts',
          channelDescription: 'Notifications for stock trend changes',
          importance: Importance.max,
          priority: Priority.high,
          showWhen: true,
        );

    const LinuxNotificationDetails linuxPlatformChannelSpecifics =
        LinuxNotificationDetails(urgency: LinuxNotificationUrgency.critical);

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      linux: linuxPlatformChannelSpecifics,
    );

    try {
      await flutterLocalNotificationsPlugin.show(
        id,
        title,
        body,
        platformChannelSpecifics,
        payload: payload,
      );
    } catch (e) {
      debugPrint('Error showing notification: $e');
    }
  }
}
