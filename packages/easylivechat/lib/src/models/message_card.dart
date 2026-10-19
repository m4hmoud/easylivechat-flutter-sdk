/// Rich cards: a message an agent builds from an image, a title, a short text
/// and up to three buttons — an order's status, a help article, a product. A
/// button opens a link, or is a reply the visitor taps to answer; a message
/// can carry one card or a carousel of up to ten.
///
/// Carried on a `MessageContentType.card` message as `metadata.card` (one) or
/// `metadata.cards` (a carousel), with a plain-text version in `body`. Read it
/// through `ChatMessage.cards` (or `ChatMessage.card` for the single card),
/// which is empty for anything that isn't usable — render the message's body
/// then, exactly as for a text message.
///
/// A port of `packages/shared/src/message-card.ts`, the validator the server
/// stores cards with and the web widget draws them with. It runs again here
/// rather than trusting the row, for the reason the web gives: the server
/// cleans the cards it is sent, and this keeps a row written any other way from
/// putting a `javascript:` link in front of a visitor.
library;

import 'package:meta/meta.dart';

import 'bot_buttons.dart';
import 'js_text.dart';
import 'web_url.dart';

/// One button on a [MessageCard]: a link, or a reply ([isReply]).
@immutable
class MessageCardButton {
  /// What the button says. Whitespace collapsed, at most
  /// [MessageCard.maxButtonLabelLength] UTF-16 code units, never empty.
  final String label;

  /// Where a link goes: always an `http:` or `https:` link (see
  /// [MessageCard.isSafeUrl]), as the server stored it. Empty on a reply.
  final String url;

  /// A reply button's id — tap it to answer, with `EasyLiveChat.answerButton`
  /// — or null on a link.
  final String? replyId;

  const MessageCardButton({required this.label, required this.url})
      : replyId = null;

  /// A button the visitor taps to answer instead of opening a link.
  const MessageCardButton.reply({required this.label, required String id})
      : url = '',
        replyId = id;

  /// Answers in the chat rather than opening a link.
  bool get isReply => replyId != null;

  /// [url] as the platform should be asked to open it, or null when it is not
  /// a link the web would open.
  ///
  /// For an ordinary link this is just [url] parsed. The difference is input a
  /// browser quietly repairs — `https:example.com` opens `https://example.com`
  /// on the web, and handing the unrepaired string to the platform would open
  /// nothing.
  Uri? get uri {
    final normalized = parseWebUrl(jsTrim(url));
    if (normalized == null) return null;
    final parsed = Uri.tryParse(normalized);
    if (parsed == null) return null;
    return parsed.isScheme('http') || parsed.isScheme('https') ? parsed : null;
  }

  @override
  bool operator ==(Object other) =>
      other is MessageCardButton &&
      other.label == label &&
      other.url == url &&
      other.replyId == replyId;

  @override
  int get hashCode => Object.hash(label, url, replyId);

  @override
  String toString() => replyId == null
      ? 'MessageCardButton($label, $url)'
      : 'MessageCardButton.reply($label, $replyId)';
}

/// An agent's card: an optional image, a title, optional text and up to
/// [maxButtons] link buttons.
@immutable
class MessageCard {
  static const int maxButtons = 3;
  static const int maxTitleLength = 80;
  static const int maxTextLength = 300;
  static const int maxButtonLabelLength = 30;

  /// A carousel holds at most this many cards.
  static const int maxCarouselCards = 10;

  /// Links are held to 1000 characters so the text version of the largest card
  /// still fits in one Telegram message.
  static const int maxUrlLength = 1000;

  /// An `http:`/`https:` URL, or one of the server's own `/uploads/…` paths —
  /// resolve that against the API with `EasyLiveChat.instance.resolveUrl`
  /// before loading it.
  final String? imageUrl;

  /// Whitespace collapsed, at most [maxTitleLength] code units, never empty.
  final String title;

  /// Trimmed, at most [maxTextLength] code units. Line breaks are kept.
  final String? text;

