import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

class WebRTCService {
  WebRTCService({this.onError, this.onConnectionState});

  static const _peerConfiguration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
  };

  final void Function(Object error)? onError;
  final void Function(RTCPeerConnectionState state)? onConnectionState;
  RTCVideoRenderer? localRenderer;
  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  DatabaseReference? _signalReference;
  String? _sessionId;
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  StreamSubscription<DatabaseEvent>? _answerSubscription;
  StreamSubscription<DatabaseEvent>? _candidateSubscription;
  StreamSubscription<DatabaseEvent>? _viewerStatusSubscription;
  bool _remoteDescriptionSet = false;
  bool _disposed = false;
  bool _audioMuted = false;
  bool _usingFrontCamera = true;

  bool get audioMuted => _audioMuted;

  Future<void> startPublishing({
    required FirebaseDatabase database,
    required String deviceId,
    required String parentUid,
    required String childId,
  }) async {
    if (!_isValidDatabaseKey(deviceId) || !_isValidDatabaseKey(childId)) {
      throw ArgumentError.value(deviceId, 'deviceId', 'Invalid RTDB key.');
    }

    _disposed = false;
    _remoteDescriptionSet = false;
    _pendingRemoteCandidates.clear();
    if (!kIsWeb) await _requestPermissions();
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': {
        'facingMode': 'user',
        'width': {'ideal': 1280},
        'height': {'ideal': 720},
        'frameRate': {'ideal': 30},
      },
    });
    if (kIsWeb && localStream!.getVideoTracks().isNotEmpty) {
      _usingFrontCamera =
          localStream!.getVideoTracks().first.getSettings()['facingMode'] !=
              'environment';
    }
    localRenderer = RTCVideoRenderer();
    await localRenderer!.initialize();
    localRenderer!.srcObject = localStream;

    peerConnection = await createPeerConnection(_peerConfiguration);
    peerConnection!.onConnectionState = (state) {
      onConnectionState?.call(state);
    };
    peerConnection!.onIceCandidate = (candidate) {
      unawaited(_writeCandidate('childCandidates', candidate));
    };
    for (final track in localStream!.getTracks()) {
      await peerConnection!.addTrack(track, localStream!);
    }

    _sessionId = '${deviceId}_${DateTime.now().microsecondsSinceEpoch}';
    _signalReference = database.ref('/webrtc_signaling/$deviceId');
    await _signalReference!.update({
      'deviceId': deviceId,
      'childId': childId,
      'sessionId': _sessionId,
      'parentUid': parentUid,
      'status': 'offered',
      'offer': null,
      'answer': null,
      'childCandidates': null,
      'parentCandidates': null,
      'viewerStatus': 'waiting',
      'updatedAt': ServerValue.timestamp,
    });
    await _signalReference!.child('viewerStatus').onDisconnect().set('stopped');
    _answerSubscription = _signalReference!.child('answer').onValue.listen(
          _handleAnswer,
          onError: _reportError,
        );
    _candidateSubscription = _signalReference!
        .child('parentCandidates')
        .onChildAdded
        .listen(_handleRemoteCandidate, onError: _reportError);
    _viewerStatusSubscription =
        _signalReference!.child('viewerStatus').onValue.listen((event) {
      if (event.snapshot.value == 'stopped') {
        unawaited(_stopAfterViewerExit());
      }
    }, onError: _reportError);

    final offer = await peerConnection!.createOffer();
    await peerConnection!.setLocalDescription(offer);
    await _signalReference!.update({
      'offer': offer.toMap(),
      'updatedAt': ServerValue.timestamp,
    });
  }

  Future<void> _stopAfterViewerExit() async {
    if (_disposed) return;
    onConnectionState?.call(
      RTCPeerConnectionState.RTCPeerConnectionStateClosed,
    );
    await dispose();
  }

  Future<void> _requestPermissions() async {
    if (kIsWeb) return;

    final statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();
    if (statuses[Permission.camera]?.isGranted != true ||
        statuses[Permission.microphone]?.isGranted != true) {
      throw StateError(
        'Camera and microphone access are required to start a live stream.',
      );
    }
  }

  void _handleAnswer(DatabaseEvent event) {
    unawaited(_applyAnswer(event.snapshot.value));
  }

  Future<void> _applyAnswer(Object? value) async {
    if (value is! Map ||
        value['sessionId'] != _sessionId ||
        value['sdp'] is! String ||
        value['type'] is! String ||
        _remoteDescriptionSet) {
      return;
    }
    await peerConnection!.setRemoteDescription(
      RTCSessionDescription(value['sdp'] as String, value['type'] as String),
    );
    _remoteDescriptionSet = true;
    await _applyPendingCandidates();
  }

  void _handleRemoteCandidate(DatabaseEvent event) {
    final value = event.snapshot.value;
    if (value is! Map || value['sessionId'] != _sessionId) return;
    final candidate = _candidateFromMap(value);
    if (candidate == null) return;
    if (_remoteDescriptionSet) {
      unawaited(_addRemoteCandidate(candidate));
    } else {
      _pendingRemoteCandidates.add(candidate);
    }
  }

  Future<void> _applyPendingCandidates() async {
    final candidates = List<RTCIceCandidate>.from(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final candidate in candidates) {
      await _addRemoteCandidate(candidate);
    }
  }

  Future<void> _addRemoteCandidate(RTCIceCandidate candidate) async {
    try {
      await peerConnection?.addCandidate(candidate);
    } catch (error) {
      _reportError(error);
    }
  }

  Future<void> _writeCandidate(
    String collection,
    RTCIceCandidate candidate,
  ) async {
    final reference = _signalReference;
    final sessionId = _sessionId;
    if (reference == null || sessionId == null || candidate.candidate == null) {
      return;
    }
    try {
      await reference.child(collection).push().set({
        ...Map<String, dynamic>.from(candidate.toMap() as Map),
        'sessionId': sessionId,
      });
    } catch (error) {
      _reportError(error);
    }
  }

  RTCIceCandidate? _candidateFromMap(Map value) {
    if (value['candidate'] is! String) return null;
    final lineIndex = value['sdpMLineIndex'];
    return RTCIceCandidate(
      value['candidate'] as String,
      value['sdpMid'] is String ? value['sdpMid'] as String : null,
      lineIndex is int ? lineIndex : null,
    );
  }

  void _reportError(Object error, [StackTrace? stackTrace]) {
    debugPrint('WebRTC signaling failed: $error');
    if (stackTrace != null) debugPrintStack(stackTrace: stackTrace);
    onError?.call(error);
  }

  bool _isValidDatabaseKey(String value) {
    return value.isNotEmpty && !RegExp(r'[.#$\[\]/]').hasMatch(value);
  }

  Future<void> switchCamera() async {
    final stream = localStream;
    if (stream == null || stream.getVideoTracks().isEmpty) {
      throw StateError('Start a live stream before switching cameras.');
    }
    final videoTrack = stream.getVideoTracks().first;

    if (kIsWeb) {
      final cameras = await Helper.cameras;
      if (cameras.length < 2) {
        throw StateError('Front and back cameras are not both available.');
      }
      final currentDeviceId = videoTrack.getSettings()['deviceId'];
      final targetFront = !_usingFrontCamera;
      final targetByFacing = cameras.where((camera) {
        if (camera.deviceId == currentDeviceId) return false;
        final label = camera.label.toLowerCase();
        return targetFront
            ? label.contains('front') || label.contains('user')
            : label.contains('back') || label.contains('environment');
      }).toList();
      final alternatives = cameras
          .where((camera) => camera.deviceId != currentDeviceId)
          .toList();
      if (alternatives.isEmpty) {
        throw StateError('No alternate camera is available.');
      }
      final target =
          targetByFacing.isNotEmpty ? targetByFacing.first : alternatives.first;
      await Helper.switchCamera(videoTrack, target.deviceId, stream);

      final replacementTrack = stream.getVideoTracks().first;
      final senders = await peerConnection!.getSenders();
      for (final sender in senders) {
        if (sender.track?.kind == 'video') {
          await sender.replaceTrack(replacementTrack);
        }
      }
      _usingFrontCamera = targetFront;
      return;
    }

    await Helper.switchCamera(videoTrack);
    _usingFrontCamera = !_usingFrontCamera;
  }

  Future<bool> toggleAudioMute() async {
    final audioTracks = localStream?.getAudioTracks() ?? <MediaStreamTrack>[];
    if (audioTracks.isEmpty) {
      throw StateError('Start a live stream before muting audio.');
    }

    _audioMuted = !_audioMuted;
    for (final track in audioTracks) {
      track.enabled = !_audioMuted;
    }
    return _audioMuted;
  }

  Future<void> dispose() async {
    _disposed = true;
    await _answerSubscription?.cancel();
    await _candidateSubscription?.cancel();
    await _viewerStatusSubscription?.cancel();
    if (_signalReference != null && _sessionId != null) {
      try {
        await _signalReference!.child('viewerStatus').set('stopped');
      } catch (error) {
        _reportError(error);
      }
    }
    await peerConnection?.close();
    await localStream?.dispose();
    await localRenderer?.dispose();
    peerConnection = null;
    localStream = null;
    localRenderer = null;
    _audioMuted = false;
    _usingFrontCamera = true;
  }
}

