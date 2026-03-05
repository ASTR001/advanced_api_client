import 'dart:async';
import 'package:dio/dio.dart';
import '../../advanced_api_client.dart';

class AuthInterceptor extends Interceptor {
  final AdvancedApiClient client;
  Completer<bool>? _refreshCompleter;

  AuthInterceptor(this.client);

  // ==========================================================
  // 🔐 ATTACH TOKEN
  // ==========================================================
  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    _handleRequest(options, handler);
  }

  Future<void> _handleRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await client.tokenStorage.getToken();

    if (token != null && options.headers["Skip-Auth"] != true) {
      options.headers["Authorization"] = "Bearer $token";
      ApiLogger.auth("Token attached to request");
    }

    options.headers.remove("Skip-Auth");
    handler.next(options);
  }

  // ==========================================================
  // 🔄 RESPONSE INTERCEPTOR (CHECK AUTH ERRORS)
  // ==========================================================
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    final data = response.data;

    if (data is Map<String, dynamic>) {
      final int? code = data["code"];
      final String message = data["message"]?.toString().toLowerCase() ?? "";

      final bool isAuthError = code == 401 ||
          code == 403 ||
          message.contains("token expired") ||
          message.contains("invalid token");

      if (isAuthError) {
        final request = response.requestOptions;

        // Prevent infinite retry loops
        if (request.extra["retrying"] == true) {
          ApiLogger.auth("Retry already attempted. Forwarding error");
          return handler.reject(
            DioException(
              requestOptions: request,
              response: response,
              type: DioExceptionType.badResponse,
            ),
          );
        }

        ApiLogger.auth("Auth error detected, refreshing token...");

        // Wait for ongoing refresh or perform new one
        final refreshSuccess = await _refreshToken();

        if (!refreshSuccess) {
          ApiLogger.auth("Token refresh failed. Forwarding error.");
          return handler.reject(
            DioException(
              requestOptions: request,
              response: response,
              type: DioExceptionType.badResponse,
            ),
          );
        }

        // Retry original request once
        request.extra["retrying"] = true;

        // If this was a FormData upload, rebuild it
        if (request.extra.containsKey("_dataBuilder")) {
          final builder = request.extra["_dataBuilder"] as dynamic Function();
          request.data = builder(); // rebuild fresh FormData
        }

        // Attach new token
        final newToken = await client.tokenStorage.getToken();
        if (newToken != null) {
          request.headers["Authorization"] = "Bearer $newToken";
        }

        ApiLogger.auth("Retrying original request after refresh...");

        try {
          final retryResponse = await client.dio.fetch(request);
          handler.resolve(retryResponse);
        } catch (e) {
          handler.reject(
            DioException(
              requestOptions: request,
              type: DioExceptionType.unknown,
              error: e,
            ),
          );
        }

        return;
      }
    }

    handler.next(response);
  }

  // ==========================================================
  // ❗ ERROR HANDLING + AUTO REFRESH
  // ==========================================================
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    ApiLogger.auth("onError triggered");

    if (CancelToken.isCancel(err)) {
      ApiLogger.auth("Request cancelled");
      return handler.next(err);
    }

    final statusCode = err.response?.statusCode;
    final isAuthError =
        statusCode == 401 || statusCode == 403 || _isTokenExpired(err);

    if (!isAuthError || client.config.refreshConfig == null) {
      return handler.next(err);
    }

    ApiLogger.auth("Authentication error detected. Attempting refresh...");

    final request = err.requestOptions;

    if (request.extra["retrying"] == true) {
      ApiLogger.auth("Retry already attempted. Preventing loop.");
      return handler.next(err);
    }

    try {
      final success = await _refreshToken();

      if (!success) {
        ApiLogger.auth("Token refresh failed. Forwarding error.");
        return handler.next(err);
      }

      request.extra["retrying"] = true;

      final newToken = await client.tokenStorage.getToken();
      if (newToken != null) {
        request.headers["Authorization"] = "Bearer $newToken";
      }

      ApiLogger.auth("Retrying original request...");

      final retryResponse = await client.dio.fetch(request);
      handler.resolve(retryResponse);
    } catch (e) {
      ApiLogger.error("Retry failed: $e");
      handler.next(err);
    }
  }

  // ==========================================================
  // 🔎 TOKEN EXPIRED CHECK
  // ==========================================================
  bool _isTokenExpired(DioException err) {
    final data = err.response?.data;

    if (data is Map<String, dynamic>) {
      final message = data["message"]?.toString().toLowerCase() ?? "";
      return message.contains("token expired") ||
          message.contains("invalid token");
    }

    return false;
  }

  // ==========================================================
  // 🔄 REFRESH TOKEN (Safe + Clean Logs)
  // ==========================================================
  Future<bool> _refreshToken() async {
    // Wait for ongoing refresh if exists
    if (_refreshCompleter != null) {
      ApiLogger.auth("Refresh already in progress. Waiting...");
      await _refreshCompleter!.future;
      final token = await client.tokenStorage.getToken();
      return token != null;
    }

    ApiLogger.auth("Starting token refresh...");
    _refreshCompleter = Completer<bool>();

    try {
      final refreshConfig = client.config.refreshConfig!;
      final accessToken = await client.tokenStorage.getToken();

      if (accessToken == null) {
        ApiLogger.auth("No access token available for refresh!");
        _refreshCompleter!.complete(false);
        return false;
      }

      // Build Dio instance for refresh request
      final dioToUse = Dio(BaseOptions(
        baseUrl: client.config.baseUrl,
        connectTimeout: const Duration(seconds: 50),
        receiveTimeout: const Duration(seconds: 50),
        sendTimeout: const Duration(seconds: 50),
      ));

      // Merge headers: Skip-Auth + Bearer token
      final options = refreshConfig.toOptions().copyWith(
        headers: {
          "Authorization": "Bearer $accessToken",
          if (refreshConfig.headers != null) ...refreshConfig.headers!,
        },
      );

      // Build body for refresh request
      final body = refreshConfig.bodyBuilder != null
          ? await refreshConfig.bodyBuilder!()
          : (refreshConfig.body ?? {});

      final response = await dioToUse.request(
        refreshConfig.path,
        data: body,
        queryParameters: refreshConfig.query,
        options: options,
      );

      // Parse new token
      final newAccessToken = refreshConfig.tokenParser(response.data);
      if (newAccessToken != null) {
        await client.tokenStorage.saveToken(newAccessToken);
        ApiLogger.auth("Token refresh SUCCESS");
        _refreshCompleter!.complete(true);
        return true;
      }

      ApiLogger.auth(
          "Refresh token parser returned null. Please check API config token parser value");
      _refreshCompleter!.complete(false);
      return false;
    } catch (e) {
      ApiLogger.error("Refresh call failed: $e");
      if (!_refreshCompleter!.isCompleted) _refreshCompleter!.complete(false);
      return false;
    } finally {
      Future.microtask(() => _refreshCompleter = null);
      ApiLogger.auth("Refresh cycle completed");
    }
  }
}
