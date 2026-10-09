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
      final pairingPath = 'pairing_codes/$code';
      final pairingReference = _database.ref(pairingPath);
      debugPrint(
        'Reading pairing code at Firebase path: ${pairingReference.path}',
      );
      final pairingSnapshot = await _logDatabaseOperation(
        'read pairing code',
        pairingPath,
        pairingReference.get,
      );
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
          pairingDevice.status != 'waiting') {
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

      final childPath =
          'parents/$_parentUid/children/${pairingDevice.childId}';
      final device = ParentChildDevice(
        childId: pairingDevice.childId,
        pairingCode: pairingDevice.pairingCode,
        status: 'paired',
        timestamp: DateTime.now().toUtc().toIso8601String(),
      );
      debugPrint(
        'Atomically linking child at $childPath and consuming code '
        'at $pairingPath',
      );
      await _logDatabaseOperation(
        'atomically link child and consume pairing code',
        '$childPath, $pairingPath',
        () => _database.ref().update({
          childPath: device.toMap(),
          pairingPath: null,
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
