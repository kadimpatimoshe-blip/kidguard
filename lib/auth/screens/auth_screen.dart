import 'package:flutter/material.dart';
import '../auth_service.dart';

// No longer using PIN passcode, only Email & Password

/// Onboarding Login / Register Screen for KidGuard
/// Supports Passcode (PIN) access and Email & Password authentication
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
  // Default to Email/Password
  bool _isRegistering = false;
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _emailError;

  @override
  void initState() {
    super.initState();
    _isSettingNewPin = !_authService.hasPasscode;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onKeypadTap(String value) {
    if (_enteredPin.length < _pinLength) {
      setState(() {
        _enteredPin += value;
        _passcodeError = null;
      });

      if (_enteredPin.length == _pinLength) {
        _handlePinSubmit();
      }
    }
  }

  void _onBackspace() {
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        _passcodeError = null;
      });
    }
  }

  void _onClearPin() {
    setState(() {
      _enteredPin = '';
      _passcodeError = null;
    });
  }

  Future<void> _handlePinSubmit() async {
    if (_isSettingNewPin) {
      if (_firstEnteredPin == null) {
        // Step 1: Save first entry, ask to confirm
        setState(() {
          _firstEnteredPin = _enteredPin;
          _enteredPin = '';
        });
      } else {
        // Step 2: Confirm entered pin
        if (_enteredPin == _firstEnteredPin) {
          await _authService.setPasscode(_enteredPin);
          await _authService.verifyPasscode(_enteredPin);
          widget.onAuthenticated();
        } else {
          setState(() {
            _passcodeError = 'Passcodes do not match. Please try again.';
            _enteredPin = '';
            _firstEnteredPin = null;
          });
        }
      }
    } else {
      final success = await _authService.verifyPasscode(_enteredPin);
      if (success) {
        widget.onAuthenticated();
      } else {
        setState(() {
          _passcodeError = 'Incorrect passcode. Try again.';
          _enteredPin = '';
        });
      }
    }
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

  void _handleQuickDemo() {
    _authService.signInAsDemo('parent');
    widget.onAuthenticated();
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
                    'KidGuard Protection',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1D302B),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _authMode == AuthMode.passcode
                        ? (_isSettingNewPin
                            ? (_firstEnteredPin == null ? 'Set a 4-Digit Passcode to secure this app' : 'Re-enter your 4-digit Passcode')
                            : 'Enter your 4-Digit Passcode to unlock')
                        : (_isRegistering ? 'Create your account to safeguard family devices' : 'Log in to your KidGuard account'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF71807B),
                    ),
                  ),
                  _buildEmailSection(),

                  const SizedBox(height: 20),

                  // Quick Demo Login Button (Parent role)
                  TextButton.icon(
                    onPressed: () {
                      _authService.signInAsDemo('parent');
                      widget.onAuthenticated();
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

  // Removing PIN logic as requested

  Widget _buildPasscodeSection() {
    return Column(
      children: [
        // PIN Dot Indicators
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE4E9E5)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pinLength, (index) {
                  final isFilled = index < _enteredPin.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFilled ? const Color(0xFF0A9B70) : Colors.transparent,
                      border: Border.all(
                        color: isFilled ? const Color(0xFF0A9B70) : const Color(0xFFCBD5E1),
                        width: 2,
                      ),
                    ),
                  );
                }),
              ),
              if (_passcodeError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _passcodeError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFE11D48),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Custom Keypad (0-9)
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.6,
          ),
          itemCount: 12,
          itemBuilder: (context, index) {
            if (index == 9) {
              // Clear Button
              return TextButton(
                onPressed: _enteredPin.isEmpty ? null : _onClearPin,
                child: const Text(
                  'Clear',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF71807B),
                  ),
                ),
              );
            } else if (index == 10) {
              // Digit '0'
              return _buildKeypadButton('0');
            } else if (index == 11) {
              // Backspace Button
              return IconButton(
                onPressed: _enteredPin.isEmpty ? null : _onBackspace,
                icon: const Icon(
                  Icons.backspace_outlined,
                  color: Color(0xFF1D302B),
                  size: 20,
                ),
              );
            } else {
              // Digits 1-9
              final digit = (index + 1).toString();
              return _buildKeypadButton(digit);
            }
          },
        ),
      ],
    );
  }

  Widget _buildKeypadButton(String digit) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 0,
      child: InkWell(
        onTap: () => _onKeypadTap(digit),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE4E9E5)),
          ),
          child: Center(
            child: Text(
              digit,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1D302B),
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
