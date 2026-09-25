import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness/api/auth_interceptor.dart';
import 'package:fitness/auth/auth_service.dart';
import 'package:fitness/ui/auth_gate.dart';
import 'package:fitness/ui/sign_in_screen.dart';

class FakeAuth implements AuthService {
  final _changes = StreamController<bool>.broadcast();
  bool signedIn = false;
  String? token = 'token-1';

  void emit(bool value) {
    signedIn = value;
    _changes.add(value);
  }

  @override
  Stream<bool> get signedInChanges async* {
    yield signedIn;
    yield* _changes.stream;
  }

  @override
  Future<void> signInWithGoogle() async => emit(true);

  @override
  Future<void> signOut() async => emit(false);

  @override
  Future<String?> idToken() async => signedIn ? token : null;

  @override
  String? get email => signedIn ? 'owner@example.com' : null;
}

void main() {
  group('AuthGate', () {
    testWidgets('signs in, then out, following the auth state', (tester) async {
      final auth = FakeAuth();
      await tester.pumpWidget(MaterialApp(
        home: AuthGate(
          auth: auth,
          signedOut: (_) => SignInScreen(signIn: auth.signInWithGoogle),
          signedIn: (_) => Scaffold(
            body: TextButton(onPressed: auth.signOut, child: const Text('Signed in')),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Sign in with Google'), findsOneWidget);

      await tester.tap(find.text('Sign in with Google'));
      await tester.pumpAndSettle();
      expect(find.text('Signed in'), findsOneWidget);

      await tester.tap(find.text('Signed in'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in with Google'), findsOneWidget);
    });
  });

  group('AuthInterceptor', () {
    Future<RequestOptions> intercept(Future<String?> Function() idToken) async {
      final seen = Completer<RequestOptions>();
      final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
        ..interceptors.add(AuthInterceptor(idToken))
        ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
          seen.complete(options);
          handler.reject(DioException(requestOptions: options)); // never hit the network
        }));
      await dio.get<void>('/me').catchError((_) => Response<void>(requestOptions: RequestOptions()));
      return seen.future;
    }

    test('adds the bearer token when signed in', () async {
      final options = await intercept(() async => 'abc');
      expect(options.headers['Authorization'], 'Bearer abc');
    });

    test('sends no Authorization header when signed out', () async {
      final options = await intercept(() async => null);
      expect(options.headers.containsKey('Authorization'), isFalse);
    });
  });
}
