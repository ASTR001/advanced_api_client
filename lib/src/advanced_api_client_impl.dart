import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../advanced_api_client.dart';

class AdvancedApiClient {
  static AdvancedApiClient? _instance;

  final Dio dio;
  final TokenStorage tokenStorage;
  final ApiConfig config;

  CancelToken _globalCancelToken = CancelToken();

  AdvancedApiClient._internal({
    required this.config,
    required this.tokenStorage,
  }) : dio = Dio(
         BaseOptions(
           baseUrl: config.baseUrl,
           headers: {"Content-Type": "application/json"},
         ),
       ) {
    // Default interceptors
    dio.interceptors.add(AuthInterceptor(this));
    dio.interceptors.add(RetryInterceptor(dio));

    // Optional custom interceptors from config
    if (config.interceptors != null) {
      dio.interceptors.addAll(config.interceptors!);
    }
  }

  // ================= AUTO INITIALIZE =================

  static Future<void> initialize({required ApiConfig config}) async {
    final prefs = await SharedPreferences.getInstance();
    final storage = SharedPrefsTokenStorage(prefs);

    _instance = AdvancedApiClient._internal(
      config: config,
      tokenStorage: storage,
    );
  }

  static AdvancedApiClient get instance {
    if (_instance == null) {
      throw Exception("AdvancedApiClient is not initialized.");
    }
    return _instance!;
  }

