import 'package:flutter/material.dart';
import '../viewmodels/parent_view_model.dart';
import '../models/child_device.dart';

/// Screen for entering and validating the 4-digit bind code against Firebase RTDB
class PairDeviceScreen extends StatefulWidget {
  final ParentViewModel viewModel;
  final Function(ChildDevice device) onDevicePaired;

  const PairDeviceScreen({
    Key? key,
    required this.viewModel,
    required this.onDevicePaired,
  }) : super(key: key);

  @override
  State<PairDeviceScreen> createState() => _PairDeviceScreenState();
}

class _PairDeviceScreenState extends State<PairDeviceScreen> {
  final _codeController = TextEditingController();
  final _labelController = TextEditingController();

  bool _isSearching = false;
  bool _isPairing = false;
  Map<String, dynamic>? _verificationResult;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  void _onCodeChanged(String value) {
    setState(() => _errorMessage = null);
    final clean = value.trim();
    if (clean.length >= 4) {
      _searchCode(clean);
    } else {
      setState(() {
        _verificationResult = null;
      });
    }
  }

  Future<void> _searchCode(String code) async {
    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });

    final res = await widget.viewModel.verifyPairingCode(code);

    if (mounted) {
      setState(() {
        _isSearching = false;
        if (res['valid'] == true) {
          _verificationResult = res;
          if (_labelController.text.isEmpty && res['deviceModelName'] != null) {
            _labelController.text = res['deviceModelName'];
          }
        } else {
          _verificationResult = null;
          _errorMessage = res['error'] ?? 'Device code could not be verified.';
        }
      });
    }
  }

  Future<void> _handlePairDevice() async {
    final code = _codeController.text.trim();
    if (code.isEmpty || code.length < 4) {
      setState(() => _errorMessage = 'Please enter a valid 4-digit code.');
      return;
    }

    setState(() {
      _isPairing = true;
      _errorMessage = null;
    });

    try {
      final finalCode = _verificationResult?['code'] ?? code;
      final device = await widget.viewModel.confirmPairDevice(
        finalCode,
        customLabel: _labelController.text.trim(),
      );

      if (mounted) {
        widget.onDevicePaired(device);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPairing = false;
          _errorMessage = 'Pairing failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F4),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text(
          'Pair Child Device',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1D302B),
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Illustration icon
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A9B70).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.phonelink_setup_rounded,
                          size: 32,
                          color: Color(0xFF0A9B70),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    'Enter 4-Digit Bind Code',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1D302B),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Open the KidGuard Child app on your child\'s phone and enter the 4-digit code displayed on their screen.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF71807B),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 4-Digit Code Input Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE4E9E5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '4-DIGIT CODE / PAIRING KEY',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF71807B),
                                letterSpacing: 1.0,
                              ),
                            ),
                            Text(
                              'Real-time RTDB Lookup',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0A9B70),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Code Input Field
                        TextField(
                          controller: _codeController,
                          textCapitalization: TextCapitalization.characters,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 6,
                            fontFamily: 'monospace',
                            color: Color(0xFF1D302B),
                          ),
                          onChanged: _onCodeChanged,
                          decoration: InputDecoration(
                            hintText: '8492',
                            hintStyle: TextStyle(
                              color: Colors.grey.shade300,
                              letterSpacing: 6,
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF9FAF9),
                            suffixIcon: _isSearching
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0A9B70)),
                                    ),
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFE4E9E5)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFE4E9E5)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF0A9B70), width: 2),
                            ),
                          ),
                        ),

                        if (_errorMessage != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF1F2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFFECDD3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFE11D48)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFFBE123C),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Verification Card (When found in Firebase RTDB)
                  if (_verificationResult != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.check_circle_rounded, color: Color(0xFF047857), size: 18),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Device Verified in Firebase RTDB',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF065F46),
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD1FAE5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Ready to Pair',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF065F46),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Divider(height: 1, color: Color(0xFFA7F3D0)),
                          const SizedBox(height: 10),
                          _buildDetailRow('Device Model', _verificationResult!['deviceModelName'] ?? 'Android Device'),
                          const SizedBox(height: 4),
                          _buildDetailRow('Battery Level', '${_verificationResult!['batteryLevel']}%'),
                          const SizedBox(height: 4),
                          _buildDetailRow('RTDB Node', _verificationResult!['rtdbPath'] ?? '/devices'),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                    // Child Nickname Field
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE4E9E5)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Child Name / Device Nickname',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1D302B)),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _labelController,
                            decoration: InputDecoration(
                              hintText: 'e.g. Maya\'s Phone',
                              filled: true,
                              fillColor: const Color(0xFFF9FAF9),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFFE4E9E5)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFFE4E9E5)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFF0A9B70), width: 1.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Confirm Pair Button
                  ElevatedButton(
                    onPressed: (_isPairing || _verificationResult == null) ? null : _handlePairDevice,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0A9B70),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _isPairing
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              ),
                              SizedBox(width: 10),
                              Text('Establishing RTDB connection...', style: TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.link_rounded, size: 18),
                              SizedBox(width: 8),
                              Text('Validate & Pair Device', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF71807B))),
        Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1D302B))),
      ],
    );
  }
}
