import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// What the app needs from sign-in, so widgets and tests do not touch
/// Firebase directly.
abstract class AuthService {
  /// Emits whenever the signed-in state changes; `true` while signed in.
  Stream<bool> get signedInChanges;

  Future<void> signInWithGoogle();

  Future<void> signOut();

  /// A current Firebase ID token for the API, refreshed by Firebase when it
  /// has expired; null when signed out.
  Future<String?> idToken();
}

class FirebaseAuthService implements AuthService {
  FirebaseAuthService(this._auth);

  final FirebaseAuth _auth;

  @override
  Stream<bool> get signedInChanges => _auth.authStateChanges().map((user) => user != null);

  @override
  Future<void> signInWithGoogle() async {
    final provider = GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'});
    // The browser gets a popup; Android and iOS open Google's page in a
    // browser tab and return to the app. Either way Firebase ends up
    // holding the session, and the API only ever sees its ID token.
    if (kIsWeb) {
      await _auth.signInWithPopup(provider);
    } else {
      await _auth.signInWithProvider(provider);
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<String?> idToken() async => _auth.currentUser?.getIdToken();
}
