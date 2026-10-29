import 'package:flutter/material.dart';
import '../auth_service.dart';

/// Onboarding Login / Register Screen for KidGuard
/// Simplified to Email & Password authentication for FlashGet Kids style account linking.
class AuthScreen extends StatefulWidget {
  final VoidCallback onAuthenticated;

  const AuthScreen({
    Key? key,
    required this.onAuthenticated,
  }) : super(key: key);

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _emailController = TextEditingController(text: 'kadimpatimoshe@gmail.com');
  final TextEditingController _passwordController = TextEditingController(text: 'secret123');
  
  bool _isRegistering = false;
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _emailError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleEmailSubmit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || !email.contains('@')) {
      setState(() => _emailError = 'Please enter a valid email address.');
      return;
    }
    if (password.length < 6) {
      setState(() => _emailError = 'Password must be at least 6 characters.');
      return;
    }

    setState(() {
      _isLoading = true;
      _emailError = null;
    });

    try {
      final res = _isRegistering
          ? await _authService.registerWithEmailPassword(email, password)
          : await _authService.signInWithEmailPassword(email, password);

      if (res['success'] == true) {
        widget.onAuthenticated();
      } else {
        setState(() => _emailError = res['error'] ?? 'Authentication failed.');
      }
    } catch (e) {
      setState(() => _emailError = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F4),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // App Brand Icon
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A9B70),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0A9B70).withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.shield_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    'KidGuard Pro',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1D302B),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isRegistering 
                        ? 'Create your account to safeguard family devices' 
                        : 'Log in to your KidGuard account',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF71807B),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  _buildEmailSection(),

                  const SizedBox(height: 20),

                  // Quick Demo Login Button
                  TextButton.icon(
                    onPressed: () {
                      _emailController.text = 'kadimpatimoshe@gmail.com';
                      _passwordController.text = 'secret123';
                      _handleEmailSubmit();
                    },
                    icon: const Icon(Icons.bolt_rounded, size: 16, color: Color(0xFF0A9B70)),
                    label: const Text(
                      'Quick Demo Access',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0A9B70),
                      ),
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

  Widget _buildEmailSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE4E9E5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_emailError != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFECDD3)),
              ),
              child: Text(
                _emailError!,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFBE123C),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],

          // Email Input
          const Text(
            'Email Address',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1D302B),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              hintText: 'parent@example.com',
              filled: true,
              fillColor: const Color(0xFFF9FAF9),
              prefixIcon: const Icon(Icons.mail_outline_rounded, size: 18, color: Color(0xFF71807B)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                borderSide: const BorderSide(color: Color(0xFF0A9B70), width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Password Input
          const Text(
            'Password',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1D302B),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              hintText: '••••••••',
              filled: true,
              fillColor: const Color(0xFFF9FAF9),
              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18, color: Color(0xFF71807B)),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 18,
                  color: const Color(0xFF71807B),
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                borderSide: const BorderSide(color: Color(0xFF0A9B70), width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Submit Button
          ElevatedButton(
            onPressed: _isLoading ? null : _handleEmailSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0A9B70),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    _isRegistering ? 'Create Account' : 'Sign In',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
          ),
          const SizedBox(height: 12),

          // Toggle Register / Login
          TextButton(
            onPressed: () {
              setState(() {
                _isRegistering = !_isRegistering;
                _emailError = null;
              });
            },
            child: Text(
              _isRegistering ? 'Already have an account? Sign In' : 'New to KidGuard? Create Account',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF0A9B70),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
