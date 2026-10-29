import 'package:flutter/material.dart';
import '../viewmodels/child_view_model.dart';
import 'pairing_display_screen.dart';

/// KidGuard Child Protection Dashboard
/// Simplified UI as requested to match FlashGet Kids style.
/// Shows protection status and recent alerts only.
class ChildHomeScreen extends StatefulWidget {
  final ChildViewModel viewModel;

  const ChildHomeScreen({
    Key? key,
    required this.viewModel,
  }) : super(key: key);

  @override
  State<ChildHomeScreen> createState() => _ChildHomeScreenState();
}

class _ChildHomeScreenState extends State<ChildHomeScreen> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.viewModel,
      builder: (context, _) {
        if (!widget.viewModel.isPaired) {
          return PairingDisplayScreen(viewModel: widget.viewModel);
        }

        final vm = widget.viewModel;

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
                    color: const Color(0xFF0A9B70),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.shield_rounded,
                    color: Colors.white,
                    size: 18,
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
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 20),
                
                // 1. Status Shield (Big & Centered)
                Center(
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A9B70).withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF0A9B70).withOpacity(0.2), width: 2),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.shield_rounded,
                        color: Color(0xFF0A9B70),
                        size: 64,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                
                const Text(
                  'Device Protected',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1D302B),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Everything is working correctly. Your parent can now supervise this device activities remotely.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: const Color(0xFF71807B),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 40),

                // 2. Active Status Pills
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildStatusPill(
                      label: 'Background Monitoring',
                      isActive: true,
                      color: const Color(0xFF0A9B70),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildStatusPill(
                      label: 'Safe GPS Tracking',
                      isActive: true,
                      color: Colors.blue,
                    ),
                  ],
                ),
                const SizedBox(height: 48),

                // 3. Activity Log (Notifications Only)
                const Text(
                  'LATEST SYSTEM ALERTS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF71807B),
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 16),

                _buildAlertItem(
                  icon: Icons.check_circle_rounded,
                  color: const Color(0xFF0A9B70),
                  title: 'Security Sync Successful',
                  subtitle: 'Device status was updated 1 minute ago.',
                ),
                const SizedBox(height: 12),
                _buildAlertItem(
                  icon: Icons.radio_button_checked_rounded,
                  color: Colors.indigo,
                  title: 'Background Service Running',
                  subtitle: 'Continuous protection is active in background.',
                ),
                const SizedBox(height: 40),

                // 4. Very discrete device info
                Center(
                  child: Text(
                    'Device ID: ${vm.deviceId.toUpperCase().substring(0, 12)}... • Version 1.0.0',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF9CA3AF),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Linked via pairing code: ${vm.pairingCode}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusPill({
    required String label,
    required bool isActive,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE4E9E5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isActive ? color : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF71807B),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            isActive ? 'ACTIVE' : 'INACTIVE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: isActive ? color : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertItem({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E9E5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1D302B)),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF71807B)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
