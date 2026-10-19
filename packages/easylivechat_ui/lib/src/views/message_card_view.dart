import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easylivechat/easylivechat.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../bidi.dart';
import '../theme.dart';
import 'bubble_shape.dart';

/// An agent's card: image, title, text and link buttons — the native analog of
/// `MessageCardView` in the web widget's `Thread.tsx`.
///
/// Built from the same surface, corners and tail as a message from the team,
/// so it reads as one — only with more in it. The buttons wear the workspace
/// accent, as quick replies do, and open their link in the visitor's browser.
///
/// The card itself comes from `ChatMessage.cards`, which has already run the
/// server's validator: every link button is an `http:`/`https:` link. A reply
/// button answers instead (`EasyLiveChat.answerButton`): live while
/// [onReply] is set, marked once [chosenReplyId] names it.
class ElcMessageCardView extends StatelessWidget {
  final MessageCard card;
  final EasyLiveChatTheme theme;

  /// The widest a bubble may be on this screen. The card is 280 wide (or
  /// [width]), or this when the screen is narrower — the web's
  /// `min(280px, 100%)`.
  final double maxWidth;

  /// The reply button the visitor already chose, if any.
  final String? chosenReplyId;

  /// Answers with a reply button: its id and its label. Null draws reply
  /// buttons disabled — the question has moved on, or a send is under way.
  final void Function(String id, String label)? onReply;

  /// The card's own width; a carousel's cards are a little narrower.
  final double width;

  const ElcMessageCardView({
    super.key,
    required this.card,
    required this.theme,
    required this.maxWidth,
    this.chosenReplyId,
    this.onReply,
    this.width = _width,
  });

  static const double _width = 280;

  @override
  Widget build(BuildContext context) {
    final fg = theme.text;
    final radius = ElcBubbleShape.radius(fromCustomer: false);
    final hairline = fg.withValues(alpha: 0.10);
    final imageUrl = card.imageUrl;
    final text = card.text;

    return SizedBox(
      width: math.min(width, maxWidth),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: theme.surface, borderRadius: radius),
        // In front, so the image cannot paint over the outline at the top.
        foregroundDecoration: BoxDecoration(
          borderRadius: radius,
          border: ElcBubbleShape.teamBorder(theme),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (imageUrl != null)
              AspectRatio(
                aspectRatio: 16 / 9,
                // Decorative, as on the web (`alt=""`): the title says what
                // the card is about.
                child: ExcludeSemantics(child: _image(imageUrl, fg)),
              ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Each run faces the way its own text reads — `dir="auto"`
                  // on the web — so an English card in an Arabic workspace
                  // still starts at the left.
                  Text(
                    card.title,
                    textDirection: textDirectionOf(card.title),
                    style: TextStyle(
                      color: fg,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                  if (text != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      text,
                      textDirection: textDirectionOf(text),
                      style: TextStyle(
                        color: fg.withValues(alpha: 0.8),
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            for (final button in card.buttons) ...[
              ColoredBox(color: hairline, child: const SizedBox(height: 1)),
              if (button.isReply)
                _ReplyButton(
                  button: button,
                  theme: theme,
                  chosen: chosenReplyId != null && chosenReplyId == button.replyId,
                  dimmed: chosenReplyId != null && chosenReplyId != button.replyId,
                  onPressed: onReply == null
                      ? null
                      : () => onReply!(button.replyId!, button.label),
                )
              else
                _CardButton(button: button, theme: theme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _image(String url, Color fg) {
    final tint = ColoredBox(color: fg.withValues(alpha: 0.06));
    return CachedNetworkImage(
      // Our own uploads arrive as `/uploads/…`, resolved against the API the
      // same way every attachment is.
      imageUrl: EasyLiveChat.instance.resolveUrl(url),
      fit: BoxFit.cover,
      placeholder: (context, _) => tint,
      // A broken or blocked image must never break the card: the space it
      // would have taken stays, marked, so the layout doesn't jump.
      errorWidget: (context, _, __) => Stack(
        fit: StackFit.expand,
        children: [
          tint,
          Icon(
            Icons.broken_image_outlined,
            size: 22,
            color: fg.withValues(alpha: 0.35),
          ),
        ],
      ),
    );
  }
}

class _CardButton extends StatelessWidget {
  final MessageCardButton button;
  final EasyLiveChatTheme theme;

  const _CardButton({required this.button, required this.theme});

  /// Opens in the visitor's browser, never inside the host app: the host has
  /// no business watching where a support link takes someone.
  ///
  /// Only `http:`/`https:` reach the platform — the card was validated when it
  /// was parsed, and [MessageCardButton.uri] checks again. A link that cannot
  /// be opened is a no-op, not a crash inside a message.
  Future<void> _open() async {
    final uri = button.uri;
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // No browser, or the platform refused — nothing useful to show.
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = theme.primary;
    // One node per button — a link, named by its label — rather than folded
    // into the card or into the button beside it.
    return Semantics(
      container: true,
      link: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => unawaited(_open()),
          highlightColor: accent.withValues(alpha: 0.08),
          splashColor: accent.withValues(alpha: 0.12),
          hoverColor: accent.withValues(alpha: 0.08),
          focusColor: accent.withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 11, 14, 11),
            child: Text(
              button.label,
              textAlign: TextAlign.center,
              textDirection: textDirectionOf(button.label),
              style: TextStyle(
                color: accent,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A card's reply button: an answer, so it wears the accent like a quick
/// reply; filled once chosen, quiet while the question has moved on.
class _ReplyButton extends StatelessWidget {
  final MessageCardButton button;
  final EasyLiveChatTheme theme;
  final bool chosen;
  final bool dimmed;
  final VoidCallback? onPressed;

  const _ReplyButton({
    required this.button,
    required this.theme,
    required this.chosen,
    required this.dimmed,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final accent = theme.primary;
    final onAccent =
        accent.computeLuminance() > 0.5 ? const Color(0xFF0F172A) : Colors.white;
    final fg = chosen
        ? onAccent
        : accent.withValues(alpha: onPressed == null || dimmed ? 0.5 : 1);
    return Semantics(
      container: true,
      button: true,
      selected: chosen,
      enabled: onPressed != null,
      child: Material(
        color: chosen ? accent : Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          highlightColor: accent.withValues(alpha: 0.08),
          splashColor: accent.withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 11, 14, 11),
            child: Text(
              button.label,
              textAlign: TextAlign.center,
              textDirection: textDirectionOf(button.label),
              style: TextStyle(
                color: fg,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Two or more cards side by side, swiped through — the web widget's
/// `.msg-carousel`. Each card keeps its own corners and buttons.
class ElcCardCarousel extends StatelessWidget {
  final List<MessageCard> cards;
  final EasyLiveChatTheme theme;

  /// What a screen reader calls the row.
  final String semanticLabel;
  final String? chosenReplyId;
  final void Function(String id, String label)? onReply;

  const ElcCardCarousel({
    super.key,
    required this.cards,
    required this.theme,
    required this.semanticLabel,
    this.chosenReplyId,
    this.onReply,
  });

  static const double _cardWidth = 240;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              ElcMessageCardView(
                card: cards[i],
                theme: theme,
                maxWidth: _cardWidth,
                width: _cardWidth,
                chosenReplyId: chosenReplyId,
                onReply: onReply,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
