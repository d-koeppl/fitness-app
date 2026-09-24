import 'package:dio/dio.dart';

/// `/healthz` — the one endpoint phase 0 needs. Replaced by the client
/// generated from openapi/openapi.json in phase 4.
class HealthApi {
  HealthApi(this._dio);

  final Dio _dio;

  /// The API's reported status, `"ok"` when it is up.
  Future<String> status() async {
    final response = await _dio.get<Map<String, dynamic>>('/healthz');
    return response.data?['status'] as String? ?? 'unknown';
  }
}
