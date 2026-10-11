import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kidguard/features/dashboard/services/parent_device_service.dart';

void main() {
  group('ParentDeviceService.unlinkChildDevice', () {
    test('uses the Firebase device key when childId is empty', () async {
      final database = _FakeFirebaseDatabase();
      final service = ParentDeviceService(
        database: database,
        parentUid: 'parent-123',
      );

      await service.unlinkChildDevice(
        '',
        deviceKey: 'firebase-device-key',
      );

      expect(
        database.refPaths,
        ['parents/parent-123/children/firebase-device-key'],
      );
      expect(database.references.single.removed, isTrue);
    });

    test('rejects a missing childId and device key before creating a ref',
        () async {
      final database = _FakeFirebaseDatabase();
      final service = ParentDeviceService(
        database: database,
        parentUid: 'parent-123',
      );

      await expectLater(
        service.unlinkChildDevice(null),
        throwsArgumentError,
      );

      expect(database.refPaths, isEmpty);
    });
  });
}

class _FakeFirebaseDatabase implements FirebaseDatabase {
  final refPaths = <String?>[];
  final references = <_FakeDatabaseReference>[];

  @override
  DatabaseReference ref([String? path]) {
    refPaths.add(path);
    final reference = _FakeDatabaseReference();
    references.add(reference);
    return reference;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDatabaseReference implements DatabaseReference {
  var removed = false;

  @override
  Future<void> remove() async {
    removed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
