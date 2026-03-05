# Advanced API Client

A powerful, production-ready Flutter/Dart HTTP client built on top of `dio`.

`advanced_api_client` simplifies REST API integration with built-in:

- Authentication handling
- Automatic token refresh
- Retry mechanism
- File uploads
- Pagination support
- Global error handling
- Custom interceptors
- Session termination
- Clean architecture

Designed for scalability and real-world production apps.

---

## ✨ Features

- ✅ GET, POST, PUT, PATCH, DELETE
- 🔐 Token-based authentication
- 🔄 Automatic token refresh (401 handling)
- ♻️ Retry interceptor (connection errors + timeout support)
- 📤 Single & multiple file uploads
- 📦 Pagination-ready
- 🧩 Custom interceptor support
- 🛑 Global error callback
- 🚪 Session termination support
- 🧪 Works with Flutter & pure Dart
- 🆕 Dynamic refresh token bodyBuilder support for passing runtime data (e.g., user_id from SharedPreferences)
- 🛡 Safe retry after token refresh for file uploads

---

## 📦 Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  advanced_api_client: ^1.0.1
```

Then run:

```
flutter pub get
```

---

# 🚀 Getting Started

## 1️⃣ Initialize (Recommended – Pre-init in `main()`)

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AdvancedApiClient.initialize(
    config: ApiConfig(
      baseUrl: "https://api.example.com",
      refreshConfig: RefreshConfig(
        path: "/auth/refresh",
        method: "POST",
        // Use bodyBuilder for dynamic runtime body
        bodyBuilder: () async {
          final prefs = await SharedPreferences.getInstance();
          final userId = prefs.getString("user_id") ?? "";
          return {"user_id": userId, "from_source": 1};
        },
        // or use body for static data
        body: {
          "from_source": 1
        },
        tokenParser: (data) => data["access_token"],
        headers: {
          "App-Version": "1.0.0",
          "Platform": "Flutter",
        },
      ),
    ),
  );

  runApp(MyApp());
}
```

Access anywhere:

```dart
final client = AdvancedApiClient.instance;
```

---

## 2️⃣ Lazy Initialization (Optional)

```dart
final client = await AdvancedApiClient.getInstance();
```

---

# ⚙️ ApiConfig

The `ApiConfig` class allows you to configure the API client behavior.

```dart
class ApiConfig {
  final String baseUrl;
  final RefreshConfig? refreshConfig;
  final List<Interceptor>? interceptors;
  final void Function(DioException e, RequestOptions request)? onError;
  final bool enableLogs;

  const ApiConfig({
    required this.baseUrl,
    this.refreshConfig,
    this.interceptors,
    this.onError,
    this.enableLogs = true,
  });
}
```

---

## 🔹 baseUrl (Required)

Base URL of your API.

```dart
ApiConfig(
  baseUrl: "https://api.example.com",
);
```

---

## 🔹 refreshConfig (Optional)

Used to automatically refresh access tokens when a `401` response is received.

Example:

```dart
ApiConfig(
  baseUrl: "https://api.example.com",
  refreshConfig: RefreshConfig(
    path: "/auth/refresh",
    method: "POST",
    // Dynamic runtime body
    bodyBuilder: () async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString("user_id") ?? "";
    return {"user_id": userId, "from_source": 1};
    },
    // Static body
    body: {"from_source": 1}
    tokenParser: (data) => data["access_token"],
  ),
);
```

---

## 🔹 interceptors (Optional)

Add custom `dio` interceptors.

```dart
ApiConfig(
  baseUrl: "https://api.example.com",
  interceptors: [
    LogInterceptor(responseBody: true),
  ],
);
```

---

## 🔹 onError (Optional)

Global error callback triggered for all request errors.

```dart
ApiConfig(
  baseUrl: "https://api.example.com",
  onError: (DioException e, RequestOptions request) async {
    final statusCode = e.response?.statusCode;

    if (statusCode == 401) {
      await AdvancedApiClient.instance.terminateSession();
    }

    if (statusCode == 500) {
      debugPrint("Server error occurred");
    }

    if (e.type == DioExceptionType.connectionError) {
      debugPrint("No internet connection");
    }
  },
);
```

---

# 🌐 Basic Requests

### GET

```dart
await client.get(
  endpoint: "/users",
  headers: {"X-Custom-Header": "12345"},
);
```

### POST

```dart
await client.post(
  endpoint: "/users",
  body: {"name": "John"},
  headers: {"X-Custom-Header": "12345"},
);
```

### PUT

```dart
await client.put(
  endpoint: "/users/1",
  body: {"name": "Updated"},
  headers: {"X-Custom-Header": "12345"},
);
```

### PATCH

```dart
await client.patch(
  endpoint: "/users/1",
  body: {"status": "active"},
  headers: {"X-Custom-Header": "12345"},
);
```

### DELETE

```dart
await client.delete(endpoint: "/users/1");
```

---

# 📤 File Upload Examples

```dart
final client = AdvancedApiClient.instance;
```

### Upload Single File

```dart
await client.upload(
  endpoint: "/common/file-upload/image",
  files: {
    "image": [pickedFile.path],
  },
  headers: {"X-Custom-Header": "12345"},
);
```

---

### Upload Multiple Files (Same Field)

```dart
await client.upload(
  endpoint: "/common/file-upload/image",
  files: {
    "image": filePaths, // List<String>
  },
  headers: {"X-Custom-Header": "12345"},
);
```

---

### Upload Multiple Files (Different Fields)

```dart
await client.upload(
  endpoint: "/upload",
  files: {
    "profile_image": [profilePath],
    "documents": documentPaths,
  },
  fields: {
    "user_id": 1,
    "type": "verification",
  },
  headers: {"X-Custom-Header": "12345"},
);
```

---

# 🚪 Terminate Session

Clears tokens and cancels all pending requests:

```dart
await AdvancedApiClient.instance.terminateSession();
```

---

# 🔄 Retry Mechanism

Built-in retry interceptor supports:

- Connection errors
- Receive timeout
- Configurable retry attempts
- Optional exponential backoff

Helps reduce random network failures in production.

---

# 🏗 Architecture

```
AdvancedApiClient
 ├── AuthInterceptor
 ├── RetryInterceptor
 ├── TokenStorage
 ├── ApiConfig
 ├── RefreshConfig (supports bodyBuilder)
 └── ApiException
```

Clean separation of concerns and extensibility.

---

# 🧪 Works With

- Flutter Mobile
- Flutter Web
- Flutter Desktop
- Pure Dart projects

---

# 📝 License

MIT License © 2026

---

# ❤️ Why Advanced API Client?

Because production apps need more than just `dio`.

You get:

- Cleaner codebase
- Centralized API management
- Safer authentication flow
- Easier scaling
- Better maintainability