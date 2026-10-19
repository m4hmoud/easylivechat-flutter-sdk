import 'dart:async';

import 'package:flutter/foundation.dart';

import 'config.dart';
import 'errors.dart';
import 'models/chat_message.dart';
import 'models/help_article.dart';
import 'models/results.dart';
import 'models/widget_config.dart';
import 'session_controller.dart';
import 'storage.dart';

/// Public singleton facade for the EasyLiveChat client. Thin delegation over
/// [SessionController]; this is the surface apps (and `easylivechat_ui`) bind.
///
/// ```dart
/// await EasyLiveChat.instance.boot(const EasyLiveChatConfig(
///   apiBase: 'https://api.livechattools.com', tenantSlug: 'acme'));
/// await EasyLiveChat.instance.open();
/// ```
class EasyLiveChat {
  EasyLiveChat._();
  static final EasyLiveChat instance = EasyLiveChat._();

  SessionController? _c;
  SessionController get _controller {
    final c = _c;
    if (c == null) {
      throw StateError('EasyLiveChat.boot() must be called before use.');
    }
    return c;
  }

  bool get isBooted => _c != null;

  bool _supportsConsent = false;

  /// Whether this app draws the workspace's consent checkboxes — a pre-chat
  /// field of type [PreChatFieldType.consent]: a checkbox, the tenant's
  /// sentence beside it, and its privacy-policy link.
  ///
  /// Off by default, and the prebuilt `easylivechat_ui` screens turn it on
  /// themselves. A host that builds its OWN pre-chat form turns it on once it
  /// renders consent fields — it may be set before [boot]:
  ///
  /// ```dart
  /// EasyLiveChat.instance.supportsConsent = true;
  /// // … then pass the ticked ids:
  /// await EasyLiveChat.instance.startSession(fields: values, consents: ticked);
  /// ```
  ///
  /// While it is off the config is requested without consent fields — the
  /// server leaves them out for a client that does not ask, rather than have
  /// it draw a text box labelled "I agree to…" — and no consent is asked of
  /// the visitor, exactly as before consent existed. Takes effect at the next
  /// config fetch ([open], [loadConfig], [refreshAvailability]).
  bool get supportsConsent => _supportsConsent;
  set supportsConsent(bool value) {
    _supportsConsent = value;
    _c?.supportsConsent = value;
  }

  /// Initialize with [config]. Inject a durable [storage] (an
  /// `EasyLiveChatStorage`); defaults to ephemeral [InMemoryStorage] which is
  /// NOT durable — production apps must provide a persistent implementation
  /// (e.g. the one in `easylivechat_ui`).
  Future<void> boot(EasyLiveChatConfig config,
      {EasyLiveChatStorage? storage}) async {
    // Already booted: adopt whatever changed rather than ignoring the new
    // config. The host rebuilds it from the CURRENT app language on every
    // open, and returning early here left the chat fetching tenant copy in
    // the language the app happened to be in the first time.
    if (_c != null) {
      config.validate();
      _c!.applyConfig(config);
      return;
    }
    // Fail fast on a misconfigured apiBase/tenantSlug rather than deep in the
    // transport with an opaque error.
    config.validate();
    final c = SessionController(
        config: config, storage: storage ?? InMemoryStorage())
      ..supportsConsent = _supportsConsent;
    _c = c;
    await c.boot();
    // An identify()/clearIdentity() made before boot, now that there is a
    // visitor to line it up against.
    final pending = _pendingIdentity;
    _pendingIdentity = null;
    pending?.call(c);
  }

  /// identify()/clearIdentity() called before [boot], applied by it.
  void Function(SessionController c)? _pendingIdentity;

