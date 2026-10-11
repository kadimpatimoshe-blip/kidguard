import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import 'views/auth_screen.dart';
import 'views/child_pairing_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  late final FirebaseApp app;
  try {
    app = await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'AIzaSyCn_0mbkQNSlOIvUA3Tv9QKFn8skyZL0vg',
        appId: '1:897177192961:android:205829551a9fac30938e00',
        messagingSenderId: '897177192961',
        projectId: 'kidguard-3b499',
        databaseURL:
            'https://kidguard-3b499-default-rtdb.asia-southeast1.firebasedatabase.app',
        storageBucket: 'kidguard-3b499.firebasestorage.app',
      ),
    );
  } catch (error) {
    runApp(
      MaterialApp(
        home: FirebaseStartupError(error: error.toString()),
      ),
    );
    return;
  }

  runApp(KidGuardChildApp(firebaseApp: app));
}

class KidGuardChildApp extends StatefulWidget {
  const KidGuardChildApp({required this.firebaseApp, super.key});

  final FirebaseApp firebaseApp;

  @override
  State<KidGuardChildApp> createState() => _KidGuardChildAppState();
}

class _KidGuardChildAppState extends State<KidGuardChildApp> {
  late final Future<_FirebaseServices> _firebaseServicesFuture;

  @override
  void initState() {
    super.initState();
    _firebaseServicesFuture = _initializeFirebase(widget.firebaseApp);
  }

  Future<_FirebaseServices> _initializeFirebase(FirebaseApp app) async {
    final auth = FirebaseAuth.instanceFor(app: app);
    await auth.signOut();

    return _FirebaseServices(
      auth: auth,
      database: FirebaseDatabase.instanceFor(
        app: app,
        databaseURL: app.options.databaseURL,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KidGuard Child',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF176B57),
          surface: const Color(0xFFF5F6F1),
        ),
        useMaterial3: true,
      ),
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
          final services = snapshot.data!;
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
        },
      ),
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
