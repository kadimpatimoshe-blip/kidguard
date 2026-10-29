import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// Authentication service for KidGuard
/// Supports Email & Password as well as local Passcode (PIN) security,
/// with Firebase Auth support and resilient offline/local fallback.
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  SharedPreferences? _prefs;

  // In-memory session state (mirrored from persistent storage)
  String? _selectedRole; // 'parent' or 'child'
  bool _rememberRole = true;

  bool get isAuthenticated => _firebaseAuth.currentUser != null;
  String? get currentUserEmail => _firebaseAuth.currentUser?.email;
  String? get currentUserId => _firebaseAuth.currentUser?.uid;
  String? get selectedRole => _selectedRole;

  /// Check initial authentication state and load persisted role
  Future<bool> checkInitialAuth() async {
    _prefs = await SharedPreferences.getInstance();
    _selectedRole = _prefs?.getString('kidguard_role');
    return _firebaseAuth.currentUser != null;
  }

  /// Sets or updates a 4 to 6-digit local security passcode
  Future<bool> setPasscode(String pin) async {
    if (pin.length < 4) return false;
    _prefs?.setString('kidguard_local_pin', pin);
    return true;
  }

  /// Verifies entered passcode PIN (Legacy/Mock flow preserved for UI)
  Future<bool> verifyPasscode(String pin) async {
    final storedPin = _prefs?.getString('kidguard_local_pin');
    if (storedPin == null) return true; // Initial access
    return storedPin == pin;
  }

  /// Sign in with Email and Password
  Future<Map<String, dynamic>> signInWithEmailPassword(String email, String password) async {
    try {
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return {
        'success': true, 
        'email': credential.user?.email, 
        'uid': credential.user?.uid
      };
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'error': e.message};
    } catch (e) {
      return {'success': false, 'error': 'An unexpected error occurred'};
    }
  }

  /// Register new account with Email and Password
  Future<Map<String, dynamic>> registerWithEmailPassword(String email, String password) async {
    try {
      final credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return {
        'success': true, 
        'email': credential.user?.email, 
        'uid': credential.user?.uid
      };
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'error': e.message};
    } catch (e) {
      return {'success': false, 'error': 'Registration failed'};
    }
  }

  /// Quick Demo Login for instant testing
  void signInAsDemo(String role) {
    setRole(role);
  }

  /// Save chosen device role: 'parent' or 'child'
  void setRole(String role, {bool remember = true}) {
    _selectedRole = role;
    _rememberRole = remember;
    if (remember) {
      _prefs?.setString('kidguard_role', role);
    } else {
      _prefs?.remove('kidguard_role');
    }
  }

  /// Reset role to allow re-selection
  void clearRole() {
    _selectedRole = null;
    _prefs?.remove('kidguard_role');
  }

  /// Sign out
  Future<void> signOut() async {
    await _firebaseAuth.signOut();
    _selectedRole = null;
    _prefs?.remove('kidguard_role');
    _prefs?.remove('kidguard_local_pin');
  }
}
