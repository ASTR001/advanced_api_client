import 'dart:async';
import 'package:dio/dio.dart';
import '../../advanced_api_client.dart';

class AuthInterceptor extends Interceptor {
  final AdvancedApiClient client;
  Completer<bool>? _refreshCompleter;

  AuthInterceptor(this.client);

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await client.tokenStorage.getToken();

    if (token != null && options.headers["Skip-Auth"] != true) {
      options.headers["Authorization"] = "Bearer $token";
    }
    options.headers.remove("Skip-Auth");

    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (CancelToken.isCancel(err)) {
      return handler.next(err);
    }

    final statusCode = err.response?.statusCode;
    final isAuthError =
        statusCode == 401 || statusCode == 403 || _isTokenExpired(err);

    if (!isAuthError || client.config.refreshConfig == null) {
      return handler.next(err);
    }

    final request = err.requestOptions;

    if (request.extra["retrying"] == true) {
      return handler.next(err); // Prevent infinite loop
    }

    try {
      final success = await _refreshToken();

      if (!success) {
        return handler.next(err);
      }

      request.extra["retrying"] = true;
      final newToken = await client.tokenStorage.getToken();

      if (newToken != null) {
        request.headers["Authorization"] = "Bearer $newToken";
      }

      final response = await client.dio.fetch(request);
      handler.resolve(response);
    } catch (_) {
      handler.next(err);
    }
  }

  bool _isTokenExpired(DioException err) {
    // Customize depending on API response
    final data = err.response?.data;
    if (data is Map<String, dynamic>) {
      final message = data["message"]?.toString().toLowerCase() ?? "";
      return message.contains("token expired") ||
          message.contains("invalid token");
    }
    return false;
  }

  Future<bool> _refreshToken() async {
    if (_refreshCompleter != null) return _refreshCompleter!.future;

    _refreshCompleter = Completer<bool>();

    try {
      final success = await client.executeRefresh();
      _refreshCompleter!.complete(success);
      return success;
    } catch (_) {
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      // Prevent race condition: only reset if future is complete
      if (_refreshCompleter!.isCompleted) {
        _refreshCompleter = null;
      }
    }
  }
}
