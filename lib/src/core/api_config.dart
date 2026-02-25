import 'package:dio/dio.dart';
import 'refresh_config.dart';

class ApiConfig {
  final String baseUrl;
  final RefreshConfig? refreshConfig;
  final List<Interceptor>? interceptors; // optional custom interceptors

  const ApiConfig({
    required this.baseUrl,
    this.refreshConfig,
    this.interceptors,
  });
}
