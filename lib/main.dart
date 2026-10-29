import 'package:flutter/material.dart';
import 'auth/auth_service.dart';
import 'auth/screens/auth_screen.dart';
import 'role_selection/screens/role_selection_screen.dart';
import 'child_app/child_app.dart';
import 'parent_app/parent_app.dart';

import 'package:firebase_core/firebase_core.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const KidGuardApp());
}

/// Root Application Widget for KidGuard (Parent & Child Companion)
class KidGuardApp extends StatefulWidget {
  const KidGuardApp({Key? key}) : super(key: key);

  @override
  State<KidGuardApp> createState() => _KidGuardAppState();
}

class _KidGuardAppState extends State<KidGuardApp> {
  final AuthService _authService = AuthService();
  late final ChildViewModel _childViewModel;
  late final ParentViewModel _parentViewModel;

  bool _isInitialized = false;
  bool _isAuthenticated = false;
  String? _currentRole;

  @override
  void initState() {
    super.initState();
    _childViewModel = ChildViewModel();
    _parentViewModel = ParentViewModel();
    _initApp();
  }

  Future<void> _initApp() async {
    final authed = await _authService.checkInitialAuth();
    setState(() {
      _isAuthenticated = authed;
      _currentRole = _authService.selectedRole;
      _isInitialized = true;
    });
  }

  @override
  void dispose() {
    _childViewModel.dispose();
    _parentViewModel.dispose();
    super.dispose();
  }

  void _onAuthenticated() {
    setState(() {
      _isAuthenticated = true;
      _currentRole = _authService.selectedRole;
      
      // If logging in as child, establish the account link immediately
      if (_currentRole == 'child' && _authService.currentUserId != null) {
        _childViewModel.setAuthenticatedUser(
          _authService.currentUserId!, 
          _authService.currentUserEmail ?? 'unknown@kidguard.family'
        );
      }
    });
  }

  void _onRoleSelected(String role) {
    setState(() {
      _currentRole = role;
    });
  }

  void _onSwitchRole() {
    _authService.clearRole();
    setState(() {
      _currentRole = null;
    });
  }

  void _onSignOut() {
    _authService.signOut();
    setState(() {
      _isAuthenticated = false;
      _currentRole = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KidGuard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: const Color(0xFF0A9B70),
        scaffoldBackgroundColor: const Color(0xFFF4F6F4),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0A9B70),
          primary: const Color(0xFF0A9B70),
          surface: Colors.white,
        ),
        fontFamily: 'Roboto',
      ),
      home: _buildCurrentScreen(),
    );
  }

  Widget _buildCurrentScreen() {
    if (!_isInitialized) {
      return const Scaffold(
        backgroundColor: Color(0xFFF4F6F4),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF0A9B70)),
        ),
      );
    }

    // Step 1: Initial Launch Auth Check (Passcode PIN or Email & Password)
    if (!_isAuthenticated) {
      return AuthScreen(onAuthenticated: _onAuthenticated);
    }

    // Step 2: Role Selection (Parent vs Child)
    if (_currentRole == null) {
      return RoleSelectionScreen(
        onRoleSelected: _onRoleSelected,
        onSignOut: _onSignOut,
      );
    }

    // Step 3A: Parent Dashboard Console with 4-Digit Bind Code Pairing
    if (_currentRole == 'parent') {
      return ParentDashboardScreen(
        viewModel: _parentViewModel,
        onSwitchRole: _onSwitchRole,
        onSignOut: _onSignOut,
      );
    }

    // Step 3B: Child Protection Client with 4-Digit Code Generator
    return Scaffold(
      body: ChildHomeScreen(viewModel: _childViewModel),
      bottomNavigationBar: Container(
        height: 48,
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Child Mode Active',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFF71807B),
              ),
            ),
            TextButton.icon(
              onPressed: _onSwitchRole,
              icon: const Icon(Icons.swap_horiz_rounded, size: 14, color: Color(0xFF0A9B70)),
              label: const Text(
                'Switch Role',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0A9B70),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
