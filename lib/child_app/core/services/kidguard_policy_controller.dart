import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

class KidGuardPolicyController {
  final DatabaseReference _root;

  KidGuardPolicyController({DatabaseReference? root})
      : _root = root ?? FirebaseDatabase.instance.ref();

  /// Stream listening to real-time parental policy changes under /devices/{deviceCode}/policy
  Stream<Map<String, dynamic>> listenPolicy(String deviceCode) {
    final policyRef = _root.child('devices').child(deviceCode).child('policy');

    return policyRef.onValue.map((event) {
      final raw = event.snapshot.value;
      if (raw == null || raw is! Map) {
        return <String, dynamic>{
          'appLockEnabled': false,
          'blockedApps': <String, dynamic>{},
          'safeZones': <String, dynamic>{},
          'screenTimeLimitMinutes': 120,
        };
      }

      final map = Map<String, dynamic>.from(raw);
      
      // Normalize blockedApps map
      if (map['blockedApps'] != null && map['blockedApps'] is Map) {
        map['blockedApps'] = Map<String, dynamic>.from(map['blockedApps'] as Map);
      } else if (map['blockedApps'] != null && map['blockedApps'] is List) {
        // Handle list representation
        final list = map['blockedApps'] as List;
        final converted = <String, bool>{};
        for (final item in list) {
          if (item != null) converted[item.toString()] = true;
        }
        map['blockedApps'] = converted;
      }

      // Normalize safeZones map
      if (map['safeZones'] != null && map['safeZones'] is Map) {
        map['safeZones'] = Map<String, dynamic>.from(map['safeZones'] as Map);
      }

      return map;
    });
  }

  /// One-time fetch of current policy for deviceCode
  Future<Map<String, dynamic>?> getPolicy(String deviceCode) async {
    try {
      final snapshot = await _root.child('devices').child(deviceCode).child('policy').get();
      if (!snapshot.exists || snapshot.value == null || snapshot.value is! Map) {
        return null;
      }
      return Map<String, dynamic>.from(snapshot.value as Map);
    } catch (e) {
      debugPrint("KidGuardPolicyController: Error getting policy: $e");
      return null;
    }
  }

  /// Sets or updates the appLockEnabled flag
  Future<bool> setAppLockEnabled(String deviceCode, bool enabled) async {
    try {
      await _root.child('devices').child(deviceCode).child('policy').update({
        'appLockEnabled': enabled,
        'updatedAt': ServerValue.timestamp,
      });
      return true;
    } catch (e) {
      debugPrint("KidGuardPolicyController: Error updating appLockEnabled: $e");
      return false;
    }
  }

  /// Sets the full map of blocked applications
  Future<bool> setBlockedApps(String deviceCode, Map<String, bool> blockedApps) async {
    try {
      await _root.child('devices').child(deviceCode).child('policy').child('blockedApps').set(blockedApps);
      await _root.child('devices').child(deviceCode).child('policy').update({
        'updatedAt': ServerValue.timestamp,
      });
      return true;
    } catch (e) {
      debugPrint("KidGuardPolicyController: Error setting blockedApps: $e");
      return false;
    }
  }

  /// Toggles blocking state for a single package
  Future<bool> toggleBlockedApp(String deviceCode, String packageName, bool isBlocked) async {
    try {
      final ref = _root.child('devices').child(deviceCode).child('policy').child('blockedApps').child(packageName);
      if (isBlocked) {
        await ref.set(true);
      } else {
        await ref.remove();
      }
      await _root.child('devices').child(deviceCode).child('policy').update({
        'updatedAt': ServerValue.timestamp,
      });
      return true;
    } catch (e) {
      debugPrint("KidGuardPolicyController: Error toggling blocked app $packageName: $e");
      return false;
    }
  }

  /// Updates arbitrary policy properties
  Future<bool> updatePolicy(String deviceCode, Map<String, dynamic> policyUpdates) async {
    try {
      final updates = Map<String, dynamic>.from(policyUpdates);
      updates['updatedAt'] = ServerValue.timestamp;
      await _root.child('devices').child(deviceCode).child('policy').update(updates);
      return true;
    } catch (e) {
      debugPrint("KidGuardPolicyController: Error updating policy: $e");
      return false;
    }
  }
}
