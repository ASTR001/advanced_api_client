import 'package:dio/dio.dart';
import 'refresh_config.dart';

class ApiConfig {
  final String baseUrl;
  final bool enableAutoRefresh;
  final void Function()? onSessionExpired;
  final RefreshConfig? refreshConfig;
  final List<Interceptor>? interceptors;
  final void Function(DioException e, RequestOptions request)? onError;
  final bool enableLogs;
  final Map<String, dynamic>? headers;
  final bool allowBadCertificates;

  const ApiConfig({
    required this.baseUrl,
    this.enableAutoRefresh = true,
    this.onSessionExpired,
    this.refreshConfig,
    this.interceptors,
    this.onError,
    this.enableLogs = true,
    this.headers,
    this.allowBadCertificates = false,
  });
}
