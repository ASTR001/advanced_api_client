import 'dart:async';
import 'package:dio/dio.dart';

class RetryInterceptor extends Interceptor {
  final Dio dio;
  final int maxRetries;
  final Duration initialDelay;

  RetryInterceptor(this.dio,
      {this.maxRetries = 2, this.initialDelay = const Duration(seconds: 1)});

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final request = err.requestOptions;
    int retryCount = request.extra["retryCount"] ?? 0;

    final shouldRetry = _isRetryable(err);

    if (shouldRetry && retryCount < maxRetries) {
      retryCount++;
      request.extra["retryCount"] = retryCount;

      final delay =
          initialDelay * (1 << (retryCount - 1)); // Exponential backoff
      await Future.delayed(delay);

      try {
        final response = await dio.fetch(request);
        return handler.resolve(response);
      } catch (e) {
        return handler.next(err);
      }
    }

    handler.next(err);
  }

  bool _isRetryable(DioException err) {
    return err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.receiveTimeout;
  }
}
