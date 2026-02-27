import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../advanced_api_client.dart';

class AdvancedApiClient {
  static AdvancedApiClient? _instance;
  static ApiConfig? _defaultConfig;
  static TokenStorage? _defaultStorage;

  final Dio dio;
  final TokenStorage tokenStorage;
  final ApiConfig config;

  CancelToken _globalCancelToken = CancelToken();

  // ==========================================================
  // 🔐 PRIVATE CONSTRUCTOR
  // ==========================================================

  AdvancedApiClient._internal({
    required this.config,
    required this.tokenStorage,
  }) : dio = Dio(
          BaseOptions(
            baseUrl: config.baseUrl,
            headers: const {"Content-Type": "application/json"},
            connectTimeout: const Duration(seconds: 50),
            receiveTimeout: const Duration(seconds: 50),
            sendTimeout: const Duration(seconds: 50),
          ),
        ) {
    dio.interceptors.add(AuthInterceptor(this));
    dio.interceptors.add(RetryInterceptor(dio));

    if (config.interceptors != null) {
      dio.interceptors.addAll(config.interceptors!);
    }
  }

  // ==========================================================
  // 🚀 INITIALIZATION
  // ==========================================================

  static Future<void> initialize({required ApiConfig config}) async {
    final prefs = await SharedPreferences.getInstance();
    _defaultStorage = SharedPrefsTokenStorage(prefs);
    _defaultConfig = config;

    _instance = AdvancedApiClient._internal(
      config: config,
      tokenStorage: _defaultStorage!,
    );
  }

  static Future<AdvancedApiClient> getInstance() async {
    if (_instance != null) return _instance!;

    if (_defaultConfig == null) {
      throw Exception(
        "AdvancedApiClient is not initialized. Call initialize() first.",
      );
    }

    if (_defaultStorage == null) {
      final prefs = await SharedPreferences.getInstance();
      _defaultStorage = SharedPrefsTokenStorage(prefs);
    }

    _instance = AdvancedApiClient._internal(
      config: _defaultConfig!,
      tokenStorage: _defaultStorage!,
    );

    return _instance!;
  }

  static AdvancedApiClient get instance {
    if (_instance == null) {
      throw Exception("AdvancedApiClient is not initialized.");
    }
    return _instance!;
  }

  // ==========================================================
  // 🌐 CORE REQUEST
  // ==========================================================

