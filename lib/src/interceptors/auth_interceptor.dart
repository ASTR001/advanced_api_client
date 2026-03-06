import 'dart:async';
import 'package:dio/dio.dart';
import '../../advanced_api_client.dart';

class AuthInterceptor extends Interceptor {
  final AdvancedApiClient client;

  Completer<bool>? _refreshCompleter;

  /// Prevent multiple redirects
  bool _sessionExpiredHandled = false;

  /// Queue for requests waiting for token refresh
  final List<_QueuedRequest> _requestQueue = [];

  AuthInterceptor(this.client);

  // ==========================================================
  // 🔐 ATTACH TOKEN
  // ==========================================================

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    /// Wait if refresh running
    if (_refreshCompleter != null && options.extra["skipRefreshWait"] != true) {
      ApiLogger.auth("Waiting for token refresh before sending request...");
      try {
        await _refreshCompleter!.future;
      } catch (_) {}
    }

    final token = await client.tokenStorage.getToken();

    if (token != null &&
        options.headers["Skip-Auth"] != true &&
        options.extra["skipAuthAttach"] != true) {
      options.headers["Authorization"] = "Bearer $token";
    }

    options.headers.remove("Skip-Auth");

    handler.next(options);
  }

  // ==========================================================
  // 🔄 RESPONSE INTERCEPTOR
  // ==========================================================

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    final data = response.data;

    if (data is Map<String, dynamic>) {
      final int? code = data["code"];
      final String message = data["message"]?.toLowerCase() ?? "";

      final bool isAuthError = code == 401 ||
          code == 403 ||
          message.contains("token expired") ||
          message.contains("invalid token");

      if (isAuthError) {
        final request = response.requestOptions;

        /// 🚨 refresh disabled
        if (!client.config.enableAutoRefresh ||
            client.config.refreshConfig == null) {
          _handleSessionExpired();
          return handler.reject(
            DioException(
              requestOptions: request,
              response: response,
              type: DioExceptionType.badResponse,
            ),
          );
        }

        /// prevent infinite retry
        if (request.extra["retrying"] == true) {
          return handler.reject(
            DioException(
              requestOptions: request,
              response: response,
              type: DioExceptionType.badResponse,
            ),
          );
        }

        final completer = Completer<Response>();

        _requestQueue.add(
          _QueuedRequest(
            requestOptions: request,
            completer: completer,
          ),
        );

        if (_refreshCompleter == null) {
          await _startTokenRefresh();
        }

        try {
          final retryResponse = await completer.future;
          handler.resolve(retryResponse);
        } catch (e) {
          handler.reject(
            DioException(
              requestOptions: request,
              response: response,
              type: DioExceptionType.badResponse,
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
  // ❗ ERROR INTERCEPTOR
  // ==========================================================

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (CancelToken.isCancel(err)) {
      return handler.next(err);
    }

    final statusCode = err.response?.statusCode;

    final bool isAuthError =
        statusCode == 401 || statusCode == 403 || _isTokenExpired(err);

    if (!isAuthError) {
      return handler.next(err);
    }

    /// refresh disabled
    if (!client.config.enableAutoRefresh ||
        client.config.refreshConfig == null) {
      _handleSessionExpired();
      return handler.next(err);
    }

    final request = err.requestOptions;

    if (request.extra["retrying"] == true) {
      return handler.next(err);
    }

    final completer = Completer<Response>();

    _requestQueue.add(
      _QueuedRequest(
        requestOptions: request,
        completer: completer,
      ),
    );

    if (_refreshCompleter == null) {
      await _startTokenRefresh();
    }

    try {
      final response = await completer.future;
      handler.resolve(response);
    } catch (_) {
      handler.next(err);
    }
  }

  // ==========================================================
  // 🔄 START TOKEN REFRESH
  // ==========================================================

  Future<void> _startTokenRefresh() async {
    if (_refreshCompleter != null) return;

    ApiLogger.auth("Starting token refresh...");

    _refreshCompleter = Completer<bool>();

    bool refreshSuccess = false;

    try {
      refreshSuccess = await _refreshToken();
    } catch (e) {
      ApiLogger.error("Refresh exception: $e");
    }

    if (refreshSuccess) {
      ApiLogger.auth("Token refresh success → retrying requests");

      final token = await client.tokenStorage.getToken();

      for (final queued in _requestQueue) {
        final request = queued.requestOptions;

        request.extra["retrying"] = true;
        request.extra["skipRefreshWait"] = true;

        /// rebuild FormData
        if (request.extra.containsKey("_dataBuilder")) {
          final builder = request.extra["_dataBuilder"] as dynamic Function();
          request.data = builder();
        }

        if (token != null) {
          request.headers["Authorization"] = "Bearer $token";
        }

        try {
          final response = await client.dio.fetch(request);
          queued.completer.complete(response);
        } catch (e) {
          queued.completer.completeError(e);
        }
      }
    } else {
      ApiLogger.auth("Refresh failed");

      for (final queued in _requestQueue) {
        queued.completer.completeError("Token refresh failed");
      }

      _handleSessionExpired();
    }

    _requestQueue.clear();

    _refreshCompleter!.complete(refreshSuccess);
    _refreshCompleter = null;
  }

  // ==========================================================
  // 🔄 REFRESH TOKEN
  // ==========================================================

  Future<bool> _refreshToken() async {
    final refreshConfig = client.config.refreshConfig!;
    final accessToken = await client.tokenStorage.getToken();

    if (accessToken == null) {
      return false;
    }

    final dioToUse = Dio(client.dio.options);

    final options = refreshConfig.toOptions().copyWith(
      headers: {
        "Authorization": "Bearer $accessToken",
        if (refreshConfig.headers != null) ...refreshConfig.headers!,
      },
      extra: {"skipRefresh": true},
    );

    final body = refreshConfig.bodyBuilder != null
        ? await refreshConfig.bodyBuilder!()
        : (refreshConfig.body ?? {});

    final response = await dioToUse.request(
      refreshConfig.path,
      data: body,
      queryParameters: refreshConfig.query,
      options: options,
    );

    final newToken = refreshConfig.tokenParser(response.data);

    if (newToken != null) {
      await client.tokenStorage.saveToken(newToken);
      return true;
    }

    return false;
  }

  // ==========================================================
  // 🔎 TOKEN EXPIRED CHECK
  // ==========================================================

  bool _isTokenExpired(DioException err) {
    final data = err.response?.data;

    if (data is Map<String, dynamic>) {
      final message = data["message"]?.toLowerCase() ?? "";
      return message.contains("token expired") ||
          message.contains("invalid token");
    }

    return false;
  }

  // ==========================================================
  // 🚨 SESSION EXPIRED HANDLER
  // ==========================================================

  void _handleSessionExpired() {
    if (_sessionExpiredHandled) return;

    _sessionExpiredHandled = true;

    ApiLogger.auth("Session expired → redirecting");

    client.config.onSessionExpired?.call();
  }
}

class _QueuedRequest {
  final RequestOptions requestOptions;
  final Completer<Response> completer;

  _QueuedRequest({
    required this.requestOptions,
    required this.completer,
  });
}
