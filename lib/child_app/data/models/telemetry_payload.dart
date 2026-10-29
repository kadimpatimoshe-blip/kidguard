import 'dart:convert';

/// GPS Location payload matching Firebase RTDB path /devices/{pairingCode}/location
class LocationPayload {
  final double latitude;
  final double longitude;
  final double accuracy;
  final String address;
  final double speed;
  final int timestamp;

  LocationPayload({
    required this.latitude,
    required this.longitude,
    this.accuracy = 10.0,
    this.address = '',
    this.speed = 0.0,
    int? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'address': address,
    'speed': speed,
    'timestamp': timestamp,
    'updatedAt': DateTime.now().toIso8601String(),
  };

  factory LocationPayload.fromJson(Map<String, dynamic> json) => LocationPayload(
    latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
    longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
    accuracy: (json['accuracy'] as num?)?.toDouble() ?? 10.0,
    address: json['address'] as String? ?? '',
    speed: (json['speed'] as num?)?.toDouble() ?? 0.0,
    timestamp: json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
  );
}

/// Call Log Item payload matching Firebase RTDB path /devices/{pairingCode}/callLogs
class CallLogPayload {
  final String id;
  final String name;
  final String number;
  final String type; // 'incoming' | 'outgoing' | 'missed'
  final int duration; // in seconds
  final int timestamp;

  CallLogPayload({
    required this.id,
    required this.name,
    required this.number,
    required this.type,
    required this.duration,
    int? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'number': number,
    'type': type,
    'duration': duration,
    'timestamp': timestamp,
  };

  factory CallLogPayload.fromJson(Map<String, dynamic> json) => CallLogPayload(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? 'Unknown Contact',
    number: json['number'] as String? ?? '',
    type: json['type'] as String? ?? 'incoming',
    duration: (json['duration'] as num?)?.toInt() ?? 0,
    timestamp: json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
  );
}

/// App Usage Item payload matching Firebase RTDB path /devices/{pairingCode}/appUsage
class AppUsagePayload {
  final String id;
  final String appName;
  final String packageName;
  final double hoursUsed;
  final String durationText;
  final String category;
  final String icon;
  final String color;
  final int? lastTimeUsed;

  AppUsagePayload({
    required this.id,
    required this.appName,
    required this.packageName,
    required this.hoursUsed,
    required this.durationText,
    required this.category,
    required this.icon,
    required this.color,
    this.lastTimeUsed,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'appName': appName,
    'packageName': packageName,
    'hoursUsed': hoursUsed,
    'durationText': durationText,
    'category': category,
    'icon': icon,
    'color': color,
    if (lastTimeUsed != null) 'lastTimeUsed': lastTimeUsed,
  };

  factory AppUsagePayload.fromJson(Map<String, dynamic> json) => AppUsagePayload(
    id: json['id'] as String? ?? json['packageName'] as String? ?? '',
    appName: json['appName'] as String? ?? 'Application',
    packageName: json['packageName'] as String? ?? '',
    hoursUsed: (json['hoursUsed'] as num?)?.toDouble() ?? 0.0,
    durationText: json['durationText'] as String? ?? '0m',
    category: json['category'] as String? ?? 'General',
    icon: json['icon'] as String? ?? 'smartphone',
    color: json['color'] as String? ?? '#6366F1',
    lastTimeUsed: json['lastTimeUsed'] as int?,
  );
}

/// Notification Item payload matching Firebase RTDB path /devices/{pairingCode}/notifications
class NotificationPayload {
  final String id;
  final String appName;
  final String packageName;
  final String title;
  final String text;
  final int timestamp;
  final String category;