  /// Pre-identify a known (logged-in) visitor BEFORE [open]. [open] then skips
  /// the pre-chat form and starts the session directly as this person; [phone]
  /// (optional) and [fields] (your own keys, e.g. plan / app) are sent with
  /// the session so agents see who they're talking to. Safe to call before or
  /// after [boot] (applied at boot); a no-op identity (`null`s) is ignored.
  ///
  /// **Identity verification.** [userId] is YOUR app's own id for the signed-in
  /// user; [userHash] proves it: your BACKEND computes
  /// `hex(HMAC_SHA256(workspaceIdentitySecret, userId))` and hands it to the
  /// app with the id. Never compute it in the app — the secret must not ship
  /// in a binary. Both are sent on every session call (the silent resume and
  /// the start). With the workspace's verification off they are ignored; when
  /// it is optional a correct hash marks the contact verified and a wrong one
  /// is simply not trusted; when it is ENFORCED a `userId` with a missing or
  /// wrong hash is refused and [open] throws an [EasyLiveChatError] whose
  /// `isIdentityNotVerified` is true (also emitted on [onError]) — its
  /// `reason` says what to fix. Anonymous visitors are never refused.
  ///
  /// Declare the identity on EVERY launch, before the chat opens — the SDK
  /// remembers which `userId` this device's visitor belongs to and lines the
  /// two up the way the web widget does:
  ///  • anonymous → signed in keeps the visitor: the conversation they already
  ///    started continues, with the identity attached;
  ///  • a DIFFERENT `userId`, or opening the chat with none after one was set,
  ///    forgets the stored visitor — a fresh visitorId, nothing to resume — so
  ///    the next person on the device never sees the last one's conversation.
  /// Signing out mid-session: call [clearIdentity] (or [reset]).
  void identify(
      {String? name,
      String? email,
      String? phone,
      Map<String, String>? fields,
      String? userId,
      String? userHash}) {
    void apply(SessionController c) => c.identify(
        name: name,
        email: email,
        phone: phone,
        fields: fields,
        userId: userId,
        userHash: userHash);
    final c = _c;
    if (c == null) {
      _pendingIdentity = apply;
      return;
    }
    apply(c);
  }

  /// The signed-in user signed out: drop the identity passed to [identify]
  /// without tearing the SDK down.
  ///
  /// When this device's visitor had been identified with a `userId`, the
  /// visitor is forgotten as well — a fresh visitorId, no conversation to
  /// resume — and a chat on screen restarts as an anonymous visitor. For a
  /// visitor that never carried a `userId` only the declared identity and the
  /// cached profile go; [reset] is the full logout that also abandons the
  /// visitorId in every case.
  void clearIdentity() {
    final c = _c;
    if (c == null) {
      // Nothing booted yet: the next open() lines up "nobody signed in" by
      // itself, so all there is to do is drop an identify() still waiting.
      _pendingIdentity = null;
      return;
    }
    c.clearIdentity();
  }

  // ── reactive state (read-only) ──
  ValueListenable<ChatPhase> get phase => _controller.phase;
  ValueListenable<WidgetConfigModel?> get widgetConfig =>
      _controller.widgetConfig;
  ValueListenable<bool> get isOpen => _controller.isOpen;

  /// Whether any agent is currently accepting chats. Updates live alongside
  /// [isOpen]; only gates the UI for `WHEN_ACCEPTING` tenants.
  ValueListenable<bool> get agentsAccepting => _controller.agentsAccepting;

  /// True when the workspace is closed — outside working hours, or (for
  /// WHEN_ACCEPTING tenants) nobody accepting. Presentational: show a notice.
  /// It never blocks writing, because a message sent while closed still becomes
  /// a real conversation the team picks up when they are back.
  bool get workspaceClosed => _controller.workspaceClosed;

  /// Server-decided: `CHAT`, `LEAVE_MESSAGE` or `NOTICE_ONLY`.
  ValueListenable<String> get visitorMode => _controller.visitorMode;

  /// When the workspace reopens, as `HH:mm` on the BUSINESS's clock.
  ValueListenable<String?> get nextOpenLocal => _controller.nextOpenLocal;

  /// The tenant's configured IANA timezone, e.g. `Asia/Baghdad`.
  ValueListenable<String?> get workspaceTimezone =>
      _controller.workspaceTimezone;

