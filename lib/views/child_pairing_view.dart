import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../services/child_pairing_service.dart';
import '../services/pairing_code_expiration.dart';

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
  late Future<String> _pairingCode;
  String? _statusCode;
  Stream<DatabaseEvent>? _pairingStatusStream;
  Timer? _expiryTimer;
  String? _expiryTimerCode;
  bool _refreshingExpiredCode = false;

  @override
  void initState() {
    super.initState();
    _pairingCode = _createPairingCode();
  }

  Future<String> _createPairingCode() async {
    debugPrint('Starting Firebase pairing-code creation under /pairing_codes');
    try {
      final code = await ChildPairingService(
        auth: widget.auth,
        database: widget.database,
      ).createPairingCode();
      debugPrint(
        'Firebase pairing-code creation succeeded at /pairing_codes/$code',
      );
      return code;
    } catch (error, stackTrace) {
      debugPrint('Firebase pairing-code creation failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Stream<DatabaseEvent> _statusStreamFor(String code) {
    if (_statusCode != code) {
      _statusCode = code;
      final path = '/pairing_codes/$code';
      debugPrint('Listening for Firebase pairing updates at $path');
      _pairingStatusStream = widget.database
          .ref(path)
          .onValue
          .where((event) => event.snapshot.value != null)
          .transform(
        StreamTransformer<DatabaseEvent, DatabaseEvent>.fromHandlers(
          handleError: (error, stackTrace, sink) {
            debugPrint(
              'Firebase RTDB listener failed at $path: $error',
            );
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
      _pairingCode = _createPairingCode();
    });
  }

  void _scheduleExpiry(String code, String timestamp) {
    _scheduleRefresh(code, pairingCodeTimeRemaining(timestamp));
  }

  void _scheduleImmediateRefresh(String code) {
    _scheduleRefresh(code, Duration.zero);
  }

  void _scheduleRefresh(String code, Duration delay) {
    if (_expiryTimerCode == code) return;
    _expiryTimer?.cancel();
    _expiryTimerCode = code;
    _expiryTimer = Timer(delay, () => _refreshExpiredCode(code));
  }

  Future<void> _refreshExpiredCode(String code) async {
    if (_refreshingExpiredCode || !mounted) return;

    _refreshingExpiredCode = true;
    final replacementCode = _createPairingCode();
    setState(() {
      _expiryTimer = null;
      _expiryTimerCode = null;
      _pairingCode = replacementCode;
    });

    try {
      await replacementCode;
      await ChildPairingService(
        auth: widget.auth,
        database: widget.database,
      ).removeExpiredPairingCode(code);
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

  Future<void> _signOut() async {
    try {
      await widget.auth.signOut();
    } catch (error) {
      debugPrint('Firebase sign-out failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not sign out: $error')),
      );
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('KidGuard Child'),
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Return to parent screen',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
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
                  const SizedBox(height: 32),
                  FutureBuilder<String>(
                    future: _pairingCode,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return _PairingError(
                          error: snapshot.error.toString(),
                          onRetry: _retry,
                        );
                      }
                      if (!snapshot.hasData) {
                        return const SizedBox(
                          height: 112,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final code = snapshot.data!;
                      return StreamBuilder<DatabaseEvent>(
                        stream: _statusStreamFor(code),
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
                              !value.keys.toSet().containsAll(const {
                                'childId',
                                'pairingCode',
                                'status',
                                'timestamp',
                              }) ||
                              value['childId'] is! String ||
                              value['pairingCode'] != code ||
                              value['status'] is! String ||
                              (value['status'] != 'waiting' &&
                                  value['status'] != 'paired' &&
                                  value['status'] != 'expired') ||
                              value['timestamp'] is! String) {
                            return const _PairingStatusError(
                              error: 'Invalid pairing record schema.',
                            );
                          }
                          if (value['status'] == 'expired') {
                            _scheduleImmediateRefresh(code);
                            return const SizedBox(
                              height: 112,
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          if (value['status'] == 'paired') {
                            _expiryTimer?.cancel();
                            _expiryTimer = null;
                            _expiryTimerCode = code;
                            return const _DevicePairedSuccess();
                          }
                          _scheduleExpiry(code, value['timestamp'] as String);
                          return _PairingCode(
                            code: code,
                            colors: colors,
                            onGenerateNewCode: _retry,
                          );
                        },
                      );
                    },
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

class _DevicePairedSuccess extends StatelessWidget {
  const _DevicePairedSuccess();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(Icons.check_circle, size: 64, color: colors.primary),
        const SizedBox(height: 16),
        Text(
          'Device Paired Successfully',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
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
