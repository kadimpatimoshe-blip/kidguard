import 'package:flutter/material.dart';
import '../../auth/auth_service.dart';

/// Screen allowing the user to select whether this device is a Parent Console or Child Client
class RoleSelectionScreen extends StatefulWidget {
  final Function(String role) onRoleSelected;
  final VoidCallback onSignOut;

  const RoleSelectionScreen({
    Key? key,
    required this.onRoleSelected,
    required this.onSignOut,
  }) : super(key: key);

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  String _selectedRole = 'parent';
  bool _rememberChoice = true;
  final AuthService _authService = AuthService();

  void _handleContinue() {
    _authService.setRole(_selectedRole, remember: _rememberChoice);
    widget.onRoleSelected(_selectedRole);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F4),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text(
          'KidGuard Setup',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1D302B),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Sign Out',
            icon: const Icon(Icons.logout_rounded, size: 20, color: Color(0xFF71807B)),
            onPressed: widget.onSignOut,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header badge
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A9B70).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'STEP 2: DEVICE ROLE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0A9B70),
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  const Text(
                    'Who is using this device?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1D302B),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Select the role for this specific smartphone or tablet. You can change this later in settings.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF71807B),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Option 1: I am a Parent
                  _buildRoleCard(
                    roleKey: 'parent',
                    title: 'I am a Parent',
                    subtitle: 'Parent Monitoring & Control Console',
                    description: 'Pair with your child\'s device using a 4-digit code. View live GPS location, screen mirroring, camera feeds, call logs, and app usage.',
                    icon: Icons.family_restroom_rounded,
                    badges: ['Parent Dashboard', 'Pair Device with Code', 'Live GPS & Camera', 'Screen Mirroring'],
                  ),
                  const SizedBox(height: 16),

                  // Option 2: I am a Child
                  _buildRoleCard(
                    roleKey: 'child',
                    title: 'I am a Child',
                    subtitle: 'Child Protection Companion Client',
                    description: 'Generates a secure 4-digit pairing code to link with your parent. Runs safe background telemetry for battery, location, and protection services.',
                    icon: Icons.child_care_rounded,
                    badges: ['Generate 4-Digit Code', 'Battery Telemetry', 'Live Location Sync', 'Continuous Protection'],
                  ),
                  const SizedBox(height: 20),

                  // Remember Choice Checkbox
                  Row(
                    children: [
                      Checkbox(
                        value: _rememberChoice,
                        activeColor: const Color(0xFF0A9B70),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        onChanged: (val) => setState(() => _rememberChoice = val ?? true),
                      ),
                      const Expanded(
                        child: Text(
                          'Remember my choice and open this role automatically next time',
                          style: TextStyle(fontSize: 12, color: Color(0xFF71807B)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Continue Button
                  ElevatedButton(
                    onPressed: _handleContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0A9B70),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _selectedRole == 'parent'
                              ? 'Open Parent Dashboard'
                              : 'Open Child Protection Client',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 18),
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

  Widget _buildRoleCard({
    required String roleKey,
    required String title,
    required String subtitle,
    required String description,
    required IconData icon,
    required List<String> badges,
  }) {
    final isSelected = _selectedRole == roleKey;

    return GestureDetector(
      onTap: () => setState(() => _selectedRole = roleKey),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? const Color(0xFF0A9B70) : const Color(0xFFE4E9E5),
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected ? const Color(0xFF0A9B70).withOpacity(0.08) : Colors.black.withOpacity(0.02),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF0A9B70) : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: isSelected ? Colors.white : const Color(0xFF71807B),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1D302B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? const Color(0xFF0A9B70) : const Color(0xFF71807B),
                        ),
                      ),
                    ],
                  ),
                ),
                Radio<String>(
                  value: roleKey,
                  groupValue: _selectedRole,
                  activeColor: const Color(0xFF0A9B70),
                  onChanged: (val) => setState(() => _selectedRole = val!),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              description,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF71807B),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: badges.map((badge) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFECFDF5) : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected ? const Color(0xFFA7F3D0) : const Color(0xFFE5E7EB),
                    ),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? const Color(0xFF065F46) : const Color(0xFF6B7280),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
