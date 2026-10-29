import 'dart:async';
import '../../data/models/telemetry_payload.dart';
import 'rtdb_client_service.dart';

/// Standalone Notification Listener & Sync Service for Child Device
/// Strictly manages real notifications intercepted from Android NotificationListenerService.
class NotificationService {
  final RtdbClientService _rtdbClient;
  final List<NotificationPayload> _bufferedNotifications = [];

  NotificationService({RtdbClientService? rtdbClient})
      : _rtdbClient = rtdbClient ?? RtdbClientService();

  List<NotificationPayload> get currentNotifications => List.unmodifiable(_bufferedNotifications);

  /// Pushes an incoming real notification captured by NotificationListenerService to RTDB
  Future<bool> pushNotification({
    required String pairingCode,
    required NotificationPayload notification,
  }) async {
    _bufferedNotifications.insert(0, notification);
    if (_bufferedNotifications.length > 50) {
      _bufferedNotifications.removeLast();
    }

    final payloadList = _bufferedNotifications.map((n) => n.toJson()).toList();

    // Keyword & Bad Words Detection: real-time alert push
    final badWords = ["badword1", "badword2", "suicide", "drugs", "porn"];
    final textToScan = "${notification.title} ${notification.body}".toLowerCase();
    for (final word in badWords) {
      if (textToScan.contains(word)) {
        _rtdbClient.updatePath('devices/$pairingCode/alerts', {
          'type': 'notification_keyword_alert',
          'keyword': word,
          'context': textToScan,
          'package': notification.packageName,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        break; 
      }
    }

    return await _rtdbClient.setPath(
      'devices/$pairingCode/notifications',
      payloadList,
    );
  }

  /// Bulk syncs all real buffered notifications to /devices/{pairingCode}/notifications
  Future<bool> syncAllNotifications(String pairingCode) async {
    final payloadList = _bufferedNotifications.map((n) => n.toJson()).toList();
    return await _rtdbClient.setPath(
      'devices/$pairingCode/notifications',
      payloadList,
    );
  }

  void clear() {
    _bufferedNotifications.clear();
  }
}
