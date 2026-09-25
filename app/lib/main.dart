import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'api/api_config.dart';
import 'api/auth_interceptor.dart';
import 'api/meta_api.dart';
import 'auth/auth_service.dart';
import 'firebase_options.dart';
import 'ui/auth_gate.dart';
import 'ui/home_screen.dart';
import 'ui/sign_in_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (authEmulatorHost.isNotEmpty) {
    await FirebaseAuth.instance.useAuthEmulator(authEmulatorHost, 9099);
  }

  final auth = FirebaseAuthService(FirebaseAuth.instance);
  final dio = Dio(BaseOptions(
    baseUrl: apiBaseUrl,
    // A Python function that has scaled to zero takes a few seconds to
    // start (the free tier keeps min instances at 0), so allow for it.
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 20),
  ))
    ..interceptors.add(AuthInterceptor(auth.idToken));

  runApp(FitnessApp(auth: auth, metaApi: MetaApi(dio)));
}

class FitnessApp extends StatelessWidget {
  const FitnessApp({super.key, required this.auth, required this.metaApi});

  final AuthService auth;
  final MetaApi metaApi;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fitness',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark, useMaterial3: true),
      home: AuthGate(
        auth: auth,
        signedOut: (_) => SignInScreen(signIn: auth.signInWithGoogle),
        signedIn: (_) => HomeScreen(signedInEmail: metaApi.signedInEmail, signOut: auth.signOut),
      ),
    );
  }
}