  NotificationPayload({
    required this.id,
    required this.appName,
    required this.packageName,
    required this.title,
    required this.text,
    int? timestamp,
    this.category = 'system',
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
    'id': id,
    'appName': appName,
    'packageName': packageName,
    'title': title,
    'text': text,
    'timestamp': timestamp,
    'category': category,
  };

  factory NotificationPayload.fromJson(Map<String, dynamic> json) => NotificationPayload(
    id: json['id'] as String? ?? '',
    appName: json['appName'] as String? ?? 'App Alert',
    packageName: json['packageName'] as String? ?? '',
    title: json['title'] as String? ?? '',
    text: json['text'] as String? ?? '',
    timestamp: json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    category: json['category'] as String? ?? 'system',
  );
}

/// Device Status & System Telemetry
class DeviceTelemetryPayload {
  final int batteryLevel;
  final bool isCharging;
  final bool wifiConnected;
  final String platform;
  final String appState;
  final String deviceModelName;
  final String deviceManufacturer;
  final int lastSeen;

  DeviceTelemetryPayload({
    required this.batteryLevel,
    required this.isCharging,
    this.wifiConnected = true,
    this.platform = 'android',
    this.appState = 'resumed',
    required this.deviceModelName,
    this.deviceManufacturer = 'Android',
    int? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
    'batteryLevel': batteryLevel,
    'isCharging': isCharging,
    'wifiConnected': wifiConnected,
    'platform': platform,
    'appState': appState,
    'deviceModelName': deviceModelName,
    'deviceManufacturer': deviceManufacturer,
    'lastSeen': lastSeen,
    'updatedAt': DateTime.now().toIso8601String(),
  };

  factory DeviceTelemetryPayload.fromJson(Map<String, dynamic> json) => DeviceTelemetryPayload(
    batteryLevel: (json['batteryLevel'] as num?)?.toInt() ?? 100,
    isCharging: json['isCharging'] as bool? ?? false,
    wifiConnected: json['wifiConnected'] as bool? ?? true,
    platform: json['platform'] as String? ?? 'android',
    appState: json['appState'] as String? ?? 'resumed',
    deviceModelName: json['deviceModelName'] as String? ?? 'Android Device',
    deviceManufacturer: json['deviceManufacturer'] as String? ?? 'Android',
    lastSeen: json['lastSeen'] as int? ?? DateTime.now().millisecondsSinceEpoch,
  );
}

/// Screen Frame Data payload matching Firebase RTDB path /devices/{pairingCode}/screen
class ScreenFramePayload {
  final String frame; // Base64 data URL e.g. "data:image/jpeg;base64,..."
  final String activeApp;
  final int timestamp;
  final int fps;
  final String orientation; // 'portrait' | 'landscape'
  final int battery;
  final String status; // 'streaming' | 'stopped' | 'standby'
  final String? deviceModel;
  final String source; // 'rtdb_frame'

  ScreenFramePayload({
    required this.frame,
    this.activeApp = 'KidGuard Launcher',
    int? timestamp,
    this.fps = 10,
    this.orientation = 'portrait',
    this.battery = 85,
    this.status = 'streaming',
    this.deviceModel = 'Android Device',
    this.source = 'rtdb_frame',
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
    'frame': frame,
    'activeApp': activeApp,
    'timestamp': timestamp,
    'fps': fps,
    'orientation': orientation,
    'battery': battery,
    'status': status,
    if (deviceModel != null) 'deviceModel': deviceModel,
    'source': source,
    'updatedAt': DateTime.now().toIso8601String(),
  };

  factory ScreenFramePayload.fromJson(Map<String, dynamic> json) => ScreenFramePayload(
    frame: json['frame'] as String? ?? '',
    activeApp: json['activeApp'] as String? ?? 'HomeScreen',
    timestamp: json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    fps: (json['fps'] as num?)?.toInt() ?? 10,
    orientation: json['orientation'] as String? ?? 'portrait',
    battery: (json['battery'] as num?)?.toInt() ?? 85,
    status: json['status'] as String? ?? 'streaming',
    deviceModel: json['deviceModel'] as String?,
    source: json['source'] as String? ?? 'rtdb_frame',
  );
}