class WebRTCViewerService {
  WebRTCViewerService({
    required this.database,
    required this.deviceId,
    required this.parentUid,
    required this.childId,
    this.onError,
    this.onConnectionState,
    this.onOfferReceived,
  });

  static const _peerConfiguration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
  };

  final FirebaseDatabase database;
  final String deviceId;
  final String parentUid;
  final String childId;
  final void Function(Object error)? onError;
  final void Function(RTCPeerConnectionState state)? onConnectionState;
  final VoidCallback? onOfferReceived;
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  StreamSubscription<DatabaseEvent>? _signalSubscription;
  StreamSubscription<DatabaseEvent>? _candidateSubscription;
  DatabaseReference? _signalReference;
  RTCPeerConnection? _peerConnection;
  String? _sessionId;
  bool _remoteDescriptionSet = false;
  bool _viewerStopped = false;

  Future<void> start() async {
    if (!_isValidDatabaseKey(deviceId) || !_isValidDatabaseKey(childId)) {
      throw ArgumentError.value(deviceId, 'deviceId', 'Invalid RTDB key.');
    }
    await remoteRenderer.initialize();
    _signalReference = database.ref('/webrtc_signaling/$deviceId');
    await _signalReference!.child('viewerStatus').onDisconnect().set('stopped');
    _signalSubscription = _signalReference!.onValue.listen(
      _handleSignal,
      onError: _reportError,
    );
  }

  void _handleSignal(DatabaseEvent event) {
    final value = event.snapshot.value;
    if (value is! Map) return;
    final sessionId = value['sessionId'];
    if (value['viewerStatus'] == 'stopped') {
      if (sessionId == _sessionId && !_viewerStopped) {
        unawaited(_stopViewing());
      }
      return;
    }
    final offer = value['offer'];
    if (value['parentUid'] != parentUid ||
        value['childId'] != childId ||
        sessionId is! String ||
        offer is! Map ||
        offer['sdp'] is! String ||
        offer['type'] is! String ||
        sessionId == _sessionId) {
      return;
    }
    _sessionId = sessionId;
    _viewerStopped = false;
    onOfferReceived?.call();
    unawaited(_answerOffer(offer, sessionId));
  }

  Future<void> _stopViewing() async {
    _viewerStopped = true;
    await _closePeerConnection();
    onConnectionState?.call(
      RTCPeerConnectionState.RTCPeerConnectionStateClosed,
    );
  }

  Future<void> _answerOffer(Map offer, String sessionId) async {
    await _closePeerConnection();
    _remoteDescriptionSet = false;
    _pendingRemoteCandidates.clear();
    final peerConnection = await createPeerConnection(_peerConfiguration);
    _peerConnection = peerConnection;
    peerConnection.onConnectionState = (state) {
      onConnectionState?.call(state);
    };
    peerConnection.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams.first;
      }
    };
    peerConnection.onIceCandidate = (candidate) {
      unawaited(_writeCandidate('parentCandidates', candidate, sessionId));
    };
    await peerConnection.setRemoteDescription(
      RTCSessionDescription(offer['sdp'] as String, offer['type'] as String),
    );
    _remoteDescriptionSet = true;
    _candidateSubscription?.cancel();
    _candidateSubscription = _signalReference!
        .child('childCandidates')
        .onChildAdded
        .listen(_handleRemoteCandidate, onError: _reportError);
    await _applyPendingCandidates();

    final answer = await peerConnection.createAnswer();
    await peerConnection.setLocalDescription(answer);
    await _signalReference!.child('answer').set({
      ...Map<String, dynamic>.from(answer.toMap() as Map),
      'sessionId': sessionId,
    });
    await _signalReference!.update({
      'status': 'answered',
      'viewerStatus': 'viewing',
      'updatedAt': ServerValue.timestamp,
    });
  }

  void _handleRemoteCandidate(DatabaseEvent event) {
    final value = event.snapshot.value;
    if (value is! Map ||
        value['sessionId'] != _sessionId ||
        value['candidate'] is! String) {
      return;
    }
    final index = value['sdpMLineIndex'];
    final candidate = RTCIceCandidate(
      value['candidate'] as String,
      value['sdpMid'] is String ? value['sdpMid'] as String : null,
      index is int ? index : null,
    );
    if (_remoteDescriptionSet) {
      unawaited(_addRemoteCandidate(candidate));
    } else {
      _pendingRemoteCandidates.add(candidate);
    }
  }

  Future<void> _applyPendingCandidates() async {
    final candidates = List<RTCIceCandidate>.from(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final candidate in candidates) {
      await _addRemoteCandidate(candidate);
    }
  }

  Future<void> _addRemoteCandidate(RTCIceCandidate candidate) async {
    try {
      await _peerConnection?.addCandidate(candidate);
    } catch (error) {
      _reportError(error);
    }
  }

  Future<void> _writeCandidate(
    String collection,
    RTCIceCandidate candidate,
    String sessionId,
  ) async {
    if (candidate.candidate == null) return;
    try {
      await _signalReference!.child(collection).push().set({
        ...Map<String, dynamic>.from(candidate.toMap() as Map),
        'sessionId': sessionId,
      });
    } catch (error) {
      _reportError(error);
    }
  }

  Future<void> _closePeerConnection() async {
    await _candidateSubscription?.cancel();
    _candidateSubscription = null;
    remoteRenderer.srcObject = null;
    await _peerConnection?.close();
    _peerConnection = null;
  }

  void _reportError(Object error, [StackTrace? stackTrace]) {
    debugPrint('WebRTC viewer failed: $error');
    if (stackTrace != null) debugPrintStack(stackTrace: stackTrace);
    onError?.call(error);
  }

  bool _isValidDatabaseKey(String value) {
    return value.isNotEmpty && !RegExp(r'[.#$\[\]/]').hasMatch(value);
  }

  Future<void> dispose() async {
    await _signalSubscription?.cancel();
    await _candidateSubscription?.cancel();
    try {
      await _signalReference?.child('viewerStatus').set('stopped');
    } catch (error) {
      _reportError(error);
    }
    await _peerConnection?.close();
    await remoteRenderer.dispose();
  }
}
