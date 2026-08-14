import 'dart:async';

import 'package:flutter/foundation.dart';

import 'config.dart';
import 'errors.dart';
import 'models/chat_message.dart';
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
    _c = SessionController(
        config: config, storage: storage ?? InMemoryStorage());
    await _c!.boot();
  }

  /// Pre-identify a known (logged-in) visitor BEFORE [open]. [open] then skips
  /// the pre-chat form and starts the session directly as this person; [phone]
  /// (optional) and [fields] (your own keys, e.g. userId / app) are sent with
  /// the session so agents see who they're talking to. Safe to call before or
  /// after [boot] (re-applied at boot); a no-op identity (`null`s) is ignored.
  void identify(
          {String? name,
          String? email,
          String? phone,
          Map<String, String>? fields}) =>
      _controller.identify(
          name: name, email: email, phone: phone, fields: fields);

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
  ValueListenable<int> get unreadCount => _controller.unreadCount;

  /// How far into the thread an agent has read.
  ///
  /// Only needed when building your own thread UI — pair it with
  /// `ChatMessage.receiptFor(agentLastReadAt.value)` to render sent/read ticks.
  /// The bundled [EasyLiveChatScreen] already does this.
  ValueListenable<DateTime?> get agentLastReadAt => _controller.agentLastReadAt;
  Stream<ChatMessage> get onMessage => _controller.onMessage;
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
  Future<void> startSession(
          {String? name,
          String? email,
          String? phone,
          Map<String, String>? fields}) =>
      _controller.startSession(
          name: name, email: email, phone: phone, fields: fields);
  void closeSession() => _controller.closeSession();

  // ── messaging ──
  SendResult sendMessage(String body,
          {List<String> attachmentUrls = const []}) =>
      _controller.sendMessage(body, attachmentUrls: attachmentUrls);

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

  // ── offline + CSAT ──
  Future<String> submitOfflineForm(
          {String? name, String? email, required String message}) =>
      _controller.submitOfflineForm(name: name, email: email, message: message);
  Future<FeedbackResult> submitFeedback(
          {required int rating, String? comment}) =>
      _controller.submitFeedback(rating: rating, comment: comment);

  // ── presence / lifecycle ──
  void setAppLifecycle(EasyLiveChatLifecycle state) =>
      _controller.setAppLifecycle(state);
  void heartbeat({String? currentUrl, String? currentTitle}) =>
      _controller.heartbeat(currentUrl: currentUrl, currentTitle: currentTitle);

  /// Tear everything down. After this you must [boot] again.
  void shutdown() {
    _c?.dispose();
    _c = null;
  }
}
