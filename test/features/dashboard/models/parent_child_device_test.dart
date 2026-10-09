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

    test('normalizes epoch timestamps expressed in seconds', () {
      final device = ParentChildDevice.fromMap({
        ...record,
        'timestamp': 1791532800,
      });

      expect(device.timestamp, '2026-10-09T08:00:00.000Z');
    });

    test('rejects missing required fields', () {
      expect(
        () => ParentChildDevice.fromMap({
          'childId': 'child-123',
          'pairingCode': '1234',
          'status': 'paired',
        }),
        throwsFormatException,
      );
    });

    test('rejects values with incompatible types', () {
      expect(
        () => ParentChildDevice.fromMap({
          ...record,
          'timestamp': true,
        }),
        throwsFormatException,
      );
    });
  });
}
