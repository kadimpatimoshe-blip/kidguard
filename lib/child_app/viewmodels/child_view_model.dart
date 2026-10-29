import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' as android_plugins;
import 'package:device_info_plus/device_info_plus.dart';

import '../core/services/rtdb_client_service.dart';
import '../core/services/battery_service.dart';
import '../core/services/location_service.dart';
import '../core/services/notification_service.dart';
import '../core/services/call_log_service.dart';
import '../core/services/app_usage_service.dart';
import '../core/services/camera_stream_service.dart';
import '../core/services/screen_mirror_service.dart';
import '../core/services/audio_stream_service.dart';
import '../core/services/foreground_task_service.dart';

/// MVVM ViewModel coordinating Child Device real sensors, pairing lifecycle, and RTDB telemetry.
/// Strict production implementation: zero mock data, starts unpaired, reads real hardware sensors.
class ChildViewModel extends ChangeNotifier {
  final RtdbClientService _rtdbClient;
  final BatteryService batteryService;
  final LocationService locationService;
  final NotificationService notificationService;
  final CallLogService callLogService;
  final AppUsageService appUsageService;
  final CameraStreamService cameraStreamService;
  final ScreenMirrorService screenMirrorService;
  final AudioStreamService audioStreamService;
  final ForegroundTaskService foregroundTaskService;

  // State
  late String _deviceId;
  late String _pairingCode;
  bool _isPaired = false; // Strictly starts unpaired until claimed in RTDB
  Timer? _pairingCheckTimer;
  Timer? _heartbeatTimer;
  String? _parentUid;
  String? _childId;

  // Feature Toggles
  bool _locationEnabled = true;
  bool _notificationsEnabled = true;
  bool _appUsageEnabled = true;
  bool _callLogsEnabled = true;

  // Screen Mirroring State & Error Handling
  String? _screenMirrorError;
  bool _isRequestingScreenPermission = false;

  // Real Hardware Device Telemetry
  int? _batteryLevel;
  bool _isCharging = false;
  String _batteryStateStr = 'unknown';
  String _deviceModelName = 'Android Device (API 34)';
  String? _parentUid;
  String? _childId;
  String? _stableHardwareId;

  ChildViewModel({
    RtdbClientService? rtdbClient,
    BatteryService? batteryService,
    LocationService? locationService,
    NotificationService? notificationService,
    CallLogService? callLogService,
    AppUsageService? appUsageService,
    CameraStreamService? cameraStreamService,
    ScreenMirrorService? screenMirrorService,
    AudioStreamService? audioStreamService,
    ForegroundTaskService? foregroundTaskService,
  })  : _rtdbClient = rtdbClient ?? RtdbClientService(),
        batteryService = batteryService ?? BatteryService(),
        locationService = locationService ?? LocationService(),
        notificationService = notificationService ?? NotificationService(),
        callLogService = callLogService ?? CallLogService(),
        appUsageService = appUsageService ?? AppUsageService(),
        cameraStreamService = cameraStreamService ?? CameraStreamService(),
        screenMirrorService = screenMirrorService ?? ScreenMirrorService(),
        audioStreamService = audioStreamService ?? AudioStreamService(),
        foregroundTaskService = foregroundTaskService ?? ForegroundTaskService() {
    
    // Generate fresh FlashGet style binding code on launch: FG-XXXXXX
    _pairingCode = _generateFlashGetCode();

    // Wire up screen mirror callbacks
    this.screenMirrorService.onError = (err) {
      _screenMirrorError = err;
      notifyListeners();
    };
    this.screenMirrorService.onFrameDispatched = (_) {
      notifyListeners();
    };
    this.screenMirrorService.onStreamingStateChanged = (isStreaming) {
      notifyListeners();
    };

    // Wire up real battery sensor listener
    this.batteryService.onBatteryUpdated = (data) {
      _batteryLevel = data.level;
      _isCharging = data.isCharging;
      _batteryStateStr = data.state;
      this.screenMirrorService.updateBattery(data.level);
      notifyListeners();
    };

    // Wire up real location listener
    this.locationService.onLocationUpdated = (payload) {
      notifyListeners();
    };

    _initializeDevice();
  }

