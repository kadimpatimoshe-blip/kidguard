import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../models/parent_child_device.dart';
import '../../../services/pairing_code_expiration.dart';

class ParentDeviceService {
  ParentDeviceService({
    required FirebaseDatabase database,
    required String parentUid,
  })  : _database = database,
        _parentUid = parentUid;

  final FirebaseDatabase _database;
  final String _parentUid;

  Future<void> unlinkChildDevice(
    String? childId, {
    String? deviceKey,
  }) async {
    if (!_isValidDatabaseKey(_parentUid)) {
      throw StateError('The signed-in parent ID is not a valid database key.');
    }
    final recordKey =
        childId != null && _isValidDatabaseKey(childId) ? childId : deviceKey;
    if (recordKey == null || !_isValidDatabaseKey(recordKey)) {
      throw ArgumentError.value(
        childId ?? deviceKey,
        'childId',
        'A valid childId or deviceKey is required.',
      );
    }

    final childPath = 'parents/$_parentUid/children/$recordKey';
    await _logDatabaseOperation(
      'unlink child device',
      childPath,
      () => _database.ref(childPath).remove(),
    );
  }

  Future<ParentChildDevice> claimPairingCode(String input) async {
    final code = input.trim();
    if (!RegExp(r'^(?:\d{4}|\d{6})$').hasMatch(code)) {
      throw const FormatException('Enter a 4- or 6-digit pairing code.');
    }
    if (_parentUid.isEmpty) {
      throw StateError('Sign in before adding a child device.');
    }
    if (!_isValidDatabaseKey(_parentUid)) {
      throw StateError('The signed-in parent ID is not a valid database key.');
    }

    try {
      const pairingRootPath = 'pairing_codes';
      final pairingRoot = _database.ref(pairingRootPath);
      debugPrint(
        'Searching pairing codes at Firebase path: ${pairingRoot.path}',
      );
      final matchingSnapshot = await _logDatabaseOperation(
        'find pairing code',
        pairingRootPath,
        () => pairingRoot.orderByChild('pairingCode').equalTo(code).get(),
      );
      if (matchingSnapshot.children.length > 1) {
        throw StateError(
          'Pairing code is ambiguous. Generate a new code on the child device.',
        );
      }

      late final DataSnapshot pairingSnapshot;
      late final String pairingPath;
      if (matchingSnapshot.children.isNotEmpty) {
        pairingSnapshot = matchingSnapshot.children.single;
        final deviceId = pairingSnapshot.key;
        if (deviceId == null || !_isValidDatabaseKey(deviceId)) {
          throw StateError('Pairing record has an invalid deviceId.');
        }
        pairingPath = '$pairingRootPath/$deviceId';
      } else {
        pairingPath = '$pairingRootPath/$code';
        pairingSnapshot = await _logDatabaseOperation(
          'read legacy pairing code',
          pairingPath,
          () => _database.ref(pairingPath).get(),
        );
      }

      final pairingValue = pairingSnapshot.value;
      debugPrint(
        'Pairing code read completed at $pairingPath; '
        'record exists: ${pairingValue != null}',
      );
      if (pairingValue is! Map) {
        throw StateError('Pairing code is invalid or expired.');
      }
      final pairingDevice = ParentChildDevice.fromMap(pairingValue);
      if (pairingDevice.pairingCode != code ||
          (pairingDevice.status != 'pending' &&
              pairingDevice.status != 'waiting')) {
        throw StateError(
          'Pairing code is invalid, expired, or already claimed.',
        );
      }

      if (!_isValidDatabaseKey(pairingDevice.childId)) {
        throw StateError('Pairing record has an invalid childId.');
      }
      if (isPairingCodeExpired(pairingDevice.timestamp)) {
        throw StateError(
          'Pairing code has expired. Generate a new code on the child device.',
        );
      }

      final childPath = 'parents/$_parentUid/children/${pairingDevice.childId}';
      final pairedAt = DateTime.now().toUtc().toIso8601String();
      final device = ParentChildDevice(
        childId: pairingDevice.childId,
        pairingCode: pairingDevice.pairingCode,
        status: 'paired',
        timestamp: pairedAt,
        deviceId: pairingDevice.deviceId ?? pairingDevice.childUid,
        childUid: pairingDevice.childUid,
      );
      debugPrint(
        'Atomically linking child at $childPath and marking code claimed '
        'at $pairingPath',
      );
      await _logDatabaseOperation(
        'atomically link child and mark pairing code claimed',
        '$childPath, $pairingPath',
        () => _database.ref().update({
          childPath: device.toMap(),
          pairingPath: {
            'deviceId': pairingSnapshot.key ?? pairingDevice.childId,
            'childId': pairingDevice.childId,
            if (pairingDevice.childUid != null)
              'childUid': pairingDevice.childUid,
            'pairingCode': pairingDevice.pairingCode,
            'parentUid': _parentUid,
            'status': 'paired',
            'createdAt': pairingDevice.timestamp,
            'lastSeen': pairedAt,
            'timestamp': pairingDevice.timestamp,
          },
        }),
      );

      return device;
    } on FirebaseException catch (error, stackTrace) {
      debugPrint('Firebase pairing-code claim failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<T> _logDatabaseOperation<T>(
    String operation,
    String path,
    Future<T> Function() execute,
  ) async {
    try {
      debugPrint('Firebase RTDB $operation started at $path');
      final result = await execute();
      debugPrint('Firebase RTDB $operation succeeded at $path');
      return result;
    } on FirebaseException catch (error, stackTrace) {
      debugPrint(
        'Firebase RTDB $operation failed at $path: '
        '${error.message ?? error.code} ($error)',
      );
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  bool _isValidDatabaseKey(String value) {
    return value.isNotEmpty && !RegExp(r'[.#$\[\]/]').hasMatch(value);
  }
}
