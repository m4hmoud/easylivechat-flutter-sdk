import '../errors.dart';
import 'enums.dart';
import 'post_chat_form.dart';
import 'pre_chat_form.dart';

/// The full `WidgetConfig` row returned by `GET /:slug/config`, plus the
/// resolved [preChatForm]. Drives all theming/locale/RTL and feature toggles.
///
/// Unknown/extra server fields are ignored; everything is null-tolerant.
class WidgetConfigModel {
  final String id;
  final String tenantId;

  // Theme
  final String primaryColor;
  final String backgroundColor;
  final String textColor;
  final String? bubbleIconUrl;
  final String? logoUrl;
  final String? soundUrl;

  /// Raw CSS — parsed off the wire but IGNORED by native (cannot map to
  /// Flutter). Hosts override via the UI theme instead.
  final String? customCss;

  // Copy
  final String welcomeTitle;
  final String welcomeSubtitle;
  final String offlineMessage;

  // Layout / behavior
  final String position; // e.g. bottom-right | bottom-left
  final String locale;
  final LocaleDirection direction;
  final bool soundEnabled;
  final bool showAgentAvatars;
  final bool showAgentNames;
  final bool collectEmailPreChat; // legacy fallback flag

  final PreChatForm preChatForm;

  /// The survey shown once the conversation is closed. Built by the tenant in
  /// the dashboard; empty/disabled means fall back to the built-in CSAT.
  final PostChatForm postChatForm;
  final List<String> allowedOrigins;

  const WidgetConfigModel({
    required this.id,
    required this.tenantId,
    required this.primaryColor,
    required this.backgroundColor,
    required this.textColor,
    this.bubbleIconUrl,
    this.logoUrl,
    this.soundUrl,
    this.customCss,
    required this.welcomeTitle,
    required this.welcomeSubtitle,
    required this.offlineMessage,
    required this.position,
    required this.locale,
    required this.direction,
    required this.soundEnabled,
    required this.showAgentAvatars,
    required this.showAgentNames,
    required this.collectEmailPreChat,
    required this.preChatForm,
    this.postChatForm = PostChatForm.disabled,
    this.allowedOrigins = const [],
  });

  factory WidgetConfigModel.fromJson(Map<String, dynamic> j) {
    String s(String k, String d) =>
        (j[k] as String?)?.trim().isNotEmpty == true ? j[k] as String : d;
    return WidgetConfigModel(
      id: (j['id'] ?? '').toString(),
      tenantId: (j['tenantId'] ?? '').toString(),
      primaryColor: s('primaryColor', '#2563EB'),
      backgroundColor: s('backgroundColor', '#FFFFFF'),
      textColor: s('textColor', '#0F172A'),
      bubbleIconUrl: j['bubbleIconUrl'] as String?,
      logoUrl: j['logoUrl'] as String?,
      soundUrl: j['soundUrl'] as String?,
      customCss: j['customCss'] as String?,
      welcomeTitle: s('welcomeTitle', 'Chat with us'),
      welcomeSubtitle: s('welcomeSubtitle', "We're here to help"),
      offlineMessage: s('offlineMessage', "We're offline — leave a message"),
      position: s('position', 'bottom-right'),
      locale: s('locale', 'en'),
      direction: LocaleDirection.fromWire(j['direction']),
      soundEnabled: j['soundEnabled'] != false,
      showAgentAvatars: j['showAgentAvatars'] != false,
      showAgentNames: j['showAgentNames'] != false,
      collectEmailPreChat: j['collectEmailPreChat'] == true,
      postChatForm: j['postChatForm'] is Map
          ? PostChatForm.fromJson(
              (j['postChatForm'] as Map).cast<String, dynamic>())
          : PostChatForm.disabled,
      preChatForm: j['preChatForm'] is Map
          ? PreChatForm.fromJson(
              (j['preChatForm'] as Map).cast<String, dynamic>())
          : PreChatForm.disabled,
      allowedOrigins: (j['allowedOrigins'] is List)
          ? (j['allowedOrigins'] as List).map((e) => e.toString()).toList()
          : const [],
    );
  }
}

/// The server's availability verdict for a workspace.
///
/// Arrives two ways — in `GET /:slug/config` at open time, and on the
/// `workspace:availability` socket event when it changes — so it lives in one
/// place rather than being re-parsed (or, as it was, quietly dropped) in each.
class WorkspaceAvailability {
  /// Inside working hours.
  final bool isOpen;

  /// Any agent currently accepting chats.
  final bool agentsAccepting;

  /// What the visitor may do: `CHAT`, `LEAVE_MESSAGE` or `NOTICE_ONLY`.
  final String visitorMode;

  /// Why: `OPEN`, `AFTER_HOURS`, `NO_AGENTS` or `HOLIDAY`.
  final String reason;

  /// When we next open, so the UI can say "back at 09:00". Null when open.
  final DateTime? nextOpenAt;

  /// The closure's name when [reason] is `HOLIDAY`, e.g. "Eid al-Adha".
  final String? closureLabel;

  /// [nextOpenAt] as `HH:mm` on the BUSINESS's clock, formatted by the server.
  ///
  /// Dart carries no IANA timezone database, so an app cannot render "09:00 in
  /// Baghdad" from an instant on its own — it can only show the device's own
  /// zone, which is a different time for a visitor who is travelling or abroad.
  /// The server knows the tenant's timezone and sends the answer.
  final String? nextOpenLocal;

  /// The tenant's configured IANA timezone, e.g. `Asia/Baghdad`.
  final String? timezone;

