import '../../child_app/data/models/telemetry_payload.dart';

/// Real-Time Child Device Telemetry Model for Parent Console
/// Bound directly to Firebase Realtime Database node: `/devices/{pairingCode}`
class ChildDevice {
  final String childId;
  final String deviceId;
  final String pairingCode;
  final String deviceModelName;
  final String platform;
  final String status;
  final bool isOnline;
  final int? lastSeen;
  final int? heartbeatAt;

  // Real-Time Battery Telemetry (/devices/{pairingCode}/telemetry/battery)
  final int batteryLevel;
  final bool isCharging;
  final String batteryState; // 'charging', 'discharging', 'full', 'unknown'
  final double batteryVoltage;
  final double batteryTemp;
  final String batteryHealth;
  final bool powerSaveMode;
  final int? batteryUpdatedAt;

  // Real-Time Live Location (/devices/{pairingCode}/location)
  final double latitude;
  final double longitude;
  final double accuracy;
  final double speed;
  final String address;
  final int? locationTimestamp;
  final bool hasValidGps;

  // Real WebRTC & Media Streaming States
  final bool isScreenMirroring;
  final bool isCameraStreaming;
  final bool isAudioStreaming;
  final String screenActiveApp;
  final int screenFps;
  final String cameraFacing;
  final String? screenFrameBase64;

  // Real Activity Lists from RTDB
  final List<NotificationPayload> notifications;
  final List<CallLogPayload> callLogs;
  final List<AppUsagePayload> appUsage;

  ChildDevice({
    required this.childId,
    required this.deviceId,
    required this.pairingCode,
    required this.deviceModelName,
    this.platform = 'android',
    this.status = 'paired',
    this.isOnline = true,
    this.lastSeen,
    this.heartbeatAt,
    this.batteryLevel = 100,
    this.isCharging = false,
    this.batteryState = 'unknown',
    this.batteryVoltage = 4.1,
    this.batteryTemp = 28.0,
    this.batteryHealth = 'Good (Li-ion)',
    this.powerSaveMode = false,
    this.batteryUpdatedAt,
    this.latitude = 0.0,
    this.longitude = 0.0,
    this.accuracy = 0.0,
    this.speed = 0.0,
    this.address = '',
    this.locationTimestamp,
    this.hasValidGps = false,
    this.isScreenMirroring = false,
    this.isCameraStreaming = false,
    this.isAudioStreaming = false,
    this.screenActiveApp = 'HomeScreen',
    this.screenFps = 12,
    this.cameraFacing = 'back',
    this.screenFrameBase64,
    this.notifications = const [],
    this.callLogs = const [],
    this.appUsage = const [],
  });

