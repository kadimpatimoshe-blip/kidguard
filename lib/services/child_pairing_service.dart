import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import 'pairing_code_expiration.dart';

class ChildPairingCode {
  const ChildPairingCode({
    required this.code,
    required this.childId,
    required this.deviceId,
  });

  final String code;
  final String childId;
  final String deviceId;
}

class ChildPairingService {
  ChildPairingService({
    required FirebaseAuth auth,
    required FirebaseDatabase database,
  })  : _auth = auth,
        _database = database;

  final FirebaseAuth _auth;
  final FirebaseDatabase _database;
  final Random _random = Random.secure();

  Future<ChildPairingCode> createPairingCode() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw StateError(
          'Authenticate before creating a pairing code.',
        );
      }

      final childId = _createChildId();
      final childUid = user.uid;
      final deviceId = user.uid;
      if (deviceId.isEmpty || RegExp(r'[.#$\[\]/]').hasMatch(deviceId)) {
        throw StateError('The child account ID is not a valid database key.');
      }
      final createdAt = DateTime.now().toUtc().toIso8601String();

      for (var attempt = 0; attempt < 20; attempt++) {
        final code = (1000 + _random.nextInt(9000)).toString();
        final codeMatches = await _database
            .ref('/pairing_codes')
            .orderByChild('pairingCode')
            .equalTo(code)
            .get();
        if (codeMatches.children.any(
          (match) => match.key != deviceId,
        )) {
          continue;
        }

        final reference = _database.ref('/pairing_codes/$deviceId');
        final result = await reference.runTransaction((currentData) {
          return Transaction.success({
            'deviceId': deviceId,
            'childId': childId,
            'childUid': childUid,
            'pairingCode': code,
            'status': 'pending',
            'createdAt': createdAt,
            'lastSeen': createdAt,
            'timestamp': createdAt,
          });
        }, applyLocally: false);

        if (result.committed) {
          return ChildPairingCode(
            code: code,
            childId: childId,
            deviceId: deviceId,
          );
        }
      }

      throw StateError('Could not reserve a unique pairing code. Try again.');
    } on FirebaseException catch (error, stackTrace) {
      debugPrint('Firebase pairing-code creation failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> removeExpiredPairingCode(String code, String deviceId) async {
    final path = '/pairing_codes/$deviceId';
    try {
      final reference = _database.ref(path);
      final result = await reference.runTransaction((currentData) {
        if (currentData is! Map) return Transaction.abort();

        final record = Map<String, Object?>.from(currentData);
        final timestamp = record['createdAt'] ?? record['timestamp'];
        final isExpired = record['status'] == 'expired' ||
            ((record['status'] == 'pending' || record['status'] == 'waiting') &&
                timestamp is String &&
                isPairingCodeExpired(timestamp));
        if (record['deviceId'] != deviceId ||
            record['pairingCode'] != code ||
            !isExpired) {
          return Transaction.abort();
        }

        return Transaction.success(null);
      }, applyLocally: false);

      if (!result.committed) {
        debugPrint('Expired pairing code cleanup skipped at $path');
      }
    } on FirebaseException catch (error, stackTrace) {
      debugPrint('Expired pairing code cleanup failed at $path: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> removePairedPairingCode(
    String code,
    String childId,
    String deviceId,
  ) async {
    final path = '/pairing_codes/$deviceId';
    try {
      final reference = _database.ref(path);
      final result = await reference.runTransaction((currentData) {
        if (currentData is! Map) return Transaction.abort();

        final record = Map<String, Object?>.from(currentData);
        if (record['deviceId'] != deviceId ||
            record['pairingCode'] != code ||
            record['childId'] != childId ||
            record['status'] != 'paired') {
          return Transaction.abort();
        }

        return Transaction.success(null);
      }, applyLocally: false);

      if (!result.committed) {
        debugPrint('Paired pairing-code cleanup skipped at $path');
      }
    } on FirebaseException catch (error, stackTrace) {
      debugPrint('Paired pairing-code cleanup failed at $path: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  String _createChildId() {
    return List.generate(
      16,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}
