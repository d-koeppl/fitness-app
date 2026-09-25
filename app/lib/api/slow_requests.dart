import 'package:dio/dio.dart';

/// Pass as `extra:` on a request that is slow by design — the Google sync
/// and a Gemini report, which the server allows up to five minutes for
/// (functions/main.py). Every other request keeps the client's 20 s.
const slowRequest = {'slow': true};

/// Lengthens the receive timeout for requests marked [slowRequest]. The
/// generated client takes `extra` but no per-request timeout, so this is
/// where the one becomes the other.
class SlowRequestInterceptor extends Interceptor {
  const SlowRequestInterceptor();

  static const timeout = Duration(minutes: 5);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.extra['slow'] == true) options.receiveTimeout = timeout;
    handler.next(options);
  }
}
