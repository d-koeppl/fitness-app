import 'package:dio/dio.dart';

/// Who the API says is calling. Replaced by the client generated from
/// openapi/openapi.json in phase 4.
class MetaApi {
  MetaApi(this._dio);

  final Dio _dio;

  /// The email the API accepted for this session.
  Future<String> signedInEmail() async {
    final response = await _dio.get<Map<String, dynamic>>('/me');
    return response.data?['email'] as String? ?? '';
  }
}

/// Why a call to the API failed, in the terms the screen has to explain.
enum ApiFailure { notSignedIn, notAllowed, unreachable }

ApiFailure classifyApiError(Object error) => switch (error) {
      DioException(response: Response(statusCode: 401)) => ApiFailure.notSignedIn,
      DioException(response: Response(statusCode: 403)) => ApiFailure.notAllowed,
      _ => ApiFailure.unreachable,
    };
