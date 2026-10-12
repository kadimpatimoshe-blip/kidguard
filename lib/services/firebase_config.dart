import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';

class FirebaseConfig {
  static const FirebaseOptions childAndroid = FirebaseOptions(
    apiKey: 'AIzaSyCn_0mbkQNSlOIvUA3Tv9QKFn8skyZL0vg',
    appId: '1:897177192961:android:205829551a9fac30938e00',
    messagingSenderId: '897177192961',
    projectId: 'kidguard-3b499',
    databaseURL:
        'https://kidguard-3b499-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'kidguard-3b499.firebasestorage.app',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCn_0mbkQNSlOIvUA3Tv9QKFn8skyZL0vg',
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

    const appId = String.fromEnvironment('FIREBASE_APP_ID');
    const messagingSenderId =
        String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
    const databaseURL = String.fromEnvironment('FIREBASE_DATABASE_URL');
    const authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');

    final missingValues = <String>[
      if (appId.isEmpty) 'FIREBASE_APP_ID',
      if (messagingSenderId.isEmpty) 'FIREBASE_MESSAGING_SENDER_ID',
      if (databaseURL.isEmpty) 'FIREBASE_DATABASE_URL',
    ];
    if (missingValues.isNotEmpty) {
      throw StateError(
        'Missing Firebase configuration: ${missingValues.join(', ')}',
      );
    }

    return FirebaseOptions(
      apiKey: 'AIzaSyCn_0mbkQNSlOIvUA3Tv9QKFn8skyZL0vg',
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: 'kidguard-3b499',
      databaseURL: databaseURL,
      authDomain: authDomain.isEmpty ? null : authDomain,
    );
  }
}
