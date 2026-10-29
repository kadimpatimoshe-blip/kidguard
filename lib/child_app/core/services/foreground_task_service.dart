import 'dart:async';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Manages Android 14 (API 34) Foreground Services for Continuous OEM Persistence
class ForegroundTaskService {
  static final ForegroundTaskService _instance = ForegroundTaskService._internal();
  factory ForegroundTaskService() => _instance;
  ForegroundTaskService._internal();

  bool _isInitialized = false;
  bool _isRunning = false;

  bool get isRunning => _isRunning;

  /// Initializes foreground task configuration with Android 14 requirements
  Future<void> initForegroundTask() async {
    if (_isInitialized) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'kidguard_protection_channel',
        channelName: 'KidGuard Active Protection',
        channelDescription: 'Maintains continuous background protection, telemetry sync, and streaming',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        iconData: const NotificationIconData(
          resType: ResourceType.mipmap,
          resPrefix: ResourcePrefix.ic,
          name: 'launcher',
        ),
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 10000,
        isOnceEvent: false,
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    _isInitialized = true;
  }

  /// Starts the foreground service to ensure Android 14 does not kill the child process
  Future<bool> startProtectionService({
    String title = 'KidGuard Active Protection',
    String text = 'Telemetry, GPS, and security services active',
  }) async {
    await initForegroundTask();

    // Check if permission to send notifications on Android 13+ is granted
    final hasNotificationPermission = await FlutterForegroundTask.checkNotificationPermission();
    if (hasNotificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    if (await FlutterForegroundTask.isRunningService) {
      _isRunning = true;
      return true;
    }

    final result = await FlutterForegroundTask.startService(
      notificationTitle: title,
      notificationText: text,
      callback: startCallback,
    );

    _isRunning = result;
    return result;
  }

  /// Updates foreground notification description (e.g. when streaming screen or camera)
  Future<void> updateNotification({required String title, required String text}) async {
    if (_isRunning) {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      );
    }
  }

  /// Stops foreground task
  Future<bool> stopProtectionService() async {
    final result = await FlutterForegroundTask.stopService();
    _isRunning = false;
    return result;
  }
}

// Top-level callback required by flutter_foreground_task
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(ChildProtectionTaskHandler());
}

class ChildProtectionTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}
