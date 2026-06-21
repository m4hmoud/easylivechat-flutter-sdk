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
    if (_c != null) return;
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
  ValueListenable<ConnectionState> get connection => _controller.connection;
  ValueListenable<List<ChatMessage>> get messages => _controller.messages;
  ValueListenable<bool> get agentTyping => _controller.agentTyping;
  ValueListenable<int> get unreadCount => _controller.unreadCount;
  Stream<ChatMessage> get onMessage => _controller.onMessage;
  Stream<ProactiveMessage> get onProactiveMessage =>
      _controller.onProactiveMessage;
  Stream<EasyLiveChatError> get onError => _controller.onError;

  String get visitorId => _controller.visitorId;
  String? get conversationId => _controller.conversationId;

  // ── lifecycle ──
  Future<WidgetConfigModel> loadConfig() => _controller.loadConfig();
  Future<void> open() => _controller.open();
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

  /// Re-send a message that previously failed (tap-to-retry). Drops the failed
  /// row and sends its body + attachments fresh. Returns null when [message] is
  /// not in a failed state.
  SendResult? resend(ChatMessage message) => _controller.resend(message);

  void setTyping(bool isTyping) => _controller.setTyping(isTyping);
  Future<MessagePage> loadOlderMessages() => _controller.loadOlderMessages();
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
