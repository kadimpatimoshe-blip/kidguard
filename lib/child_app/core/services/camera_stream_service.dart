import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'rtdb_client_service.dart';
import 'foreground_task_service.dart';

/// Real WebRTC Remote Camera Streaming Service for Child Device
/// Uses real device camera sensors via `flutter_webrtc` and exchanges SDP/ICE over Firebase RTDB.
class CameraStreamService {
  final RtdbClientService _rtdbClient;
  final ForegroundTaskService _foregroundService;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  StreamSubscription? _signalingSubscription;
  Timer? _signalingPollTimer;

  bool _isStreaming = false;
  String _cameraFacing = 'back'; // 'back' | 'front'
  bool _isMicMuted = false;
  String _currentPairingCode = '';
  String? _lastError;

  void Function(bool isStreaming)? onStreamStateChanged;
  void Function(String error)? onError;

  CameraStreamService({
    RtdbClientService? rtdbClient,
    ForegroundTaskService? foregroundService,
  })  : _rtdbClient = rtdbClient ?? RtdbClientService(),
        _foregroundService = foregroundService ?? ForegroundTaskService();

  bool get isStreaming => _isStreaming;
  String get cameraFacing => _cameraFacing;
  bool get isMicMuted => _isMicMuted;
  MediaStream? get localStream => _localStream;
  String? get lastError => _lastError;

  /// Starts real hardware camera feed and establishes WebRTC signaling
  Future<bool> startStream({
    required String pairingCode,
    String cameraFacing = 'back',
  }) async {
    _currentPairingCode = pairingCode.trim();
    _cameraFacing = cameraFacing;

    try {
      // 1. Release any existing stream
      await stopStream(_currentPairingCode);

      // 2. Request real device camera and microphone hardware tracks
      final mediaConstraints = <String, dynamic>{
        'audio': true,
        'video': {
          'facingMode': _cameraFacing == 'front' ? 'user' : 'environment',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
          'frameRate': {'ideal': 24},
        },
      };

      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);

      // 3. Initialize real WebRTC PeerConnection
      final rtcConfig = <String, dynamic>{
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
          {'urls': 'stun:stun2.l.google.com:19302'},
        ],
        'sdpSemantics': 'unified-plan',
      };

      _peerConnection = await createPeerConnection(rtcConfig);

      // Add local media tracks to WebRTC peer connection
      for (final track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }

