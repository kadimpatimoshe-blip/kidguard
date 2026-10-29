import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

class TelemetryManager {
  final Battery _battery = Battery();
  final Duration locationInterval = const Duration(minutes: 5);
  final double minDistanceMeters = 100.0;

  DateTime? _lastLocationUpload;
  Position? _lastPosition;
  String? defaultDeviceId;

  TelemetryManager({this.defaultDeviceId});

  /// Reads current battery telemetry without blocking or hanging on stream events
  Future<Map<String, dynamic>> getBatteryStatus() async {
    try {
      final level = await _battery.batteryLevel;
      BatteryState state;
      try {
        state = await _battery.batteryState;
      } catch (_) {
        try {
          state = await _battery.onBatteryStateChanged.first.timeout(
            const Duration(milliseconds: 500),
          );
        } catch (_) {
          state = BatteryState.unknown;
        }
      }

      final isCharging = state == BatteryState.charging || state == BatteryState.full;

      return {
        'batteryLevel': level,
        'isCharging': isCharging,
        'batteryState': state.name,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
    } catch (e) {
      debugPrint("TelemetryManager: Error fetching battery status: $e");
      return {
        'batteryLevel': 0,
        'isCharging': false,
        'batteryState': 'unknown',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
    }
  }

  /// Evaluates time elapsed and displacement thresholds before streaming GPS telemetry
  Future<void> streamLocationIfNeeded({String? deviceId}) async {
    try {
      final targetDevice = deviceId ?? defaultDeviceId;
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      final now = DateTime.now();

      if (_lastLocationUpload == null || _lastPosition == null) {
        _lastLocationUpload = now;
        _lastPosition = position;
        await _uploadLocation(position, deviceId: targetDevice);
        return;
      }

      final diff = now.difference(_lastLocationUpload!);
      final distance = Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        position.latitude,
        position.longitude,
      );

      // Upload if elapsed duration exceeded OR distance threshold met
      if (diff >= locationInterval || distance >= minDistanceMeters) {
        await _uploadLocation(position, deviceId: targetDevice);
        _lastLocationUpload = now;
        _lastPosition = position;
      }
    } catch (e) {
      debugPrint("TelemetryManager: Error in streamLocationIfNeeded: $e");
    }
  }

  /// Uploads location telemetry to Firebase Realtime Database with safety checks
  Future<void> _uploadLocation(Position position, {String? deviceId}) async {
    final targetDevice = deviceId ?? defaultDeviceId;
    if (targetDevice == null || targetDevice.isEmpty) {
      debugPrint("TelemetryManager: No target device specified for location upload.");
      return;
    }

    try {
      final db = FirebaseDatabase.instance.ref();
      final locationData = {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'speed': (position.speed >= 0 ? position.speed * 3.6 : 0.0), // km/h
        'accuracy': position.accuracy,
        'altitude': position.altitude,
        'timestamp': position.timestamp.millisecondsSinceEpoch,
      };

      await db.child('devices').child(targetDevice).child('location').update(locationData);
      debugPrint("TelemetryManager: Synced GPS telemetry for device $targetDevice (lat: ${position.latitude}, lon: ${position.longitude})");
    } catch (e) {
      debugPrint("TelemetryManager: Error uploading location to RTDB: $e");
    }
  }
}
