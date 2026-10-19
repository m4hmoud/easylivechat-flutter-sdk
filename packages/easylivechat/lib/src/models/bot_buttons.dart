/// Reply buttons under a message from the team — a bot flow's answers, or the
/// ones an agent added — and the visitor's choice.
///
/// A port of `packages/shared/src/bot-buttons.ts`. A message with buttons
/// carries them in three layers so every client ever shipped reads something:
///
///  • `metadata.bot = {text, buttons: [{id, label}]}` — the words and the
///    buttons. Draw [BotButtons.text] in the bubble (NOT `body`) and the
///    buttons under it; a tap answers with [EasyLiveChat.answerButton].
///  • `metadata.quickReplies` — the labels again, for clients that predate
///    buttons (`quickRepliesOnOffer` still finds them).
///  • `body` — the words with a numbered menu ("1. Sales / 2. Support"), for
///    everything that draws neither. Drawing it beside the buttons says the
///    options twice.
///
/// The visitor's answer is stored on their message as `metadata.botReply`
/// ([ChatMessage.botReply]) once the server has matched it.
library;

import 'package:meta/meta.dart';

import 'chat_message.dart';
import 'enums.dart';
import 'js_text.dart';

/// The ids the server mints for buttons.
final RegExp _buttonId = RegExp(r'^[A-Za-z0-9_-]{1,40}$');

/// Whether [v] is a button id the server could have minted.
bool isBotButtonId(Object? v) => v is String && _buttonId.hasMatch(v);

/// One reply button.
@immutable
class BotButton {
  final String id;

  /// What it says, and what a tap sends as the visitor's words.
  final String label;

  const BotButton({required this.id, required this.label});

  @override
  bool operator ==(Object other) =>
      other is BotButton && other.id == id && other.label == label;

  @override
  int get hashCode => Object.hash(id, label);

  @override
  String toString() => 'BotButton($id, $label)';
}

/// What `metadata.bot` holds on a message with buttons.
@immutable
class BotButtons {
  static const int maxButtons = 10;
  static const int maxLabelLength = 40;

  /// The message's own words, without the numbered menu `body` carries.
  final String text;

  /// Never empty; ids unique; at most [maxButtons].
  final List<BotButton> buttons;

  const BotButtons({required this.text, required this.buttons});

  /// The buttons in [raw] (`metadata.bot`), cleaned — or null when there are
  /// none usable.
  static BotButtons? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final rawButtons = raw['buttons'];
    if (rawButtons is! List) return null;
    final out = <BotButton>[];
    final seen = <String>{};
    for (final b in rawButtons) {
      if (b is! Map) continue;
      final id = b['id'];
      final label = b['label'];
      if (!isBotButtonId(id) || label is! String) continue;
      final clean = jsTrim(jsCollapseWhitespace(label));
      if (clean.isEmpty || !seen.add(id as String)) continue;
      out.add(BotButton(id: id, label: jsTrim(jsSlice(clean, maxLabelLength))));
      if (out.length >= maxButtons) break;
    }
    if (out.isEmpty) return null;
    final text = raw['text'];
    return BotButtons(
      text: text is String ? text : '',
      buttons: List<BotButton>.unmodifiable(out),
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! BotButtons ||
        other.text != text ||
        other.buttons.length != buttons.length) {
      return false;
    }
    for (var i = 0; i < buttons.length; i++) {
      if (other.buttons[i] != buttons[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(text, Object.hashAll(buttons));
}

/// The visitor's answer to a message's buttons (`metadata.botReply`).
@immutable
class BotReply {
  /// The message whose button this answers.
  final String messageId;
  final String buttonId;

  /// The button's label as it was offered.
  final String label;

  const BotReply({
    required this.messageId,
    required this.buttonId,
    required this.label,
  });

  static BotReply? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final messageId = raw['messageId'];
    final buttonId = raw['buttonId'];
    if (messageId is! String || !isBotButtonId(buttonId)) return null;
    final label = raw['label'];
    return BotReply(
      messageId: messageId,
      buttonId: buttonId as String,
      label: label is String ? label : '',
    );
  }
}

/// Which button of [messageId] the thread says was chosen, if any — mark it,
/// and quiet the rest.
String? chosenButtonId(List<ChatMessage> messages, String messageId) {
  for (final m in messages) {
    if (m.senderType != SenderType.customer) continue;
    final reply = m.botReply;
    if (reply != null && reply.messageId == messageId) return reply.buttonId;
  }
  return null;
}

/// Whether the buttons under [messageId] can still be tapped: it is the
/// newest thing anyone but the system said, and nobody has answered it. Once
/// the visitor has written (with a tap or by typing) or the team has spoken
/// again, the question has moved on.
bool buttonsOpen(List<ChatMessage> messages, String messageId) {
  for (var i = messages.length - 1; i >= 0; i--) {
    final m = messages[i];
    if (m.senderType == SenderType.system) continue;
    return m.id == messageId && chosenButtonId(messages, messageId) == null;
  }
  return false;
}
