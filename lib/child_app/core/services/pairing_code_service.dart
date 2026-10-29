import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

class PairingCodeService {
  static const int codeLength = 4;
  static const int codeValidityMinutes = 5; // Code expires in 5 minutes
  static const String tag = "PairingCodeService";

  /// Generates a cryptographically secure 4-digit numeric binding code.
  static String generateCode() {
    final rand = Random.secure();
    final digits = List.generate(codeLength, (_) => rand.nextInt(10));
    return digits.join();
  }

  /// Creates child device binding node with expiration timestamp.
  static Future<String?> createChildBinding({
    required String deviceId,
    required String uid,
  }) async {
    try {
      final db = FirebaseDatabase.instance.ref();
      final code = generateCode();
      final now = DateTime.now().millisecondsSinceEpoch;
      final expiresAt = now + (codeValidityMinutes * 60 * 1000);

      await db.child('devices').child(deviceId).set({
        'bindingCode': code,
        'childUid': uid,
        'status': 'pending_parent_bind',
        'createdAt': now,
        'expiresAt': expiresAt,
      });

      debugPrint("$tag: Successfully generated pairing code $code for device $deviceId");
      return code;
    } catch (e) {
      debugPrint("$tag: Error creating child binding: $e");
      return null;
    }
  }

  /// Finds Device ID dynamically by matching the 4-digit code entered by parent.
  static Future<String?> findDeviceIdByCode(String enteredCode) async {
    try {
      final db = FirebaseDatabase.instance.ref();
      final snapshot = await db.child('devices').get();

      if (!snapshot.exists || snapshot.value == null) return null;

      final rawValue = snapshot.value;
      if (rawValue is! Map) return null;

      final devicesMap = Map<String, dynamic>.from(rawValue);
      final now = DateTime.now().millisecondsSinceEpoch;

      for (var entry in devicesMap.entries) {
        final deviceId = entry.key;
        if (entry.value is! Map) continue;
        final data = Map<String, dynamic>.from(entry.value as Map);
        
        final validCode = data['bindingCode'] as String?;
        final expiresAt = (data['expiresAt'] as num?)?.toInt() ?? 0;
        final status = data['status'] as String?;

        // Check if code matches, is not null, hasn't expired, and is pending bind
        if (validCode == enteredCode && status == 'pending_parent_bind') {
          if (now <= expiresAt) {
            debugPrint("$tag: Valid device found for code: $deviceId");
            return deviceId;
          } else {
            debugPrint("$tag: Pairing code expired for device: $deviceId");
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint("$tag: Error finding device by code: $e");
      return null;
    }
  }

  /// Binds parent to the child device using verified 4-digit code.
  static Future<bool> bindParentToDevice({
    required String deviceId,
    required String parentUid,
    required String enteredCode,
  }) async {
    try {
      final db = FirebaseDatabase.instance.ref();
      final snapshot = await db.child('devices').child(deviceId).get();

      if (!snapshot.exists || snapshot.value == null) return false;

      final rawValue = snapshot.value;
      if (rawValue is! Map) return false;

      final data = Map<String, dynamic>.from(rawValue);
      final validCode = data['bindingCode'] as String?;
      final expiresAt = (data['expiresAt'] as num?)?.toInt() ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      // Validate code and expiration
      if (validCode == null || validCode != enteredCode || now > expiresAt) {
        debugPrint("$tag: Invalid or expired pairing code attempt.");
        return false;
      }

      // Update device binding status and clear binding code for security
      await db.child('devices').child(deviceId).update({
        'parentUid': parentUid,
        'status': 'bound',
        'boundAt': ServerValue.timestamp,
        'bindingCode': null, // One-time use security cleanup
        'expiresAt': null,
      });

      // Map device under parent's profile
      await db.child('parents').child(parentUid).child('devices').child(deviceId).set({
        'boundAt': ServerValue.timestamp,
        'deviceId': deviceId,
      });

      debugPrint("$tag: Successfully bound parent $parentUid to device $deviceId");
      return true;
    } catch (e) {
      debugPrint("$tag: Error during parent device binding: $e");
      return false;
    }
  }

  /// Convenience method: Resolves device by code and binds in a single operation
  static Future<bool> bindParentByCode({
    required String parentUid,
    required String enteredCode,
  }) async {
    final deviceId = await findDeviceIdByCode(enteredCode);
    if (deviceId == null) return false;
    return await bindParentToDevice(
      deviceId: deviceId,
      parentUid: parentUid,
      enteredCode: enteredCode,
    );
  }
}
