import 'package:flutter_test/flutter_test.dart';
import 'package:kidguard/features/dashboard/models/parent_child_device.dart';

void main() {
  group('ParentChildDevice.fromMap', () {
    const record = {
      'childId': 'child-123',
      'pairingCode': '1234',
      'status': 'paired',
      'timestamp': '2026-10-09T08:00:00.000Z',
    };

    test('maps required fields and ignores additional metadata', () {
      final device = ParentChildDevice.fromMap({
        ...record,
        'metadata': 'additional field',
      });

      expect(device.childId, 'child-123');
      expect(device.pairingCode, '1234');
      expect(device.status, 'paired');
      expect(device.timestamp, '2026-10-09T08:00:00.000Z');
    });

    test('normalizes numeric pairing codes and epoch timestamps', () {
      final device = ParentChildDevice.fromMap({
        ...record,
        'pairingCode': 1234,
        'timestamp': 1791532800000,
      });

      expect(device.pairingCode, '1234');
      expect(device.timestamp, '2026-10-09T08:00:00.000Z');
    });

    test('normalizes integer and short numeric pairing codes', () {
      final numeric = ParentChildDevice.fromMap({
        ...record,
        'pairingCode': 1234,
      });
      final integralDouble = ParentChildDevice.fromMap({
        ...record,
        'pairingCode': 1234.0,
      });
      final shortNumeric = ParentChildDevice.fromMap({
        ...record,
        'pairingCode': 123,
      });

      expect(numeric.pairingCode, '1234');
      expect(integralDouble.pairingCode, '1234');
      expect(shortNumeric.pairingCode, '0123');
    });

    test('trims string pairing codes and preserves leading zeroes', () {
      final device = ParentChildDevice.fromMap({
        ...record,
        'pairingCode': ' 0123 ',
      });

      expect(device.pairingCode, '0123');
    });

    test('normalizes epoch timestamps expressed in seconds', () {
      final device = ParentChildDevice.fromMap({
        ...record,
        'timestamp': 1791532800,
      });

      expect(device.timestamp, '2026-10-09T08:00:00.000Z');
    });

    test('maps canonical pending pairing records', () {
      final createdAt = DateTime.now().toUtc().toIso8601String();
      final device = ParentChildDevice.fromMap({
        'deviceId': 'device-123',
        'pairingCode': '4321',
        'status': 'pending',
        'createdAt': createdAt,
        'lastSeen': createdAt,
      });

      expect(device.childId, 'device-123');
      expect(device.pairingCode, '4321');
      expect(device.status, 'pending');
      expect(device.timestamp, createdAt);
      expect(device.lastHeartbeat, DateTime.parse(createdAt));
    });

    test('falls back to canonical fields when legacy fields are missing', () {
      final createdAt = DateTime.now().toUtc().toIso8601String();
      final device = ParentChildDevice.fromMap({
        'deviceId': 'device-456',
        'pairingCode': '5678',
        'createdAt': createdAt,
      });

      expect(device.childId, 'device-456');
      expect(device.status, 'pending');
      expect(device.timestamp, createdAt);
    });

    test('uses safe defaults when child ID and timestamps are missing', () {
      final beforeParsing = DateTime.now().toUtc();
      final device = ParentChildDevice.fromMap({
        'pairingCode': '5678',
      });

      expect(device.childId, isEmpty);
      expect(device.status, 'pending');
      expect(DateTime.parse(device.timestamp).isUtc, isTrue);
      expect(
        DateTime.parse(device.timestamp).isAfter(beforeParsing) ||
            DateTime.parse(device.timestamp).isAtSameMomentAs(beforeParsing),
        isTrue,
      );
    });

    test('maps pending records without a pairing code', () {
      final missingCode = ParentChildDevice.fromMap({
        'deviceId': 'device-pending',
        'status': 'pending',
      });
      final emptyCode = ParentChildDevice.fromMap({
        'deviceId': 'device-pending-empty',
        'pairingCode': '  ',
        'status': 'pending',
      });

      expect(missingCode.pairingCode, isEmpty);
      expect(emptyCode.pairingCode, isEmpty);
      expect(missingCode.status, 'pending');
      expect(emptyCode.status, 'pending');
    });

    test('retains the Firebase device key for unlinking', () {
      final device = ParentChildDevice.fromMap({
        'status': 'pending',
      }, deviceKey: 'firebase-device-key');

      expect(device.childId, isEmpty);
      expect(device.deviceKey, 'firebase-device-key');
    });

    test('maps child identity, presence, and telemetry', () {
      final now = DateTime.fromMillisecondsSinceEpoch(
        DateTime.now().millisecondsSinceEpoch,
        isUtc: true,
      );
      final device = ParentChildDevice.fromMap({
        ...record,
        'childUid': 'child-user-uid',
        'presence': {
          'online': true,
          'heartbeatAt': now.millisecondsSinceEpoch,
          'lastSeen': now.millisecondsSinceEpoch,
        },
        'telemetry': {
          'platform': 'android',
          'appState': 'resumed',
        },
      });

      expect(device.childUid, 'child-user-uid');
      expect(device.isOnline, isTrue);
      expect(device.lastHeartbeat, now);
      expect(device.platform, 'android');
      expect(device.appState, 'resumed');
    });

    test('retains the signaling device ID in paired child records', () {
      final device = ParentChildDevice.fromMap({
        ...record,
        'deviceId': 'child-auth-uid',
        'childUid': 'child-auth-uid',
      });

      expect(device.deviceId, 'child-auth-uid');
      expect(device.childUid, 'child-auth-uid');
      expect(device.toMap()['deviceId'], 'child-auth-uid');
    });

    test('accepts recent ISO 8601 UTC lastSeen values', () {
      final lastSeen = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 2))
          .toIso8601String();
      final device = ParentChildDevice.fromMap({
        ...record,
        'presence': {
          'online': true,
          'lastSeen': lastSeen,
        },
      });

      expect(device.isOnline, isTrue);
    });

    test('reports offline when lastSeen is stale even if online flag is true',
        () {
      final staleLastSeen = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 4))
          .millisecondsSinceEpoch;
      final device = ParentChildDevice.fromMap({
        ...record,
        'presence': {
          'online': true,
          'lastSeen': staleLastSeen,
        },
      });

      expect(device.isOnline, isFalse);
    });

    test('requires a recent lastSeen even when an online flag is true', () {
      final device = ParentChildDevice.fromMap({
        ...record,
        'presence': {'online': true},
      });

      expect(device.isOnline, isFalse);
    });

    test('uses isOnline presence flag when online is false and lastSeen recent',
        () {
      final lastSeen = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch;
      final device = ParentChildDevice.fromMap({
        ...record,
        'presence': {
          'isOnline': true,
          'online': false,
          'lastSeen': lastSeen,
        },
      });

      expect(device.isOnline, isTrue);
    });

    test('reports online when lastSeen is recent even if flags are false', () {
      final lastSeen = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch;
      final device = ParentChildDevice.fromMap({
        ...record,
        'presence': {'online': false, 'lastSeen': lastSeen},
      });

      expect(device.isOnline, isTrue);
      expect(device.lastHeartbeat, isNotNull);
    });

    test('reports offline when lastSeen is older than three minutes', () {
      final lastSeen = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 4))
          .millisecondsSinceEpoch;
      final device = ParentChildDevice.fromMap({
        ...record,
        'presence': {'online': false, 'lastSeen': lastSeen},
      });

      expect(device.isOnline, isFalse);
    });

    test('rejects records without a usable pairing code', () {
      expect(
        () => ParentChildDevice.fromMap({
          'childId': 'child-123',
          'status': 'paired',
        }),
        throwsFormatException,
      );
      expect(
        () => ParentChildDevice.fromMap({
          ...record,
          'pairingCode': '  ',
          'status': 'paired',
        }),
        throwsFormatException,
      );
    });

    test('rejects pairing codes with incompatible types', () {
      expect(
        () => ParentChildDevice.fromMap({
          ...record,
          'pairingCode': true,
        }),
        throwsFormatException,
      );
    });
  });
}
