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
/// The card itself comes from `ChatMessage.card`, which has already run the
/// server's validator: every button is an `http:`/`https:` link.
class ElcMessageCardView extends StatelessWidget {
  final MessageCard card;
  final EasyLiveChatTheme theme;

  /// The widest a bubble may be on this screen. The card is 280 wide, or this
  /// when the screen is narrower — the web's `min(280px, 100%)`.
  final double maxWidth;

  const ElcMessageCardView({
    super.key,
    required this.card,
    required this.theme,
    required this.maxWidth,
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
      width: math.min(_width, maxWidth),
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
