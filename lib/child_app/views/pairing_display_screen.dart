import 'package:flutter/material.dart';
import '../viewmodels/child_view_model.dart';

/// Screen displayed before pairing, showing the 4-digit code and countdown timer
class PairingDisplayScreen extends StatelessWidget {
  final ChildViewModel viewModel;

  const PairingDisplayScreen({
    Key? key,
    required this.viewModel,
  }) : super(key: key);

  String _formatTimer(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final code = viewModel.pairingCode;
    final seconds = viewModel.secondsRemaining;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F4),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF0A9B70).withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.shield_outlined,
                color: Color(0xFF0A9B70),
                size: 20,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'KidGuard Child Companion',
              style: TextStyle(
                color: Color(0xFF1D302B),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Top phone illustration badge
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.phonelink_setup_rounded,
                      size: 40,
                      color: Color(0xFF0A9B70),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                const Text(
                  'Pair with Parent Console',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1D302B),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter this 4-digit code in the KidGuard Parent Web Dashboard to activate real-time GPS tracking, camera streaming, and telemetry sync.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF71807B),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 32),

                // 4-Digit Code Box Container
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE4E9E5)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'YOUR 4-DIGIT PAIRING CODE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF71807B),
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Code Digit Cards
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: code.split('').map((char) {
                            if (char == '-') {
                              return const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 4),
                                child: Text(
                                  '-',
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF71807B),
                                  ),
                                ),
                              );
                            }
                            final isLong = code.length > 5;
                            return Container(
                              margin: EdgeInsets.symmetric(horizontal: isLong ? 3 : 5),
                              width: isLong ? 38 : 52,
                              height: isLong ? 52 : 62,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF9FAF9),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFF0A9B70).withOpacity(0.5),
                                  width: 1.5,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  char,
                                  style: TextStyle(
                                    fontSize: isLong ? 24 : 30,
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFF1D302B),
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Countdown & Expiry Pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.timer_outlined,
                              size: 14,
                              color: Color(0xFFB45309),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Code expires in ${_formatTimer(seconds)}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFB45309),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Regenerate Code Button
                OutlinedButton.icon(
                  onPressed: () => viewModel.generateNewPairingCode(),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text(
                    'Generate New Code',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0A9B70),
                    side: const BorderSide(color: Color(0xFF0A9B70)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Device Hardware Info
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE4E9E5)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildInfoColumn('DEVICE MODEL', viewModel.deviceModelName),
                      Container(width: 1, height: 28, color: const Color(0xFFE4E9E5)),
                      _buildInfoColumn('BATTERY', '${viewModel.batteryLevel}%'),
                      Container(width: 1, height: 28, color: const Color(0xFFE4E9E5)),
                      _buildInfoColumn('STATUS', 'Waiting for Parent'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoColumn(String title, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: Color(0xFF71807B),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1D302B),
          ),
        ),
      ],
    );
  }
}