  /// Why: `OPEN`, `AFTER_HOURS` or `NO_AGENTS`.
  ValueListenable<String> get availabilityReason =>
      _controller.availabilityReason;

  /// When we next open — lets the UI say "back at 09:00". Null when open.
  ValueListenable<DateTime?> get nextOpenAt => _controller.nextOpenAt;

  /// Holiday/closure name when the reason is `HOLIDAY`, else null.
  ValueListenable<String?> get closureLabel => _controller.closureLabel;

  /// True when the tenant chose to show a notice and take nothing.
  bool get composerLocked => _controller.composerLocked;
  ValueListenable<ConnectionState> get connection => _controller.connection;
  ValueListenable<List<ChatMessage>> get messages => _controller.messages;
  ValueListenable<bool> get agentTyping => _controller.agentTyping;

  /// True while that typing is the AI assistant composing a reply.
  ValueListenable<bool> get assistantTyping => _controller.assistantTyping;

  /// Whether the AI assistant answers a message sent right now — use it to
  /// swap the closed/busy notice for "our assistant can help in the meantime".
  ValueListenable<bool> get assistantCovers => _controller.assistantCovers;
  ValueListenable<int> get unreadCount => _controller.unreadCount;

  /// How far into the thread an agent has read.
  ///
  /// Only needed when building your own thread UI — pair it with
  /// `ChatMessage.receiptFor(agentLastReadAt.value)` to render sent/read ticks.
  /// The bundled [EasyLiveChatScreen] already does this.
  ValueListenable<DateTime?> get agentLastReadAt => _controller.agentLastReadAt;
  Stream<ChatMessage> get onMessage => _controller.onMessage;

  /// A message an agent unsent, once per id.
  ///
  /// Fires for the live `message:deleted`, and for every id a history response
  /// lists in `unsentIds` the first time this session hears of it — so it can
  /// include a message this client never displayed, such as one that only
  /// reached the device as a push notification. Use it to withdraw anything you
  /// derived from the message yourself (a notification, a cached preview); the
  /// [messages] listenable already drops it.
  Stream<DeletedMessage> get onMessageDeleted => _controller.onMessageDeleted;
  Stream<ProactiveMessage> get onProactiveMessage =>
      _controller.onProactiveMessage;
  Stream<EasyLiveChatError> get onError => _controller.onError;

  String get visitorId => _controller.visitorId;
  String? get conversationId => _controller.conversationId;

  // ── lifecycle ──
  Future<WidgetConfigModel> loadConfig() => _controller.loadConfig();
  Future<void> open() => _controller.open();

  /// Re-read availability and re-gate the UI. Call whenever the chat becomes
  /// visible again — reopening the screen, or the app returning to foreground.
  Future<void> refreshAvailability() => _controller.refreshAvailability();
  Future<bool> silentResume() => _controller.silentResume();

  /// Start a new chat from the pre-chat form: [fields] keyed by field id, and
  /// [consents] — the ids of the consent fields the visitor ticked.
  ///
  /// Consent is not a value, so it never goes in [fields]. [consents] only
  /// matters with [supportsConsent] on; a required consent field left out of
  /// it fails with `CONSENT_REQUIRED` (its `fieldId` set), locally first and
  /// then from the server, as other field errors do.
  Future<void> startSession(
          {String? name,
          String? email,
          String? phone,
          Map<String, String>? fields,
          List<String>? consents}) =>
      _controller.startSession(
          name: name,
          email: email,
          phone: phone,
          fields: fields,
          consents: consents);
  void closeSession() => _controller.closeSession();

  // ── messaging ──
  SendResult sendMessage(String body,
          {List<String> attachmentUrls = const []}) =>
      _controller.sendMessage(body, attachmentUrls: attachmentUrls);

