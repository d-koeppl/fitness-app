import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Firebase project `fitness-75c22`, in the shape `flutterfire configure`
/// writes. Values from `firebase apps:sdkconfig` (2026-09-25). These keys
/// identify the project to Google; they are not secrets — access is
/// decided by the API's allowlist (ADR-029).
///
/// iOS is registered in phase 9 and fails loudly until then.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => android,
      _ => throw UnsupportedError('No Firebase app is registered for $defaultTargetPlatform yet.'),
    };
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyB_FucEYww1KUdLvSXhLwJez5_KKgOSKKg',
    appId: '1:1026765822354:web:cc391707109a9e971d494b',
    messagingSenderId: '1026765822354',
    projectId: 'fitness-75c22',
    authDomain: 'fitness-75c22.firebaseapp.com',
    storageBucket: 'fitness-75c22.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBfI9EW_ToS2EnR4TGg9KzH3wiKi67Ji0Q',
    appId: '1:1026765822354:android:a468b28b7f18eab61d494b',
    messagingSenderId: '1026765822354',
    projectId: 'fitness-75c22',
    storageBucket: 'fitness-75c22.firebasestorage.app',
  );
}
