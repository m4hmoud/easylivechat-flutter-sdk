/// Pluggable key/value persistence for the durable `visitorId`, cached
/// profile, and the widget JWT. The core ships [InMemoryStorage] (NON-durable,
/// for tests); apps should inject a real implementation — `easylivechat_ui`
/// provides a `flutter_secure_storage` + `shared_preferences` adapter.
///
/// IMPORTANT: the visitorId MUST persist across cold starts. If it regenerates,
/// every relaunch creates a NEW server-side Contact and orphans prior
/// conversations + CSAT.
abstract class EasyLiveChatStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Canonical storage keys. The visitorId/profile keys reuse the legacy web
/// names so a user is consistent across web + native within one tenant.
abstract final class StorageKeys {
  static const visitorId = 'livechattools:visitorId';
  static const profile = 'livechattools:visitorProfile';
  static const token = 'easylivechat:widgetToken';
  static const conversationId = 'easylivechat:conversationId';
}

/// Ephemeral, process-lifetime storage. Do NOT use in production — the
/// visitorId will not survive an app restart.
class InMemoryStorage implements EasyLiveChatStorage {
  final Map<String, String> _m = {};

  @override
  Future<String?> read(String key) async => _m[key];

  @override
  Future<void> write(String key, String value) async => _m[key] = value;

  @override
  Future<void> delete(String key) async => _m.remove(key);
}
