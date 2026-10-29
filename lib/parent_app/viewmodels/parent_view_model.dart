import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../child_app/core/services/rtdb_client_service.dart';
import '../models/child_device.dart';
import '../services/parent_webrtc_service.dart';

/// ViewModel managing Parent Console state, active devices, real-time Firebase RTDB sync,
/// and real WebRTC audio/video streaming sessions.
class ParentViewModel extends ChangeNotifier {
  final RtdbClientService _rtdbClient;
  final ParentWebRtcService _webRtcService;
  final String parentUid;

  final List<ChildDevice> _devices = [];
  ChildDevice? _selectedDevice;
  bool _isLoading = false;
  String? _errorMessage;
  String? _statusMessage;
  Timer? _telemetryPollingTimer;

  ParentViewModel({
    RtdbClientService? rtdbClient,
    ParentWebRtcService? webRtcService,
    this.parentUid = 'parent_default_uid',
  })  : _rtdbClient = rtdbClient ?? RtdbClientService(),
        _webRtcService = webRtcService ?? ParentWebRtcService(parentUid: parentUid) {
    _webRtcService.onStreamStateChanged = () => notifyListeners();
    _webRtcService.onStatusUpdate = (msg) {
      _statusMessage = msg;
      notifyListeners();
    };
    _webRtcService.onError = (err) {
      _errorMessage = err;
      notifyListeners();
    };

    _startTelemetryPolling();
  }

  List<ChildDevice> get devices => List.unmodifiable(_devices);
  ChildDevice? get selectedDevice => _selectedDevice;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get statusMessage => _statusMessage;
  ParentWebRtcService get webRtc => _webRtcService;

  void selectDevice(ChildDevice device) {
    _selectedDevice = device;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // ========================================================================
  // 1. 4-DIGIT BIND CODE VERIFICATION & CLAIM
  // ========================================================================

  /// Queries Firebase RTDB at `/devices/{cleanCode}` to verify presence and status
  Future<Map<String, dynamic>> verifyPairingCode(String code) async {
    final cleanCode = code.trim().toUpperCase();
    if (cleanCode.length < 4) {
      return {'valid': false, 'error': 'Pairing code must be at least 4 characters.'};
    }

    try {
      var data = await _rtdbClient.getPath('devices/$cleanCode');
      String resolvedCode = cleanCode;

      // Also try with FG- prefix if not found
      if (data == null || data is! Map<String, dynamic>) {
        final altData = await _rtdbClient.getPath('devices/FG-$cleanCode');
        if (altData is Map<String, dynamic>) {
          data = altData;
          resolvedCode = 'FG-$cleanCode';
        }
      }

      // Also try pure numeric if letters were included
      final numOnly = cleanCode.replaceAll(RegExp(r'\D'), '');
      if ((data == null || data is! Map<String, dynamic>) && numOnly.isNotEmpty) {
        final numData = await _rtdbClient.getPath('devices/$numOnly');
        if (numData is Map<String, dynamic>) {
          data = numData;
          resolvedCode = numOnly;
        }
      }

      if (data == null || data is! Map<String, dynamic>) {
        return {
          'valid': false,
          'error': 'No active child device found matching code "$cleanCode" in Firebase RTDB.',
        };
      }

      return _parseVerificationData(resolvedCode, data);
    } catch (e) {
      return {
        'valid': false,
        'error': 'Failed to reach Firebase RTDB: $e',
      };
    }
  }

  Map<String, dynamic> _parseVerificationData(String code, Map<String, dynamic> data) {
    final status = data['status']?.toString() ?? 'pending';
    final model = data['deviceModelName']?.toString() ??
        data['deviceName']?.toString() ??
        data['telemetry']?['deviceModelName']?.toString() ??
        'Android Smartphone';
    final telemetry = data['telemetry'] as Map<String, dynamic>? ?? {};
    final batteryNode = telemetry['battery'] as Map<String, dynamic>? ?? {};
    final battery = (batteryNode['level'] as num?)?.toInt() ??
        (telemetry['batteryLevel'] as num?)?.toInt() ??
        100;

    return {
      'valid': true,
      'code': code,
      'deviceModelName': model,
      'batteryLevel': battery,
      'status': status,
      'platform': data['platform'] ?? 'android',
      'rtdbPath': '/devices/$code',
    };
  }

  /// Claims child device node and adds to Parent active device list
  Future<ChildDevice> confirmPairDevice(String code, {String? customLabel}) async {
    final cleanCode = code.trim().toUpperCase();
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final payload = <String, dynamic>{
        'status': 'paired',
        'parentUid': parentUid,
        'pairedAt': now,
        'presence': {
          'online': true,
          'lastSeen': now,
          'heartbeatAt': now,
        },
      };

      if (customLabel != null && customLabel.trim().isNotEmpty) {
        payload['deviceModelName'] = customLabel.trim();
      }

      // Update RTDB node
      await _rtdbClient.updatePath('devices/$cleanCode', payload);
      await _rtdbClient.updatePath('pairings/$cleanCode', payload);

      // Fetch snapshot from RTDB
      final snapshot = await _rtdbClient.getPath('devices/$cleanCode');
      final deviceData = (snapshot is Map<String, dynamic>) ? snapshot : payload;

      final newDevice = ChildDevice.fromMap(cleanCode, deviceData);

      final existingIndex = _devices.indexWhere((d) => d.pairingCode == cleanCode);
      if (existingIndex >= 0) {
        _devices[existingIndex] = newDevice;
      } else {
        _devices.insert(0, newDevice);
      }

      _selectedDevice = newDevice;
      _isLoading = false;
      notifyListeners();
      return newDevice;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Pairing failed: $e';
      notifyListeners();
      rethrow;
    }
  }

