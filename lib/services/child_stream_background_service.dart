import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_config.dart';
import 'webrtc_service.dart';

class ChildStreamBackgroundService {
  static const _deviceIdKey = 'kidguard_stream_device_id';
  static const _parentUidKey = 'kidguard_stream_parent_uid';
  static const _childIdKey = 'kidguard_stream_child_id';

  static Future<void> start({
    required String deviceId,
    required String parentUid,
    required String childId,
  }) async {
    final configuration = <String, dynamic>{
      'deviceId': deviceId,
      'parentUid': parentUid,
      'childId': childId,
    };
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_deviceIdKey, deviceId);
    await preferences.setString(_parentUidKey, parentUid);
    await preferences.setString(_childIdKey, childId);

    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      final configured = service
          .on('configured')
          .firstWhere((event) => event?['deviceId'] == deviceId)
          .timeout(const Duration(seconds: 15));
      service.invoke('configure', configuration);
      final result = await configured;
      if (result?['success'] != true) {
        throw StateError(
          result?['error'] as String? ??
              'The background stream service could not be configured.',
        );
      }
      return;
    }

    await service.configure(
      iosConfiguration: IosConfiguration(autoStart: false),
      androidConfiguration: AndroidConfiguration(
        onStart: childStreamServiceEntrypoint,
        autoStart: false,
        autoStartOnBoot: false,
        isForegroundMode: true,
        initialNotificationTitle: 'KidGuard is ready',
        initialNotificationContent:
            'Waiting for a parent-authorized stream request.',
        foregroundServiceNotificationId: 8314,
        foregroundServiceTypes: const [
          AndroidForegroundType.camera,
          AndroidForegroundType.microphone,
        ],
      ),
    );
    final ready = service.on('ready').first.timeout(
          const Duration(seconds: 20),
        );
    if (!await service.startService()) {
      throw StateError('The Android camera streaming service did not start.');
    }
    final result = await ready;
    if (result?['success'] != true) {
      throw StateError(
        result?['error'] as String? ??
            'The Android camera streaming service failed to initialize.',
      );
    }
  }
}

@pragma('vm:entry-point')
Future<void> childStreamServiceEntrypoint(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  try {
    final app = await Firebase.initializeApp(
      options: FirebaseConfig.childAndroid,
    );
    final database = FirebaseDatabase.instanceFor(
      app: app,
      databaseURL: FirebaseConfig.childAndroid.databaseURL,
    );
    final runner = _ChildStreamCommandRunner(service, database);
    service.on('configure').listen((configuration) {
      unawaited(runner.configure(configuration));
    });
    service.on('stopService').listen((_) {
      unawaited(runner.dispose());
      unawaited(service.stopSelf());
    });

    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    final deviceId =
        preferences.getString(ChildStreamBackgroundService._deviceIdKey);
    final parentUid =
        preferences.getString(ChildStreamBackgroundService._parentUidKey);
    final childId =
        preferences.getString(ChildStreamBackgroundService._childIdKey);
    if (deviceId == null || parentUid == null || childId == null) {
      throw StateError('Paired child-device details are not available.');
    }
    await runner.configure({
      'deviceId': deviceId,
      'parentUid': parentUid,
      'childId': childId,
    });
    service.invoke('ready', {'success': true});
  } catch (error, stackTrace) {
    debugPrint('Child stream service initialization failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    service.invoke('ready', {
      'success': false,
      'error': error.toString(),
    });
    await Future<void>.delayed(const Duration(seconds: 1));
    await service.stopSelf();
  }
}

class _ChildStreamCommandRunner {
  _ChildStreamCommandRunner(this._service, this._database) {
    _webRTCService = WebRTCService(
      onError: (error) {
        _service.invoke('serviceError', {'error': error.toString()});
      },
      onConnectionState: (state) {
        final active =
            state != RTCPeerConnectionState.RTCPeerConnectionStateClosed &&
                state != RTCPeerConnectionState.RTCPeerConnectionStateFailed;
        _service.invoke('streamState', {'active': active});
      },
    );
  }