  /// Sets the authenticated user UID from the auth service to enable account-based linking
  void setAuthenticatedUser(String uid, String email) {
    _parentUid = uid;
    _guardianEmail = email;
    _guardianName = "Account Owner";
    _initializeDevice();
  }

  // Getters
  String get deviceId => _deviceId;
  String get pairingCode => _pairingCode;
  bool get isPaired => _isPaired;
  int get secondsRemaining => _secondsRemaining;
  bool get locationEnabled => _locationEnabled;
  bool get notificationsEnabled => _notificationsEnabled;
  bool get appUsageEnabled => _appUsageEnabled;
  bool get callLogsEnabled => _callLogsEnabled;
  int get batteryLevel => _batteryLevel ?? 0;
  bool get hasBatteryReading => _batteryLevel != null;
  bool get isCharging => _isCharging;
  String get batteryStateStr => _batteryStateStr;
  String get deviceModelName => _deviceModelName;
  String? get guardianName => _guardianName;
  String? get guardianPhone => _guardianPhone;
  String? get guardianEmail => _guardianEmail;

  // Real sensor readings (no static fake coordinates)
  double get latitude => locationService.lastLocation?.latitude ?? 0.0;
  double get longitude => locationService.lastLocation?.longitude ?? 0.0;
  double get speed => locationService.lastLocation?.speed ?? 0.0;
  double get accuracy => locationService.lastLocation?.accuracy ?? 0.0;
  String get locationAddress => locationService.lastLocation?.address ?? 'Awaiting real GPS hardware fix…';
  bool get hasValidLocationFix => locationService.hasValidFix;

  // Active Background Services Getters
  bool get isScreenMirroring => screenMirrorService.isScreenSharing;
  bool get isCameraStreaming => cameraStreamService.isStreaming;
  bool get isAudioStreaming => audioStreamService.isTransmitting;
  String get cameraFacing => cameraStreamService.cameraFacing;
  String? get screenMirrorError => _screenMirrorError;
  bool get isRequestingScreenPermission => _isRequestingScreenPermission;
  int get screenMirrorFps => screenMirrorService.targetFps;
  int get screenMirrorFrameCount => screenMirrorService.frameCount;

  /// Toggles remote camera stream (Parent-controlled)
  Future<void> toggleCameraStream() async {
    if (isCameraStreaming) {
      await cameraStreamService.stopStream(_pairingCode);
    } else {
      await cameraStreamService.startStream(pairingCode: _pairingCode, cameraFacing: 'back');
    }
    notifyListeners();
  }

  /// Toggles one-way audio streaming
  Future<void> toggleAudioStream() async {
    await audioStreamService.toggleAudioStream(_pairingCode);
    notifyListeners();
  }

  /// Initializes device ID, reads real physical hardware info, and starts foreground protection
  Future<void> _initializeDevice() async {
    // 1. Fetch real physical Android hardware device model and stable ID
    await _detectPhysicalHardwareInfo();

    // 2. Use stable hardware ID if available to ensure persistence after reinstall
    _deviceId = _stableHardwareId ?? 'dev_flutter_${Random().nextInt(900000) + 100000}';
    _childId = 'child_$_deviceId';

    // 3. Start Android 14 (API 34) Foreground Task Service
    await foregroundTaskService.startProtectionService(
      title: 'KidGuard Pro Protection',
      text: 'Synced with account: $_guardianEmail',
    );

    // 4. Initial Setup: Request MediaProjection & Foreground Service permissions ONCE
    await screenMirrorService.initializePermissionsOnce();

    // 5. Check if this device is already linked to the parent account in RTDB
    if (_parentUid != null) {
      final existingDevice = await _rtdbClient.getPath('parents/$_parentUid/children/$_childId');
      if (existingDevice != null && existingDevice['status'] == 'paired') {
        _isPaired = true;
        _pairingCode = existingDevice['pairingCode']?.toString() ?? _pairingCode;
        _onPairingSuccess();
        notifyListeners();
      } else {
        // Not linked yet: Check if we have an active pending bind for this account
        final pendingBinds = await _rtdbClient.getPath('pending_binds', queryParams: {
          'orderBy': 'parentUid',
          'equalTo': _parentUid!,
        });

        if (pendingBinds != null && pendingBinds is Map && pendingBinds.isNotEmpty) {
          // Use existing pending code
          final firstKey = pendingBinds.keys.first;
          _pairingCode = firstKey;
        } else {
          // Create new pending bind
          await _publishPendingBind();
        }
        _startPairingCheckTimer();
      }
    }

    _startHeartbeat();
    _subscribeToNativeNotifications();
  }

