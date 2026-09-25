import 'package:dio/dio.dart';

/// Puts the signed-in user's Firebase ID token on every API request
/// (ADR-029). Requests made while signed out go without one and get the
/// API's 401.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._idToken);

  final Future<String?> Function() _idToken;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _idToken();
    if (token != null) options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }
}