  /// Factory constructor to parse real Firebase RTDB snapshot at `/devices/{key}`
  factory ChildDevice.fromMap(String key, Map<String, dynamic> data) {
    // 1. Telemetry nodes
    final telemetry = (data['telemetry'] as Map<String, dynamic>?) ?? {};
    final batteryNode = (telemetry['battery'] as Map<String, dynamic>?) ?? {};
    final locationNode = (data['location'] as Map<String, dynamic>?) ?? {};
    final presenceNode = (data['presence'] as Map<String, dynamic>?) ?? {};
    final screenNode = (data['screen'] as Map<String, dynamic>?) ?? {};
    final streamNode = (data['stream'] as Map<String, dynamic>?) ?? {};
    final audioNode = (data['audio'] as Map<String, dynamic>?) ?? {};

    // 2. Battery Telemetry extraction
    final level = (batteryNode['level'] as num?)?.toInt() ??
        (batteryNode['batteryLevel'] as num?)?.toInt() ??
        (telemetry['batteryLevel'] as num?)?.toInt() ??
        (data['batteryLevel'] as num?)?.toInt() ??
        -1;

    final charging = (batteryNode['isCharging'] as bool?) ??
        (telemetry['isCharging'] as bool?) ??
        (data['isCharging'] as bool?) ??
        false;

    final stateStr = batteryNode['state']?.toString() ??
        (charging ? 'charging' : 'discharging');

    final voltage = (batteryNode['voltage'] as num?)?.toDouble() ?? 4.10;
    final temp = (batteryNode['temperature'] as num?)?.toDouble() ?? 28.5;
    final health = batteryNode['health']?.toString() ?? 'Good (Li-ion)';
    final powerSave = (batteryNode['powerSaveMode'] as bool?) ??
        (telemetry['powerSaveMode'] as bool?) ??
        false;
    final batUpdated = (batteryNode['updatedAt'] as num?)?.toInt() ??
        (telemetry['updatedAt'] as num?)?.toInt();

    // 3. Location extraction
    final lat = (locationNode['latitude'] as num?)?.toDouble() ?? 0.0;
    final lng = (locationNode['longitude'] as num?)?.toDouble() ?? 0.0;
    final spd = (locationNode['speed'] as num?)?.toDouble() ?? 0.0;
    final acc = (locationNode['accuracy'] as num?)?.toDouble() ?? 0.0;
    final addr = locationNode['address']?.toString() ?? '';
    final locTimestamp = (locationNode['timestamp'] as num?)?.toInt();
    final validGps = lat != 0.0 || lng != 0.0 || addr.isNotEmpty;

    // 4. Status & Presence extraction
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastSeenMs = (presenceNode['lastSeen'] as num?)?.toInt() ??
        (data['lastSeen'] as num?)?.toInt() ??
        (data['lastHeartbeat'] as num?)?.toInt();
    final heartbeatMs = (presenceNode['heartbeatAt'] as num?)?.toInt() ??
        (data['heartbeatAt'] as num?)?.toInt();

    final rawOnline = presenceNode['online'] == true ||
        data['status'] == 'active' ||
        data['status'] == 'paired';
    // Consider offline if no heartbeat/presence for more than 120 seconds
    final isRecentlyActive = lastSeenMs != null && (now - lastSeenMs) < 120000;
    final online = rawOnline && (lastSeenMs == null || isRecentlyActive);

    // 5. WebRTC streaming nodes
    final screenStatus = screenNode['status']?.toString().toLowerCase() ?? '';
    final screenSharing = screenNode['isSharing'] == true ||
        screenStatus == 'mirroring' ||
        screenStatus == 'streaming';
    final screenApp = screenNode['activeApp']?.toString() ?? 'Active Screen';
    final screenFpsVal = (screenNode['fps'] as num?)?.toInt() ?? 12;
    final screenFrame = screenNode['frame']?.toString();

    final camStatus = streamNode['status']?.toString().toLowerCase() ?? '';
    final camStreaming = camStatus == 'active' || camStatus == 'streaming';
    final camFacing = streamNode['cameraFacing']?.toString() ?? 'back';

    final audioStatus = audioNode['status']?.toString().toLowerCase() ?? '';
    final audioStreaming = audioNode['isTransmitting'] == true ||
        audioStatus == 'transmitting';

    // 6. Dynamic Activity Lists
    final notifsList = _parseNotifications(data['notifications']);
    final callsList = _parseCallLogs(data['callLogs']);
    final usageList = _parseAppUsage(data['appUsage']);

    final code = data['pairingCode']?.toString() ?? key;
    final model = data['deviceModelName']?.toString() ??
        data['deviceName']?.toString() ??
        telemetry['deviceModelName']?.toString() ??
        "Child's Device";

    return ChildDevice(
      childId: data['deviceId']?.toString() ?? key,
      deviceId: data['deviceId']?.toString() ?? key,
      pairingCode: code,
      deviceModelName: model,
      platform: data['platform']?.toString() ?? 'android',
      status: data['status']?.toString() ?? 'paired',
      isOnline: online,
      lastSeen: lastSeenMs,
      heartbeatAt: heartbeatMs,
      batteryLevel: level >= 0 ? level : 0,
      isCharging: charging,
      batteryState: stateStr,
      batteryVoltage: voltage,
      batteryTemp: temp,
      batteryHealth: health,
      powerSaveMode: powerSave,
      batteryUpdatedAt: batUpdated,
      latitude: lat,
      longitude: lng,
      accuracy: acc,
      speed: spd,
      address: addr,
      locationTimestamp: locTimestamp,
      hasValidGps: validGps,
      isScreenMirroring: screenSharing,
      isCameraStreaming: camStreaming,
      isAudioStreaming: audioStreaming,
      screenActiveApp: screenApp,
      screenFps: screenFpsVal,
      cameraFacing: camFacing,
      screenFrameBase64: screenFrame,
      notifications: notifsList,
      callLogs: callsList,
      appUsage: usageList,
    );
  }

  static List<NotificationPayload> _parseNotifications(dynamic raw) {
    if (raw == null) return const [];
    final list = <NotificationPayload>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          list.add(NotificationPayload.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    } else if (raw is Map) {
      for (final item in raw.values) {
        if (item is Map) {
          list.add(NotificationPayload.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    // Sort newest first
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  static List<CallLogPayload> _parseCallLogs(dynamic raw) {
    if (raw == null) return const [];
    final list = <CallLogPayload>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          list.add(CallLogPayload.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    } else if (raw is Map) {
      for (final item in raw.values) {
        if (item is Map) {
          list.add(CallLogPayload.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  static List<AppUsagePayload> _parseAppUsage(dynamic raw) {
    if (raw == null) return const [];
    final list = <AppUsagePayload>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          list.add(AppUsagePayload.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    } else if (raw is Map) {
      for (final item in raw.values) {
        if (item is Map) {
          list.add(AppUsagePayload.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    list.sort((a, b) => b.hoursUsed.compareTo(a.hoursUsed));
    return list;
  }
}
