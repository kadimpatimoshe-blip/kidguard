/// Pairing state and device identity model
class PairingStateModel {
  final String deviceId;
  final String pairingCode;
  final bool isPaired;
  final String status; // 'pending' | 'paired' | 'regenerated' | 'expired'
  final int createdAt;
  final int expiresAt;
  final String? parentUid;

  PairingStateModel({
    required this.deviceId,
    required this.pairingCode,
    this.isPaired = false,
    this.status = 'pending',
    int? createdAt,
    int? expiresAt,
    this.parentUid,
  })  : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        expiresAt = expiresAt ?? (DateTime.now().millisecondsSinceEpoch + (300 * 1000));

  bool get isExpired => DateTime.now().millisecondsSinceEpoch > expiresAt;
  int get secondsRemaining => ((expiresAt - DateTime.now().millisecondsSinceEpoch) / 1000).clamp(0, 300).toInt();

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'pairingCode': pairingCode,
    'isPaired': isPaired,
    'status': status,
    'createdAt': createdAt,
    'expiresAt': expiresAt,
    if (parentUid != null) 'parentUid': parentUid,
  };

  PairingStateModel copyWith({
    String? deviceId,
    String? pairingCode,
    bool? isPaired,
    String? status,
    int? createdAt,
    int? expiresAt,
    String? parentUid,
  }) => PairingStateModel(
    deviceId: deviceId ?? this.deviceId,
    pairingCode: pairingCode ?? this.pairingCode,
    isPaired: isPaired ?? this.isPaired,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    expiresAt: expiresAt ?? this.expiresAt,
    parentUid: parentUid ?? this.parentUid,
  );
}

/// Remote parent command sent over /devices/{pairingCode}/control or /devices/{deviceId}/control
class RemoteCommandPayload {
  final String commandId;
  final String command; // 'startStream' | 'stopStream' | 'switchCamera' | 'toggleAudioMute' | 'startScreenShare' | 'stopScreenShare'
  final String? cameraFacing; // 'front' | 'back'
  final String requestedBy;
  final int requestedAt;

  RemoteCommandPayload({
    required this.commandId,
    required this.command,
    this.cameraFacing,
    required this.requestedBy,
    required this.requestedAt,
  });

  factory RemoteCommandPayload.fromJson(Map<String, dynamic> json) => RemoteCommandPayload(
    commandId: json['commandId'] as String? ?? '',
    command: json['command'] as String? ?? '',
    cameraFacing: json['cameraFacing'] as String?,
    requestedBy: json['requestedBy'] as String? ?? 'Parent Console',
    requestedAt: json['requestedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
  );
}
