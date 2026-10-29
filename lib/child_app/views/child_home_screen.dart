import 'package:flutter/material.dart';
import '../viewmodels/child_view_model.dart';
import 'pairing_display_screen.dart';

/// KidGuard Child Protection Dashboard
/// Finalized production layout without SOS buttons, flip camera buttons, or parent sidebars.
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
            title: Row(
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
                  'KidGuard Protection',
                  style: TextStyle(
                    color: Color(0xFF1D302B),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            actions: [
              Container(
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Live Synced',
                      style: TextStyle(
                        color: Color(0xFF065F46),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // 1. Simplified Header (FlashGet Kids Style)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF192723), Color(0xFF263D36)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.link_rounded, color: Color(0xFF34D399), size: 14),
                            const SizedBox(width: 6),
                            const Text(
                              'Linked with Parent',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.shield_rounded,
                            color: Color(0xFF34D399),
                            size: 42,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Device Protected',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'KidGuard Pro is monitoring this device in the background. Your parent can supervise safely.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Pairing Code: ',
                              style: TextStyle(color: Colors.white60, fontSize: 12),
                            ),
                            Text(
                              vm.pairingCode,
                              style: const TextStyle(
                                color: Color(0xFF34D399),
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // 2. Active Status Indicators
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE4E9E5)),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.gps_fixed_rounded, color: Colors.blue, size: 24),
                            const SizedBox(height: 8),
                            const Text(
                              'Location',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'ACTIVE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE4E9E5)),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.sync_rounded, color: Color(0xFF0A9B70), size: 24),
                            const SizedBox(height: 8),
                            const Text(
                              'Sync',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'ENCRYPTED',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0A9B70),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // 3. Activity History (Optional Notifications Only)
                const Text(
                  'RECENT SYSTEM ALERTS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF71807B),
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),

                _buildAlertItem(
                  icon: Icons.check_circle_rounded,
                  color: const Color(0xFF0A9B70),
                  title: 'Security Sync Ready',
                  subtitle: 'Device status updated successfully.',
                ),
                const SizedBox(height: 8),
                _buildAlertItem(
                  icon: Icons.bolt_rounded,
                  color: Colors.amber.shade700,
                  title: 'Background Guard Active',
                  subtitle: 'Continuous protection service is running.',
                ),
                const SizedBox(height: 24),

                // 4. Active Background Services List (Exact 3 Toggles)
                const Text(
                  'ACTIVE BACKGROUND SERVICES',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF71807B),
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 12),

                // Service 1: Screen Mirroring Service (STREAMING badge + toggle)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: vm.isScreenMirroring ? const Color(0xFF0A9B70) : const Color(0xFFE4E9E5),
                      width: vm.isScreenMirroring ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.screen_share_rounded,
                          color: Color(0xFF6366F1),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'Screen Mirroring Service',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1D302B),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                if (vm.isScreenMirroring)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFECFDF5),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFFA7F3D0)),
                                    ),
                                    child: const Text(
                                      'STREAMING',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF065F46),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'MediaProjection foreground capture to /devices/${vm.pairingCode}/screen',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF71807B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: vm.isScreenMirroring,
                        activeColor: const Color(0xFF0A9B70),
                        onChanged: (_) => vm.toggleScreenMirror(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Service 2: Remote Camera Stream (BACK LENS badge, Parent Controlled tag, toggle - NO manual flip button)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: vm.isCameraStreaming ? const Color(0xFF0A9B70) : const Color(0xFFE4E9E5),
                      width: vm.isCameraStreaming ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A9B70).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.videocam_rounded,
                          color: Color(0xFF0A9B70),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'Remote Camera Stream',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1D302B),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF3F4F6),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFFE5E7EB)),
                                  ),
                                  child: const Text(
                                    'BACK LENS',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF374151),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Parent Controlled',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF2563EB),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Encrypted WebRTC feed',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF71807B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: vm.isCameraStreaming,
                        activeColor: const Color(0xFF0A9B70),
                        onChanged: (_) => vm.toggleCameraStream(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Service 3: One-Way Audio Stream (TRANSMITTING badge + toggle)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: vm.isAudioStreaming ? const Color(0xFF0A9B70) : const Color(0xFFE4E9E5),
                      width: vm.isAudioStreaming ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEC4899).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.mic_rounded,
                          color: Color(0xFFEC4899),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'One-Way Audio Stream',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1D302B),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                if (vm.isAudioStreaming)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFDF2F8),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFFFBCFE8)),
                                    ),
                                    child: const Text(
                                      'TRANSMITTING',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFFBE185D),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Background microphone relay to /devices/${vm.pairingCode}/audio',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF71807B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: vm.isAudioStreaming,
                        activeColor: const Color(0xFF0A9B70),
                        onChanged: (_) => vm.toggleAudioStream(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // 5. Primary Guardian Contact Card
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'LINKED PARENT SUPERVISOR',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF71807B),
                              letterSpacing: 1.0,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Verified & Synced',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF065F46),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: const Color(0xFF0A9B70).withOpacity(0.15),
                            child: const Icon(
                              Icons.verified_user_rounded,
                              color: Color(0xFF0A9B70),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  vm.guardianName?.isNotEmpty == true
                                      ? vm.guardianName!
                                      : 'Parent Supervisor Connected',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1D302B),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  vm.guardianPhone?.isNotEmpty == true || vm.guardianEmail?.isNotEmpty == true
                                      ? '${vm.guardianPhone ?? ''} ${vm.guardianEmail ?? ''}'.trim()
                                      : 'Active Parent Console session linked via Firebase RTDB',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF71807B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Discrete footer
                const Center(
                  child: Text(
                    'KidGuard Security Suite • Continuous Foreground Protection Active',
                    style: TextStyle(
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
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
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
