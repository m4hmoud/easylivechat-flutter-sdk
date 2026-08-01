import 'package:easylivechat/easylivechat.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Durable [EasyLiveChatStorage] for production apps.
///
/// Splits persistence by sensitivity:
///  • the widget **JWT** ([StorageKeys.token]) and the cached **profile**
///    ([StorageKeys.profile], which holds the visitor's name / email / pre-chat
///    answers — PII) → `flutter_secure_storage` (Keychain /
///    EncryptedSharedPreferences), kept out of plain prefs;
///  • the durable **visitorId** and **conversationId**
///    ([StorageKeys.visitorId], [StorageKeys.conversationId] — opaque,
///    non-sensitive) → `shared_preferences`.
///
/// The visitorId MUST survive cold starts — `shared_preferences` is durable, so
/// a relaunch reuses the same server-side Contact instead of orphaning prior
/// conversations + CSAT.
class SecurePrefsStorage implements EasyLiveChatStorage {
  /// Secure backend for the JWT. Defaults to a standard [FlutterSecureStorage]
  /// with Android `encryptedSharedPreferences` enabled.
  final FlutterSecureStorage _secure;

  /// Lazily-opened `shared_preferences` for the non-secret values. Cache the
  /// FUTURE (not the resolved value) so concurrent first reads/writes share a
  /// single `getInstance()` rather than racing two.
  Future<SharedPreferences>? _prefsFuture;

  SecurePrefsStorage({FlutterSecureStorage? secureStorage})
      : _secure = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  /// True for keys that must live in secure storage: the bearer JWT and the
  /// PII-bearing profile blob.
  bool _isSecure(String key) =>
      key == StorageKeys.token || key == StorageKeys.profile;

  Future<SharedPreferences> _ensurePrefs() =>
      _prefsFuture ??= SharedPreferences.getInstance();

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