  final ServiceInstance _service;
  final FirebaseDatabase _database;
  late final WebRTCService _webRTCService;
  DatabaseReference? _controlReference;
  StreamSubscription<DatabaseEvent>? _controlSubscription;
  StreamSubscription<DatabaseEvent>? _deviceSubscription;
  StreamSubscription<DatabaseEvent>? _connectionSubscription;
  Timer? _presenceHeartbeatTimer;
  Future<void> _commandQueue = Future<void>.value();
  DatabaseReference? _presenceReference;
  String? _deviceId;
  String? _parentUid;
  String? _childId;
  bool _disposed = false;
  bool _databaseConnected = false;

  Future<void> configure(Map<String, dynamic>? configuration) async {
    final deviceId = configuration?['deviceId'];
    final parentUid = configuration?['parentUid'];
    final childId = configuration?['childId'];
    if (deviceId is! String ||
        parentUid is! String ||
        childId is! String ||
        !_isValidDatabaseKey(deviceId) ||
        !_isValidDatabaseKey(parentUid) ||
        !_isValidDatabaseKey(childId)) {
      _service.invoke('configured', {
        'deviceId': deviceId,
        'success': false,
        'error': 'Paired child-device details are invalid.',
      });
      return;
    }

    if (_deviceId == deviceId &&
        _parentUid == parentUid &&
        _childId == childId &&
        _controlSubscription != null) {
      _service.invoke('configured', {
        'deviceId': deviceId,
        'success': true,
      });
      return;
    }

    try {
      await _controlSubscription?.cancel();
      await _deviceSubscription?.cancel();
      await _connectionSubscription?.cancel();
      _presenceHeartbeatTimer?.cancel();
      await _webRTCService.dispose();
      _deviceId = deviceId;
      _parentUid = parentUid;
      _childId = childId;
      _disposed = false;
      _databaseConnected = false;
      _controlReference = _database.ref('/devices/$deviceId/control');
      _presenceReference = _database.ref(
        '/parents/$parentUid/children/$childId/presence',
      );
      _controlSubscription = _controlReference!.onValue.listen(
        _handleRemoteControl,
        onError: _reportError,
      );
      _connectionSubscription =
          _database.ref('.info/connected').onValue.listen((event) {
        _databaseConnected = event.snapshot.value == true;
        if (_databaseConnected) unawaited(_confirmPairedDevice());
      }, onError: _reportError);
      _deviceSubscription = _database
          .ref('/parents/$parentUid/children/$childId')
          .onValue
          .listen((event) {
        if (_databaseConnected &&
            !_isPairedDeviceRecord(event.snapshot.value)) {
          unawaited(_handleUnlinkedDevice());
        }
      }, onError: _reportError);
      _presenceHeartbeatTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) {
          if (_webRTCService.localStream != null) {
            unawaited(_writePresenceHeartbeat());
          }
        },
      );
      _service.invoke('configured', {
        'deviceId': deviceId,
        'success': true,
      });
    } catch (error, stackTrace) {
      _reportError(error, stackTrace);
      _service.invoke('configured', {
        'deviceId': deviceId,
        'success': false,
        'error': error.toString(),
      });
    }
  }

  Future<void> _confirmPairedDevice() async {
    final deviceId = _deviceId;
    final parentUid = _parentUid;
    final childId = _childId;
    if (deviceId == null || parentUid == null || childId == null) return;
    try {
      final snapshot =
          await _database.ref('/parents/$parentUid/children/$childId').get();
      if (_databaseConnected &&
          !_isPairedDeviceRecord(snapshot.value) &&
          _deviceId == deviceId) {
        await _handleUnlinkedDevice();
      }
    } catch (error, stackTrace) {
      _reportError(error, stackTrace);
    }
  }

  void _handleRemoteControl(DatabaseEvent event) {
    final value = event.snapshot.value;
    if (value is! Map ||
        value['deviceId'] != _deviceId ||
        value['parentUid'] != _parentUid ||
        value['childId'] != _childId ||
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

    _commandQueue =
        _commandQueue.then((_) => _processCommand(value)).catchError(
      (Object error, StackTrace stackTrace) {
        _reportError(error, stackTrace);
      },
    );
  }

  Future<void> _processCommand(Map value) async {
    final commandId = value['commandId'] as String;
    var status = 'completed';
    String? message;
    try {
      final childRecord =
          await _database.ref('/parents/$_parentUid/children/$_childId').get();
      if (!_isPairedDeviceRecord(childRecord.value)) {
        throw StateError('The parent device is no longer paired.');
      }
      await _executeRemoteCommand(value['command'] as String);
    } catch (error, stackTrace) {
      status = 'failed';
      message = error.toString();
      _reportError(error, stackTrace);
    }

    try {
      await _controlReference!.update({
        'acknowledgement': {
          'commandId': commandId,
          'status': status,
          if (message != null) 'message': message,
          'completedAt': ServerValue.timestamp,
        },
      });
    } catch (error, stackTrace) {
      _reportError(error, stackTrace);
    }
  }

  Future<void> _executeRemoteCommand(String command) async {
    switch (command) {
      case 'startStream':
        try {
          await _webRTCService.startPublishing(
            database: _database,
            deviceId: _deviceId!,
            parentUid: _parentUid!,
            childId: _childId!,
            permissionsAlreadyGranted: true,
          );
        } catch (_) {
          await _webRTCService.dispose();
          rethrow;
        }
        _service.invoke('streamState', {
          'active': true,
          'audioMuted': false,
        });
        await _writePresenceHeartbeat();
        await _updateForegroundNotification(
          title: 'KidGuard live stream is active',
          content: 'The paired parent is viewing this device.',
        );
      case 'stopStream':
        await _webRTCService.dispose();
        _service.invoke('streamState', {
          'active': false,
          'audioMuted': false,
        });
        await _updateForegroundNotification(
          title: 'KidGuard is ready',
          content: 'Waiting for a parent-authorized stream request.',
        );
      case 'switchCamera':
        await _webRTCService.switchCamera();
      case 'toggleAudioMute':
        final muted = await _webRTCService.toggleAudioMute();
        _service.invoke('streamState', {
          'active': true,
          'audioMuted': muted,
        });
      default:
        throw FormatException('Unsupported remote stream command: $command');
    }
  }

  Future<void> _handleUnlinkedDevice() async {
    if (_disposed) return;
    _disposed = true;
    await _webRTCService.dispose();
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(ChildStreamBackgroundService._deviceIdKey);
      await preferences.remove(ChildStreamBackgroundService._parentUidKey);
      await preferences.remove(ChildStreamBackgroundService._childIdKey);
    } catch (error, stackTrace) {
      _reportError(error, stackTrace);
    } finally {
      _service.invoke('unlinked');
      await _service.stopSelf();
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _controlSubscription?.cancel();
    await _deviceSubscription?.cancel();
    await _connectionSubscription?.cancel();
    _presenceHeartbeatTimer?.cancel();
    await _webRTCService.dispose();
  }

  Future<void> _writePresenceHeartbeat() async {
    try {
      await _presenceReference?.update({
        'online': true,
        'heartbeatAt': ServerValue.timestamp,
        'lastSeen': ServerValue.timestamp,
      });
    } catch (error, stackTrace) {
      _reportError(error, stackTrace);
    }
  }

  Future<void> _updateForegroundNotification({
    required String title,
    required String content,
  }) async {
    final service = _service;
    if (service is AndroidServiceInstance &&
        await service.isForegroundService()) {
      await service.setForegroundNotificationInfo(
        title: title,
        content: content,
      );
    }
  }

  void _reportError(Object error, [StackTrace? stackTrace]) {
    debugPrint('Child background stream command failed: $error');
    if (stackTrace != null) debugPrintStack(stackTrace: stackTrace);
    _service.invoke('serviceError', {'error': error.toString()});
  }

  bool _isPairedDeviceRecord(Object? value) {
    return value is Map && value['status'] == 'paired';
  }

  bool _isValidDatabaseKey(String value) {
    return value.isNotEmpty && !RegExp(r'[.#$\[\]/]').hasMatch(value);
  }
}
