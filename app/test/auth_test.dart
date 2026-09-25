import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness/api/auth_interceptor.dart';
import 'package:fitness/auth/auth_service.dart';
import 'package:fitness/ui/auth_gate.dart';
import 'package:fitness/ui/home_screen.dart';
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
}

DioException _status(int code) {
  final options = RequestOptions(path: '/me');
  return DioException(requestOptions: options, response: Response(requestOptions: options, statusCode: code));
}

Widget _home(Future<String> Function() email, {Future<void> Function()? signOut}) =>
    MaterialApp(home: HomeScreen(signedInEmail: email, signOut: signOut ?? () async {}));

void main() {
  group('AuthGate', () {
    testWidgets('signs in, then out, following the auth state', (tester) async {
      final auth = FakeAuth();
      await tester.pumpWidget(MaterialApp(
        home: AuthGate(
          auth: auth,
          signedOut: (_) => SignInScreen(signIn: auth.signInWithGoogle),
          signedIn: (_) => _home(() async => 'owner@example.com', signOut: auth.signOut),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Sign in with Google'), findsOneWidget);

      await tester.tap(find.text('Sign in with Google'));
      await tester.pumpAndSettle();
      expect(find.text('Signed in as owner@example.com'), findsOneWidget);

      await tester.tap(find.byTooltip('Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in with Google'), findsOneWidget);
    });
  });

  group('HomeScreen', () {
    testWidgets('an account the API refuses is told so and offered sign-out, not retry', (tester) async {
      await tester.pumpWidget(_home(() => Future.error(_status(403))));
      await tester.pumpAndSettle();

      expect(find.text('This Google account is not allowed.'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('a rejected session asks to sign in again', (tester) async {
      await tester.pumpWidget(_home(() => Future.error(_status(401))));
      await tester.pumpAndSettle();

      expect(find.text('Your session was not accepted. Sign in again.'), findsOneWidget);
    });

    testWidgets('an unreachable API can be retried', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_home(() async {
        if (++calls == 1) throw DioException(requestOptions: RequestOptions(path: '/me'));
        return 'owner@example.com';
      }));
      await tester.pumpAndSettle();
      expect(find.text('API unreachable'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Signed in as owner@example.com'), findsOneWidget);
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
