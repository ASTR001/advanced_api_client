import 'dart:async';

import 'package:dio/dio.dart';

typedef RefreshTokenParser = String? Function(dynamic responseData);
typedef RefreshBodyBuilder = FutureOr<Map<String, dynamic>> Function();

class RefreshConfig {
  final String path;
  final String method;
  final Map<String, dynamic>? query;
  final Map<String, dynamic>? body; // static body
  final RefreshBodyBuilder? bodyBuilder; // dynamic body
  final Map<String, dynamic>? headers;
  final RefreshTokenParser tokenParser;

  const RefreshConfig({
    required this.path,
    required this.method,
    required this.tokenParser,
    this.query,
    this.body,
    this.bodyBuilder,
    this.headers,
  });

  Options toOptions() {
    return Options(
      method: method,
      headers: {"Skip-Auth": true, if (headers != null) ...headers!},
    );
  }
}
