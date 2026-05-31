/// EasyLiveChat — headless Dart client for the EasyLiveChat widget protocol.
///
/// Embed real-time, omni-channel customer support into any Flutter app. This
/// package is UI-free: it speaks the anonymous widget protocol (HTTP +
/// Socket.IO) and exposes reactive state. Pair with `easylivechat_ui` for
/// prebuilt widgets.
///
/// ```dart
/// await EasyLiveChat.instance.boot(const EasyLiveChatConfig(
///   apiBase: 'https://api.livechattools.com', tenantSlug: 'acme'));
/// await EasyLiveChat.instance.open();
/// EasyLiveChat.instance.messages.addListener(() { /* rebuild */ });
/// await EasyLiveChat.instance.sendMessage('Hi!');
/// ```
library easylivechat;

export 'src/config.dart';
export 'src/errors.dart';
export 'src/storage.dart' show EasyLiveChatStorage, StorageKeys, InMemoryStorage;
export 'src/models/enums.dart';
export 'src/models/chat_message.dart';
export 'src/models/pre_chat_form.dart';
export 'src/models/widget_config.dart';
export 'src/models/results.dart';
export 'src/session_controller.dart' show ChatPhase, ConnectionState, EasyLiveChatLifecycle;
export 'src/easylivechat_client.dart' show EasyLiveChat;
