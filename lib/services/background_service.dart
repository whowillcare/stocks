import 'dart:io';
import 'package:workmanager/workmanager.dart';
import 'package:flutter/foundation.dart';
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
          isInDebugMode: false, // Set to true to see notifications immediately
        );

        // Schedule periodic task
        // Android constraint: Minimum 15 minutes.
        // We schedule it every 1 hour to check updates.
        // For 8 AM specifically, we'd need complex logic (OneOffTask chain),
        // but periodic is robust for keeping user updated.
        await Workmanager().registerPeriodicTask(
          'stock-fetch-periodic',
          fetchStockTask,
          frequency: const Duration(hours: 1),
          constraints: Constraints(
            networkType: NetworkType.connected, // Only when online
          ),
        );
      } catch (e) {
        debugPrint('Workmanager init failed: $e');
      }
    }
  }
}
