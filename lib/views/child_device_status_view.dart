import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

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
  String? _streamError;
  String? _syncError;

  @override
  void initState() {
    super.initState();
    _webRTCService = WebRTCService(
      onError: (error) {
        if (mounted) setState(() => _streamError = error.toString());
      },
      onConnectionState: (state) {
        if (!mounted) return;
        setState(() {
          _streamActive =
              state != RTCPeerConnectionState.RTCPeerConnectionStateClosed &&
                  state != RTCPeerConnectionState.RTCPeerConnectionStateFailed;
        });
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
        await _executeRemoteCommand(value['command'] as String);
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

  Future<void> _executeRemoteCommand(String command) async {
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
        await _webRTCService.switchCamera();
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
      await _telemetryReference.update({
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'appState': (state ?? WidgetsBinding.instance.lifecycleState)?.name ??
            'unknown',
        'updatedAt': ServerValue.timestamp,
      });
      if (mounted) setState(() => _syncError = null);
    } catch (error, stackTrace) {
      _handleSyncError(error, stackTrace);
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
      _streamError = null;
    });
    try {
      await _webRTCService.dispose();
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
                  if (_syncError != null) ...[
                    const SizedBox(height: 16),
                    SelectableText(
                      'Could not sync device status: $_syncError',
                      style: TextStyle(color: colors.error),
                      textAlign: TextAlign.center,
                    ),
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