      // Handle ICE Candidates from physical device
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) async {
        if (_currentPairingCode.isEmpty) return;
        final candidateData = {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        };
        await _rtdbClient.updatePath(
          'devices/$_currentPairingCode/stream/childCandidates/${DateTime.now().millisecondsSinceEpoch}',
          candidateData,
        );
      };

      // 4. Update status in RTDB
      _isStreaming = true;
      await _rtdbClient.updatePath(
        'devices/$_currentPairingCode/stream',
        {
          'status': 'active',
          'cameraFacing': _cameraFacing,
          'micMuted': _isMicMuted,
          'signalingReady': true,
          'startedAt': DateTime.now().millisecondsSinceEpoch,
        },
      );

      // 5. Start listening for Parent WebRTC Offer via RTDB
      _startSignalingListener();

      // 6. Update Android 14 Foreground Notification
      await _foregroundService.updateNotification(
        title: 'KidGuard Camera Active',
        text: 'Live encrypted camera stream transmitting (Back Lens)',
      );

      onStreamStateChanged?.call(true);
      return true;
    } catch (e) {
      _lastError = 'WebRTC Camera error: $e';
      onError?.call(_lastError!);
      _isStreaming = false;
      return false;
    }
  }

  /// Listens for Parent SDP offer and answers via RTDB signaling
  void _startSignalingListener() {
    _signalingPollTimer?.cancel();
    _signalingPollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
      if (!_isStreaming || _currentPairingCode.isEmpty || _peerConnection == null) return;

      try {
        final streamNode = await _rtdbClient.getPath('devices/$_currentPairingCode/stream');
        if (streamNode is Map<String, dynamic>) {
          // Check for incoming offer from Parent Console
          final offer = streamNode['offer'] as Map<String, dynamic>?;
          final answer = streamNode['answer'] as Map<String, dynamic>?;

          if (offer != null && answer == null) {
            final sdp = offer['sdp'] as String?;
            final type = offer['type'] as String? ?? 'offer';

            if (sdp != null && sdp.isNotEmpty) {
              await _peerConnection!.setRemoteDescription(
                RTCSessionDescription(sdp, type),
              );

              final createdAnswer = await _peerConnection!.createAnswer();
              await _peerConnection!.setLocalDescription(createdAnswer);

              await _rtdbClient.updatePath(
                'devices/$_currentPairingCode/stream/answer',
                {
                  'type': createdAnswer.type,
                  'sdp': createdAnswer.sdp,
                  'answeredAt': DateTime.now().millisecondsSinceEpoch,
                },
              );
            }
          }

          // Process any parent ICE candidates
          final parentCandidates = streamNode['parentCandidates'] as Map<String, dynamic>?;
          if (parentCandidates != null) {
            for (final candItem in parentCandidates.values) {
              if (candItem is Map<String, dynamic>) {
                final candStr = candItem['candidate'] as String?;
                final sdpMid = candItem['sdpMid'] as String?;
                final sdpMLineIndex = candItem['sdpMLineIndex'] as int?;
                if (candStr != null) {
                  await _peerConnection!.addCandidate(
                    RTCIceCandidate(candStr, sdpMid, sdpMLineIndex),
                  );
                }
              }
            }
          }
        }
      } catch (_) {}
    });
  }

  /// Switches camera between front and back physical lenses
  Future<bool> switchCamera({
    required String pairingCode,
    String? preferredFacing,
  }) async {
    _cameraFacing = preferredFacing ?? (_cameraFacing == 'front' ? 'back' : 'front');

    if (_localStream != null) {
      final videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        await Helper.switchCamera(videoTracks.first);
      }
    }

    if (_isStreaming) {
      await _rtdbClient.updatePath(
        'devices/$pairingCode/stream',
        {'cameraFacing': _cameraFacing},
      );
    }
    return true;
  }

  /// Toggles microphone audio track
  Future<bool> toggleAudioMute(String pairingCode) async {
    _isMicMuted = !_isMicMuted;

    if (_localStream != null) {
      for (final track in _localStream!.getAudioTracks()) {
        track.enabled = !_isMicMuted;
      }
    }

    if (_isStreaming) {
      await _rtdbClient.updatePath(
        'devices/$pairingCode/stream',
        {'micMuted': _isMicMuted},
      );
    }
    return true;
  }

  /// Stops camera stream, releases hardware tracks, and updates RTDB
  Future<bool> stopStream(String pairingCode) async {
    _isStreaming = false;
    _signalingPollTimer?.cancel();
    _signalingPollTimer = null;

    try {
      // Stop and dispose real media stream hardware tracks
      if (_localStream != null) {
        for (final track in _localStream!.getTracks()) {
          track.stop();
        }
        await _localStream!.dispose();
        _localStream = null;
      }

      if (_peerConnection != null) {
        await _peerConnection!.close();
        await _peerConnection!.dispose();
        _peerConnection = null;
      }

      if (pairingCode.isNotEmpty) {
        await _rtdbClient.updatePath(
          'devices/$pairingCode/stream',
          {
            'status': 'stopped',
            'stoppedAt': DateTime.now().millisecondsSinceEpoch,
          },
        );
      }

      await _foregroundService.updateNotification(
        title: 'KidGuard Protection Active',
        text: 'Continuous telemetry sync active',
      );

      onStreamStateChanged?.call(false);
      return true;
    } catch (e) {
      return false;
    }
  }

  void dispose() {
    stopStream(_currentPairingCode);
  }
}