  // ==========================================================
  // 🔥 CORE REQUEST METHOD
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
      (key, value) => MapEntry(key, value.toString()),
    );

    final uri = Uri.parse(
      dio.options.baseUrl + endpoint,
    ).replace(queryParameters: safeQuery);

    final options = Options(
      method: method,
      headers: {
        if (!withToken) "Skip-Auth": true,
        if (headers != null) ...headers,
      },
    );

    debugPrint("========== API REQUEST ==========");
    debugPrint("Full URL: $uri");
    debugPrint("Method: $method");

    if (data is FormData) {
      debugPrint("Body: FormData {");
      for (var f in data.fields) {
        debugPrint("  Field - ${f.key}: ${f.value}");
      }
      for (var f in data.files) {
        debugPrint("  File  - ${f.key}: ${f.value.filename}");
      }
      debugPrint("}");
    } else {
      debugPrint("Body: $data");
    }

    debugPrint("Headers: ${options.headers}");
    debugPrint("=================================");

    try {
      final response = await dio.request(
        endpoint,
        data: data,
        queryParameters: query,
        options: options,
        cancelToken: cancelToken ?? _globalCancelToken,
      );

      debugPrint("========== API RESPONSE ==========");
      debugPrint("Full URL: $uri");
      debugPrint("Status Code: ${response.statusCode}");
      debugPrint("Response Data: ${response.data}");
      debugPrint("==================================");

      final responseData = response.data;

      if (response.statusCode == 200 || response.statusCode == 201) {
        return responseData;
      }

      throw ApiException(
        message: "HTTP Error: ${response.statusCode}",
        statusCode: response.statusCode,
        data: responseData,
      );
    } on DioException catch (e) {
      debugPrint("========== API ERROR ============");
      debugPrint("Full URL: $uri");
      debugPrint("Error Type: ${e.type}");
      debugPrint("Status Code: ${e.response?.statusCode}");
      debugPrint("Response Data: ${e.response?.data}");
      debugPrint("Message: ${e.message}");
      debugPrint("=================================");

      throw _handleError(e);
    } catch (e, st) {
      debugPrint("========== UNKNOWN ERROR ==========");
      debugPrint("Full URL: $uri");
      debugPrint("Error: $e");
      debugPrint("StackTrace: $st");
      debugPrint("===================================");

      rethrow;
    }
  }

  // ==========================================================
  // 🔄 PAGINATION REQUEST WRAPPER
  // ==========================================================

  Future<dynamic> getPaginated({
    required String endpoint,
    Map<String, dynamic>? query,
    bool withToken = true,
  }) async {
    try {
      final data = await _request(
        endpoint: endpoint,
        method: "GET",
        query: query,
        withToken: withToken,
      );
      debugPrint("Paginated Response: $data"); // log here
      return data;
    } catch (e, st) {
      debugPrint("Error in getPaginated: $e");
      debugPrint("StackTrace: $st");
      rethrow;
    }
  }

  // ==========================================================
  // HTTP METHODS
  // ==========================================================

  Future<dynamic> get({
    required String endpoint,
    Map<String, dynamic>? query,
    bool withToken = true,
  }) {
    return _request(
      endpoint: endpoint,
      method: "GET",
      query: query,
      withToken: withToken,
    );
  }

  Future<dynamic> post({
    required String endpoint,
    dynamic body,
    bool withToken = true,
  }) {
    return _request(
      endpoint: endpoint,
      method: "POST",
      data: body,
      withToken: withToken,
    );
  }

  Future<dynamic> put({
    required String endpoint,
    dynamic body,
    bool withToken = true,
  }) {
    return _request(
      endpoint: endpoint,
      method: "PUT",
      data: body,
      withToken: withToken,
    );
  }

  Future<dynamic> patch({
    required String endpoint,
    dynamic body,
    bool withToken = true,
  }) {
    return _request(
      endpoint: endpoint,
      method: "PATCH",
      data: body,
      withToken: withToken,
    );
  }

  Future<dynamic> delete({
    required String endpoint,
    dynamic body,
    bool withToken = true,
  }) {
    return _request(
      endpoint: endpoint,
      method: "DELETE",
      data: body,
      withToken: withToken,
    );
  }

  // ==========================================================
  // 📤 FILE / IMAGE UPLOAD
  // ==========================================================

  Future<dynamic> uploadFile({
    required String endpoint,
    required String filePath,
    String fileField = "file",
    Map<String, dynamic>? fields,
    bool withToken = true,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint("========== FILE NOT FOUND ==========");
      debugPrint("File Path: $filePath");
      debugPrint("====================================");
      throw Exception("File not found at $filePath");
    }

    debugPrint("========== FILE UPLOAD ==========");
    debugPrint("Full URL: ${dio.options.baseUrl}$endpoint");
    debugPrint("File Path: $filePath");
    debugPrint("Fields: $fields");
    debugPrint("Headers: ${{"Content-Type": "multipart/form-data"}}");
    debugPrint("=================================");

    final formData = FormData.fromMap({
      if (fields != null) ...fields,
      fileField: await MultipartFile.fromFile(filePath),
    });

    // Log FormData properly
    debugPrint("FormData fields:");
    for (var f in formData.fields) {
      debugPrint("${f.key}: ${f.value}");
    }
    for (var f in formData.files) {
      debugPrint("${f.key}: ${f.value.filename}");
    }

    return _request(
      endpoint: endpoint,
      method: "POST",
      data: formData,
      withToken: withToken,
      headers: {"Content-Type": "multipart/form-data"},
    );
  }

  // ==========================================================
  // 🔄 TOKEN REFRESH
  // ==========================================================

  Future<bool> executeRefresh() async {
    final refresh = config.refreshConfig;
    if (refresh == null) return false;

    try {
      debugPrint("========== REFRESH TOKEN ==========");
      final response = await dio.request(
        refresh.path,
        data: refresh.body,
        queryParameters: refresh.query,
        options: refresh.toOptions(),
        cancelToken: _globalCancelToken,
      );

      debugPrint("Refresh Response: ${response.data}");

      final newToken = refresh.tokenParser(response.data);
      if (newToken == null) return false;

      await tokenStorage.saveToken(newToken);

      debugPrint("Token Saved Successfully");
      debugPrint("===================================");
      return true;
    } catch (e) {
      debugPrint("Refresh Failed: $e");
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
  // ERROR HANDLING
  // ==========================================================

  ApiException _handleError(DioException e) {
    if (CancelToken.isCancel(e)) {
      return ApiException(message: "Request Cancelled");
    }

    if (e.response != null) {
      final statusCode = e.response?.statusCode;
      final responseData = e.response?.data;

      String message = "Server Error";
      if (responseData is Map<String, dynamic>) {
        message =
            responseData["message"]?.toString() ??
            responseData["error"]?.toString() ??
            e.response?.statusMessage ??
            "Server Error";
      } else if (responseData is String) {
        message = responseData;
      }

      return ApiException(
        message: message,
        statusCode: statusCode,
        data: responseData,
      );
    }

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return ApiException(message: "Connection Timeout");
      case DioExceptionType.receiveTimeout:
        return ApiException(message: "Receive Timeout");
      case DioExceptionType.connectionError:
        return ApiException(message: "No Internet Connection");
      default:
        return ApiException(message: "Unknown Error");
    }
  }
}
