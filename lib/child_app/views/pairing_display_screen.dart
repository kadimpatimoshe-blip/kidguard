import 'package:flutter/material.dart';
import '../viewmodels/child_view_model.dart';

/// Screen displayed before pairing, showing the FlashGet style binding code.
/// Simplified as requested (no countdown timers).
class PairingDisplayScreen extends StatelessWidget {
  final ChildViewModel viewModel;

  const PairingDisplayScreen({
    Key? key,
    required this.viewModel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final code = viewModel.pairingCode;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F4),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
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
              'KidGuard Pro',
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
                // Illustration badge
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.phonelink_setup_rounded,
                      size: 44,
                      color: Color(0xFF0A9B70),
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                const Text(
                  'Link with Parent Console',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1D302B),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Enter the binding code displayed below in your parent’s KidGuard Pro dashboard to establish a secure link.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF71807B),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 40),

                // Binding Code Container
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE4E9E5)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 30,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'CHILD BINDING CODE',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF71807B),
                          letterSpacing: 2.0,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Code Display
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: code.split('').map((char) {
                            if (char == '-') {
                              return const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Text(
                                  '-',
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFE4E9E5),
                                  ),
                                ),
                              );
                            }
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: 44,
                              height: 60,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF9FAF9),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFF0A9B70).withOpacity(0.3),
                                  width: 1.5,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  char,
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF1D302B),
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Manual Refresh Button
                TextButton.icon(
                  onPressed: () => viewModel.generateNewPairingCode(),
                  icon: const Icon(Icons.refresh_rounded, size: 18, color: Color(0xFF0A9B70)),
                  label: const Text(
                    'Regenerate Code',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0A9B70),
                      fontSize: 13,
                    ),
                  ),
                ),
                
                const SizedBox(height: 48),

                // Hardware attributes summary
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE4E9E5)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildInfoColumn('HARDWARE', viewModel.deviceModelName.split('•').first.trim()),
                      _buildInfoColumn('BATTERY', '${viewModel.batteryLevel}%'),
                      _buildInfoColumn('STATE', 'WAITING'),
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
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: Color(0xFF9CA3AF),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1D302B),
          ),
        ),
      ],
    );
  }
}
