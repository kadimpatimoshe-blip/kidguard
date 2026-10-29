import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

class GeofenceService {
  final DatabaseReference _root;

  GeofenceService({DatabaseReference? root})
      : _root = root ?? FirebaseDatabase.instance.ref();

  DatabaseReference _deviceRef(String deviceCode) =>
      _root.child('devices').child(deviceCode);

  /// Adds or updates a circular Safe Zone under /devices/{deviceCode}/policy/safeZones/{zoneId}
  Future<void> addSafeZone({
    required String deviceCode,
    required String zoneId,
    required double lat,
    required double lon,
    double radiusMeters = 200.0,
    String? name,
  }) async {
    final cleanDevice = deviceCode.trim();
    final cleanZone = zoneId.trim();

    if (cleanDevice.isEmpty || cleanZone.isEmpty) {
      throw ArgumentError('deviceCode and zoneId must not be empty');
    }

    final zoneData = {
      'lat': lat,
      'lon': lon,
      'latitude': lat,
      'longitude': lon,
      'radiusMeters': radiusMeters,
      'name': name ?? cleanZone,
      'createdAt': ServerValue.timestamp,
      'updatedAt': ServerValue.timestamp,
    };

    // Save under policy/safeZones for policy listener sync
    await _deviceRef(cleanDevice)
        .child('policy')
        .child('safeZones')
        .child(cleanZone)
        .set(zoneData);

    // Also mirror to safeZones top-level node for fast parent console querying
    await _deviceRef(cleanDevice)
        .child('safeZones')
        .child(cleanZone)
        .set(zoneData);

    debugPrint("GeofenceService: Added safe zone '$cleanZone' at ($lat, $lon) with radius ${radiusMeters}m for device $cleanDevice");
  }

  /// Removes a safe zone from the device's active policy
  Future<void> removeSafeZone({
    required String deviceCode,
    required String zoneId,
  }) async {
    final cleanDevice = deviceCode.trim();
    final cleanZone = zoneId.trim();

    await _deviceRef(cleanDevice)
        .child('policy')
        .child('safeZones')
        .child(cleanZone)
        .remove();

    await _deviceRef(cleanDevice)
        .child('safeZones')
        .child(cleanZone)
        .remove();

    debugPrint("GeofenceService: Removed safe zone '$cleanZone' for device $cleanDevice");
  }

  /// Fetches all configured safe zones for a device
  Future<Map<String, dynamic>> getSafeZones(String deviceCode) async {
    try {
      final snapshot = await _deviceRef(deviceCode.trim())
          .child('policy')
          .child('safeZones')
          .get();

      if (!snapshot.exists || snapshot.value == null || snapshot.value is! Map) {
        return <String, dynamic>{};
      }

      return Map<String, dynamic>.from(snapshot.value as Map);
    } catch (e) {
      debugPrint("GeofenceService: Error fetching safe zones: $e");
      return <String, dynamic>{};
    }
  }

  /// Real-time stream of safe zones configured for the device
  Stream<Map<String, dynamic>> listenSafeZones(String deviceCode) {
    return _deviceRef(deviceCode.trim())
        .child('policy')
        .child('safeZones')
        .onValue
        .map((event) {
      final raw = event.snapshot.value;
      if (raw == null || raw is! Map) return <String, dynamic>{};
      return Map<String, dynamic>.from(raw);
    });
  }

  /// Real-time stream of geofence transition alerts (e.g., entered or exited zone)
  Stream<List<Map<String, dynamic>>> listenGeofenceAlerts(String deviceCode, {int limit = 20}) {
    return _deviceRef(deviceCode.trim())
        .child('geofenceAlerts')
        .limitToLast(limit)
        .onValue
        .map((event) {
      final raw = event.snapshot.value;
      if (raw == null || raw is! Map) return <Map<String, dynamic>>[];

      final map = Map<String, dynamic>.from(raw);
      final alerts = <Map<String, dynamic>>[];

      for (final entry in map.entries) {
        if (entry.value is Map) {
          final alert = Map<String, dynamic>.from(entry.value as Map);
          alert['id'] = entry.key;
          alerts.add(alert);
        }
      }

      // Sort newest first
      alerts.sort((a, b) {
        final tA = (a['timestamp'] as num?)?.toInt() ?? 0;
        final tB = (b['timestamp'] as num?)?.toInt() ?? 0;
        return tB.compareTo(tA);
      });

      return alerts;
    });
  }
}
