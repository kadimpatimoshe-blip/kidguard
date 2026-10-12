import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../services/stream_control_service.dart';
import '../../../services/webrtc_service.dart';

class ParentLiveStreamView extends StatefulWidget {
  const ParentLiveStreamView({
    required this.database,
    required this.deviceId,
    required this.parentUid,
    required this.childId,
    required this.childName,
    super.key,
  });

  final FirebaseDatabase database;
  final String deviceId;
  final String parentUid;
  final String childId;
  final String childName;

  @override
  State<ParentLiveStreamView> createState() => _ParentLiveStreamViewState();
}

class _ParentLiveStreamViewState extends State<ParentLiveStreamView> {
  late final WebRTCViewerService _viewer;
  bool _offerReceived = false;
  bool _streamRequested = false;
  bool _commandBusy = false;
  bool _audioMuted = false;
  bool _usingFrontCamera = true;
  RTCPeerConnectionState? _connectionState;
  String? _error;
  String? _controlError;

  @override
  void initState() {
    super.initState();
    _viewer = WebRTCViewerService(
      database: widget.database,
      deviceId: widget.deviceId,
      parentUid: widget.parentUid,
      childId: widget.childId,
      onOfferReceived: () {
        if (mounted) {
          setState(() {
            _offerReceived = true;
            _streamRequested = true;
          });
        }
      },
      onConnectionState: (state) {
        if (!mounted) return;
        setState(() {
          _connectionState = state;
          if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed ||
              state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
            _streamRequested = false;
            _audioMuted = false;
            _usingFrontCamera = true;
          }
        });
      },
      onError: (error) {
        if (mounted) setState(() => _error = error.toString());
      },
    );
    unawaited(_startViewer());
  }

  Future<void> _startViewer() async {
    try {
      await _viewer.start();
    } catch (error, stackTrace) {
      debugPrint('Could not start parent WebRTC viewer: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _sendCommand(RemoteStreamCommand command) async {
    setState(() {
      _commandBusy = true;
      _controlError = null;
    });
    try {
      await StreamControlService(
        database: widget.database,
        deviceId: widget.deviceId,
        parentUid: widget.parentUid,
        childId: widget.childId,
      ).send(command);
      if (!mounted) return;
      setState(() {
        switch (command) {
          case RemoteStreamCommand.startStream:
            _streamRequested = true;
            _offerReceived = false;
            _audioMuted = false;
            _usingFrontCamera = true;
          case RemoteStreamCommand.stopStream:
            _streamRequested = false;
            _offerReceived = false;
            _audioMuted = false;
          case RemoteStreamCommand.switchCamera:
            _usingFrontCamera = !_usingFrontCamera;
          case RemoteStreamCommand.toggleAudioMute:
            _audioMuted = !_audioMuted;
        }
      });
    } catch (error, stackTrace) {
      debugPrint('Could not send remote stream command: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) setState(() => _controlError = error.toString());
    } finally {
      if (mounted) setState(() => _commandBusy = false);
    }
  }

  @override
  void dispose() {
    unawaited(_viewer.dispose());
    super.dispose();
  }

  String get _statusMessage {
    if (_error != null) return 'Could not establish the live stream.';
    if (_connectionState ==
        RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
      return 'Live stream connected';
    }
    if (_connectionState ==
            RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
        _connectionState ==
            RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
      return 'The live stream connection has ended.';
    }
    if (_offerReceived) return 'Connecting to child device…';
    if (_streamRequested) return 'Start request sent; waiting for the child…';
    return 'Send a start request to begin a live stream.';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final connected = _connectionState ==
        RTCPeerConnectionState.RTCPeerConnectionStateConnected;
    return Scaffold(
      appBar: AppBar(title: Text(widget.childName)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        connected ? Icons.videocam : Icons.videocam_outlined,
                        color: connected ? colors.primary : colors.outline,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _statusMessage,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (_offerReceived && !connected)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ColoredBox(
                        color: Colors.black,
                        child: _error == null
                            ? RTCVideoView(
                                _viewer.remoteRenderer,
                                objectFit: RTCVideoViewObjectFit
                                    .RTCVideoViewObjectFitContain,
                              )
                            : Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: SelectableText(
                                    _error!,
                                    style: TextStyle(color: colors.onError),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _commandBusy || _streamRequested
                            ? null
                            : () => _sendCommand(
                                  RemoteStreamCommand.startStream,
                                ),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start Stream'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _commandBusy || !_streamRequested
                            ? null
                            : () => _sendCommand(
                                  RemoteStreamCommand.stopStream,
                                ),
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop Stream'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _commandBusy || !connected
                            ? null
                            : () => _sendCommand(
                                  RemoteStreamCommand.switchCamera,
                                ),
                        icon: const Icon(Icons.cameraswitch),
                        label: Text(
                          'Switch Camera (${_usingFrontCamera ? 'Front' : 'Back'})',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _commandBusy || !connected
                            ? null
                            : () => _sendCommand(
                                  RemoteStreamCommand.toggleAudioMute,
                                ),
                        icon: Icon(
                          _audioMuted ? Icons.mic_off : Icons.mic,
                        ),
                        label: Text(
                          _audioMuted ? 'Unmute Audio' : 'Mute Audio',
                        ),
                      ),
                    ],
                  ),
                  if (_controlError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Could not send stream control: $_controlError',
                      style: TextStyle(color: colors.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'The child device needs camera and microphone permissions '
                    'and its background streaming service initialized. If '
                    'Android force-stops the app, reopen it to reconnect.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