  /// In the agent's order. Possibly empty.
  final List<MessageCardButton> buttons;

  const MessageCard({
    this.imageUrl,
    required this.title,
    this.text,
    this.buttons = const [],
  });

  /// The card, cleaned — or null when there is no usable card: no title, or a
  /// shape that isn't one.
  ///
  /// A button with an unsafe URL or no label is dropped rather than failing the
  /// card; an unusable image is dropped the same way.
  static MessageCard? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final title = _clean(raw['title'], maxTitleLength);
    if (title == null) return null;

    final rawText = raw['text'];
    final text = rawText is String
        ? jsTrim(jsSlice(jsTrim(rawText), maxTextLength))
        : '';

    final rawImage = raw['imageUrl'];
    final imageUrl = _isCardImage(rawImage) ? jsTrim(rawImage as String) : null;

    final buttons = <MessageCardButton>[];
    final replies = <String>{};
    final rawButtons = raw['buttons'];
    if (rawButtons is List) {
      for (final b in rawButtons) {
        if (b is! Map) continue;
        final label = _clean(b['label'], maxButtonLabelLength);
        if (label == null) continue;
        final url = b['url'];
        final reply = b['reply'];
        // A safe link is a link; otherwise a reply id of ours is an answer.
        if (isSafeUrl(url)) {
          buttons.add(MessageCardButton(label: label, url: jsTrim(url as String)));
        } else if (isBotButtonId(reply) && replies.add(reply as String)) {
          buttons.add(MessageCardButton.reply(label: label, id: reply));
        } else {
          continue;
        }
        if (buttons.length == maxButtons) break;
      }
    }

    return MessageCard(
      imageUrl: imageUrl,
      title: title,
      text: text.isEmpty ? null : text,
      buttons: List<MessageCardButton>.unmodifiable(buttons),
    );
  }

  /// A carousel (`metadata.cards`), cleaned: the usable cards, at most
  /// [maxCarouselCards], no reply id twice across them. Not a list: none.
  static List<MessageCard> tryParseCarousel(Object? raw) {
    if (raw is! List) return const [];
    final out = <MessageCard>[];
    final replies = <String>{};
    for (final item in raw) {
      final card = tryParse(item);
      if (card == null) continue;
      final kept = card.buttons
          .where((b) => b.replyId == null || replies.add(b.replyId!))
          .toList();
      out.add(MessageCard(
        imageUrl: card.imageUrl,
        title: card.title,
        text: card.text,
        buttons: List<MessageCardButton>.unmodifiable(kept),
      ));
      if (out.length == maxCarouselCards) break;
    }
    return List<MessageCard>.unmodifiable(out);
  }

  /// A link a visitor may be sent to: `http:` or `https:` only, as the web's URL
  /// parser reads it. Anything else — above all `javascript:` — is refused, not
  /// rewritten.
  static bool isSafeUrl(Object? url) {
    if (url is! String || url.length > maxUrlLength) return false;
    return parseWebUrl(jsTrim(url)) != null;
  }

  /// An image the card may show: a safe URL, or an upload of ours.
  static bool _isCardImage(Object? url) {
    if (url is! String) return false;
    if (_uploadPath.hasMatch(url) && !url.contains('..')) return true;
    return isSafeUrl(url);
  }

  static final RegExp _uploadPath = RegExp(r'^\/uploads\/[A-Za-z0-9._\-/]+$');

  static String? _clean(Object? v, int max) {
    if (v is! String) return null;
    final t = jsTrim(jsCollapseWhitespace(v));
    return t.isEmpty ? null : jsTrim(jsSlice(t, max));
  }

  @override
  bool operator ==(Object other) {
    if (other is! MessageCard ||
        other.imageUrl != imageUrl ||
        other.title != title ||
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
  int get hashCode => Object.hash(imageUrl, title, text, Object.hashAll(buttons));

  @override
  String toString() =>
      'MessageCard(title: $title, text: $text, imageUrl: $imageUrl, buttons: $buttons)';
}
