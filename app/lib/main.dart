import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:fitness_api/fitness_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_config.dart';
import 'api/auth_interceptor.dart';
import 'api/slow_requests.dart';
import 'auth/auth_service.dart';
import 'data/dashboard.dart';
import 'data/push.dart';
import 'firebase_options.dart';
import 'push/push_service.dart';
import 'ui/auth_gate.dart';
import 'ui/shell.dart';
import 'ui/sign_in_screen.dart';
import 'ui/theme/palette.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (authEmulatorHost.isNotEmpty) {
    await FirebaseAuth.instance.useAuthEmulator(authEmulatorHost, 9099);
  }

  final auth = FirebaseAuthService(FirebaseAuth.instance);
  final dio = Dio(
    BaseOptions(
      baseUrl: apiBaseUrl,
      // A Python function that has scaled to zero takes a few seconds to
      // start (the free tier keeps min instances at 0), so allow for it.
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );
  // Our interceptor instead of the generated client's own auth ones: the
  // token comes from Firebase on every request, refreshed when it expires.
  final api = FitnessApi(dio: dio, interceptors: [AuthInterceptor(auth.idToken), const SlowRequestInterceptor()]);

  // The report push reaches Android and the browser build (ADR-030); iOS
  // would need an APNs key first.
  final push = kIsWeb || defaultTargetPlatform == TargetPlatform.android
      ? FirebasePushService(FirebaseMessaging.instance)
      : null;

  runApp(FitnessApp(auth: auth, api: api, push: push));

  // The web build draws to a canvas, so without the semantics tree a
  // screen reader or a browser extension finds no text on the page (the
  // web app it replaced was plain HTML). Flutter builds that tree only
  // when it detects assistive technology; ask for it always instead.
  if (kIsWeb) SemanticsBinding.instance.ensureSemantics();
}

class FitnessApp extends StatelessWidget {
  const FitnessApp({super.key, required this.auth, required this.api, this.push});

  final AuthService auth;
  final FitnessApi api;
  final PushService? push;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // The browser tab's title on the web, as the old web app's was.
      title: 'Fitness Dashboard',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Palette.light, Brightness.light),
      darkTheme: buildTheme(Palette.dark, Brightness.dark),
      home: AuthGate(
        auth: auth,
        signedOut: (_) => SignInScreen(signIn: auth.signInWithGoogle),
        // A fresh scope per sign-in, so a second account never sees the
        // first one's data while its own loads.
        signedIn: (_) => ProviderScope(
          overrides: [apiProvider.overrideWithValue(api), pushServiceProvider.overrideWithValue(push)],
          child: DashboardShell(email: auth.email, signOut: auth.signOut),
        ),
      ),
    );
  }
}
