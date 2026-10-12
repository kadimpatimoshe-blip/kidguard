import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:usage_stats/usage_stats.dart';

import '../services/child_stream_background_service.dart';
import '../services/webrtc_service.dart';

class ChildDeviceStatusView extends StatefulWidget {
  const ChildDeviceStatusView({
    required this.database,
    required this.parentUid,
    required this.childId,
    required this.deviceId,
    required this.onUnlinked,
    super.key,
  });

  final FirebaseDatabase database;
  final String parentUid;
  final String childId;
  final String deviceId;
  final VoidCallback onUnlinked;

  @override
  State<ChildDeviceStatusView> createState() => _ChildDeviceStatusViewState();
}

class _ChildDeviceStatusViewState extends State<ChildDeviceStatusView>
    with WidgetsBindingObserver {
  static const _heartbeatInterval = Duration(seconds: 30);
  static const _monitoringChannel = MethodChannel('com.kidguard/monitoring');
  static const _locationEnabledKey = 'kidguard_location_enabled';
  static const _callLogsEnabledKey = 'kidguard_call_logs_enabled';
  static const _appUsageEnabledKey = 'kidguard_app_usage_enabled';

  late final DatabaseReference _deviceReference;
  late final DatabaseReference _presenceReference;
  late final DatabaseReference _telemetryReference;
  late final DatabaseReference _controlReference;
  StreamSubscription<DatabaseEvent>? _connectionSubscription;
  StreamSubscription<DatabaseEvent>? _deviceSubscription;
  StreamSubscription<DatabaseEvent>? _controlSubscription;
  StreamSubscription<Map<String, dynamic>?>? _streamStateSubscription;
  StreamSubscription<Map<String, dynamic>?>? _streamErrorSubscription;
  Future<void> _remoteCommandQueue = Future<void>.value();
  Timer? _heartbeatTimer;
  bool _connected = false;
  bool _deviceRecordConfirmed = false;
  bool _appActive = true;
  bool _parentUnlinked = false;
  late final WebRTCService _webRTCService;
  bool _startingStream = false;
  bool _streamActive = false;
  bool _cameraPermissionsGranted = false;
  bool _backgroundServiceReady = false;
  bool _permissionFlowInProgress = false;
  bool _streamAudioMuted = false;
  bool _locationSharingEnabled = false;
  bool _callLogSyncEnabled = false;
  bool _appUsageSyncEnabled = false;
  bool _notificationAccessGranted = false;
  bool _usageAccessGranted = false;
  bool _startingScreenMirror = false;
  bool _screenMirrorActive = false;
  String? _streamError;
  String? _syncError;
  String? _featureError;
  Future<AndroidDeviceInfo?>? _androidDeviceInfoFuture;

  @override
  void initState() {
    super.initState();
    _webRTCService = WebRTCService(
      onError: (error) {
        if (mounted) setState(() => _streamError = error.toString());
      },
      onConnectionState: (state) {
        if (!mounted) return;
        final active =
            state != RTCPeerConnectionState.RTCPeerConnectionStateClosed &&
                state != RTCPeerConnectionState.RTCPeerConnectionStateFailed;
        setState(() {
          _streamActive = active;
          if (!active) _screenMirrorActive = false;
        });
        if (!active) {
          unawaited(ChildStreamBackgroundService.setScreenCaptureActive(false));
        }
      },
    );
    unawaited(_prepareSignalingRecord());
    WidgetsBinding.instance.addObserver(this);
    final devicePath =
        '/parents/${widget.parentUid}/children/${widget.childId}';
    _deviceReference = widget.database.ref(devicePath);
    _deviceSubscription = _deviceReference.onValue.listen(
      _handleDeviceRecord,
      onError: _handleSyncError,
    );
    _presenceReference = widget.database.ref('$devicePath/presence');
    _telemetryReference = widget.database.ref('$devicePath/telemetry');
    _controlReference =
        widget.database.ref('/devices/${widget.deviceId}/control');
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final service = FlutterBackgroundService();
      _streamStateSubscription = service.on('streamState').listen((event) {
        if (!mounted || event == null) return;
        setState(() {
          _streamActive = event['active'] == true;
          _screenMirrorActive = false;
          if (event['audioMuted'] is bool) {
            _streamAudioMuted = event['audioMuted'] as bool;
          }
          if (_streamActive) _streamError = null;
        });
      });
      _streamErrorSubscription = service.on('serviceError').listen((event) {
        if (!mounted || event?['error'] is! String) return;
        setState(() => _streamError = event!['error'] as String);
      });
      unawaited(_requestPermissionsAndStartBackgroundService());
      unawaited(_refreshMonitoringAccess());
    }
    _connectionSubscription =
        widget.database.ref('.info/connected').onValue.listen(
              _handleConnection,
              onError: _handleSyncError,
            );
    _heartbeatTimer = Timer.periodic(
      _heartbeatInterval,
      (_) => _sendHeartbeat(),
    );
  }

  bool get _canSyncDevice =>
      _connected && _deviceRecordConfirmed && !_parentUnlinked;

  void _handleDeviceRecord(DatabaseEvent event) {
    _checkDeviceRecord(event.snapshot.value);
  }

  void _checkDeviceRecord(Object? value) {
    if (!_connected || !_deviceRecordConfirmed || _parentUnlinked) return;
    if (_isPairedDeviceRecord(value)) return;

    _notifyParentUnlinked();
  }

  bool _isPairedDeviceRecord(Object? value) {
    return value is Map && value['status'] == 'paired';
  }

  void _notifyParentUnlinked() {
    if (_parentUnlinked) return;
    _parentUnlinked = true;
    widget.onUnlinked();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (_appActive &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      unawaited(_refreshMonitoringAccess());
    }
    if (_appActive &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        !_backgroundServiceReady) {
      unawaited(
        _requestPermissionsAndStartBackgroundService(requestIfNeeded: false),
      );
    }
    if (!_canSyncDevice) return;
    _syncTelemetry(state);
    if (_appActive || _streamActive) {
      unawaited(_sendHeartbeat());
    } else {
      unawaited(_markOffline());
    }
  }

  Future<void> _refreshMonitoringAccess() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final notificationAccess =
          await _monitoringChannel.invokeMethod<bool>('hasNotificationAccess');
      final usageAccess = await UsageStats.checkUsagePermission() ?? false;
      await _monitoringChannel.invokeMethod<void>(
        'configureNotificationSync',
        {
          'deviceId': widget.deviceId,
          'parentUid': widget.parentUid,
          'childId': widget.childId,
        },
      );
      final callLogsEnabled =
          preferences.getBool(_callLogsEnabledKey) ?? false;
      if (callLogsEnabled) {
        await _monitoringChannel.invokeMethod<void>(
          'setCallLogSyncEnabled',
          {'enabled': true},
        );
      }
      if (mounted) {
        setState(() {
          _notificationAccessGranted = notificationAccess == true;
          _usageAccessGranted = usageAccess;
          _locationSharingEnabled =
              preferences.getBool(_locationEnabledKey) ?? false;
          _callLogSyncEnabled =
              preferences.getBool(_callLogsEnabledKey) ?? false;
          _appUsageSyncEnabled =
              preferences.getBool(_appUsageEnabledKey) ?? false;
        });
      }
    } catch (error, stackTrace) {
      _handleFeatureError(
          'Could not load monitoring permissions', error, stackTrace);
    }
  }

  Future<void> _openNotificationSettings() async {
    try {
      await _monitoringChannel
          .invokeMethod<void>('openNotificationAccessSettings');
    } catch (error, stackTrace) {
      _handleFeatureError(
        'Could not open notification access settings',
        error,
        stackTrace,
      );
    }
  }

  Widget _buildMonitoringControls(ColorScheme colors) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Child device monitoring',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Each feature is optional and uses Android permissions. '
              'Location updates about every 30 seconds while enabled; call '
              'history (including numbers, names, type, and duration) is read '
              'only and syncs about every 15 minutes while enabled; Android '
              'may delay background jobs. App usage syncs about every '
              '15 minutes. Notifications sync after notification access is '
              'enabled in Android settings. Screen sharing always requires '
              'your approval in the Android system prompt.',
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _locationSharingEnabled
                  ? () => _setFeatureEnabled(
                        feature: 'location',
                        enabled: false,
                      )
                  : _enableLocationSharing,
              child: Text(
                _locationSharingEnabled
                    ? 'Stop Live Location sharing'
                    : 'Enable Live Location',
              ),
            ),
            OutlinedButton(
              onPressed: _callLogSyncEnabled
                  ? () => _setFeatureEnabled(feature: 'calls', enabled: false)
                  : _enableCallLogSync,
              child: Text(
                _callLogSyncEnabled ? 'Stop Call Log sync' : 'Enable Call Logs',
              ),
            ),
            OutlinedButton(
              onPressed: _appUsageSyncEnabled
                  ? () => _setFeatureEnabled(feature: 'usage', enabled: false)
                  : _enableAppUsageSync,
              child: Text(
                _appUsageSyncEnabled
                    ? 'Stop App Usage sync'
                    : _usageAccessGranted
                        ? 'Enable App Usage'
                        : 'Grant App Usage access',
              ),
            ),
            OutlinedButton(
              onPressed: _openNotificationSettings,
              child: Text(
                _notificationAccessGranted
                    ? 'Manage notification access (enabled)'
                    : 'Enable notification sharing',
              ),
            ),
            if (_streamActive && _screenMirrorActive)
              FilledButton(
                onPressed: _stopScreenMirror,
                child: const Text('Stop Screen Sharing'),
              )
            else
              FilledButton.tonal(
                onPressed: _startingScreenMirror || _streamActive
                    ? null
                    : _startScreenMirror,
                child: Text(
                  _startingScreenMirror
                      ? 'Waiting for Android screen-sharing approval…'
                      : 'Start Screen Sharing',
                ),
              ),
            if (_streamActive && _screenMirrorActive)
              Text(
                'Your screen is currently being shared with the paired parent.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.error),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _enableLocationSharing() async {
    try {
      var permission = await Permission.locationWhenInUse.request();
      if (!permission.isGranted) {
        throw StateError('Location permission was not granted.');
      }
      permission = await Permission.locationAlways.request();
      if (!permission.isGranted) {
        throw StateError(
          'Allow all the time location access in Android app settings '
          'to enable background location sharing.',
        );
      }
      await ChildStreamBackgroundService.configureMonitoring(
        locationEnabled: true,
        callLogsEnabled: _callLogSyncEnabled,
        appUsageEnabled: _appUsageSyncEnabled,
      );
      if (mounted) {
        setState(() {
          _locationSharingEnabled = true;
          _featureError = null;
        });
      }
    } catch (error, stackTrace) {
      _handleFeatureError(
          'Could not enable location sharing', error, stackTrace);
    }
  }

  Future<void> _enableCallLogSync() async {
    try {
      final permissionGranted = await _monitoringChannel
              .invokeMethod<bool>('requestCallLogPermission') ??
          false;
      if (!permissionGranted) {
        throw StateError(
          'Call log access is required to enable call history syncing.',
        );
      }
      await ChildStreamBackgroundService.configureMonitoring(
        locationEnabled: _locationSharingEnabled,
        callLogsEnabled: true,
        appUsageEnabled: _appUsageSyncEnabled,
      );
      if (mounted) {
        setState(() {
          _callLogSyncEnabled = true;
          _featureError = null;
        });
      }
    } catch (error, stackTrace) {
      _handleFeatureError('Could not enable call log sync', error, stackTrace);
    }
  }

  Future<void> _openUsageSettings() async {
    try {
      await UsageStats.openUsageAccessSettings();
    } catch (error, stackTrace) {
      _handleFeatureError(
          'Could not open App Usage settings', error, stackTrace);
    }
  }

  Future<void> _enableAppUsageSync() async {
    try {
      final accessGranted = await UsageStats.checkUsagePermission() ?? false;
      if (!accessGranted) {
        await _openUsageSettings();
        return;
      }
      await ChildStreamBackgroundService.configureMonitoring(
        locationEnabled: _locationSharingEnabled,
        callLogsEnabled: _callLogSyncEnabled,
        appUsageEnabled: true,
      );
      if (mounted) {
        setState(() {
          _usageAccessGranted = true;
          _appUsageSyncEnabled = true;
          _featureError = null;
        });
      }
    } catch (error, stackTrace) {
      _handleFeatureError('Could not enable App Usage sync', error, stackTrace);
    }
  }

  Future<void> _setFeatureEnabled({
    required String feature,
    required bool enabled,
  }) async {
    try {
      await ChildStreamBackgroundService.configureMonitoring(
        locationEnabled:
            feature == 'location' ? enabled : _locationSharingEnabled,
        callLogsEnabled: feature == 'calls' ? enabled : _callLogSyncEnabled,
        appUsageEnabled: feature == 'usage' ? enabled : _appUsageSyncEnabled,
      );
      if (!mounted) return;
      setState(() {
        if (feature == 'location') _locationSharingEnabled = enabled;
        if (feature == 'calls') _callLogSyncEnabled = enabled;
        if (feature == 'usage') _appUsageSyncEnabled = enabled;
        _featureError = null;
      });
    } catch (error, stackTrace) {
      _handleFeatureError(
          'Could not update $feature sharing', error, stackTrace);
    }
  }

  void _handleFeatureError(
    String message,
    Object error,
    StackTrace stackTrace,
  ) {
    debugPrint('$message: $error');
    debugPrintStack(stackTrace: stackTrace);
    if (mounted) setState(() => _featureError = '$message: $error');
  }

  Future<void> _handleConnection(DatabaseEvent event) async {
    final connected = event.snapshot.value == true;
    if (_connected == connected) return;
    _connected = connected;
    _deviceRecordConfirmed = false;
    if (!connected) {
      unawaited(_controlSubscription?.cancel());
      _controlSubscription = null;
    }
    if (mounted) setState(() => _syncError = null);
    if (connected) {
      try {
        final deviceSnapshot = await _deviceReference.get();
        if (!_connected || !mounted) return;
        _deviceRecordConfirmed = true;
        if (!_isPairedDeviceRecord(deviceSnapshot.value)) {
          _notifyParentUnlinked();
          return;
        }

        if (kIsWeb) await _listenForRemoteControls();
        await _presenceReference.onDisconnect().update({
          'online': false,
          'lastSeen': ServerValue.timestamp,
        });
        if (!_canSyncDevice) return;
        if (_appActive) {
          await _writePresence();
        } else {
          await _markOffline();
        }
        await _syncTelemetry();
      } catch (error, stackTrace) {
        _handleSyncError(error, stackTrace);
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _listenForRemoteControls() async {
    await _controlSubscription?.cancel();
    _controlSubscription = _controlReference.onValue.listen(
      _handleRemoteControl,
      onError: _handleSyncError,
    );
  }

  void _handleRemoteControl(DatabaseEvent event) {
    final value = event.snapshot.value;
    if (!_canSyncDevice ||
        value is! Map ||
        value['deviceId'] != widget.deviceId ||
        value['parentUid'] != widget.parentUid ||
        value['childId'] != widget.childId ||
        value['commandId'] is! String ||
        value['command'] is! String) {
      return;
    }

    final commandId = value['commandId'] as String;
    final acknowledgement = value['acknowledgement'];
    if (commandId.isEmpty ||
        (acknowledgement is Map && acknowledgement['commandId'] == commandId)) {
      return;
    }

    _remoteCommandQueue = _remoteCommandQueue.then((_) async {
      var status = 'completed';
      String? message;
      try {
        if (!_canSyncDevice) {
          throw StateError('The parent device is no longer paired.');
        }
        final cameraFacing = value['cameraFacing'];
        await _executeRemoteCommand(
          value['command'] as String,
          cameraFacing: cameraFacing is String ? cameraFacing : null,
        );
      } catch (error, stackTrace) {
        status = 'failed';
        message = error.toString();
        debugPrint('Remote stream command failed: $error');
        debugPrintStack(stackTrace: stackTrace);
        if (mounted) setState(() => _streamError = message);
      }

      try {
        await _controlReference.update({
          'acknowledgement': {
            'commandId': commandId,
            'status': status,
            if (message != null) 'message': message,
            'completedAt': ServerValue.timestamp,
          },
        });
      } catch (error, stackTrace) {
        _handleSyncError(error, stackTrace);
      }
    });
  }

  Future<void> _executeRemoteCommand(
    String command, {
    String? cameraFacing,
  }) async {
    switch (command) {
      case 'startStream':
        if (kIsWeb && !_appActive) {
          throw StateError(
              'The child browser must be active to start a live stream.');
        }
        await _startLiveStream(rethrowOnError: true);
      case 'stopStream':
        await _stopLiveStream(rethrowOnError: true);
      case 'switchCamera':
        final frontFacing = switch (cameraFacing) {
          'front' => true,
          'back' => false,
          _ => null,
        };
        await _webRTCService.switchCamera(frontFacing: frontFacing);
      case 'toggleAudioMute':
        final muted = await _webRTCService.toggleAudioMute();
        if (mounted) setState(() => _streamAudioMuted = muted);
      default:
        throw FormatException('Unsupported remote stream command: $command');
    }
  }

  Future<void> _sendHeartbeat() async {
    if (!_canSyncDevice || (!_appActive && !_streamActive)) return;
    try {
      await _writePresence();
      if (mounted) setState(() => _syncError = null);
    } catch (error, stackTrace) {
      _handleSyncError(error, stackTrace);
    }
  }

  Future<void> _writePresence() async {
    if (!_canSyncDevice) return;
    await _presenceReference.update({
      'online': true,
      'heartbeatAt': ServerValue.timestamp,
      'lastSeen': ServerValue.timestamp,
    });
  }

  Future<void> _markOffline() {
    if (!_canSyncDevice) return Future<void>.value();
    return _presenceReference.update({
      'online': false,
      'lastSeen': ServerValue.timestamp,
    }).catchError((Object error, StackTrace stackTrace) {
      _handleSyncError(error, stackTrace);
    });
  }

  Future<void> _syncTelemetry([AppLifecycleState? state]) async {
    if (!_canSyncDevice) return;
    try {
      final androidInfo =
          await (_androidDeviceInfoFuture ??= _readAndroidDeviceInfo());
      final manufacturer = androidInfo?.manufacturer.trim();
      final model = androidInfo?.model.trim();
      final deviceModelName = [
        if (manufacturer != null && manufacturer.isNotEmpty) manufacturer,
        if (model != null && model.isNotEmpty) model,
      ].join(' ');
      await _telemetryReference.update({
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'appState': (state ?? WidgetsBinding.instance.lifecycleState)?.name ??
            'unknown',
        if (manufacturer != null && manufacturer.isNotEmpty)
          'deviceManufacturer': manufacturer,
        if (model != null && model.isNotEmpty) 'deviceModel': model,
        if (deviceModelName.isNotEmpty) 'deviceModelName': deviceModelName,
        'updatedAt': ServerValue.timestamp,
      });
      if (mounted) setState(() => _syncError = null);
    } catch (error, stackTrace) {
      _handleSyncError(error, stackTrace);
    }
  }

  Future<AndroidDeviceInfo?> _readAndroidDeviceInfo() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return await DeviceInfoPlugin().androidInfo;
    } catch (error) {
      debugPrint('Could not read Android device information: $error');
      return null;
    }
  }

  void _handleSyncError(Object error, [StackTrace? stackTrace]) {
    debugPrint('Child device sync failed: $error');
    if (stackTrace != null) debugPrintStack(stackTrace: stackTrace);
    if (mounted) {
      setState(() => _syncError = error.toString());
    }
  }

  Future<void> _requestPermissionsAndStartBackgroundService({
    bool requestIfNeeded = true,
  }) async {
    if (_permissionFlowInProgress) return;
    _permissionFlowInProgress = true;
    try {
      final permissions = [Permission.camera, Permission.microphone];
      final statuses = requestIfNeeded
          ? await permissions.request()
          : {
              for (final permission in permissions)
                permission: await permission.status,
            };
      if (statuses[Permission.camera]?.isGranted != true ||
          statuses[Permission.microphone]?.isGranted != true) {
        throw StateError(
          'Camera and microphone permissions are required for parent-'
          'controlled live streaming.',
        );
      }
      if (mounted) {
        setState(() {
          _cameraPermissionsGranted = true;
          _streamError = null;
        });
      }
      await ChildStreamBackgroundService.start(
        deviceId: widget.deviceId,
        parentUid: widget.parentUid,
        childId: widget.childId,
      );
      _backgroundServiceReady = true;
    } catch (error, stackTrace) {
      debugPrint('Could not enable parent-controlled live streaming: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) setState(() => _streamError = error.toString());
    } finally {
      _permissionFlowInProgress = false;
    }
  }

  Future<void> _startLiveStream({bool rethrowOnError = false}) async {
    if (_startingStream || _streamActive) return;
    setState(() {
      _startingStream = true;
      _streamError = null;
    });
    try {
      await _webRTCService.startPublishing(
        database: widget.database,
        deviceId: widget.deviceId,
        parentUid: widget.parentUid,
        childId: widget.childId,
      );
      if (mounted) {
        setState(() {
          _streamActive = true;
          _screenMirrorActive = false;
          _streamAudioMuted = false;
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Could not start child live stream: $error');
      debugPrintStack(stackTrace: stackTrace);
      try {
        await _webRTCService.dispose();
      } catch (disposeError, disposeStackTrace) {
        debugPrint(
            'Could not clean up failed child live stream: $disposeError');
        debugPrintStack(stackTrace: disposeStackTrace);
      }
      if (mounted) setState(() => _streamError = error.toString());
      if (rethrowOnError) rethrow;
    } finally {
      if (mounted) setState(() => _startingStream = false);
    }
  }

  Future<void> _startScreenMirror() async {
    if (_startingScreenMirror || _streamActive) return;
    setState(() {
      _startingScreenMirror = true;
      _streamError = null;
    });
    try {
      await ChildStreamBackgroundService.setScreenCaptureActive(true);
      await _webRTCService.startPublishing(
        database: widget.database,
        deviceId: widget.deviceId,
        parentUid: widget.parentUid,
        childId: widget.childId,
        screenCapture: true,
      );
      if (mounted) {
        setState(() {
          _streamActive = true;
          _screenMirrorActive = true;
          _streamAudioMuted = true;
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Could not start child screen mirroring: $error');
      debugPrintStack(stackTrace: stackTrace);
      try {
        await _webRTCService.dispose();
      } catch (disposeError, disposeStackTrace) {
        debugPrint('Could not clean up failed screen mirroring: $disposeError');
        debugPrintStack(stackTrace: disposeStackTrace);
      }
      await ChildStreamBackgroundService.setScreenCaptureActive(false);
      if (mounted) setState(() => _streamError = error.toString());
    } finally {
      if (mounted) setState(() => _startingScreenMirror = false);
    }
  }

  Future<void> _stopScreenMirror() async {
    await _stopLiveStream();
    await ChildStreamBackgroundService.setScreenCaptureActive(false);
    if (mounted) setState(() => _screenMirrorActive = false);
  }

  Future<void> _prepareSignalingRecord() async {
    try {
      await widget.database.ref('/webrtc_signaling/${widget.deviceId}').update({
        'deviceId': widget.deviceId,
        'parentUid': widget.parentUid,
        'childId': widget.childId,
      });
    } catch (error, stackTrace) {
      debugPrint('Could not prepare WebRTC signaling record: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _streamError = error.toString());
      }
    }
  }

  Future<void> _stopLiveStream({bool rethrowOnError = false}) async {
    setState(() {
      _streamActive = false;
      _screenMirrorActive = false;
      _streamError = null;
    });
    try {
      await _webRTCService.dispose();
      await ChildStreamBackgroundService.setScreenCaptureActive(false);
    } catch (error, stackTrace) {
      debugPrint('Could not stop child live stream: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) setState(() => _streamError = error.toString());
      if (rethrowOnError) rethrow;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _connectionSubscription?.cancel();
    _deviceSubscription?.cancel();
    _controlSubscription?.cancel();
    _streamStateSubscription?.cancel();
    _streamErrorSubscription?.cancel();
    if (_connected && !_parentUnlinked) {
      unawaited(_markOffline());
    }
    unawaited(_webRTCService.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('KidGuard Child')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _connected ? Icons.cloud_done : Icons.cloud_off,
                    size: 56,
                    color: _connected ? colors.primary : colors.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _connected ? 'Device online' : 'Waiting for connection',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Presence and basic device status sync automatically.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (kIsWeb &&
                      _streamActive &&
                      _webRTCService.localRenderer != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: RTCVideoView(
                          _webRTCService.localRenderer!,
                          mirror: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _streamAudioMuted
                          ? 'Live video is being shared; microphone is muted.'
                          : 'Live camera and microphone are being shared.',
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    kIsWeb
                        ? 'The paired parent controls when a live stream starts '
                            'and stops. Your browser may request camera and '
                            'microphone access when the parent starts one.'
                        : _cameraPermissionsGranted
                            ? _streamActive
                                ? _streamAudioMuted
                                    ? 'A parent-authorized live stream is active. '
                                        'The microphone is muted.'
                                    : 'A parent-authorized live stream is active.'
                                : 'Camera and microphone permissions are ready. '
                                    'The paired parent controls when streaming starts and stops.'
                            : 'Allow camera and microphone access once to enable '
                                'live streams controlled by the paired parent.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (_streamError != null) ...[
                    const SizedBox(height: 12),
                    SelectableText(
                      'Could not start or maintain the live stream: $_streamError',
                      style: TextStyle(color: colors.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (_featureError != null) ...[
                    const SizedBox(height: 12),
                    SelectableText(
                      _featureError!,
                      style: TextStyle(color: colors.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (_syncError != null) ...[
                    const SizedBox(height: 16),
                    SelectableText(
                      'Could not sync device status: $_syncError',
                      style: TextStyle(color: colors.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (!kIsWeb &&
                      defaultTargetPlatform == TargetPlatform.android) ...[
                    const SizedBox(height: 20),
                    _buildMonitoringControls(colors),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
