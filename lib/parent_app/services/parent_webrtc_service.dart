import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../child_app/core/services/rtdb_client_service.dart';

/// Real WebRTC Streaming & Media Rendering Service for Parent Console
/// Manages real P2P video/audio streams and RTDB signaling with the child device.
class ParentWebRtcService {
  final RtdbClientService _rtdbClient;
  final String parentUid;

  final RTCVideoRenderer cameraRenderer = RTCVideoRenderer();
  final RTCVideoRenderer screenRenderer = RTCVideoRenderer();

  RTCPeerConnection? _cameraPeerConnection;
  RTCPeerConnection? _screenPeerConnection;
  RTCPeerConnection? _audioPeerConnection;

  Timer? _cameraSignalingTimer;
  Timer? _screenSignalingTimer;
  Timer? _audioSignalingTimer;

  bool _isCameraConnecting = false;
  bool _isCameraConnected = false;
  bool _isScreenConnecting = false;
  bool _isScreenConnected = false;
  bool _isAudioConnecting = false;
  bool _isAudioConnected = false;

  String _currentCameraFacing = 'back';
  String? _lastError;
  bool _isInitialized = false;

  void Function(String status)? onStatusUpdate;
  void Function(String error)? onError;
  void Function()? onStreamStateChanged;

  ParentWebRtcService({
    RtdbClientService? rtdbClient,
    this.parentUid = 'parent_console_uid',
  }) : _rtdbClient = rtdbClient ?? RtdbClientService();

  bool get isCameraConnecting => _isCameraConnecting;
  bool get isCameraConnected => _isCameraConnected;
  bool get isScreenConnecting => _isScreenConnecting;
  bool get isScreenConnected => _isScreenConnected;
  bool get isAudioConnecting => _isAudioConnecting;
  bool get isAudioConnected => _isAudioConnected;
  String get currentCameraFacing => _currentCameraFacing;
  String? get lastError => _lastError;
  bool get isInitialized => _isInitialized;

  /// Initializes hardware video renderers
  Future<void> initializeRenderers() async {
    if (_isInitialized) return;
    try {
      await cameraRenderer.initialize();
      await screenRenderer.initialize();
      _isInitialized = true;
    } catch (e) {
      _lastError = 'Failed to initialize WebRTC renderers: $e';
      onError?.call(_lastError!);
    }
  }

  final Map<String, dynamic> _rtcConfiguration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  // ========================================================================
  // 1. REAL CAMERA STREAMING (WebRTC PeerConnection over RTDB)
  // ========================================================================

  /// Connects to Child Camera stream via real WebRTC signaling
  Future<bool> startCameraStream({
    required String pairingCode,
    String cameraFacing = 'back',
  }) async {
    final cleanCode = pairingCode.trim();
    if (cleanCode.isEmpty) return false;

    _isCameraConnecting = true;
    _currentCameraFacing = cameraFacing;
    onStatusUpdate?.call('Initiating WebRTC camera session…');
    onStreamStateChanged?.call();

    try {
      await initializeRenderers();
      await stopCameraStream(cleanCode);

      _cameraPeerConnection = await createPeerConnection(_rtcConfiguration);

      // Handle incoming remote video track from child device
      _cameraPeerConnection!.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          cameraRenderer.srcObject = event.streams[0];
          _isCameraConnected = true;
          _isCameraConnecting = false;
          onStatusUpdate?.call('Live child camera feed active');
          onStreamStateChanged?.call();
        }
      };

