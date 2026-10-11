class ParentChildDevice {
  const ParentChildDevice({
    required this.childId,
    required this.pairingCode,
    required this.status,
    required this.timestamp,
    this.deviceId,
    this.childUid,
    this.isOnline = false,
    this.lastHeartbeat,
    this.platform,
    this.appState,
    this.deviceKey,
  });

  final String childId;
  final String pairingCode;
  final String status;
  final String timestamp;
  final String? deviceId;
  final String? childUid;
  final bool isOnline;
  final DateTime? lastHeartbeat;
  final String? platform;
  final String? appState;
  final String? deviceKey;

  factory ParentChildDevice.fromMap(
    Map<Object?, Object?> map, {
    String? deviceKey,
  }) {
    final childId = _normalizeIdentifier(map['childId']) ??
        _normalizeIdentifier(map['deviceId']) ??
        '';
    final status = map['status'] ?? 'pending';
    final normalizedPairingCode = _normalizePairingCode(map['pairingCode']);
    final timestamp = _normalizeTimestamp(map['timestamp']) ??
        _normalizeTimestamp(map['createdAt']) ??
        _normalizeTimestamp(map['lastSeen']) ??
        DateTime.now().toUtc().toIso8601String();
    final childUid = map['childUid'];
    final deviceId = map['deviceId'];
    final presence = map['presence'];
    final telemetry = map['telemetry'];

    if (status is! String) {
      throw const FormatException('Pairing record has an invalid status.');
    }
    if (normalizedPairingCode == null && status == 'paired') {
      throw const FormatException(
        'Paired device record is missing a pairingCode.',
      );
    }
    if (normalizedPairingCode == null && status != 'pending') {
      throw const FormatException('Pairing record has an invalid pairingCode.');
    }
    final pairingCode = normalizedPairingCode ?? '';
    if (childUid != null && (childUid is! String || childUid.isEmpty)) {
      throw const FormatException('Pairing record has an invalid childUid.');
    }
    if (deviceId != null && (deviceId is! String || deviceId.isEmpty)) {
      throw const FormatException('Pairing record has an invalid deviceId.');
    }
    if (presence != null && presence is! Map) {
      throw const FormatException('Pairing record has invalid presence data.');
    }
    if (telemetry != null && telemetry is! Map) {
      throw const FormatException('Pairing record has invalid telemetry data.');
    }

    final presenceMap = presence is Map ? presence : const {};
    final telemetryMap = telemetry is Map ? telemetry : const {};
    final lastSeen =
        _normalizeDateTime(presenceMap['lastSeen'] ?? map['lastSeen']);
    final lastHeartbeat =
        _normalizeDateTime(presenceMap['heartbeatAt']) ?? lastSeen;
    final isOnline = _wasRecentlySeen(lastSeen);
    final platform = telemetryMap['platform'];
    final appState = telemetryMap['appState'];
    if (platform != null && platform is! String) {
      throw const FormatException('Pairing record has an invalid platform.');
    }
    if (appState != null && appState is! String) {
      throw const FormatException('Pairing record has an invalid appState.');
    }

    return ParentChildDevice(
      childId: childId,
      pairingCode: pairingCode,
      status: status,
      timestamp: timestamp,
      deviceId: deviceId as String?,
      childUid: childUid as String?,
      isOnline: isOnline,
      lastHeartbeat: lastHeartbeat,
      platform: platform as String?,
      appState: appState as String?,
      deviceKey: deviceKey,
    );
  }

  static String? _normalizeIdentifier(Object? value) {
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  static String? _normalizePairingCode(Object? value) {
    if (value == null) return null;
    if (value is! String && value is! int && value is! double) {
      throw const FormatException('Pairing record has an invalid pairingCode.');
    }

    final code = value.toString().trim();
    if (code.isEmpty) return null;
    if (value is int && value < 0) {
      throw const FormatException('Pairing record has an invalid pairingCode.');
    }
    if (value is double) {
      if (!value.isFinite || value < 0 || value != value.truncateToDouble()) {
        throw const FormatException(
          'Pairing record has an invalid pairingCode.',
        );
      }
      return _padShortNumericPairingCode(value.toInt().toString());
    }
    return _padShortNumericPairingCode(code);
  }

  static String _padShortNumericPairingCode(String code) {
    if (RegExp(r'^\d{1,3}$').hasMatch(code)) {
      return code.padLeft(4, '0');
    }
    return code;
  }

  static String? _normalizeTimestamp(Object? value) {
    final dateTime = _normalizeDateTime(value);
    return dateTime?.toIso8601String();
  }

  static DateTime? _normalizeDateTime(Object? value) {
    if (value is String) {
      final dateTime = DateTime.tryParse(value);
      if (dateTime != null) return dateTime.toUtc();
      final numericValue = int.tryParse(value);
      if (numericValue == null) return null;
      return _dateTimeFromEpoch(numericValue);
    }
    if (value is int) return _dateTimeFromEpoch(value);
    if (value is double &&
        value.isFinite &&
        value == value.truncateToDouble()) {
      return _dateTimeFromEpoch(value.toInt());
    }
    return null;
  }

  static bool _wasRecentlySeen(DateTime? lastSeen) {
    if (lastSeen == null) return false;
    final now = DateTime.now().toUtc();
    final lastSeenUtc = lastSeen.toUtc();
    return now.difference(lastSeenUtc).inMinutes.abs() <= 3;
  }

  static DateTime? _dateTimeFromEpoch(int value) {
    final milliseconds = value.abs() < 100000000000 ? value * 1000 : value;
    try {
      return DateTime.fromMillisecondsSinceEpoch(
        milliseconds,
        isUtc: true,
      );
    } on RangeError {
      return null;
    }
  }

  Map<String, Object?> toMap() => {
        'childId': childId,
        'pairingCode': pairingCode,
        'status': status,
        'timestamp': timestamp,
        if (deviceId != null) 'deviceId': deviceId,
        if (childUid != null) 'childUid': childUid,
      };
}
