import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/foundation.dart';

class KidGuardSignaling {
  final DatabaseReference _root;
  final String deviceCode;
  final String role; // "parent" or "child"
  
  RTCPeerConnection? _peerConnection;
  final List<StreamSubscription> _subscriptions = [];
  
  KidGuardSignaling({
    required this.deviceCode,
    required this.role,
    DatabaseReference? root,
  }) : _root = root ?? FirebaseDatabase.instance.ref();

  DatabaseReference get _deviceRef => _root.child('devices').child(deviceCode);

  /// Initialize WebRTC Peer Connection mapping for signaling callbacks
  void setPeerConnection(RTCPeerConnection pc) {
    _peerConnection = pc;
    
    // Listen for outgoing ICE candidates and send to Firebase RTDB
    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null) {
        sendIceCandidate(
          candidate.candidate!,
          candidate.sdpMid ?? '',
          candidate.sdpMLineIndex ?? 0,
        );
      }
    };
  }

  /// Sets up signaling listeners for Child or Parent node synchronization
  Future<void> listenForSignaling({
    required Function(RTCSessionDescription description) onRemoteDescription,
    required Function(RTCIceCandidate candidate) onRemoteIceCandidate,
  }) async {
    final streamRef = _deviceRef.child('stream');

    // Listen to Offer changes (Mainly used by Child to receive from Parent or vice versa)
    final offerSub = streamRef.child('offer').onValue.listen((event) async {
      final rawData = event.snapshot.value;
      if (rawData is! Map) return;
      
      final sdp = rawData['sdp'] as String?;
      final from = rawData['from'] as String?;
      
      if (sdp != null && from != role) {
        debugPrint("Received remote SDP Offer from $from");
        await onRemoteDescription(RTCSessionDescription(sdp, 'offer'));
      }
    });
    _subscriptions.add(offerSub);

    // Listen to Answer changes (Mainly used by Parent/Initiator)
    final answerSub = streamRef.child('answer').onValue.listen((event) async {
      final rawData = event.snapshot.value;
      if (rawData is! Map) return;
      
      final sdp = rawData['sdp'] as String?;
      final from = rawData['from'] as String?;
      
      if (sdp != null && from != role) {
        debugPrint("Received remote SDP Answer from $from");
        await onRemoteDescription(RTCSessionDescription(sdp, 'answer'));
      }
    });
    _subscriptions.add(answerSub);

    // Listen to incoming ICE candidates
    final iceSub = streamRef.child('ice').onChildAdded.listen((event) {
      final rawData = event.snapshot.value;
      if (rawData is! Map) return;

      final candidate = rawData['candidate'] as String?;
      final sdpMid = rawData['sdpMid'] as String?;
      final sdpMLineIndex = (rawData['sdpMLineIndex'] as num?)?.toInt();
      final from = rawData['from'] as String?;

      if (candidate != null && from != role) {
        debugPrint("Received remote ICE candidate from $from");
        onRemoteIceCandidate(RTCIceCandidate(candidate, sdpMid, sdpMLineIndex));
      }
    });
    _subscriptions.add(iceSub);
  }

  Future<void> setupChildStream({
    required RTCVideoRenderer localRenderer,
    required MediaStream stream,
  }) async {
    final node = _deviceRef.child('stream');
    await node.set({
      'status': 'ready',
      'createdAt': ServerValue.timestamp,
      'role': role,
    });
  }

  Future<void> sendOffer(String offerSdp) async {
    await _deviceRef.child('stream').child('offer').set({
      'sdp': offerSdp,
      'from': role,
      'createdAt': ServerValue.timestamp,
    });
  }

  Future<void> sendAnswer(String answerSdp) async {
    await _deviceRef.child('stream').child('answer').set({
      'sdp': answerSdp,
      'from': role,
      'createdAt': ServerValue.timestamp,
    });
  }

  Future<void> sendIceCandidate(String candidate, String sdpMid, int sdpMLineIndex) async {
    await _deviceRef.child('stream').child('ice').push().set({
      'candidate': candidate,
      'sdpMid': sdpMid,
      'sdpMLineIndex': sdpMLineIndex,
      'from': role,
      'createdAt': ServerValue.timestamp,
    });
  }
  
  /// Cleanup signaling listeners and nodes when session ends
  Future<void> clearSession() async {
    disposeListeners();
    await _deviceRef.child('stream').remove();
  }

  /// Cancels active RTDB stream subscriptions
  void disposeListeners() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  void dispose() {
    disposeListeners();
    _peerConnection = null;
  }
}
