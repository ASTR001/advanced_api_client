import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../advanced_api_client.dart';

class AdvancedApiClient {
  static AdvancedApiClient? _instance;
  static ApiConfig? _defaultConfig;
  static TokenStorage? _defaultStorage;

  final Dio dio;
  final TokenStorage tokenStorage;
  final ApiConfig config;

  final Map<String, CancelToken> _uploadTokens = {};

  /// Prevent duplicate API calls
  final Map<String, Future<dynamic>> _runningRequests = {};

  /// Rate limiting tracker
  final Map<String, DateTime> _rateLimitTracker = {};

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
            connectTimeout: const Duration(seconds: 60),
            receiveTimeout: const Duration(seconds: 60),
            sendTimeout: const Duration(seconds: 60),
          ),
        ) {
    // SSL CERTIFICATE HANDLING
    if (config.allowBadCertificates) {
      final adapter = dio.httpClientAdapter as IOHttpClientAdapter;

      adapter.createHttpClient = () {
        final client = HttpClient();

        client.badCertificateCallback =
            (X509Certificate cert, String host, int port) {
          ApiLogger.auth("Bad SSL certificate detected for host: $host:$port");

          /// Allow connection (DEV ONLY)
          return true;
        };

        return client;
      };
    }

    // RETRY INTERCEPTOR
    dio.interceptors.add(RetryInterceptor(dio));

    // CUSTOM INTERCEPTORS
    if (config.interceptors != null) {
      dio.interceptors.addAll(config.interceptors!);
    }

    // AUTH INTERCEPTOR (LAST)
    dio.interceptors.add(AuthInterceptor(this));

    ApiLogger.request("AdvancedApiClient initialized");
  }

  // ==========================================================
  // 🚀 INITIALIZATION
  // ==========================================================

  static Future<void> initialize({
    required ApiConfig config,
  }) async {
    ApiLogger.enabled = config.enableLogs;

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
  // 🌐 REQUEST FINGERPRINT
  // ==========================================================
  String _requestFingerprint(
    String method,
    String endpoint,
    Map<String, dynamic>? query,
    dynamic body,
  ) {
    return "$method|$endpoint|${query.toString()}|${body.toString()}";
  }

  // ==========================================================
  // 🌐 RATE LIMIT CHECK
  // ==========================================================
  bool _isRateLimited(String key, Duration limit) {
    final last = _rateLimitTracker[key];

    if (last == null) {
      _rateLimitTracker[key] = DateTime.now();
      return false;
    }

    final diff = DateTime.now().difference(last);

    if (diff < limit) {
      return true;
    }

    _rateLimitTracker[key] = DateTime.now();
    return false;
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
    void Function(int sent, int total)? onSendProgress,
    dynamic Function()? dataBuilder,
    Duration? rateLimit,
  }) async {
    final effectiveRateLimit = rateLimit ?? const Duration(seconds: 2);

    final fingerprint = _requestFingerprint(
      method,
      endpoint,
      query,
      data,
    );

    /// 🚀 REQUEST DEDUPLICATION
    if (_runningRequests.containsKey(fingerprint)) {
      ApiLogger.request(
          "Duplicate request detected → returning existing future");
      return _runningRequests[fingerprint];
    }

    /// 🚀 RATE LIMIT
    if (_isRateLimited(fingerprint, effectiveRateLimit)) {
      ApiLogger.request("Rate limit triggered ($effectiveRateLimit)");
      throw ApiException(
        message: "Too many requests. Please wait.",
      );
    }

    final safeQuery = query?.map(
      (k, v) => MapEntry(k, v?.toString()),
    );

    final mergedHeaders = {
      if (config.headers != null) ...config.headers!,
      if (!withToken) "Skip-Auth": true,
      if (headers != null) ...headers,
    };

    final options = Options(
      method: method,
      headers: mergedHeaders,
    );

    final uri = Uri.parse("${dio.options.baseUrl}$endpoint")
        .replace(queryParameters: safeQuery);

    _logRequest(uri, method, data, options.headers);

    final safeOptions = options.copyWith(
      extra: {
        if (dataBuilder != null) "_dataBuilder": dataBuilder,
        if (options.extra != null) ...options.extra!,
      },
    );

    final startTime = DateTime.now();

    final future = () async {
      try {
        final response = await dio.request(
          endpoint,
          data: data,
          queryParameters: safeQuery,
          options: safeOptions,
          cancelToken: cancelToken ?? _globalCancelToken,
          onSendProgress: onSendProgress,
        );

        final duration = DateTime.now().difference(startTime);

        _logResponse(uri, response, duration);

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
        final errorBody = e.response?.data;

        ApiLogger.error(
          "$method $uri → ${e.response?.statusCode} ${errorBody ?? e.error ?? 'Unknown error'}",
        );

        throw _handleError(e);
      } finally {
        /// remove running request
        _runningRequests.remove(fingerprint);
      }
    }();

    _runningRequests[fingerprint] = future;

    return future;
  }

  // ==========================================================
  // 📦 HTTP METHODS
  // ==========================================================

  Future<dynamic> get({
    required String endpoint,
    Map<String, dynamic>? query,
    bool withToken = true,
    Map<String, dynamic>? headers,
    Duration? rateLimit,
  }) =>
      _request(
        endpoint: endpoint,
        method: "GET",
        query: query,
        withToken: withToken,
        headers: headers,
        rateLimit: rateLimit,
      );

  Future<dynamic> post({
    required String endpoint,
    dynamic body,
    bool withToken = true,
    Map<String, dynamic>? headers,
    Duration? rateLimit,
  }) =>
      _request(
        endpoint: endpoint,
        method: "POST",
        data: body,
        withToken: withToken,
        headers: headers,
        rateLimit: rateLimit,
      );

  Future<dynamic> put({
    required String endpoint,
    dynamic body,
    bool withToken = true,
    Map<String, dynamic>? headers,
    Duration? rateLimit,
  }) =>
      _request(
        endpoint: endpoint,
        method: "PUT",
        data: body,
        withToken: withToken,
        headers: headers,
        rateLimit: rateLimit,
      );

  Future<dynamic> patch({
    required String endpoint,
    dynamic body,
    bool withToken = true,
    Map<String, dynamic>? headers,
    Duration? rateLimit,
  }) =>
      _request(
        endpoint: endpoint,
        method: "PATCH",
        data: body,
        withToken: withToken,
        headers: headers,
        rateLimit: rateLimit,
      );

  Future<dynamic> delete({
    required String endpoint,
    dynamic body,
    bool withToken = true,
    Map<String, dynamic>? headers,
    Duration? rateLimit,
  }) =>
      _request(
        endpoint: endpoint,
        method: "DELETE",
        data: body,
        withToken: withToken,
        headers: headers,
        rateLimit: rateLimit,
      );

  // ==========================================================
  // 📤 FILE UPLOAD (With Progress + Cancel Support)
  // ==========================================================

  Future<dynamic> uploadFile({
    required String endpoint,
    required Map<String, List<String>> files,
    Map<String, dynamic>? fields,
    bool withToken = true,
    void Function(int sent, int total)? onProgress,
    String? uploadId,
    Map<String, dynamic>? headers,
    Duration? rateLimit,
  }) async {
    if (files.isEmpty) throw Exception("No files provided");

    FormData buildFormData() => FormData()
      ..fields.addAll(
        fields?.entries.map((e) => MapEntry(e.key, e.value.toString())) ?? [],
      )
      ..files.addAll(
        files.entries.expand(
          (entry) => entry.value.map(
            (path) => MapEntry(
              entry.key,
              MultipartFile.fromFileSync(path),
            ),
          ),
        ),
      );

    CancelToken? token;

    if (uploadId != null) {
      token = _uploadTokens.putIfAbsent(uploadId, () => CancelToken());
    }

    ApiLogger.upload("Uploading to $endpoint (task: $uploadId)");

    try {
      return await _request(
        endpoint: endpoint,
        method: "POST",
        data: buildFormData(), // initial upload
        dataBuilder: buildFormData, // builder for retries
        withToken: withToken,
        cancelToken: token,
        headers: {
          "Content-Type": "multipart/form-data",
          if (headers != null) ...headers, // request headers
        },
        onSendProgress: onProgress,
        rateLimit: rateLimit,
      );
    } finally {
      if (uploadId != null) _uploadTokens.remove(uploadId);
      ApiLogger.upload("Upload finished (task: $uploadId)");
    }
  }

  // ==========================================================
  // 🔄 CREATE UPLOAD TASK
  // ==========================================================

  String createUploadTask() {
    final id =
        "${DateTime.now().microsecondsSinceEpoch}_${_uploadTokens.length}";
    _uploadTokens[id] = CancelToken();
    return id;
  }

  // ==========================================================
  // 🔄 CANCEL UPLOAD
  // ==========================================================

  void cancelUpload(String uploadId) {
    final token = _uploadTokens.remove(uploadId);

    if (token != null && !token.isCancelled) {
      token.cancel("Upload cancelled by user");
    }
  }

  // ==========================================================
  // 🚪 TERMINATE SESSION
  // ==========================================================

  Future<void> terminateSession() async {
    if (!_globalCancelToken.isCancelled) {
      _globalCancelToken.cancel("Session terminated");
    }

    // cancel all uploads
    for (final token in _uploadTokens.values) {
      if (!token.isCancelled) {
        token.cancel("Session terminated");
      }
    }
    _uploadTokens.clear();

    await tokenStorage.clear();
    _globalCancelToken = CancelToken();

    ApiLogger.auth("Session terminated");
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
    if (!ApiLogger.enabled) return;

    ApiLogger.divider("REQUEST");
    ApiLogger.request("$method $uri");

    if (headers != null && headers.isNotEmpty) {
      ApiLogger.request("Headers:");
      headers.forEach((key, value) {
        ApiLogger.request("  $key: $value");
      });
    }

    if (data != null) {
      if (data is FormData) {
        if (data.fields.isNotEmpty) {
          ApiLogger.request("Form Fields:");
          for (var field in data.fields) {
            ApiLogger.request("  ${field.key}: ${field.value}");
          }
        }

        if (data.files.isNotEmpty) {
          ApiLogger.request("Form Files:");
          for (var file in data.files) {
            ApiLogger.request("  ${file.key}: ${file.value.filename}");
          }
        }
      } else {
        ApiLogger.request("Body: $data");
      }
    }

    ApiLogger.divider("REQUEST");
  }

  void _logResponse(Uri uri, Response response, Duration duration) {
    if (!ApiLogger.enabled) return;

    ApiLogger.divider("RESPONSE");

    ApiLogger.response("URL: $uri");
    ApiLogger.response("Status: ${response.statusCode}");
    ApiLogger.response("Time: ${duration.inMilliseconds} ms");

    if (response.data != null) {
      ApiLogger.response("Data:");
      ApiLogger.response(response.data.toString());
    }

    ApiLogger.divider("RESPONSE");
  }
}
