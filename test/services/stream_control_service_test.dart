import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kidguard/services/stream_control_service.dart';

void main() {
  group('StreamControlService', () {
    test('writes a scoped command to the device control path', () async {
      final database = _FakeFirebaseDatabase();
      final service = StreamControlService(
        database: database,
        deviceId: 'device-123',
        parentUid: 'parent-123',
        childId: 'child-123',
      );

      await service.send(RemoteStreamCommand.switchCamera);

      expect(database.reference?.path, '/devices/device-123/control');
      final command = database.reference!.updates.single;
      expect(command, containsPair('deviceId', 'device-123'));
      expect(command, containsPair('parentUid', 'parent-123'));
      expect(command, containsPair('childId', 'child-123'));
      expect(command, containsPair('command', 'switchCamera'));
      expect(command, containsPair('requestedBy', 'parent-123'));
      expect(command, containsPair('requestedAt', ServerValue.timestamp));
      expect(command['commandId'], matches(RegExp(r'^\d+_parent-123$')));
    });

    test('rejects invalid database IDs before writing', () async {
      final database = _FakeFirebaseDatabase();
      final service = StreamControlService(
        database: database,
        deviceId: 'invalid/device',
        parentUid: 'parent-123',
        childId: 'child-123',
      );

      await expectLater(
        service.send(RemoteStreamCommand.startStream),
        throwsArgumentError,
      );
      expect(database.reference, isNull);
    });
  });
}

class _FakeFirebaseDatabase implements FirebaseDatabase {
  _FakeDatabaseReference? reference;

  @override
  DatabaseReference ref([String? path]) {
    reference = _FakeDatabaseReference(path ?? '');
    return reference!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDatabaseReference implements DatabaseReference {
  _FakeDatabaseReference(this.path);

  @override
  final String path;
  final updates = <Map<String, Object?>>[];

  @override
  Future<void> update(Map<String, Object?> value) async {
    updates.add(value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
