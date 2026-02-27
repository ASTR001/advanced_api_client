import 'package:dio/dio.dart';
import 'refresh_config.dart';

class ApiConfig {
  final String baseUrl;
  final RefreshConfig? refreshConfig;
  final List<Interceptor>? interceptors;
  final void Function(DioException e, RequestOptions request)? onError;

  const ApiConfig({
    required this.baseUrl,
    this.refreshConfig,
    this.interceptors,
    this.onError,
  });
}