  // ========================================================================
  // 2. REAL-TIME FIREBASE RTDB TELEMETRY SYNC (`/devices/{pairingCode}`)
  // ========================================================================

  /// Continuously polls live telemetry for all paired devices from Firebase RTDB
  void _startTelemetryPolling() {
    _telemetryPollingTimer?.cancel();
    _telemetryPollingTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) async {
      if (_devices.isEmpty) return;

      bool hasChanges = false;
      for (int i = 0; i < _devices.length; i++) {
        final dev = _devices[i];
        try {
          final data = await _rtdbClient.getPath('devices/${dev.pairingCode}');
          if (data is Map<String, dynamic>) {
            final updated = ChildDevice.fromMap(dev.pairingCode, data);
            _devices[i] = updated;
            if (_selectedDevice?.pairingCode == dev.pairingCode) {
              _selectedDevice = updated;
            }
            hasChanges = true;
          }
        } catch (_) {}
      }

      if (hasChanges) {
        notifyListeners();
      }
    });
  }

  /// Forces an immediate refresh of telemetry for the selected device
  Future<void> refreshSelectedDevice() async {
    if (_selectedDevice == null) return;
    try {
      final data = await _rtdbClient.getPath('devices/${_selectedDevice!.pairingCode}');
      if (data is Map<String, dynamic>) {
        final updated = ChildDevice.fromMap(_selectedDevice!.pairingCode, data);
        final idx = _devices.indexWhere((d) => d.pairingCode == _selectedDevice!.pairingCode);
        if (idx >= 0) _devices[idx] = updated;
        _selectedDevice = updated;
        notifyListeners();
      }
    } catch (_) {}
  }

  // ========================================================================
  // 3. REMOTE SIGNALS & HARDWARE CONTROL OVER RTDB
  // ========================================================================

  /// Triggers immediate hardware GPS fix update from child device
  Future<bool> refreshGpsLocation(String pairingCode) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final ok = await _rtdbClient.updatePath(
      'devices/$pairingCode/control',
      {
        'command': 'syncLocation',
        'commandId': 'cmd_${now}_gps',
        'parentUid': parentUid,
        'requestedAt': now,
        'acknowledged': false,
      },
    );
    if (ok) {
      _statusMessage = 'Dispatched real-time GPS refresh request to child device';
      notifyListeners();
    }
    return ok;
  }

  /// Starts real WebRTC remote camera feed
  Future<bool> startCameraStream(String pairingCode) async {
    return await _webRtcService.startCameraStream(pairingCode: pairingCode);
  }

  /// Stops WebRTC remote camera feed
  Future<void> stopCameraStream(String pairingCode) async {
    await _webRtcService.stopCameraStream(pairingCode);
  }

  /// Switches camera lens (Front/Back)
  Future<bool> switchCameraLens(String pairingCode) async {
    return await _webRtcService.switchCameraLens(pairingCode);
  }

  /// Starts real WebRTC screen mirror
  Future<bool> startScreenMirror(String pairingCode) async {
    return await _webRtcService.startScreenMirror(pairingCode: pairingCode);
  }

  /// Stops screen mirror
  Future<void> stopScreenMirror(String pairingCode) async {
    await _webRtcService.stopScreenMirror(pairingCode);
  }

  /// Starts real one-way remote audio
  Future<bool> startAudioStream(String pairingCode) async {
    return await _webRtcService.startAudioStream(pairingCode: pairingCode);
  }

  /// Stops one-way audio
  Future<void> stopAudioStream(String pairingCode) async {
    await _webRtcService.stopAudioStream(pairingCode);
  }

  /// Plays alarm / loud siren on child phone
  Future<bool> playSirenOnChildDevice(String pairingCode) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return await _rtdbClient.updatePath(
      'devices/$pairingCode/control',
      {
        'command': 'playSiren',
        'commandId': 'cmd_${now}_siren',
        'parentUid': parentUid,
        'requestedAt': now,
        'acknowledged': false,
      },
    );
  }

  /// Sends a generic remote command to child device
  Future<bool> sendRemoteCommand(String pairingCode, String command, [Map<String, dynamic>? extra]) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final payload = {
      'command': command,
      'commandId': 'cmd_${now}_$command',
      'parentUid': parentUid,
      'requestedAt': now,
      'acknowledged': false,
      ...?extra,
    };
    return await _rtdbClient.updatePath('devices/$pairingCode/control', payload);
  }

  /// Unlinks child device
  Future<void> unpairDevice(String pairingCode) async {
    await _webRtcService.stopCameraStream(pairingCode);
    await _webRtcService.stopScreenMirror(pairingCode);
    await _webRtcService.stopAudioStream(pairingCode);

    _devices.removeWhere((d) => d.pairingCode == pairingCode);
    if (_selectedDevice?.pairingCode == pairingCode) {
      _selectedDevice = _devices.isNotEmpty ? _devices.first : null;
    }

    await _rtdbClient.updatePath('devices/$pairingCode', {
      'status': 'unpaired',
      'unpairedAt': DateTime.now().millisecondsSinceEpoch,
    });
    notifyListeners();
  }

  @override
  void dispose() {
    _telemetryPollingTimer?.cancel();
    _webRtcService.dispose();
    super.dispose();
  }
}
