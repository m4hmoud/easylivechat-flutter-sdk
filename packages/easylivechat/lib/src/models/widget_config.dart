import '../errors.dart';
import 'enums.dart';
import 'js_text.dart';
import 'post_chat_form.dart';
import 'pre_chat_form.dart';

/// The look a workspace chose for its chat: light, dark, or following the
/// visitor's device (`auto`).
///
/// Dark is never designed twice. A workspace sets one look — its primary,
/// background and text colours — and almost always for a light page; the dark
/// one is derived from it (the brand fills kept, the light surfaces swapped
/// for a dark ground and card). See `EasyLiveChatTheme.fromConfig` in
/// `easylivechat_ui`, which does that the way the web widget does.
enum WidgetColorScheme {
  light,
  dark,

  /// Follow the device's appearance — the setting a new workspace starts on.
  auto;

  /// The scheme a config asks for. A server older than the setting sends
  /// nothing, which reads as [light] — what every chat was before it — so a
  /// missing field never changes anyone's look. Workspaces that existed when
  /// it arrived were kept on light too; new ones start on [auto].
  static WidgetColorScheme fromWire(Object? w) => switch (w) {
        'dark' => dark,
        'auto' => auto,
        _ => light,
      };

  /// Light or dark, given the device's own setting. Only [auto] asks it.
  bool resolveDark({required bool deviceDark}) => switch (this) {
        light => false,
        dark => true,
        auto => deviceDark,
      };
}

/// The launcher's size — the web loader's `LAUNCHER_PX`. [medium] is the 56
/// it always was.
enum LauncherSize {
  small(48),
  medium(56),
  large(64);

  /// The launcher's diameter (and the pill's height) in logical pixels.
  final double diameter;
  const LauncherSize(this.diameter);

  /// [medium] for anything else, so an older server draws what it always did.
  static LauncherSize fromWire(Object? w) => switch (w) {
        'small' => small,
        'large' => large,
        _ => medium,
      };
}

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

  /// Light, dark, or following the device — see [WidgetColorScheme];
  /// [WidgetColorScheme.light] when an older server leaves it out.
  final WidgetColorScheme colorScheme;

  /// A few words beside the launcher's icon ("Chat with us"), in the
  /// visitor's language — the server resolves the translation — or null for
  /// the plain round launcher. One line, at most 40 characters.
  final String? launcherLabel;

  /// How big the launcher is; [LauncherSize.medium] when an older server
  /// leaves it out.
  final LauncherSize launcherSize;

  /// Whether a link in a message shows its preview card
  /// (`ChatMessage.linkPreview`). The workspace's switch; true when an older
  /// server leaves it out, as on the web — a preview it never made is simply
  /// absent.
  final bool linkPreviews;

  // Copy
  final String welcomeTitle;
  final String welcomeSubtitle;

  /// The leave-a-message prompt from the widget copy settings. NOT the closed
  /// notice — that is [offlineInfoText]. This column carries a schema default
  /// nobody typed ("We're offline — leave us a message."), so showing it as
  /// the notice put English in front of every visitor and invited a message
  /// from workspaces that take none.
  final String offlineMessage;

  /// The business's own closed notice (Settings → Availability), in the
  /// visitor's language, or null when nobody wrote one. When set it ALWAYS
  /// wins — on the banner above the thread and on the closed screen alike,
  /// whatever the mode and whether or not the assistant covers. Without one,
  /// the client words the notice itself: closed or busy, the assistant's
  /// version while it answers, the reopening time.
  final String? offlineInfoText;

  /// Stands in for `%name%` when the visitor hasn't identified. Set by the
  /// tenant as "Default customer name".
  final String? defaultCustomerName;

  // Layout / behavior
  final String position; // e.g. bottom-right | bottom-left
  final String locale;
  final LocaleDirection direction;
  final bool soundEnabled;

  /// Whether visitors may record and send voice messages.
  ///
  /// Off unless the workspace turned it on: a microphone prompt is a large
  /// thing to spring on someone who only opened a chat, and plenty of hosts
  /// should never ask. Defaults to false when the server omits it, so an older
  /// server keeps the SDK quiet rather than guessing.
  final bool voiceNotesEnabled;

  /// Whether the workspace shows its help articles to visitors (the
  /// dashboard's "Show help articles" switch). Gate any help UI on it — with
  /// the switch off the help endpoints answer an empty list / 404. False when
  /// an older server omits it.
  final bool helpArticlesEnabled;
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
    this.colorScheme = WidgetColorScheme.light,
    this.launcherLabel,
    this.launcherSize = LauncherSize.medium,
    this.linkPreviews = true,
    required this.welcomeTitle,
    required this.welcomeSubtitle,
    required this.offlineMessage,
    this.offlineInfoText,
    this.defaultCustomerName,
    required this.position,
    required this.locale,
    required this.direction,
    required this.soundEnabled,
    this.voiceNotesEnabled = false,
    this.helpArticlesEnabled = false,
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
      colorScheme: WidgetColorScheme.fromWire(j['colorScheme']),
      launcherLabel: _launcherWords(j['launcherLabel']),
      launcherSize: LauncherSize.fromWire(j['launcherSize']),
      linkPreviews: j['linkPreviews'] != false,
      welcomeTitle: s('welcomeTitle', 'Chat with us'),
      welcomeSubtitle: s('welcomeSubtitle', "We're here to help"),
      offlineMessage: s('offlineMessage', "We're offline — leave a message"),
      offlineInfoText: _trimmedOrNull(j['offlineInfoText']),
      defaultCustomerName: (j['defaultCustomerName'] as String?)?.trim(),
      position: s('position', 'bottom-right'),
      locale: s('locale', 'en'),
      direction: LocaleDirection.fromWire(j['direction']),
      soundEnabled: j['soundEnabled'] != false,
      voiceNotesEnabled: j['voiceNotesEnabled'] == true,
      helpArticlesEnabled: j['helpArticlesEnabled'] == true,
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

  /// Whether the workspace's AI assistant answers a message sent right now.
  ///
  /// When it does, "we're offline, leave a message" is untrue — someone replies
  /// in seconds — so the closed and busy notices say the assistant can help in
  /// the meantime instead. Absent on older servers, which read as false.
  final bool assistantCovers;

  const WorkspaceAvailability({
    required this.isOpen,
    this.agentsAccepting = true,
    this.visitorMode = 'CHAT',
    this.reason = 'OPEN',
    this.nextOpenAt,
    this.closureLabel,
    this.nextOpenLocal,
    this.timezone,
    this.assistantCovers = false,
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
      assistantCovers: j['assistantCovers'] == true,
    );
  }
}