  const WorkspaceAvailability({
    required this.isOpen,
    this.agentsAccepting = true,
    this.visitorMode = 'CHAT',
    this.reason = 'OPEN',
    this.nextOpenAt,
    this.closureLabel,
    this.nextOpenLocal,
    this.timezone,
  });

  /// Every field is optional: a server that predates them must not be read as
  /// closing the widget, so each absent value falls back to the permissive one.
  factory WorkspaceAvailability.fromJson(Map<String, dynamic> j) {
    final label = j['closureLabel'];
    return WorkspaceAvailability(
      isOpen: j['isOpen'] == true,
      agentsAccepting: j['agentsAccepting'] != false,
      visitorMode: (j['visitorMode'] ?? 'CHAT').toString(),
      reason: (j['reason'] ?? 'OPEN').toString(),
      nextOpenAt: _parseIsoDate(j['nextOpenAt']),
      closureLabel:
          (label is String && label.trim().isNotEmpty) ? label.trim() : null,
      nextOpenLocal: _trimmedOrNull(j['nextOpenLocal']),
      timezone: _trimmedOrNull(j['timezone']),
    );
  }
}

String? _trimmedOrNull(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

DateTime? _parseIsoDate(Object? v) {
  if (v is! String || v.trim().isEmpty) return null;
  return DateTime.tryParse(v)?.toLocal();
}

/// Envelope of `GET /:slug/config`.
class ConfigResponse {
  final String tenantId;
  final WidgetConfigModel config;

  /// Working-hours availability at fetch time (`isWithinWorkingHours`).
  final bool isOpen;

  /// Whether any agent is currently accepting chats. Only gates the widget for
  /// tenants running `chatAvailabilityMode = WHEN_ACCEPTING`.
  final bool agentsAccepting;

  /// `ALWAYS` (default) or `WHEN_ACCEPTING` — whether [agentsAccepting] is
  /// allowed to close the widget at all.
  final String chatAvailabilityMode;

  /// Whether the offline/async form is offered when closed.
  final bool asyncEnabled;

  /// What the visitor may do, decided server-side: `CHAT`, `LEAVE_MESSAGE` or
  /// `NOTICE_ONLY`. Clients render this rather than re-deriving the policy —
  /// three copies of that logic is how the widget, this SDK and the server's
  /// own session gate came to disagree.
  final String visitorMode;

  /// Why: `OPEN`, `AFTER_HOURS` or `NO_AGENTS`. Picks which notice to show.
  final String reason;

  /// When we next open, so the UI can say "back at 09:00". Null when open.
  final DateTime? nextOpenAt;

  /// The holiday/closure name when [reason] is `HOLIDAY`, e.g. "Eid al-Adha".
  /// Naming it reads far better than a bare "we're closed".
  final String? closureLabel;

  /// [nextOpenAt] as `HH:mm` on the business's clock. See
  /// [WorkspaceAvailability.nextOpenLocal] for why the server formats it.
  final String? nextOpenLocal;

  /// The tenant's configured IANA timezone, e.g. `Asia/Baghdad`.
  final String? timezone;

  const ConfigResponse({
    required this.tenantId,
    required this.config,
    required this.isOpen,
    this.agentsAccepting = true,
    this.chatAvailabilityMode = 'ALWAYS',
    this.asyncEnabled = false,
    this.visitorMode = 'CHAT',
    this.reason = 'OPEN',
    this.nextOpenAt,
    this.closureLabel,
    this.nextOpenLocal,
    this.timezone,
  });

  /// True when the tenant chose to show a notice and take nothing.
  bool get noticeOnly => visitorMode == 'NOTICE_ONLY';

  /// True when either availability gate says the workspace is unavailable.
  /// Mirrors the web widget's rule so both clients agree.
  bool get isClosed {
    if (!isOpen) return true;
    return chatAvailabilityMode == 'WHEN_ACCEPTING' &&
        !agentsAccepting &&
        asyncEnabled;
  }

  factory ConfigResponse.fromJson(Map<String, dynamic> j) {
    final rawConfig = j['config'];
    // The one non-optional field in the protocol. Everywhere else is
    // null-tolerant; here a missing/typed `config` is a protocol violation —
    // surface a typed error instead of a raw TypeError from the cast.
    if (rawConfig is! Map) {
      throw const EasyLiveChatError(
        EasyLiveChatErrorCode.unknown,
        message: 'GET /config response missing a `config` object.',
      );
    }
    return ConfigResponse(
      tenantId: (j['tenantId'] ?? '').toString(),
      config: WidgetConfigModel.fromJson(rawConfig.cast<String, dynamic>()),
      isOpen: j['isOpen'] == true,
      // Absent on older servers — default to the permissive value so a missing
      // field can never close the widget.
      agentsAccepting: j['agentsAccepting'] != false,
      chatAvailabilityMode: (j['chatAvailabilityMode'] ?? 'ALWAYS').toString(),
      asyncEnabled: j['asyncEnabled'] == true,
      // The server's verdict. Defaulting these to the permissive values on an
      // older server is deliberate; silently defaulting them while a CURRENT
      // server was sending NOTICE_ONLY is what left the widget offering a
      // pre-chat form to visitors it had already been told to turn away.
      visitorMode: (j['visitorMode'] ?? 'CHAT').toString(),
      reason: (j['reason'] ?? 'OPEN').toString(),
      nextOpenAt: _parseIsoDate(j['nextOpenAt']),
      closureLabel: (j['closureLabel'] as String?)?.trim().isEmpty ?? true
          ? null
          : (j['closureLabel'] as String).trim(),
      nextOpenLocal: _trimmedOrNull(j['nextOpenLocal']),
      timezone: _trimmedOrNull(j['timezone']),
    );
  }
}