  /// Listens to native Android notifications via EventChannel
  void _subscribeToNativeNotifications() {
    const eventChannel = const android_plugins.EventChannel('com.kidguard.child/notifications');
    eventChannel.receiveBroadcastStream().listen((data) {
      if (!_notificationsEnabled || !_isPaired) return;
      if (data is Map) {
        final payload = NotificationPayload(
          title: data['title'] ?? 'No Title',
          body: data['text'] ?? 'No Text',
          packageName: data['packageName'] ?? 'unknown',
          timestamp: data['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
        );
        notificationService.pushNotification(
          pairingCode: _pairingCode,
          notification: payload,
        );
      }
    }, onError: (err) {
      debugPrint('Error in notification stream: $err');
    });
  }

  /// Detects real physical hardware brand and model using device_info_plus
  Future<void> _detectPhysicalHardwareInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final androidInfo = await deviceInfo.androidInfo;
        final brand = androidInfo.brand.isNotEmpty
            ? '${androidInfo.brand[0].toUpperCase()}${androidInfo.brand.substring(1)}'
            : 'Android';
        final sdk = androidInfo.version.sdkInt;
        _deviceModelName = '$brand $model • Android (API $sdk)';
        // Use androidId or serial if possible for stable identity
        _stableHardwareId = androidInfo.id.replaceAll(RegExp(r'\W'), '_');
      } else {
        _deviceModelName = "Child's Physical Device • Android 14 (API 34)";
        _stableHardwareId = "browser_instance_${_guardianEmail?.hashCode ?? 'default'}";
      }
    } catch (_) {
      _deviceModelName = 'Android Device (API 34)';
    }
    notifyListeners();
  }

  /// Publishes a one-time binding code record into /pending_binds
  /// Strictly enforces one active pairing code per parent account.
  Future<void> _publishPendingBind() async {
    if (_parentUid == null) return;
    
    // 1. Cleanup: Check for any existing pending binds for this account and remove them
    try {
      final existing = await _rtdbClient.getPath('pending_binds', queryParams: {
        'orderBy': 'parentUid',
        'equalTo': _parentUid!,
      });
      
      if (existing != null && existing is Map) {
        for (var key in existing.keys) {
          await _rtdbClient.setPath('pending_binds/$key', null); // Delete stale code
        }
      }
    } catch (e) {
      debugPrint('Stale code cleanup note: $e');
    }

    // 2. Publish the new code
    final now = DateTime.now().millisecondsSinceEpoch;
    final payload = {
      'deviceId': _deviceId,
      'childId': _childId,
      'pairingCode': _pairingCode,
      'deviceModelName': _deviceModelName,
      'parentUid': _parentUid,
      'status': 'pending_bind',
      'createdAt': now,
    };

    await _rtdbClient.updatePath('pending_binds/$_pairingCode', payload);
  }

  /// Publishes pairing record into Firebase RTDB under the parent's specific account path
  /// (Used for heartbeat and telemetry updates after pairing)
  Future<void> _publishTelemetryUpdate() async {
    if (_parentUid == null || !_isPaired) return;
    
    final now = DateTime.now().millisecondsSinceEpoch;
    final telemetry = {
      'batteryLevel': _batteryLevel ?? 0,
      'isCharging': _isCharging,
      'platform': 'android',
      'deviceModelName': _deviceModelName,
      'updatedAt': now,
    };

    await _rtdbClient.updatePath('parents/$_parentUid/children/$_childId/telemetry', telemetry);
    await _rtdbClient.updatePath('parents/$_parentUid/children/$_childId/presence', {
      'online': true,
      'heartbeatAt': now,
    });
  }

  /// Regenerates a fresh binding code and notifies RTDB
  Future<void> generateNewPairingCode([String? forcedCode]) async {
    final oldCode = _pairingCode;
    _pairingCode = forcedCode ?? _generateFlashGetCode();
    _secondsRemaining = 300;
    await _publishPendingBind();
    notifyListeners();
  }

  /// Actively checks if a parent has claimed the pairing code in RTDB
  void _startPairingCheckTimer() {
    _pairingCheckTimer?.cancel();
    _pairingCheckTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (_isPaired) {
        _listenForRemoteCommands();
        return;
      }

      if (_parentUid == null) return;

      // Check if the device is now in the parent's children list (claimed via claimBindingCode)
      final deviceData = await _rtdbClient.getPath('parents/$_parentUid/children/$_childId');
      
      if (deviceData != null && deviceData['status'] == 'paired') {
        _isPaired = true;
        _onPairingSuccess();
        notifyListeners();
      }
    });
  }

  /// Automatically trigger services and initial telemetry sync upon real pairing
  void _onPairingSuccess() {
    if (_locationEnabled) {
      locationService.startTracking(
        pairingCode: _pairingCode,
        onUpdateToParent: (data) {
          if (_parentUid != null && _childId != null) {
            _rtdbClient.updatePath('parents/$_parentUid/children/$_childId/location', data);
            _rtdbClient.updatePath('devices/$_pairingCode/location', data);
          }
        },
      );
    }
    batteryService.startMonitoring(
      pairingCode: _pairingCode,
      onUpdateToParent: (data) {
        if (_parentUid != null && _childId != null) {
          _rtdbClient.updatePath('parents/$_parentUid/children/$_childId/telemetry/battery', data);
          _rtdbClient.updatePath('devices/$_pairingCode/telemetry/battery', data);
        }
      },
    );
    screenMirrorService.initializePermissionsOnce();
    screenMirrorService.startBackgroundCommandListener(_pairingCode);
  }

  /// Checks for parent remote control commands under /devices/{code}/control
  Future<void> _listenForRemoteCommands() async {
    final control = await _rtdbClient.getPath('devices/$_pairingCode/control');
    if (control is Map<String, dynamic>) {
      final cmd = control['command'] as String?;
      final ack = control['acknowledged'] as bool? ?? false;

      if (cmd != null && !ack) {
        bool commandSuccess = true;
        String? commandError;

        try {
          if (cmd == 'startStream') {
            await cameraStreamService.startStream(pairingCode: _pairingCode);
          } else if (cmd == 'stopStream') {
            await cameraStreamService.stopStream(_pairingCode);
          } else if (cmd == 'switchCamera') {
            await cameraStreamService.switchCamera(
              pairingCode: _pairingCode,
              preferredFacing: control['cameraFacing'] as String?,
            );
          } else if (cmd == 'toggleAudioMute') {
            await cameraStreamService.toggleAudioMute(_pairingCode);
          } else if (cmd == 'startScreenShare') {
            final started = await startScreenMirror();
            if (!started) {
              commandSuccess = false;
              commandError = _screenMirrorError ?? 'MediaProjection permission denied by child';
            }
          } else if (cmd == 'stopScreenShare') {
            await stopScreenMirror();
          } else if (cmd == 'startAudio') {
            await audioStreamService.startAudioStream(pairingCode: _pairingCode);
          } else if (cmd == 'stopAudio') {
            await audioStreamService.stopAudioStream(_pairingCode);
          } else if (cmd == 'syncLocation') {
            await locationService.syncCurrentLocation(_pairingCode);
          }
        } catch (e) {
          commandSuccess = false;
          commandError = e.toString();
        }

        await _rtdbClient.updatePath('devices/$_pairingCode/control', {
          'acknowledged': true,
          'success': commandSuccess,
          if (commandError != null) 'error': commandError,
          'executedAt': DateTime.now().millisecondsSinceEpoch,
        });
        notifyListeners();
      }
    }
  }

  /// Requests MediaProjection & Foreground Service permissions ONCE during initial setup
  Future<bool> initializeScreenMirrorPermissions() async {
    _screenMirrorError = null;
    _isRequestingScreenPermission = true;
    notifyListeners();

    final granted = await screenMirrorService.initializePermissionsOnce();
    _isRequestingScreenPermission = false;
    if (!granted) {
      _screenMirrorError = 'Screen mirror permission denied during initial setup';
    }
    notifyListeners();
    return granted;
  }

  /// Starts Screen Mirroring with full MediaProjection permission check and error handling
  Future<bool> startScreenMirror({int fps = 12}) async {
    _screenMirrorError = null;
    _isRequestingScreenPermission = true;
    notifyListeners();

    try {
      final success = await screenMirrorService.startScreenShare(
        _pairingCode,
        fps: fps,
        batteryLevel: _batteryLevel ?? 100,
        deviceModel: _deviceModelName,
      );

      _isRequestingScreenPermission = false;
      if (!success && _screenMirrorError == null) {
        _screenMirrorError = 'Screen capture could not be initiated';
      }
      notifyListeners();
      return success;
    } catch (e) {
      _isRequestingScreenPermission = false;
      _screenMirrorError = 'Screen mirror exception: $e';
      notifyListeners();
      return false;
    }
  }

  /// Stops Screen Mirroring cleanly
  Future<bool> stopScreenMirror() async {
    _isRequestingScreenPermission = false;
    final success = await screenMirrorService.stopScreenShare(_pairingCode);
    _screenMirrorError = null;
    notifyListeners();
    return success;
  }

  /// Toggles Screen Mirroring on or off
  Future<void> toggleScreenMirror() async {
    if (isScreenMirroring) {
      await stopScreenMirror();
    } else {
      await startScreenMirror();
    }
  }

  void clearScreenMirrorError() {
    _screenMirrorError = null;
    notifyListeners();
  }

  /// Heartbeat ticker keeps device presence alive under /devices/{code}/presence and parent's path
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final presence = {
        'online': true,
        'heartbeatAt': now,
        'lastSeen': now,
      };
      
      await _rtdbClient.updatePath('devices/$_pairingCode/presence', presence);
      if (_parentUid != null && _childId != null) {
        await _rtdbClient.updatePath('parents/$_parentUid/children/$_childId/presence', presence);
      }

      if (_batteryLevel != null) {
        final telemetry = {
          'batteryLevel': _batteryLevel,
          'isCharging': _isCharging,
          'updatedAt': now,
        };
        await _rtdbClient.updatePath('devices/$_pairingCode/telemetry', telemetry);
        if (_parentUid != null && _childId != null) {
          await _rtdbClient.updatePath('parents/$_parentUid/children/$_childId/telemetry', telemetry);
        }
      }
    });
  }

  // Feature Toggle Handlers
  void toggleLocation(bool value) {
    _locationEnabled = value;
    if (_locationEnabled && _isPaired) {
      locationService.startTracking(pairingCode: _pairingCode);
    } else {
      locationService.stopTracking();
    }
    notifyListeners();
  }

  void toggleNotifications(bool value) {
    _notificationsEnabled = value;
    notifyListeners();
  }

  void toggleAppUsage(bool value) {
    _appUsageEnabled = value;
    notifyListeners();
  }

  void toggleCallLogs(bool value) {
    _callLogsEnabled = value;
    notifyListeners();
  }

  /// Unlinks child device and generates a new code
  Future<void> unlinkDevice() async {
    _isPaired = false;
    locationService.stopTracking();
    batteryService.stopMonitoring();
    cameraStreamService.stopStream(_pairingCode);
    await screenMirrorService.stopScreenShare(_pairingCode);
    await audioStreamService.stopAudioStream(_pairingCode);

    await generateNewPairingCode();
  }

  /// Specific device node deletion from Firebase RTDB as requested
  Future<void> deleteChildDevice(String deviceCode) async {
    try {
      // Firebase నుండి నిర్దిష్టమైన device node ని పూర్తిగా తొలగించడం
      final success = await _rtdbClient.deletePath('devices/$deviceCode');
      if (success) {
        debugPrint("Device successfully deleted and synced!");
      } else {
        debugPrint("Failed to delete device from RTDB path: devices/$deviceCode");
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Error deleting device: $e");
    }
  }

  String _generateFlashGetCode() {
    const chars = '0123456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    final rand = Random();
    final randomPart = List.generate(6, (index) => chars[rand.nextInt(chars.length)]).join();
    return 'FG-$randomPart';
  }

  @override
  void dispose() {
    _pairingCheckTimer?.cancel();
    _heartbeatTimer?.cancel();
    batteryService.dispose();
    locationService.dispose();
    screenMirrorService.dispose();
    cameraStreamService.dispose();
    audioStreamService.dispose();
    super.dispose();
  }
}
