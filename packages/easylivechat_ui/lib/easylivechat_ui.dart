/// Prebuilt Flutter UI for EasyLiveChat, built on the headless `easylivechat`
/// core. Drop an [EasyLiveChatLauncher] into a [Stack], or push an
/// [EasyLiveChatScreen]. Theming/locale/RTL come from the server widget config.
///
/// ```dart
/// await EasyLiveChat.instance.boot(
///   const EasyLiveChatConfig(apiBase: '...', tenantSlug: 'acme'),
///   storage: SecurePrefsStorage(), // durable default from this package
/// );
/// // in your widget tree:
/// Stack(children: [ MyApp(), const EasyLiveChatLauncher() ]);
/// ```
library easylivechat_ui;

export 'package:easylivechat/easylivechat.dart';

export 'src/theme.dart';
export 'src/storage_impl.dart';
export 'src/launcher.dart';
export 'src/chat_screen.dart';
export 'src/end_chat_button.dart';
// The header's ⋯ ("Email me this chat"), for a host's own app bar.
export 'src/email_offers.dart' show EasyLiveChatMenuButton;
// Help articles: the screen, and the article renderer for hosts that build
// their own help UI on the core's searchHelp()/getHelpArticle().
export 'src/help_screen.dart' show EasyLiveChatHelpScreen;
export 'src/views/help_markdown_view.dart' show ElcHelpMarkdown, ElcOpenLink;
export 'src/picked_file.dart' show ElcPickedFile, ElcAttachmentPicker;
// For hosts drawing their own thread on the core's `ChatMessage.linkPreview`
// and `reactions`: the same card, chips, quick row and picker.
export 'src/views/link_preview_view.dart' show ElcLinkPreviewCard;
export 'src/views/reactions_view.dart'
    show ElcReactionChips, ElcQuickReactions, showElcEmojiPicker;
// ElcStrings.overrideAll(...) lets a host fully own the chrome translations.
export 'src/l10n.dart' show ElcStrings;