/// The launcher's words as the shared `cleanLauncherLabel` keeps them: one
/// line, at most 40 characters, null when there is nothing to show.
String? _launcherWords(Object? v) {
  if (v is! String) return null;
  final one = jsTrim(jsCollapseWhitespace(v));
  if (one.isEmpty) return null;
  final capped = jsTrim(String.fromCharCodes(one.runes.take(40)));
  return capped.isEmpty ? null : capped;
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

  /// Whether the AI assistant answers a message sent right now. See
  /// [WorkspaceAvailability.assistantCovers].
  final bool assistantCovers;

  /// "Email me this chat" is on offer (`EasyLiveChat.emailTranscript`).
  /// False when an older server leaves it out: not offered.
  final bool transcriptEmailEnabled;

  /// "Get the reply by email" is on offer (`EasyLiveChat.setVisitorEmail`) —
  /// ask for an address while nobody can answer. False when absent.
  final bool replyEmailEnabled;

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
    this.assistantCovers = false,
    this.transcriptEmailEnabled = false,
    this.replyEmailEnabled = false,
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
      assistantCovers: j['assistantCovers'] == true,
      transcriptEmailEnabled: j['transcriptEmailEnabled'] == true,
      replyEmailEnabled: j['replyEmailEnabled'] == true,
    );
  }
}

/// Fill visitor variables into tenant-authored copy.
///
/// Mirrors `substituteVisitorVariables` on the server, which resolves the same
/// tokens for text it PERSISTS (the auto-greeting). Copy the server hands over
/// unresolved — welcome title, offline notice — is resolved here instead,
/// because at the moment `GET /config` is served nobody knows who is asking.
///
/// Both syntaxes are accepted, matching the server: this codebase shipped
/// `%number%` in queue text and `{{name}}` in canned responses, and a tenant
/// shouldn't have to remember which surface takes which.
///
/// An unknown name falls back to [defaultName], then to nothing — never to a
/// literal `%name%` on screen.
String substituteVisitorVariables(
  String template, {
  String? name,
  String? defaultName,
}) {
  final resolved = (name?.trim().isNotEmpty ?? false)
      ? name!.trim()
      : (defaultName?.trim() ?? '');
  final first = resolved.isEmpty ? '' : resolved.split(RegExp(r'\s+')).first;
  return template.replaceAllMapped(
    RegExp(r'%(name|first_name)%|\{\{\s*(name|first_name)\s*\}\}',
        caseSensitive: false),
    (m) => (m.group(1) ?? m.group(2) ?? '').toLowerCase() == 'first_name'
        ? first
        : resolved,
  );
}
