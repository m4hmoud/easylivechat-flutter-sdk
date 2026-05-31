/// Immutable configuration for the EasyLiveChat client.
class EasyLiveChatConfig {
  /// API base, e.g. `https://api.livechattools.com` (no trailing slash needed).
  final String apiBase;

  /// Tenant/workspace slug. Resolves `:slug` on widget endpoints and the
  /// `tenantSlug` on heartbeat/presence.
  final String tenantSlug;

  /// Overrides the device locale sent to the server (`Contact.locale`) and
  /// used for SDK chrome formatting. Null => device default.
  final String? locale;

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
    this.originHeader,
    this.enablePresenceSocket = true,
    this.enableHeartbeat = true,
    this.heartbeatInterval = const Duration(seconds: 30),
    this.connectTimeout = const Duration(seconds: 20),
    this.tokenRefreshLeeway = const Duration(seconds: 60),
  });

  /// `apiBase` with any trailing slash removed.
  String get normalizedApiBase =>
      apiBase.endsWith('/') ? apiBase.substring(0, apiBase.length - 1) : apiBase;
}
