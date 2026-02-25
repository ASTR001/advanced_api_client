import 'package:shared_preferences/shared_preferences.dart';
import '../core/token_storage.dart';

class SharedPrefsTokenStorage implements TokenStorage {
  final SharedPreferences prefs;

  static const _key = "auth_token";

  SharedPrefsTokenStorage(this.prefs);

  @override
  Future<String?> getToken() async {
    return prefs.getString(_key);
  }

  @override
  Future<void> saveToken(String token) async {
    await prefs.setString(_key, token);
  }

  @override
  Future<void> clear() async {
    await prefs.remove(_key);
  }
}
