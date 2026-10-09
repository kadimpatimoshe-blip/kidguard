import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';

class FirebaseConfig {
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAA0Gf_dLsJUhSw7WE0q4XiW4pkRL80m4o',
    appId: '1:897177192961:web:286e429b79dabe05938e00',
    messagingSenderId: '897177192961',
    projectId: 'kidguard-3b499',
    authDomain: 'kidguard-3b499.firebaseapp.com',
    databaseURL:
        'https://kidguard-3b499-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'kidguard-3b499.firebasestorage.app',
    measurementId: 'G-KT3LSRH7W9',
  );

  static FirebaseOptions fromEnvironment() {
    if (kIsWeb) return web;

    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    const appId = String.fromEnvironment('FIREBASE_APP_ID');
    const messagingSenderId =
        String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
    const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
    const databaseURL = String.fromEnvironment('FIREBASE_DATABASE_URL');
    const authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');

    final missingValues = <String>[
      if (apiKey.isEmpty) 'FIREBASE_API_KEY',
      if (appId.isEmpty) 'FIREBASE_APP_ID',
      if (messagingSenderId.isEmpty) 'FIREBASE_MESSAGING_SENDER_ID',
      if (projectId.isEmpty) 'FIREBASE_PROJECT_ID',
      if (databaseURL.isEmpty) 'FIREBASE_DATABASE_URL',
    ];
    if (missingValues.isNotEmpty) {
      throw StateError(
        'Missing Firebase configuration: ${missingValues.join(', ')}',
      );
    }

    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      databaseURL: databaseURL,
      authDomain: authDomain.isEmpty ? null : authDomain,
    );
  }
}
