import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import 'services/firebase_config.dart';
import 'features/dashboard/views/parent_home_view.dart';
import 'views/auth_screen.dart';
import 'views/child_pairing_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KidGuardChildApp());
}

class KidGuardChildApp extends StatefulWidget {
  const KidGuardChildApp({super.key});

  @override
  State<KidGuardChildApp> createState() => _KidGuardChildAppState();
}

class _KidGuardChildAppState extends State<KidGuardChildApp> {
  late final Future<_FirebaseServices> _firebaseServicesFuture;

  @override
  void initState() {
    super.initState();
    _firebaseServicesFuture = _initializeFirebase();
  }

  Future<_FirebaseServices> _initializeFirebase() async {
    final options = FirebaseConfig.fromEnvironment();
    final app = await Firebase.initializeApp(options: options);
    return _FirebaseServices(
      auth: FirebaseAuth.instanceFor(app: app),
      database: FirebaseDatabase.instanceFor(
        app: app,
        databaseURL: options.databaseURL,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KidGuard Parent',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF176B57),
          surface: const Color(0xFFF5F6F1),
        ),
        useMaterial3: true,
      ),
      onGenerateRoute: (settings) {
        if (settings.name != '/child') return null;
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => _buildChildRoute(),
        );
      },
      home: FutureBuilder<_FirebaseServices>(
        future: _firebaseServicesFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return FirebaseStartupError(error: snapshot.error.toString());
          }
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return _buildAuthenticatedRoute(snapshot.data!);
        },
      ),
    );
  }

  Widget _buildChildRoute() {
    return FutureBuilder<_FirebaseServices>(
      future: _firebaseServicesFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return FirebaseStartupError(error: snapshot.error.toString());
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return _buildChildAuthenticatedRoute(snapshot.data!);
      },
    );
  }

  Widget _buildChildAuthenticatedRoute(_FirebaseServices services) {
    return StreamBuilder<User?>(
      stream: services.auth.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.hasError) {
          return FirebaseStartupError(
            error:
                'Could not check Firebase authentication: ${authSnapshot.error}',
          );
        }
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = authSnapshot.data;
        if (user == null || user.isAnonymous) {
          return AuthScreen(
            auth: services.auth,
            showChildModeAction: false,
          );
        }

        return ChildPairingView(
          auth: services.auth,
          database: services.database,
        );
      },
    );
  }

  Widget _buildAuthenticatedRoute(_FirebaseServices services) {
    return StreamBuilder<User?>(
      stream: services.auth.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.hasError) {
          return FirebaseStartupError(
            error:
                'Could not check Firebase authentication: ${authSnapshot.error}',
          );
        }
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = authSnapshot.data;
        if (user == null) return AuthScreen(auth: services.auth);
        return ParentHomeView(
          auth: services.auth,
          database: services.database,
          parentUid: user.uid,
        );
      },
    );
  }
}

class _FirebaseServices {
  const _FirebaseServices({required this.auth, required this.database});

  final FirebaseAuth auth;
  final FirebaseDatabase database;
}

class FirebaseStartupError extends StatelessWidget {
  const FirebaseStartupError({required this.error, super.key});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.cloud_off, size: 40),
                const SizedBox(height: 16),
                Text('Firebase is not ready',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text(
                  'Check the Firebase configuration and try again.',
                ),
                const SizedBox(height: 16),
                SelectableText(error),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
