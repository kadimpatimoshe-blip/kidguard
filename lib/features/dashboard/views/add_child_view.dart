import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../models/parent_child_device.dart';
import '../services/parent_device_service.dart';

class AddChildView extends StatefulWidget {
  const AddChildView({
    required this.database,
    required this.parentUid,
    this.onPaired,
    super.key,
  });

  final FirebaseDatabase database;
  final String parentUid;
  final VoidCallback? onPaired;

  @override
  State<AddChildView> createState() => _AddChildViewState();
}

class _AddChildViewState extends State<AddChildView> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;
  ParentChildDevice? _pairedDevice;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final code = _codeController.text.trim();
      final device = await ParentDeviceService(
        database: widget.database,
        parentUid: widget.parentUid,
      ).claimPairingCode(code);
      if (!mounted) return;
      setState(() => _pairedDevice = device);
      widget.onPaired?.call();
    } on FirebaseException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message ?? error.code);
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } on StateError catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  String? _validateCode(String? value) {
    final code = value?.trim() ?? '';
    if (!RegExp(r'^(?:\d{4}|\d{6})$').hasMatch(code)) {
      return 'Enter a 4- or 6-digit pairing code.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final pairedDevice = _pairedDevice;
    return Scaffold(
      appBar: AppBar(title: const Text('Add Child Device')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: pairedDevice == null
                  ? _buildPairingForm(context)
                  : _buildSuccess(context, pairedDevice),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPairingForm(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.devices, size: 48, color: colors.primary),
          const SizedBox(height: 20),
          Text(
            'Pair a child device',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Enter the pairing code displayed on the child device.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 28),
          TextFormField(
            controller: _codeController,
            enabled: !_isSubmitting,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            maxLength: 6,
            onFieldSubmitted: (_) {
              if (!_isSubmitting) _submit();
            },
            decoration: const InputDecoration(
              labelText: 'Pairing code',
              hintText: '4 or 6 digits',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.pin_outlined),
              counterText: '',
            ),
            validator: _validateCode,
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.error),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Pair device'),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(BuildContext context, ParentChildDevice device) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(Icons.check_circle, size: 56, color: colors.primary),
        const SizedBox(height: 16),
        Text(
          'Device paired successfully',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        SelectableText('Device ID: ${device.childId}'),
      ],
    );
  }
}
