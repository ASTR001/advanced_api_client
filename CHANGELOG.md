# Changelog

All notable changes to this package will be documented in this file.

---

## 1.0.0

### 🚀 Production Release

### Added
- Production-ready architecture
- Centralized `AdvancedApiClient`
- Robust `_request()` core handler
- Global error handling via `ApiConfig.onError`
- Automatic token refresh mechanism
- Retry interceptor with timeout & connection retry support
- Session termination with request cancellation
- Single file upload support
- Multiple file upload support (same field)
- Multiple file upload support (dynamic field names)
- Improved error parsing with `ApiException`
- Debug logging (enabled in debug mode only)
- Custom Dio interceptor support
- Safe singleton initialization
- Lazy initialization option

### Improved
- Cleaner internal request handling
- Stronger error mapping for `DioException`
- Better file existence validation
- More stable cancel token management
- Improved production safety & scalability

---

## 0.0.1

### Added
- Initial release
- GET, POST, PUT, PATCH, DELETE requests
- Token-based authentication
- Token refresh support
- File upload support
- Pagination support
- Custom interceptors
- Example Flutter app demonstrating usage