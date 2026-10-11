import 'package:firebase_database/firebase_database.dart';

enum RemoteStreamCommand {
  startStream,
  stopStream,
  switchCamera,
  toggleAudioMute,
}

class StreamControlService {
  StreamControlService({
    required FirebaseDatabase database,
    required this.deviceId,
    required this.parentUid,
    required this.childId,
  }) : _database = database;

  final FirebaseDatabase _database;
  final String deviceId;
  final String parentUid;
  final String childId;

  Future<void> send(RemoteStreamCommand command) async {
    if (!_isValidDatabaseKey(deviceId) ||
        !_isValidDatabaseKey(parentUid) ||
        !_isValidDatabaseKey(childId)) {
      throw ArgumentError('Invalid device or account ID for stream control.');
    }

    final commandId = '${DateTime.now().microsecondsSinceEpoch}_$parentUid';
    await _database.ref('/devices/$deviceId/control').update({
      'deviceId': deviceId,
      'parentUid': parentUid,
      'childId': childId,
      'commandId': commandId,
      'command': command.name,
      'requestedBy': parentUid,
      'requestedAt': ServerValue.timestamp,
    });
  }

  bool _isValidDatabaseKey(String value) {
    return value.isNotEmpty && !RegExp(r'[.#$\[\]/]').hasMatch(value);
  }
}
