import 'dart:async';
import '../../data/models/telemetry_payload.dart';
import 'rtdb_client_service.dart';

/// Standalone Call Log Synchronization Service for Child Device
/// Strictly manages real hardware call logs captured from Android call log provider.
class CallLogService {
  final RtdbClientService _rtdbClient;
  final List<CallLogPayload> _callHistory = [];

  CallLogService({RtdbClientService? rtdbClient})
      : _rtdbClient = rtdbClient ?? RtdbClientService();

  List<CallLogPayload> get callHistory => List.unmodifiable(_callHistory);

  /// Synchronizes real call logs to /devices/{pairingCode}/callLogs
  Future<bool> syncCallLogs(String pairingCode, [List<CallLogPayload>? logs]) async {
    final list = logs ?? _callHistory;
    final payloadList = list.map((c) => c.toJson()).toList();

    return await _rtdbClient.setPath(
      'devices/$pairingCode/callLogs',
      payloadList,
    );
  }

  /// Appends an actual newly recorded call event from physical device
  Future<bool> recordCall({
    required String pairingCode,
    required CallLogPayload call,
  }) async {
    _callHistory.insert(0, call);
    if (_callHistory.length > 50) {
      _callHistory.removeLast();
    }
    return await syncCallLogs(pairingCode);
  }

  void clear() {
    _callHistory.clear();
  }
}
