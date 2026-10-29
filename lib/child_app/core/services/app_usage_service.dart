import 'dart:async';
import '../../data/models/telemetry_payload.dart';
import 'rtdb_client_service.dart';

/// Standalone Application Usage Statistics Service for Child Device
/// Strictly manages real app usage stats collected from Android UsageStatsManager.
class AppUsageService {
  final RtdbClientService _rtdbClient;
  final List<AppUsagePayload> _usageStats = [];

  AppUsageService({RtdbClientService? rtdbClient})
      : _rtdbClient = rtdbClient ?? RtdbClientService();

  List<AppUsagePayload> get usageStats => List.unmodifiable(_usageStats);

  /// Synchronizes real app usage list to /devices/{pairingCode}/appUsage
  Future<bool> syncAppUsage(String pairingCode, [List<AppUsagePayload>? stats]) async {
    final list = stats ?? _usageStats;
    final payloadList = list.map((a) => a.toJson()).toList();

    return await _rtdbClient.setPath(
      'devices/$pairingCode/appUsage',
      payloadList,
    );
  }

  /// Updates usage data from real Android UsageStatsManager query
  Future<bool> updateUsageFromSystem({
    required String pairingCode,
    required List<AppUsagePayload> actualStats,
  }) async {
    _usageStats.clear();
    _usageStats.addAll(actualStats);
    return await syncAppUsage(pairingCode);
  }

  void clear() {
    _usageStats.clear();
  }
}
