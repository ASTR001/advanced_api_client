import 'package:flutter/foundation.dart';

class ApiLogger {
  static bool enabled = kDebugMode;

  static void _print(String tag, String message) {
    if (!enabled) return;
    debugPrint("[$tag] $message");
  }

  static void request(String message) => _print("REQUEST", message);
  static void response(String message) => _print("RESPONSE", message);
  static void error(String message) => _print("ERROR", message);
  static void auth(String message) => _print("AUTH", message);
  static void upload(String message) => _print("UPLOAD", message);

  static void divider(String tag) {
    if (!enabled) return;
    debugPrint("[$tag] ----------------------------------------");
  }
}
