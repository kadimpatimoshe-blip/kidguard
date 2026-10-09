import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import 'pairing_code_expiration.dart';

class ChildPairingService {
  ChildPairingService({
    required FirebaseAuth auth,
    required FirebaseDatabase database,
  })  : _auth = auth,
        _database = database;

  final FirebaseAuth _auth;
  final FirebaseDatabase _database;
  final Random _random = Random.secure();

  Future<String> createPairingCode() async {
    try {
      final user = _auth.currentUser;
      if (user == null || user.isAnonymous) {
        throw StateError(
          'Sign in with a child account before creating a pairing code.',
        );
      }

      final childId = _createChildId();

      for (var attempt = 0; attempt < 20; attempt++) {
        final code = (1000 + _random.nextInt(9000)).toString();
        final reference = _database.ref('/pairing_codes/$code');
        final result = await reference.runTransaction((currentData) {
          if (currentData != null) return Transaction.abort();
          return Transaction.success({
            'childId': childId,
            'pairingCode': code,
            'status': 'waiting',
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          });
        }, applyLocally: false);

        if (result.committed) return code;
      }

      throw StateError('Could not reserve a unique pairing code. Try again.');
    } on FirebaseException catch (error, stackTrace) {
      debugPrint('Firebase pairing-code creation failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> removeExpiredPairingCode(String code) async {
    final path = '/pairing_codes/$code';
    try {
      final reference = _database.ref(path);
      final result = await reference.runTransaction((currentData) {
        if (currentData is! Map) return Transaction.abort();

        final record = Map<String, Object?>.from(currentData);
        final timestamp = record['timestamp'];
        final isExpired = record['status'] == 'expired' ||
            (record['status'] == 'waiting' &&
                timestamp is String &&
                isPairingCodeExpired(timestamp));
        if (record['pairingCode'] != code || !isExpired) {
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

  String _createChildId() {
    return List.generate(
      16,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}