      _cameraPeerConnection!.onConnectionState = (RTCPeerConnectionState state) {
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _isCameraConnected = true;
          _isCameraConnecting = false;
          onStatusUpdate?.call('WebRTC Peer Connection Connected');
        } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          _isCameraConnected = false;
          onStatusUpdate?.call('Camera connection $state');
        }
        onStreamStateChanged?.call();
      };

      // Listen for ICE candidates and write to RTDB
      _cameraPeerConnection!.onIceCandidate = (RTCIceCandidate candidate) async {
        final now = DateTime.now().millisecondsSinceEpoch;
        await _rtdbClient.updatePath(
          'devices/$cleanCode/stream/parentCandidates/$now',
          {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        );
      };

      // Add transceivers to receive video & audio
      try {
        await _cameraPeerConnection!.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
        );
        await _cameraPeerConnection!.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
        );
      } catch (_) {}

      // Create WebRTC Offer
      final offer = await _cameraPeerConnection!.createOffer({
        'offerToReceiveVideo': true,
        'offerToReceiveAudio': true,
      });
      await _cameraPeerConnection!.setLocalDescription(offer);

      // Publish offer to RTDB at `/devices/{cleanCode}/stream/offer`
      await _rtdbClient.updatePath(
        'devices/$cleanCode/stream',
        {
          'offer': {
            'type': offer.type,
            'sdp': offer.sdp,
            'cameraFacing': _currentCameraFacing,
            'initiator': parentUid,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
          'answer': null,
          'status': 'offer_created',
        },
      );

      // Trigger child device camera start via control command
      final now = DateTime.now().millisecondsSinceEpoch;
      await _rtdbClient.updatePath(
        'devices/$cleanCode/control',
        {
          'command': 'startStream',
          'cameraFacing': _currentCameraFacing,
          'commandId': 'cmd_${now}_cam',
          'parentUid': parentUid,
          'requestedAt': now,
          'acknowledged': false,
        },
      );

      // Start polling for Child's SDP answer & ICE candidates
      _startCameraAnswerListener(cleanCode);
      return true;
    } catch (e) {
      _isCameraConnecting = false;
      _isCameraConnected = false;
      _lastError = 'Camera signaling failed: $e';
      onError?.call(_lastError!);
      onStreamStateChanged?.call();
      return false;
    }
  }

  void _startCameraAnswerListener(String pairingCode) {
    _cameraSignalingTimer?.cancel();
    _cameraSignalingTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) async {
      if (_cameraPeerConnection == null) return;

      try {
        final streamNode = await _rtdbClient.getPath('devices/$pairingCode/stream');
        if (streamNode is Map<String, dynamic>) {
          final answer = streamNode['answer'] as Map<String, dynamic>?;

          if (answer != null &&
              _cameraPeerConnection?.signalingState ==
                  RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
            final sdp = answer['sdp'] as String?;
            final type = answer['type'] as String? ?? 'answer';

            if (sdp != null && sdp.isNotEmpty) {
              await _cameraPeerConnection!.setRemoteDescription(
                RTCSessionDescription(sdp, type),
              );
              onStatusUpdate?.call('Remote answer set. Waiting for media frames…');
            }
          }

          // Ingest child ICE candidates
          final childCandidates = streamNode['childCandidates'] as Map<String, dynamic>?;
          if (childCandidates != null) {
            for (final candItem in childCandidates.values) {
              if (candItem is Map<String, dynamic>) {
                final cand = candItem['candidate'] as String?;
                final mid = candItem['sdpMid'] as String?;
                final idx = candItem['sdpMLineIndex'] as int?;
                if (cand != null) {
                  await _cameraPeerConnection!.addCandidate(
                    RTCIceCandidate(cand, mid, idx),
                  );
                }
              }
            }
          }
        }
      } catch (_) {}
    });
  }

  /// Switches camera between front and back lens
  Future<bool> switchCameraLens(String pairingCode) async {
    _currentCameraFacing = _currentCameraFacing == 'front' ? 'back' : 'front';
    final now = DateTime.now().millisecondsSinceEpoch;

    await _rtdbClient.updatePath(
      'devices/$pairingCode/control',
      {
        'command': 'switchCamera',
        'cameraFacing': _currentCameraFacing,
        'commandId': 'cmd_${now}_switchCam',
        'parentUid': parentUid,
        'requestedAt': now,
        'acknowledged': false,
      },
    );

    onStatusUpdate?.call('Switched lens to ${_currentCameraFacing.toUpperCase()}');
    onStreamStateChanged?.call();
    return true;
  }

  /// Stops camera stream and cleans up WebRTC peer connection
  Future<void> stopCameraStream(String pairingCode) async {
    _cameraSignalingTimer?.cancel();
    _cameraSignalingTimer = null;
    _isCameraConnecting = false;
    _isCameraConnected = false;

    try {
      if (_cameraPeerConnection != null) {
        await _cameraPeerConnection!.close();
        await _cameraPeerConnection!.dispose();
        _cameraPeerConnection = null;
      }
      cameraRenderer.srcObject = null;

      if (pairingCode.isNotEmpty) {
        final now = DateTime.now().millisecondsSinceEpoch;
        await _rtdbClient.updatePath(
          'devices/$pairingCode/control',
          {
            'command': 'stopStream',
            'commandId': 'cmd_${now}_stopCam',
            'parentUid': parentUid,
            'requestedAt': now,
            'acknowledged': false,
          },
        );
        await _rtdbClient.updatePath(
          'devices/$pairingCode/stream',
          {
            'status': 'stopped',
            'stoppedAt': now,
          },
        );
      }
    } catch (_) {}

    onStreamStateChanged?.call();
  }

  // ========================================================================
  // 2. REAL SCREEN MIRRORING (WebRTC DisplayMedia / Frames)
  // ========================================================================

  /// Connects to Child Screen Mirror stream
  Future<bool> startScreenMirror({required String pairingCode}) async {
    final cleanCode = pairingCode.trim();
    if (cleanCode.isEmpty) return false;

    _isScreenConnecting = true;
    onStatusUpdate?.call('Initiating screen mirror session…');
    onStreamStateChanged?.call();

    try {
      await initializeRenderers();
      await stopScreenMirror(cleanCode);

      _screenPeerConnection = await createPeerConnection(_rtcConfiguration);

      _screenPeerConnection!.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          screenRenderer.srcObject = event.streams[0];
          _isScreenConnected = true;
          _isScreenConnecting = false;
          onStatusUpdate?.call('Live child screen streaming (WebRTC)');
          onStreamStateChanged?.call();
        }
      };

      _screenPeerConnection!.onConnectionState = (RTCPeerConnectionState state) {
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _isScreenConnected = true;
          _isScreenConnecting = false;
          onStatusUpdate?.call('Screen mirror connected');
        } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          _isScreenConnected = false;
        }
        onStreamStateChanged?.call();
      };

      _screenPeerConnection!.onIceCandidate = (RTCIceCandidate candidate) async {
        final now = DateTime.now().millisecondsSinceEpoch;
        await _rtdbClient.updatePath(
          'devices/$cleanCode/screen/parentCandidates/$now',
          {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        );
      };

      try {
        await _screenPeerConnection!.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
        );
      } catch (_) {}

      final offer = await _screenPeerConnection!.createOffer({
        'offerToReceiveVideo': true,
      });
      await _screenPeerConnection!.setLocalDescription(offer);

      await _rtdbClient.updatePath(
        'devices/$cleanCode/screen',
        {
          'offer': {
            'type': offer.type,
            'sdp': offer.sdp,
            'initiator': parentUid,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
          'answer': null,
          'status': 'mirroring',
          'isSharing': true,
        },
      );

      final now = DateTime.now().millisecondsSinceEpoch;
      await _rtdbClient.updatePath(
        'devices/$cleanCode/control',
        {
          'command': 'startScreenShare',
          'commandId': 'cmd_${now}_screen',
          'parentUid': parentUid,
          'requestedAt': now,
          'acknowledged': false,
        },
      );

      _startScreenAnswerListener(cleanCode);
      return true;
    } catch (e) {
      _isScreenConnecting = false;
      _isScreenConnected = false;
      _lastError = 'Screen mirror signaling failed: $e';
      onError?.call(_lastError!);
      onStreamStateChanged?.call();
      return false;
    }
  }

  void _startScreenAnswerListener(String pairingCode) {
    _screenSignalingTimer?.cancel();
    _screenSignalingTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) async {
      if (_screenPeerConnection == null) return;

      try {
        final screenNode = await _rtdbClient.getPath('devices/$pairingCode/screen');
        if (screenNode is Map<String, dynamic>) {
          final answer = screenNode['answer'] as Map<String, dynamic>?;

          if (answer != null &&
              _screenPeerConnection?.signalingState ==
                  RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
            final sdp = answer['sdp'] as String?;
            final type = answer['type'] as String? ?? 'answer';
            if (sdp != null && sdp.isNotEmpty) {
              await _screenPeerConnection!.setRemoteDescription(
                RTCSessionDescription(sdp, type),
              );
              onStatusUpdate?.call('Screen stream established');
            }
          }

          final childCandidates = screenNode['childCandidates'] as Map<String, dynamic>?;
          if (childCandidates != null) {
            for (final candItem in childCandidates.values) {
              if (candItem is Map<String, dynamic>) {
                final cand = candItem['candidate'] as String?;
                final mid = candItem['sdpMid'] as String?;
                final idx = candItem['sdpMLineIndex'] as int?;
                if (cand != null) {
                  await _screenPeerConnection!.addCandidate(
                    RTCIceCandidate(cand, mid, idx),
                  );
                }
              }
            }
          }
        }
      } catch (_) {}
    });
  }

  /// Stops screen mirror session
  Future<void> stopScreenMirror(String pairingCode) async {
    _screenSignalingTimer?.cancel();
    _screenSignalingTimer = null;
    _isScreenConnecting = false;
    _isScreenConnected = false;

    try {
      if (_screenPeerConnection != null) {
        await _screenPeerConnection!.close();
        await _screenPeerConnection!.dispose();
        _screenPeerConnection = null;
      }
      screenRenderer.srcObject = null;

      if (pairingCode.isNotEmpty) {
        final now = DateTime.now().millisecondsSinceEpoch;
        await _rtdbClient.updatePath(
          'devices/$pairingCode/control',
          {
            'command': 'stopScreenShare',
            'commandId': 'cmd_${now}_stopScreen',
            'parentUid': parentUid,
            'requestedAt': now,
            'acknowledged': false,
          },
        );
        await _rtdbClient.updatePath(
          'devices/$pairingCode/screen',
          {
            'status': 'standby',
            'isSharing': false,
            'stoppedAt': now,
          },
        );
      }
    } catch (_) {}

    onStreamStateChanged?.call();
  }

  // ========================================================================
  // 3. REAL ONE-WAY REMOTE AUDIO (WebRTC Audio Receiver)
  // ========================================================================

  Future<bool> startAudioStream({required String pairingCode}) async {
    final cleanCode = pairingCode.trim();
    if (cleanCode.isEmpty) return false;

    _isAudioConnecting = true;
    onStreamStateChanged?.call();

    try {
      await stopAudioStream(cleanCode);

      _audioPeerConnection = await createPeerConnection(_rtcConfiguration);

      try {
        await _audioPeerConnection!.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
        );
      } catch (_) {}

      final offer = await _audioPeerConnection!.createOffer({
        'offerToReceiveAudio': true,
      });
      await _audioPeerConnection!.setLocalDescription(offer);

      await _rtdbClient.updatePath(
        'devices/$cleanCode/audio',
        {
          'offer': {
            'type': offer.type,
            'sdp': offer.sdp,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
          'answer': null,
          'status': 'transmitting',
        },
      );

      final now = DateTime.now().millisecondsSinceEpoch;
      await _rtdbClient.updatePath(
        'devices/$cleanCode/control',
        {
          'command': 'startAudioStream',
          'commandId': 'cmd_${now}_audio',
          'parentUid': parentUid,
          'requestedAt': now,
          'acknowledged': false,
        },
      );

      _startAudioAnswerListener(cleanCode);
      _isAudioConnected = true;
      _isAudioConnecting = false;
      onStreamStateChanged?.call();
      return true;
    } catch (e) {
      _isAudioConnecting = false;
      _isAudioConnected = false;
      _lastError = 'Audio signaling error: $e';
      onError?.call(_lastError!);
      onStreamStateChanged?.call();
      return false;
    }
  }

  void _startAudioAnswerListener(String pairingCode) {
    _audioSignalingTimer?.cancel();
    _audioSignalingTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
      if (_audioPeerConnection == null) return;
      try {
        final audioNode = await _rtdbClient.getPath('devices/$pairingCode/audio');
        if (audioNode is Map<String, dynamic>) {
          final answer = audioNode['answer'] as Map<String, dynamic>?;
          if (answer != null &&
              _audioPeerConnection?.signalingState ==
                  RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
            final sdp = answer['sdp'] as String?;
            final type = answer['type'] as String? ?? 'answer';
            if (sdp != null) {
              await _audioPeerConnection!.setRemoteDescription(
                RTCSessionDescription(sdp, type),
              );
            }
          }
        }
      } catch (_) {}
    });
  }

  Future<void> stopAudioStream(String pairingCode) async {
    _audioSignalingTimer?.cancel();
    _audioSignalingTimer = null;
    _isAudioConnecting = false;
    _isAudioConnected = false;

    try {
      if (_audioPeerConnection != null) {
        await _audioPeerConnection!.close();
        await _audioPeerConnection!.dispose();
        _audioPeerConnection = null;
      }

      if (pairingCode.isNotEmpty) {
        final now = DateTime.now().millisecondsSinceEpoch;
        await _rtdbClient.updatePath(
          'devices/$pairingCode/control',
          {
            'command': 'stopAudioStream',
            'commandId': 'cmd_${now}_stopAudio',
            'parentUid': parentUid,
            'requestedAt': now,
            'acknowledged': false,
          },
        );
        await _rtdbClient.updatePath(
          'devices/$pairingCode/audio',
          {
            'status': 'standby',
            'isTransmitting': false,
            'stoppedAt': now,
          },
        );
      }
    } catch (_) {}

    onStreamStateChanged?.call();
  }

  void dispose() {
    _cameraSignalingTimer?.cancel();
    _screenSignalingTimer?.cancel();
    _audioSignalingTimer?.cancel();
    _cameraPeerConnection?.dispose();
    _screenPeerConnection?.dispose();
    _audioPeerConnection?.dispose();
    cameraRenderer.dispose();
    screenRenderer.dispose();
  }
}
