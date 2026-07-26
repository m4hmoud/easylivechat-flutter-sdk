import 'errors.dart';

/// Immutable configuration for the EasyLiveChat client.
class EasyLiveChatConfig {
  /// API base, e.g. `https://api.livechattools.com` (no trailing slash needed).
  final String apiBase;

  /// Tenant/workspace slug. Resolves `:slug` on widget endpoints and the
  /// `tenantSlug` on heartbeat/presence.
  final String tenantSlug;

  /// Overrides the device locale sent to the server (`Contact.locale`) and
  /// used for SDK chrome formatting. Null => device default.
  ///
  /// Free-form: hosts often send a readable language NAME here because it is
  /// what agents see in the dashboard. Use [contentLocale] to pick the language
  /// of the tenant's own copy.
  final String? locale;

  /// Language code (`en`, `ar`, `ku`, `kmr`…) the tenant's customer-facing copy
  /// should come back in — welcome text, offline message, pre-chat labels.
  ///
  /// Separate from [locale] precisely because that one is a display value the
  /// server cannot match against, so without this every mobile visitor got the
  /// workspace's default language however well the tenant had translated it.
  /// Unknown codes fall back to that default server-side.
  final String? contentLocale;

  /// Channel/inbox key (e.g. `'rider'`, `'driver'`). Routes the conversation
  /// to that inbox in the dashboard so agents can be assigned per channel.
  /// Null => the workspace's `default` channel.
  final String? channel;

  /// Arbitrary client-provided custom attributes (e.g. device/app info like
  /// OS, model, network, app version). Sent verbatim on session start; the
  /// server stores them on the contact and shows them in the dashboard. These
  /// are NOT validated/filtered like pre-chat form fields.
  final Map<String, String>? attributes;

  /// Optional `?origin=` value for `GET /:slug/config`. Native clients should
  /// usually OMIT this — the server's `allowedOrigins` gate is skipped entirely
  /// when no origin is supplied. Only set it if the tenant requires a match.
  final String? originHeader;

  /// Open the receive-only `/widget-presence` socket before a chat session
  /// (for proactive outreach). On native this is largely redundant with push;
  /// default true to match web behavior.
  final bool enablePresenceSocket;

  /// Send periodic `POST /visitor/heartbeat` while the app is foregrounded.
  /// NOTE: heartbeat can trigger an agent-side "new visitor" notification on
  /// first arrival / re-arrival after idle — keep the interval modest and only
  /// run it while foregrounded.
  final bool enableHeartbeat;

  /// Heartbeat cadence (default 30s). Only sent while foregrounded.
  final Duration heartbeatInterval;

  /// HTTP/socket connect timeout.
  final Duration connectTimeout;

  /// Re-mint the widget JWT this long before its `exp` (the protocol has no
  /// refresh route, so re-mint = `POST /session resumeOnly:true`).
  final Duration tokenRefreshLeeway;

  const EasyLiveChatConfig({
    required this.apiBase,
    required this.tenantSlug,
    this.locale,
    this.contentLocale,
    this.channel,
    this.attributes,
    this.originHeader,
    this.enablePresenceSocket = true,
    this.enableHeartbeat = true,
    this.heartbeatInterval = const Duration(seconds: 30),
    this.connectTimeout = const Duration(seconds: 20),
    this.tokenRefreshLeeway = const Duration(seconds: 60),
  });

  /// `apiBase` with any trailing slash removed.
  String get normalizedApiBase => apiBase.endsWith('/')
      ? apiBase.substring(0, apiBase.length - 1)
      : apiBase;

  /// Validate the config at boot (runtime — a `const` constructor can't run
  /// method-based asserts). Throws an [EasyLiveChatError] for a misconfiguration
  /// that would otherwise fail opaquely deep in the transport. `http://` is
  /// allowed (local/staging) but disables TLS for the visitor JWT + PII.
  void validate() {
    if (apiBase.trim().isEmpty) {
      throw const EasyLiveChatError(EasyLiveChatErrorCode.unknown,
          message: 'EasyLiveChatConfig.apiBase must not be empty.');
    }
    if (!apiBase.startsWith('https://') && !apiBase.startsWith('http://')) {
      throw EasyLiveChatError(EasyLiveChatErrorCode.unknown,
          message: 'EasyLiveChatConfig.apiBase must include an http(s):// '
              'scheme, e.g. https://api.example.com (got "$apiBase").');
    }
    if (tenantSlug.trim().isEmpty) {
      throw const EasyLiveChatError(EasyLiveChatErrorCode.unknown,
          message: 'EasyLiveChatConfig.tenantSlug must not be empty.');
    }
  }
}
