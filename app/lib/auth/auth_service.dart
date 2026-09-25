import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

/// What the app needs from sign-in, so widgets and tests do not touch
/// Firebase directly.
abstract class AuthService {
  /// Emits whenever the signed-in state changes; `true` while signed in.
  Stream<bool> get signedInChanges;

  /// Completes without signing in when the user backs out of the picker.
  Future<void> signInWithGoogle();

  Future<void> signOut();

  /// A current Firebase ID token for the API, refreshed by Firebase when it
  /// has expired; null when signed out.
  Future<String?> idToken();
}

/// The project's *web* OAuth client (client type 3 in google-services.json),
/// created when the Google provider was enabled. Android's Credential
/// Manager issues the Google ID token for this audience, which is the one
/// Firebase accepts. A public identifier, not a secret.
const _webClientId = '1026765822354-ds0v8k3hev7bhb61b5ge874u4uk4bt2m.apps.googleusercontent.com';

class FirebaseAuthService implements AuthService {
  FirebaseAuthService(this._auth);

  final FirebaseAuth _auth;
  Future<void>? _googleReady;

  @override
  Stream<bool> get signedInChanges => _auth.authStateChanges().map((user) => user != null);

  @override
  Future<void> signInWithGoogle() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'});
      await _auth.signInWithPopup(provider);
      return;
    }
    // Native account picker, then hand Google's ID token to Firebase.
    // Not signInWithProvider: that runs Firebase's web handler in a browser
    // tab, and on Android Chrome's storage partitioning loses the state it
    // saved before the redirect ("missing initial state", 2026-09-25).
    final google = GoogleSignIn.instance;
    await (_googleReady ??= google.initialize(serverClientId: _webClientId));
    final GoogleSignInAccount account;
    try {
      account = await google.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return;
      rethrow;
    }
    final idToken = account.authentication.idToken;
    if (idToken == null) throw StateError('Google returned no ID token');
    await _auth.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
  }

  @override
  Future<void> signOut() async {
    // Forget the Google account too, or the next sign-in picks it again
    // silently and switching accounts becomes impossible.
    if (!kIsWeb && _googleReady != null) await GoogleSignIn.instance.signOut();
    await _auth.signOut();
  }

  @override
  Future<String?> idToken() async => _auth.currentUser?.getIdToken();
}