  /// Answer a reply button under [message] — one of its
  /// [ChatMessage.botButtons], or a reply button on one of its cards. Sends
  /// [label] as the visitor's own message (it shows and ticks like anything
  /// typed) with the button's id beside it, so the server records which
  /// button was meant; the agents read "Chose: …".
  ///
  /// Offer it only while [buttonsOpen] says the question is still open. For a
  /// card's reply button pass the label [ChatMessage.botButtons] gives that
  /// id — on a carousel it names the card ("Blue shirt · Buy").
  SendResult answerButton(ChatMessage message,
          {required String buttonId, required String label}) =>
      _controller.sendMessage(label,
          reply: {'messageId': message.id, 'buttonId': buttonId});

  /// Submit the tenant's post-chat survey (see
  /// [WidgetConfigModel.postChatForm]). Keyed by field id. A conversation that
  /// was already answered resolves normally — one-shot, not an error.
  Future<void> submitPostChat(Map<String, String> fields) =>
      _controller.submitPostChat(fields);

  /// Re-send a message that previously failed (tap-to-retry). Drops the failed
  /// row and sends its body + attachments fresh. Returns null when [message] is
  /// not in a failed state.
  SendResult? resend(ChatMessage message) => _controller.resend(message);

  void setTyping(bool isTyping) => _controller.setTyping(isTyping);

  /// The visitor's name, for resolving `%name%` in tenant copy.
  String? get visitorName => _controller.visitorName;

  /// End the conversation from the visitor's side, the same way the web
  /// widget's × does. A later [open] starts a brand-new conversation rather
  /// than resuming this one.
  ///
  /// Returns true when a post-chat step (survey or CSAT) will follow and the
  /// chat should stay on screen for it; false when there is nothing more to
  /// show — because this chat was already rated, was already closed, or there
  /// was no live connection — and the caller should close the chat UI.
  Future<bool> endChat() => _controller.endChat();
  Future<MessagePage> loadOlderMessages() => _controller.loadOlderMessages();

  /// Whether the server says there is history behind the loaded page.
  ///
  /// A resumed thread opens on the visit the customer just started, so earlier
  /// visits sit behind the cursor rather than on screen. Drives the host UI's
  /// "load earlier" affordance — a brand-new conversation reports false.
  bool get hasOlderHistory => _controller.hasOlderHistory;
  void markRead() => _controller.markRead();

  // ── attachments ──
  Future<UploadedFile> uploadBytes({
    required List<int> bytes,
    required String filename,
    String? contentType,
    void Function(double progress)? onProgress,
  }) =>
      _controller.uploadBytes(
        bytes: bytes,
        filename: filename,
        contentType: contentType,
        onProgress: onProgress,
      );
  String resolveUrl(String relativeOrAbsolute) =>
      _controller.resolveUrl(relativeOrAbsolute);

  // ── help articles ──
  //
  // Public: they need [boot] (for the visitorId) but no session — a visitor
  // can read them before ever opening a chat. Gate any help UI on
  // `widgetConfig.value?.helpArticlesEnabled`; with the workspace's switch off
  // the list answers `enabled: false` and an article is NOT_FOUND.

  /// Search the workspace's help articles, best match first (server default 5,
  /// at most 20). A [q] shorter than two characters returns the top articles
  /// instead, exactly like [helpArticles]. [category] narrows to one of
  /// [HelpArticleList.categories]. Articles come in `config.contentLocale` when
  /// the workspace wrote any in it.
  Future<HelpArticleList> searchHelp(String q,
          {String? category, int? limit}) =>
      _controller.searchHelp(q, category: category, limit: limit);

  /// The top articles in the workspace's own order (default 20, at most 50) —
  /// what to show before the visitor has typed anything.
  Future<HelpArticleList> helpArticles({String? category, int? limit}) =>
      _controller.helpArticles(category: category, limit: limit);

  /// One article in full; its [HelpArticle.body] is markdown to render as
  /// text, never as HTML. Records the reading for the workspace's help
  /// analytics (fire-and-forget; a failed count is swallowed). Throws an
  /// [EasyLiveChatError] with code `NOT_FOUND` when the article is gone.
  Future<HelpArticle> getHelpArticle(String id) =>
      _controller.getHelpArticle(id);

