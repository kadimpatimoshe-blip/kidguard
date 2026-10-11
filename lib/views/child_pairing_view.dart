import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../services/child_pairing_service.dart';
import '../services/pairing_code_expiration.dart';
import 'child_device_status_view.dart';

class ChildPairingView extends StatefulWidget {
  const ChildPairingView({
    required this.auth,
    required this.database,
    super.key,
  });

  final FirebaseAuth auth;
  final FirebaseDatabase database;

  @override
  State<ChildPairingView> createState() => _ChildPairingViewState();
}

class _ChildPairingViewState extends State<ChildPairingView> {
  late Future<_PairingFlow> _pairingFlow;
  String? _statusDeviceId;
  Stream<DatabaseEvent>? _pairingStatusStream;
  Timer? _expiryTimer;
  String? _expiryTimerCode;
  bool _refreshingExpiredCode = false;
  bool _savingPairedChildId = false;
  bool _handlingParentUnlink = false;
  String? _pairedChildActivationError;
  String? _pairedChildId;
  String? _pairedParentUid;
  String? _unlinkMessage;
  String? _unlinkStorageError;

  @override
  void initState() {
    super.initState();
    _pairingFlow = _initializePairingFlow();
  }

  Future<_PairingFlow> _initializePairingFlow() async {
    final user = widget.auth.currentUser;
    if (user == null) {
      throw StateError('Authenticate before pairing this device.');
    }

    await Hive.initFlutter('kidguard');
    final pairedChildren = await Hive.openBox<String>(_pairedChildrenBoxName);
    final savedLink = _decodeSavedLink(pairedChildren.get(user.uid), user.uid);
    if (savedLink != null) {
      return _PairingFlow.dashboard(
        childId: savedLink.childId,
        parentUid: savedLink.parentUid,
      );
    }

    final pairing = await _createPairingCode();
    return _PairingFlow.pairing(pairing.code, pairing.deviceId);
  }