  Future<dynamic> _request({
    required String endpoint,
    required String method,
    Map<String, dynamic>? query,
    dynamic data,
    bool withToken = true,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
  }) async {
    final safeQuery = query?.map(
      (k, v) => MapEntry(k, v?.toString()),
    );

    final options = Options(
      method: method,
      headers: {
        if (!withToken) "Skip-Auth": true,
        if (headers != null) ...headers,
      },
    );

    final uri = Uri.parse(dio.options.baseUrl + endpoint)
        .replace(queryParameters: safeQuery);

    _logRequest(uri, method, data, options.headers);

    try {
      final response = await dio.request(
        endpoint,
        data: data,
        queryParameters: safeQuery,
        options: options,
        cancelToken: cancelToken ?? _globalCancelToken,
      );

      _logResponse(uri, response);

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        return response.data;
      }

      throw ApiException(
        message: "HTTP Error ${response.statusCode}",
        statusCode: response.statusCode,
        data: response.data,
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // ==========================================================
  // 📦 HTTP METHODS
  // ==========================================================

  Future<dynamic> get({
    required String endpoint,
    Map<String, dynamic>? query,
    bool withToken = true,
  }) =>
      _request(
        endpoint: endpoint,
        method: "GET",
        query: query,
        withToken: withToken,
      );

  Future<dynamic> post({
    required String endpoint,
    dynamic body,
    bool withToken = true,
  }) =>
      _request(
        endpoint: endpoint,
        method: "POST",
        data: body,
        withToken: withToken,
      );

  Future<dynamic> put({
    required String endpoint,
    dynamic body,
    bool withToken = true,
  }) =>
      _request(
        endpoint: endpoint,
        method: "PUT",
        data: body,
        withToken: withToken,
      );

  Future<dynamic> patch({
    required String endpoint,
    dynamic body,
    bool withToken = true,
  }) =>
      _request(
        endpoint: endpoint,
        method: "PATCH",
        data: body,
        withToken: withToken,
      );

  Future<dynamic> delete({
    required String endpoint,
    dynamic body,
    bool withToken = true,
  }) =>
      _request(
        endpoint: endpoint,
        method: "DELETE",
        data: body,
        withToken: withToken,
      );

  // ==========================================================
  // 📤 FILE UPLOAD
  // ==========================================================

  Future<dynamic> uploadFile({
    required String endpoint,
    required String filePath,
    String? fileField,
    Map<String, dynamic>? fields,
    bool withToken = true,
  }) async {
    return uploadFiles(
      endpoint: endpoint,
      files: [filePath],
      fileField: fileField,
      fields: fields,
      withToken: withToken,
    );
  }

  Future<dynamic> uploadFiles({
    required String endpoint,
    required List<String> files,
    String? fileField,
    Map<String, dynamic>? fields,
    bool withToken = true,
  }) async {
    if (files.isEmpty) {
      throw Exception("No files provided for upload");
    }

    final formData = FormData();
    final fieldName = fileField ?? "file";

    if (fields != null) {
      formData.fields.addAll(
        fields.entries.map(
          (e) => MapEntry(e.key, e.value?.toString() ?? ""),
        ),
      );
    }

    for (final path in files) {
      final file = File(path);
      if (!await file.exists()) {
        throw Exception("File not found: $path");
      }

      formData.files.add(
        MapEntry(fieldName, await MultipartFile.fromFile(path)),
      );
    }

    return _request(
      endpoint: endpoint,
      method: "POST",
      data: formData,
      withToken: withToken,
    );
  }

  Future<dynamic> uploadMultipleFiles({
    required String endpoint,
    required Map<String, String> files,
    Map<String, dynamic>? fields,
    bool withToken = true,
  }) async {
    if (files.isEmpty) {
      throw Exception("No files provided for upload");
    }

    final formData = FormData();

    if (fields != null) {
      formData.fields.addAll(
        fields.entries.map(
          (e) => MapEntry(e.key, e.value?.toString() ?? ""),
        ),
      );
    }

    for (final entry in files.entries) {
      final file = File(entry.value);
      if (!await file.exists()) {
        throw Exception("File not found: ${entry.value}");
      }

      formData.files.add(
        MapEntry(entry.key, await MultipartFile.fromFile(entry.value)),
      );
    }

    return _request(
      endpoint: endpoint,
      method: "POST",
      data: formData,
      withToken: withToken,
    );
  }

  // ==========================================================
  // 🔄 TOKEN REFRESH
  // ==========================================================

  Future<bool> executeRefresh() async {
    final refresh = config.refreshConfig;
    if (refresh == null) return false;

    try {
      final response = await dio.request(
        refresh.path,
        data: refresh.body,
        queryParameters: refresh.query,
        options: refresh.toOptions(),
        cancelToken: _globalCancelToken,
      );

      final newToken = refresh.tokenParser(response.data);
      if (newToken == null) return false;

      await tokenStorage.saveToken(newToken);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ==========================================================
  // 🚪 TERMINATE SESSION
  // ==========================================================

  Future<void> terminateSession() async {
    if (!_globalCancelToken.isCancelled) {
      _globalCancelToken.cancel("Session terminated");
    }

    await tokenStorage.clear();
    _globalCancelToken = CancelToken();
  }

  // ==========================================================
  // ❗ ERROR HANDLING
  // ==========================================================

  ApiException _handleError(DioException e) {
    config.onError?.call(e, e.requestOptions);

    final statusCode = e.response?.statusCode;
    final responseData = e.response?.data;

    String message;

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        message = "Connection Timeout";
        break;
      case DioExceptionType.sendTimeout:
        message = "Send Timeout";
        break;
      case DioExceptionType.receiveTimeout:
        message = "Receive Timeout";
        break;
      case DioExceptionType.connectionError:
        message = "No Internet Connection";
        break;
      case DioExceptionType.badCertificate:
        message = "Bad SSL Certificate";
        break;
      case DioExceptionType.badResponse:
        if (responseData is Map<String, dynamic>) {
          message = responseData["message"]?.toString() ??
              responseData["error"]?.toString() ??
              "Server Error";
        } else if (responseData is String) {
          message = responseData;
        } else {
          message = "Server Error";
        }
        break;
      default:
        message = e.message ?? "Unexpected Error";
    }

    return ApiException(
      message: message,
      statusCode: statusCode,
      data: responseData,
    );
  }

  // ==========================================================
  // 🧾 LOGGING
  // ==========================================================

  void _logRequest(
    Uri uri,
    String method,
    dynamic data,
    Map<String, dynamic>? headers,
  ) {
    if (!kDebugMode) return;

    debugPrint("========== API REQUEST ==========");
    debugPrint("URL: $uri");
    debugPrint("Method: $method");
    debugPrint("Headers: $headers");
    debugPrint("Body: $data");
    debugPrint("=================================");
  }

  void _logResponse(Uri uri, Response response) {
    if (!kDebugMode) return;

    debugPrint("========== API RESPONSE ==========");
    debugPrint("URL: $uri");
    debugPrint("Status: ${response.statusCode}");
    debugPrint("Data: ${response.data}");
    debugPrint("==================================");
  }
}
