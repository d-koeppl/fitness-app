import 'package:flutter/material.dart';

import '../auth/auth_service.dart';

/// Shows [signedIn] while a user is signed in, [signedOut] otherwise, and
/// switches as soon as Firebase reports a change.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.auth, required this.signedIn, required this.signedOut});

  final AuthService auth;
  final WidgetBuilder signedIn;
  final WidgetBuilder signedOut;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: auth.signedInChanges,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return snapshot.data! ? signedIn(context) : signedOut(context);
      },
    );
  }
}
