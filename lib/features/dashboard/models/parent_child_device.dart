class ParentChildDevice {
  const ParentChildDevice({
    required this.childId,
    required this.pairingCode,
    required this.status,
    required this.timestamp,
  });

  final String childId;
  final String pairingCode;
  final String status;
  final String timestamp;

  factory ParentChildDevice.fromMap(Map<Object?, Object?> map) {
    const fields = {'childId', 'pairingCode', 'status', 'timestamp'};
    final childId = map['childId'];
    final pairingCode = _normalizePairingCode(map['pairingCode']);
    final status = map['status'];
    final timestamp = _normalizeTimestamp(map['timestamp']);

    if (!map.keys.toSet().containsAll(fields)) {
      throw const FormatException('Pairing record is missing required fields.');
    }
    if (childId is! String || childId.isEmpty) {
      throw const FormatException('Pairing record has an invalid childId.');
    }
    if (pairingCode == null) {
      throw const FormatException('Pairing record has an invalid pairingCode.');
    }
    if (status is! String) {
      throw const FormatException('Pairing record has an invalid status.');
    }
    if (timestamp == null) {
      throw const FormatException('Pairing record has an invalid timestamp.');
    }

    return ParentChildDevice(
      childId: childId,
      pairingCode: pairingCode,
      status: status,
      timestamp: timestamp,
    );
  }

  static String? _normalizePairingCode(Object? value) {
    if (value is String) return value;
    if (value is int) return value.toString();
    if (value is double && value.isFinite && value == value.truncateToDouble()) {
      return value.toInt().toString();
    }
    return null;
  }

  static String? _normalizeTimestamp(Object? value) {
    if (value is String) {
      final dateTime = DateTime.tryParse(value);
      if (dateTime != null) return dateTime.toUtc().toIso8601String();
      final numericValue = int.tryParse(value);
      if (numericValue == null) return null;
      return _timestampFromEpoch(numericValue);
    }
    if (value is int) return _timestampFromEpoch(value);
    if (value is double && value.isFinite && value == value.truncateToDouble()) {
      return _timestampFromEpoch(value.toInt());
    }
    return null;
  }

  static String? _timestampFromEpoch(int value) {
    final milliseconds = value.abs() < 100000000000 ? value * 1000 : value;
    try {
      return DateTime.fromMillisecondsSinceEpoch(
        milliseconds,
        isUtc: true,
      ).toIso8601String();
    } on RangeError {
      return null;
    }
  }

  Map<String, Object?> toMap() => {
        'childId': childId,
        'pairingCode': pairingCode,
        'status': status,
        'timestamp': timestamp,
      };
}
