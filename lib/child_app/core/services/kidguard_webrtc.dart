import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/foundation.dart';

class KidGuardWebRTC {
  final Map<String, dynamic> config = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'iceTransportPolicy': 'all',
  };

  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  
  // Callback to handle outgoing ICE candidates and send via signaling
  Function(RTCIceCandidate candidate)? onIceCandidateGenerated;
  
  // Callback when remote stream is received (for Parent UI)
  Function(MediaStream stream)? onRemoteStreamAdded;

  /// Initialize WebRTC Peer Connection with callbacks
  Future<void> initPeerConnection() async {
    try {
      peerConnection = await createPeerConnection(config);
      
      peerConnection!.onIceCandidate = (candidate) {
        if (candidate.candidate != null) {
          debugPrint('Generated ICE candidate: ${candidate.candidate}');
          onIceCandidateGenerated?.call(candidate);
        }
      };

      peerConnection!.onConnectionState = (state) {
        debugPrint('Peer connection state changed: $state');
      };

      peerConnection!.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          debugPrint('Received remote media stream track');
          onRemoteStreamAdded?.call(event.streams[0]);
        }
      };
    } catch (e) {
      debugPrint('Error initializing peer connection: $e');
    }
  }

  /// Captures screen media stream from child device (MediaProjection)
  Future<MediaStream?> getScreenStream() async {
    try {
      final stream = await navigator.mediaDevices.getDisplayMedia({
        'video': {
          'mandatory': {
            'minWidth': '1280',
            'minHeight': '720',
            'minFrameRate': '30',
          },
          'optional': [],
        },
        'audio': true,
      });
      
      localStream = stream;
      for (final track in stream.getVideoTracks()) {
        peerConnection?.addTrack(track, stream);
      }
      for (final track in stream.getAudioTracks()) {
        peerConnection?.addTrack(track, stream);
      }
      return stream;
    } catch (e) {
      debugPrint('Error capturing screen stream: $e');
      return null;
    }
  }

  /// Captures camera media stream (front or back camera)
  Future<MediaStream?> getCameraStream({String facing = 'back'}) async {
    try {
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {
          'facingMode': facing == 'front' ? 'user' : 'environment',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
          'frameRate': {'ideal': 24},
        },
      });

      localStream = stream;
      for (final track in stream.getVideoTracks()) {
        peerConnection?.addTrack(track, stream);
      }
      for (final track in stream.getAudioTracks()) {
        peerConnection?.addTrack(track, stream);
      }
      return stream;
    } catch (e) {
      debugPrint('Error capturing camera stream: $e');
      return null;
    }
  }

  /// Creates WebRTC Offer (Used by Initiator/Parent or Child depending on flow)
  Future<String?> createOffer() async {
    try {
      final offer = await peerConnection!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      });
      await peerConnection!.setLocalDescription(offer);
      return offer.sdp;
    } catch (e) {
      debugPrint('Error creating offer: $e');
      return null;
    }
  }

  /// Creates WebRTC Answer (Used by Child when receiving offer from Parent)
  Future<String?> createAnswer() async {
    try {
      final answer = await peerConnection!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      });
      await peerConnection!.setLocalDescription(answer);
      return answer.sdp;
    } catch (e) {
      debugPrint('Error creating answer: $e');
      return null;
    }
  }

  /// Sets remote SDP Offer
  Future<void> setRemoteOffer(String sdp) async {
    try {
      await peerConnection!.setRemoteDescription(
        RTCSessionDescription(sdp, 'offer'),
      );
    } catch (e) {
      debugPrint('Error setting remote offer: $e');
    }
  }

  /// Sets remote SDP Answer
  Future<void> setRemoteAnswer(String sdp) async {
    try {
      await peerConnection!.setRemoteDescription(
        RTCSessionDescription(sdp, 'answer'),
      );
    } catch (e) {
      debugPrint('Error setting remote answer: $e');
    }
  }

  /// Add incoming remote ICE candidate
  Future<void> addIceCandidate(String candidate, String sdpMid, int sdpMLineIndex) async {
    try {
      await peerConnection!.addCandidate(
        RTCIceCandidate(candidate, sdpMid, sdpMLineIndex),
      );
    } catch (e) {
      debugPrint('Error adding ICE candidate: $e');
    }
  }

  /// Disconnect and cleanly dispose streams and peer connection
  Future<void> dispose() async {
    try {
      if (localStream != null) {
        for (final track in localStream!.getTracks()) {
          track.stop();
        }
        await localStream!.dispose();
        localStream = null;
      }
      await peerConnection?.close();
      await peerConnection?.dispose();
      peerConnection = null;
    } catch (e) {
      debugPrint('Error disposing WebRTC instance: $e');
    }
  }
}