  _PairedChildLink? _decodeSavedLink(String? value, String childUid) {
    if (value == null) return null;
    if (!value.startsWith('{')) {
      if (!_isValidDatabaseKey(value) || !_isValidDatabaseKey(childUid)) {
        throw const FormatException('Saved child-device link is invalid.');
      }
      return _PairedChildLink(childId: value, parentUid: childUid);
    }

    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic> ||
        decoded['childId'] is! String ||
        decoded['parentUid'] is! String ||
        (decoded['paired'] != null && decoded['paired'] != true) ||
        !_isValidDatabaseKey(decoded['childId'] as String) ||
        !_isValidDatabaseKey(decoded['parentUid'] as String)) {
      throw const FormatException('Saved child-device link is invalid.');
    }
    return _PairedChildLink(
      childId: decoded['childId'] as String,
      parentUid: decoded['parentUid'] as String,
    );
  }

  bool _isValidDatabaseKey(String value) {
    return value.isNotEmpty && !RegExp(r'[.#$\[\]/]').hasMatch(value);
  }

  Future<ChildPairingCode> _createPairingCode() async {
    debugPrint('Starting Firebase pairing-code creation under /pairing_codes');
    try {
      final code = await ChildPairingService(
        auth: widget.auth,
        database: widget.database,
      ).createPairingCode();
      debugPrint(
        'Firebase pairing-code creation succeeded at '
        '/pairing_codes/${code.deviceId}',
      );
      return code;
    } catch (error, stackTrace) {
      debugPrint('Firebase pairing-code creation failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Stream<DatabaseEvent> _statusStreamFor(String deviceId) {
    if (_statusDeviceId != deviceId) {
      _statusDeviceId = deviceId;
      final path = '/pairing_codes/$deviceId';
      debugPrint('Listening for Firebase pairing updates at $path');
      _pairingStatusStream = widget.database.ref(path).onValue.transform(
        StreamTransformer<DatabaseEvent, DatabaseEvent>.fromHandlers(
          handleError: (error, stackTrace, sink) {
            debugPrint('Firebase RTDB listener failed at $path: $error');
            debugPrintStack(stackTrace: stackTrace);
            sink.addError(error, stackTrace);
          },
        ),
      );
    }
    return _pairingStatusStream!;
  }

  void _retry() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _expiryTimerCode = null;
    setState(() {
      _statusDeviceId = null;
      _pairingStatusStream = null;
      _pairingFlow = _initializePairingFlow();
    });
  }

  void _scheduleExpiry(String code, String deviceId, String timestamp) {
    _scheduleRefresh(
      code,
      deviceId,
      pairingCodeTimeRemaining(timestamp),
    );
  }

  void _scheduleImmediateRefresh(String code, String deviceId) {
    _scheduleRefresh(code, deviceId, Duration.zero);
  }

  void _scheduleRefresh(String code, String deviceId, Duration delay) {
    if (_expiryTimerCode == code) return;
    _expiryTimer?.cancel();
    _expiryTimerCode = code;
    _expiryTimer = Timer(delay, () => _refreshExpiredCode(code, deviceId));
  }

  Future<void> _refreshExpiredCode(String code, String deviceId) async {
    if (_refreshingExpiredCode || !mounted) return;

    _refreshingExpiredCode = true;
    try {
      await ChildPairingService(
        auth: widget.auth,
        database: widget.database,
      ).removeExpiredPairingCode(code, deviceId);
      if (mounted) _retry();
    } catch (error, stackTrace) {
      debugPrint('Expired pairing-code refresh failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not refresh the pairing code: $error')),
        );
      }
    } finally {
      _refreshingExpiredCode = false;
    }
  }

  Future<void> _rememberPairedChild(
    String childId,
    String parentUid,
    String code,
    String deviceId,
  ) async {
    if (_savingPairedChildId) return;
    _savingPairedChildId = true;
    Object? activationError;
    try {
      final user = widget.auth.currentUser;
      if (user == null) {
        throw StateError('The signed-in child account is no longer available.');
      }
      if (user.uid.isEmpty || parentUid.isEmpty) {
        throw StateError('The paired device identity is incomplete.');
      }
      await Hive.initFlutter('kidguard');
      final pairedChildren = await Hive.openBox<String>(_pairedChildrenBoxName);
      await pairedChildren.put(
        user.uid,
        jsonEncode({
          'childId': childId,
          'parentUid': parentUid,
          'paired': true,
        }),
      );
      final presenceReference = widget.database.ref(
        '/parents/$parentUid/children/$childId/presence',
      );
      await presenceReference.onDisconnect().update({
        'online': false,
        'lastSeen': ServerValue.timestamp,
      });
      await presenceReference.update({
        'online': true,
        'heartbeatAt': ServerValue.timestamp,
        'lastSeen': ServerValue.timestamp,
      });
    } catch (error, stackTrace) {
      activationError = error;
      debugPrint('Could not activate paired child device: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _savingPairedChildId = false;
    }

    if (activationError != null) {
      if (mounted) {
        setState(
            () => _pairedChildActivationError = activationError.toString());
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _pairedChildActivationError = null;
      _pairedChildId = childId;
      _pairedParentUid = parentUid;
      _unlinkMessage = null;
      _unlinkStorageError = null;
    });

    try {
      await ChildPairingService(
        auth: widget.auth,
        database: widget.database,
      ).removePairedPairingCode(code, childId, deviceId);
    } catch (error, stackTrace) {
      debugPrint('Could not clean up paired pairing code: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _handleParentUnlink() async {
    if (_handlingParentUnlink || !mounted) return;
    _handlingParentUnlink = true;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _expiryTimerCode = null;
    setState(() {
      _pairedChildId = null;
      _pairedParentUid = null;
      _pairedChildActivationError = null;
      _statusDeviceId = null;
      _pairingStatusStream = null;
      _unlinkMessage = 'Device unlinked by parent';
      _unlinkStorageError = null;
      _pairingFlow = _createPairingCode().then(
        (pairing) => _PairingFlow.pairing(pairing.code, pairing.deviceId),
      );
    });

    try {
      final user = widget.auth.currentUser;
      if (user != null) {
        await Hive.initFlutter('kidguard');
        final pairedChildren =
            await Hive.openBox<String>(_pairedChildrenBoxName);
        await pairedChildren.delete(user.uid);
      }
    } catch (error, stackTrace) {
      debugPrint('Could not clear unlinked child-device persistence: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _unlinkStorageError = error.toString());
      }
    } finally {
      _handlingParentUnlink = false;
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_pairedChildId != null && _pairedParentUid != null) {
      return ChildDeviceStatusView(
        database: widget.database,
        parentUid: _pairedParentUid!,
        childId: _pairedChildId!,
        deviceId: widget.auth.currentUser!.uid,
        onUnlinked: _handleParentUnlink,
      );
    }

    final colors = Theme.of(context).colorScheme;
    return FutureBuilder<_PairingFlow>(
      future: _pairingFlow,
      builder: (context, flowSnapshot) {
        if (flowSnapshot.hasError) {
          return _buildScaffold(
            context,
            child: _PairingError(
              error: flowSnapshot.error.toString(),
              onRetry: _retry,
            ),
          );
        }
        if (!flowSnapshot.hasData) {
          return _buildScaffold(
            context,
            child: const SizedBox(
              height: 112,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final flow = flowSnapshot.data!;
        switch (flow.destination) {
          case _PairingDestination.dashboard:
            return ChildDeviceStatusView(
              database: widget.database,
              parentUid: flow.parentUid!,
              childId: flow.childId!,
              deviceId: widget.auth.currentUser!.uid,
              onUnlinked: _handleParentUnlink,
            );
          case _PairingDestination.pairing:
            return _buildPairingScaffold(
              context,
              colors,
              flow.code!,
              flow.deviceId!,
            );
        }
      },
    );
  }

  Widget _buildPairingScaffold(
    BuildContext context,
    ColorScheme colors,
    String code,
    String deviceId,
  ) {
    return _buildScaffold(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.phonelink_lock, size: 44, color: colors.primary),
          const SizedBox(height: 24),
          Text(
            'Pair this device',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Enter this code in the parent app to connect.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (_unlinkMessage != null) ...[
            const SizedBox(height: 16),
            Text(
              _unlinkMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.error),
            ),
            if (_unlinkStorageError != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                'Could not clear saved device link: $_unlinkStorageError',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.error),
              ),
            ],
          ],
          const SizedBox(height: 32),
          StreamBuilder<DatabaseEvent>(
            stream: _statusStreamFor(deviceId),
            builder: (context, statusSnapshot) {
              if (statusSnapshot.hasError) {
                return _PairingStatusError(
                  error: statusSnapshot.error.toString(),
                );
              }
              final value = statusSnapshot.data?.snapshot.value;
              if (value == null) {
                return _PairingCode(
                  code: code,
                  colors: colors,
                  onGenerateNewCode: _retry,
                );
              }
              if (value is! Map ||
                  value['pairingCode'] == null ||
                  value['status'] == null ||
                  (value['childId'] ?? value['deviceId']) is! String ||
                  !_isValidDatabaseKey(
                    (value['childId'] ?? value['deviceId']) as String,
                  ) ||
                  value['pairingCode'] != code ||
                  (value['deviceId'] != null &&
                      value['deviceId'] != deviceId) ||
                  value['status'] is! String ||
                  (value['status'] != 'pending' &&
                      value['status'] != 'waiting' &&
                      value['status'] != 'paired' &&
                      value['status'] != 'expired') ||
                  (value['createdAt'] ?? value['timestamp']) is! String) {
                return const _PairingStatusError(
                  error: 'Invalid pairing record schema.',
                );
              }
              final childId = (value['childId'] ?? value['deviceId']) as String;
              final createdAt =
                  (value['createdAt'] ?? value['timestamp']) as String;
              if (value['status'] == 'expired') {
                _scheduleImmediateRefresh(code, deviceId);
                return const SizedBox(
                  height: 112,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (value['status'] == 'paired') {
                final parentUid = value['parentUid'];
                final childUid = value['childUid'];
                final user = widget.auth.currentUser;
                if (parentUid is! String ||
                    parentUid.isEmpty ||
                    (childUid != null &&
                        (childUid is! String || childUid != user?.uid))) {
                  return const _PairingStatusError(
                    error: 'Pairing record has an invalid device identity.',
                  );
                }
                _expiryTimer?.cancel();
                _expiryTimer = null;
                _expiryTimerCode = code;
                if (_pairedChildActivationError != null) {
                  return _PairingActivationError(
                    error: _pairedChildActivationError!,
                    onRetry: () => _rememberPairedChild(
                      childId,
                      parentUid,
                      code,
                      deviceId,
                    ),
                  );
                }
                _rememberPairedChild(
                  childId,
                  parentUid,
                  code,
                  deviceId,
                );
                return const SizedBox(
                  height: 112,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              _scheduleExpiry(code, deviceId, createdAt);
              return _PairingCode(
                code: code,
                colors: colors,
                onGenerateNewCode: _retry,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildScaffold(
    BuildContext context, {
    required Widget child,
  }) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('KidGuard Child'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

const _pairedChildrenBoxName = 'paired_child_devices';

enum _PairingDestination { pairing, dashboard }

class _PairingFlow {
  const _PairingFlow._(
    this.destination, {
    this.code,
    this.deviceId,
    this.childId,
    this.parentUid,
  });

  const _PairingFlow.pairing(String code, String deviceId)
      : this._(
          _PairingDestination.pairing,
          code: code,
          deviceId: deviceId,
        );

  const _PairingFlow.dashboard({
    required String childId,
    required String parentUid,
  }) : this._(
          _PairingDestination.dashboard,
          childId: childId,
          parentUid: parentUid,
        );

  final _PairingDestination destination;
  final String? code;
  final String? deviceId;
  final String? childId;
  final String? parentUid;
}

class _PairedChildLink {
  const _PairedChildLink({required this.childId, required this.parentUid});

  final String childId;
  final String parentUid;
}

class _PairingCode extends StatelessWidget {
  const _PairingCode({
    required this.code,
    required this.colors,
    required this.onGenerateNewCode,
  });

  final String code;
  final ColorScheme colors;
  final VoidCallback onGenerateNewCode;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            code,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: colors.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 8,
                ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_done, size: 18, color: colors.primary),
            const SizedBox(width: 8),
            const Text('Code synced with Firebase'),
          ],
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: onGenerateNewCode,
          icon: const Icon(Icons.refresh),
          label: const Text('Generate a new code'),
        ),
      ],
    );
  }
}

class _PairingStatusError extends StatelessWidget {
  const _PairingStatusError({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.cloud_off, size: 32),
        const SizedBox(height: 12),
        const Text('Could not monitor pairing status.'),
        const SizedBox(height: 8),
        SelectableText(error, textAlign: TextAlign.center),
      ],
    );
  }
}

class _PairingActivationError extends StatelessWidget {
  const _PairingActivationError({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.warning_amber, size: 32),
        const SizedBox(height: 12),
        const Text(
          'The device is paired, but activation could not be completed.',
        ),
        const SizedBox(height: 8),
        SelectableText(error, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry saving'),
        ),
      ],
    );
  }
}

class _PairingError extends StatelessWidget {
  const _PairingError({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.cloud_off, size: 32),
        const SizedBox(height: 12),
        const Text('Could not sync the pairing code.'),
        const SizedBox(height: 8),
        SelectableText(error, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      ],
    );
  }
}
