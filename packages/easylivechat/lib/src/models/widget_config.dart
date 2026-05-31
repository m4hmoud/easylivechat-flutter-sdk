import 'enums.dart';
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
    this.allowedOrigins = const [],
  });

  factory WidgetConfigModel.fromJson(Map<String, dynamic> j) {
    String s(String k, String d) => (j[k] as String?)?.trim().isNotEmpty == true ? j[k] as String : d;
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
      preChatForm: j['preChatForm'] is Map
          ? PreChatForm.fromJson((j['preChatForm'] as Map).cast<String, dynamic>())
          : PreChatForm.disabled,
      allowedOrigins: (j['allowedOrigins'] is List)
          ? (j['allowedOrigins'] as List).map((e) => e.toString()).toList()
          : const [],
    );
  }
}

/// Envelope of `GET /:slug/config`.
class ConfigResponse {
  final String tenantId;
  final WidgetConfigModel config;

  /// Working-hours availability at fetch time (`isWithinWorkingHours`).
  final bool isOpen;

  const ConfigResponse({
    required this.tenantId,
    required this.config,
    required this.isOpen,
  });

  factory ConfigResponse.fromJson(Map<String, dynamic> j) => ConfigResponse(
        tenantId: (j['tenantId'] ?? '').toString(),
        config: WidgetConfigModel.fromJson(
            (j['config'] as Map).cast<String, dynamic>()),
        isOpen: j['isOpen'] == true,
      );
}
