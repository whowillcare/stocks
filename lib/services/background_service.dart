import 'dart:io';
import 'package:workmanager/workmanager.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../ui/home_provider.dart';
import 'notification_service.dart';

// Key for the task
const String fetchStockTask = 'fetchStockTask';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case fetchStockTask:
        debugPrint('Running background stock check: $fetchStockTask');
        try {
          // Check Constraints logic manually
          final prefs = await SharedPreferences.getInstance();
          final enabled = prefs.getBool('bgEnabled') ?? true;
          if (!enabled) {
            debugPrint('Background task disabled in settings. Skipping.');
            return Future.value(true);
          }

          final excludeWeekends = prefs.getBool('bgExcludeWeekends') ?? true;
          final dt = DateTime.now();
          if (excludeWeekends) {
            if (dt.weekday == DateTime.saturday ||
                dt.weekday == DateTime.sunday) {
              debugPrint('Background task skipped (Weekend).');
              return Future.value(true);
            }
          }

          final startHour = prefs.getInt('bgStartHour') ?? 9;
          final endHour = prefs.getInt('bgEndHour') ?? 17;
          if (dt.hour < startHour || dt.hour >= endHour) {
            debugPrint(
              'Background task skipped (Outside hours: $startHour-$endHour).',
            );
            return Future.value(true);
          }

          // Initialize Service
          final notificationService = NotificationService();
          await notificationService.init();

          // Initialize Provider (logic container)
          final provider = HomeProvider();
          await provider.loadSessions();

          if (provider.sessions.isNotEmpty) {
            // Force refresh and check for events
            await provider.refreshAllSessions(forceRefresh: true);
          }
        } catch (e) {
          debugPrint('Background task error: $e');
          return Future.value(false);
        }
        break;
    }
    return Future.value(true);
  });
}

class BackgroundService {
  static Future<void> init() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        await Workmanager().initialize(
          callbackDispatcher,
          isInDebugMode: false,
        );

        // Initial default registration if needed
        register(frequency: const Duration(hours: 1));
      } catch (e) {
        debugPrint('Workmanager init failed: $e');
      }
    }
  }

  static Future<void> register({
    Duration frequency = const Duration(hours: 1),
    Duration? initialDelay,
  }) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    try {
      await Workmanager().cancelAll();

      await Workmanager().registerPeriodicTask(
        'stock-fetch-periodic',
        fetchStockTask,
        frequency: frequency,
        initialDelay: initialDelay ?? const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      );
      debugPrint('Background task registered: $frequency');
    } catch (e) {
      debugPrint('Error registering background task: $e');
    }
  }
}
