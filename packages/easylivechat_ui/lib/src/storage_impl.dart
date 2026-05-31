import 'package:easylivechat/easylivechat.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Durable [EasyLiveChatStorage] for production apps.
///
/// Splits persistence by sensitivity:
///  • the widget **JWT** ([StorageKeys.token]) → `flutter_secure_storage`
///    (Keychain / EncryptedSharedPreferences) so the bearer credential is kept
///    out of plain prefs;
///  • the durable **visitorId**, cached **profile**, and **conversationId**
///    ([StorageKeys.visitorId], [StorageKeys.profile],
///    [StorageKeys.conversationId]) → `shared_preferences`.
///
/// The visitorId MUST survive cold starts — `shared_preferences` is durable, so
/// a relaunch reuses the same server-side Contact instead of orphaning prior
/// conversations + CSAT.
class SecurePrefsStorage implements EasyLiveChatStorage {
  /// Secure backend for the JWT. Defaults to a standard [FlutterSecureStorage]
  /// with Android `encryptedSharedPreferences` enabled.
  final FlutterSecureStorage _secure;

  /// Lazily-opened `shared_preferences` instance for the non-secret values.
  SharedPreferences? _prefs;

  SecurePrefsStorage({FlutterSecureStorage? secureStorage})
      : _secure = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  /// True for keys that must live in secure storage (currently just the JWT).
  bool _isSecure(String key) => key == StorageKeys.token;

  Future<SharedPreferences> _ensurePrefs() async =>
      _prefs ??= await SharedPreferences.getInstance();

  @override
  Future<String?> read(String key) async {
    if (_isSecure(key)) return _secure.read(key: key);
    final prefs = await _ensurePrefs();
    return prefs.getString(key);
  }

  @override
  Future<void> write(String key, String value) async {
    if (_isSecure(key)) {
      await _secure.write(key: key, value: value);
      return;
    }
    final prefs = await _ensurePrefs();
    await prefs.setString(key, value);
  }

  @override
  Future<void> delete(String key) async {
    if (_isSecure(key)) {
      await _secure.delete(key: key);
      return;
    }
    final prefs = await _ensurePrefs();
    await prefs.remove(key);
  }
}
