import 'package:dio/dio.dart';

typedef RefreshTokenParser = String? Function(dynamic responseData);

class RefreshConfig {
  final String path;
  final String method;
  final Map<String, dynamic>? query;
  final dynamic body;
  final Map<String, dynamic>? headers;
  final RefreshTokenParser tokenParser;

  const RefreshConfig({
    required this.path,
    required this.method,
    required this.tokenParser,
    this.query,
    this.body,
    this.headers,
  });

  Options toOptions() {
    return Options(
      method: method,
      headers: {"Skip-Auth": true, if (headers != null) ...headers!},
    );
  }
}
