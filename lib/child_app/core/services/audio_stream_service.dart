import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'rtdb_client_service.dart';
import 'foreground_task_service.dart';

/// Real Hardware Microphone Audio Streaming Service for Child Device
/// Captures physical microphone input using `flutter_webrtc` and streams over peer connection.
class AudioStreamService {
  final RtdbClientService _rtdbClient;
  final ForegroundTaskService _foregroundService;

  MediaStream? _audioStream;
  RTCPeerConnection? _peerConnection;
  Timer? _signalingPollTimer;

  bool _isTransmitting = false;
  int _sampleRate = 44100;
  String _currentPairingCode = '';
  String? _lastError;

  void Function(bool isTransmitting)? onStateChanged;
  void Function(String error)? onError;

  AudioStreamService({
    RtdbClientService? rtdbClient,
    ForegroundTaskService? foregroundService,
  })  : _rtdbClient = rtdbClient ?? RtdbClientService(),
        _foregroundService = foregroundService ?? ForegroundTaskService();

  bool get isTransmitting => _isTransmitting;
  int get sampleRate => _sampleRate;
  String? get lastError => _lastError;

  /// Starts real hardware microphone audio transmission
  Future<bool> startAudioStream({required String pairingCode}) async {
    _currentPairingCode = pairingCode.trim();

    try {
      await stopAudioStream(_currentPairingCode);

      // 1. Capture real physical microphone stream
      final mediaConstraints = <String, dynamic>{
        'audio': {
          'sampleRate': _sampleRate,
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      };

      _audioStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);

      // 2. Initialize real WebRTC PeerConnection for Audio Relay
      final rtcConfig = <String, dynamic>{
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
        'sdpSemantics': 'unified-plan',
      };

      _peerConnection = await createPeerConnection(rtcConfig);

      for (final track in _audioStream!.getAudioTracks()) {
        await _peerConnection!.addTrack(track, _audioStream!);
      }

      _isTransmitting = true;

      // 3. Update RTDB status
      await _rtdbClient.updatePath(
        'devices/$_currentPairingCode/audio',
        {
          'status': 'transmitting',
          'isTransmitting': true,
          'sampleRate': _sampleRate,
          'codec': 'opus',
          'source': 'hardware_mic',
          'startedAt': DateTime.now().millisecondsSinceEpoch,
        },
      );

      // 4. Update Android 14 Foreground Service Notification
      await _foregroundService.updateNotification(
        title: 'KidGuard Audio Active',
        text: 'One-way background microphone relay active',
      );

      _startAudioSignaling();
      onStateChanged?.call(true);
      return true;
    } catch (e) {
      _isTransmitting = false;
      _lastError = 'Audio streaming failed: $e';
      onError?.call(_lastError!);
      return false;
    }
  }

  void _startAudioSignaling() {
    _signalingPollTimer?.cancel();
    _signalingPollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
      if (!_isTransmitting || _currentPairingCode.isEmpty || _peerConnection == null) return;

      try {
        final audioNode = await _rtdbClient.getPath('devices/$_currentPairingCode/audio');
        if (audioNode is Map<String, dynamic>) {
          final offer = audioNode['offer'] as Map<String, dynamic>?;
          final answer = audioNode['answer'] as Map<String, dynamic>?;

          if (offer != null && answer == null) {
            final sdp = offer['sdp'] as String?;
            final type = offer['type'] as String? ?? 'offer';
            if (sdp != null) {
              await _peerConnection!.setRemoteDescription(RTCSessionDescription(sdp, type));
              final createdAnswer = await _peerConnection!.createAnswer();
              await _peerConnection!.setLocalDescription(createdAnswer);

              await _rtdbClient.updatePath('devices/$_currentPairingCode/audio/answer', {
                'type': createdAnswer.type,
                'sdp': createdAnswer.sdp,
                'answeredAt': DateTime.now().millisecondsSinceEpoch,
              });
            }
          }
        }
      } catch (_) {}
    });
  }

  /// Stops physical microphone streaming
  Future<bool> stopAudioStream(String pairingCode) async {
    _isTransmitting = false;
    _signalingPollTimer?.cancel();
    _signalingPollTimer = null;

    try {
      if (_audioStream != null) {
        for (final track in _audioStream!.getTracks()) {
          track.stop();
        }
        await _audioStream!.dispose();
        _audioStream = null;
      }

      if (_peerConnection != null) {
        await _peerConnection!.close();
        await _peerConnection!.dispose();
        _peerConnection = null;
      }

      if (pairingCode.isNotEmpty) {
        await _rtdbClient.updatePath(
          'devices/$pairingCode/audio',
          {
            'status': 'standby',
            'isTransmitting': false,
            'stoppedAt': DateTime.now().millisecondsSinceEpoch,
          },
        );
      }

      onStateChanged?.call(false);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> toggleAudioStream(String pairingCode) async {
    if (_isTransmitting) {
      return await stopAudioStream(pairingCode);
    } else {
      return await startAudioStream(pairingCode: pairingCode);
    }
  }

  void dispose() {
    stopAudioStream(_currentPairingCode);
  }
}