  /// Answer "Was this helpful?" for an article. One answer per reading;
  /// answering again replaces it.
  Future<void> rateHelpArticle(String id, bool helpful) =>
      _controller.rateHelpArticle(id, helpful);

  // ── offline + CSAT ──
  /// Leave a message for the team. [consents] are the consent fields the
  /// visitor ticked on your form, as for [startSession]; omit them and nothing
  /// about consent is sent.
  Future<String> submitOfflineForm(
          {String? name,
          String? email,
          required String message,
          List<String>? consents}) =>
      _controller.submitOfflineForm(
          name: name, email: email, message: message, consents: consents);
  Future<FeedbackResult> submitFeedback(
          {required int rating, String? comment}) =>
      _controller.submitFeedback(rating: rating, comment: comment);

  // ── presence / lifecycle ──
  void setAppLifecycle(EasyLiveChatLifecycle state) =>
      _controller.setAppLifecycle(state);
  void heartbeat({String? currentUrl, String? currentTitle}) =>
      _controller.heartbeat(currentUrl: currentUrl, currentTitle: currentTitle);

  /// The device to notify when an agent replies and the app is closed.
  ///
  /// Hand over the FCM registration token your app already receives — the SDK
  /// brings no push dependency of its own, so your project keeps one Firebase
  /// setup and one notification permission prompt. Call it as soon as you have
  /// a token, even before the visitor opens a chat: there is nothing to
  /// authenticate a registration with until a session exists, so it is held and
  /// sent the moment one does.
  ///
  /// Call it again when the token rotates — the old registration is dropped
  /// first. Pass `null` on sign-out to stop the notifications.
  ///
  /// Nothing is suppressed server-side, on purpose: a socket that is connected
  /// does not mean a person who is looking. Suppress in your notification
  /// handler when the chat is already on screen — your app is the only thing
  /// that knows.
  Future<void> setPushToken(
    String? pushToken, {
    required String platform,
    String? appVersion,
  }) =>
      _controller.setPushToken(pushToken, platform: platform, appVersion: appVersion);

  /// Tear everything down. After this you must [boot] again.
  void shutdown() {
    _c?.dispose();
    _c = null;
  }

  /// Forget who this visitor is. Call this from your app's LOGOUT path.
  ///
  /// [shutdown] only clears memory; the durable `visitorId` survives it, so the
  /// next [boot] resolves the same server-side contact and resumes the same
  /// conversation. That is right for a returning customer and wrong for a
  /// signed-out one: the contact keeps the name it already holds when a client
  /// sends none, so the next person to open the chat on that device was greeted
  /// by the previous person's name and carried on inside their transcript. On a
  /// shared device — a restaurant tablet, a POS terminal — that is somebody
  /// else's identity.
  ///
  /// This drops the visitorId, token, cached profile and conversation id, then
  /// tears down. The next [boot] mints a fresh visitorId, so the server sees a
  /// new contact with nothing to resume: no history, no "load earlier"
  /// affordance, and the greeting resolves against the workspace's own
  /// `defaultCustomerName` for the visitor's language instead of a stale name.
  ///
  /// The transcript is not deleted — this abandons the identity, not the
  /// history. Agents keep the old thread.
  ///
  /// Safe to call when the SDK was never booted this session, which is the
  /// common case for a logout that never opened the chat — pass the same
  /// [storage] you pass to [boot] so the keys can still be cleared. When it IS
  /// booted the controller's own storage is used and the argument is ignored.
  Future<void> reset({EasyLiveChatStorage? storage}) async {
    _pendingIdentity = null;
    final c = _c;
    if (c != null) {
      await c.resetVisitor();
      c.dispose();
      _c = null;
      return;
    }
    if (storage == null) return;
    for (final key in StorageKeys.identity) {
      await storage.delete(key);
    }
  }
}
