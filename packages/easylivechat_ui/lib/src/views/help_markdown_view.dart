import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../help/help_markdown.dart';

/// Opens a link tapped inside a help article. The URI has already been checked
/// (http(s), mailto: or tel: only).
typedef ElcOpenLink = Future<void> Function(Uri uri);

/// Renders a help article's markdown body ([HelpArticle.body]) as native
/// widgets — no HTML, no WebView.
///
/// Supports the help dialect only: headings, paragraphs with line breaks,
/// bulleted and numbered lists, quotes, fenced code, rules, **bold**, *italic*,
/// `code`, links (http(s)/mailto:/tel:) and images (http(s)). Anything else —
/// raw HTML included — is shown as the characters it is.
///
/// Lays out along the ambient [Directionality] (or [textDirection]), so lists
/// and quotes put their marker on the reading side in RTL.
class ElcHelpMarkdown extends StatefulWidget {
  /// The markdown source.
  final String markdown;

  /// Body text colour; headings use it too.
  final Color textColor;

  /// Colour of tappable links.
  final Color linkColor;

  /// A raised-surface colour for code and quotes.
  final Color surfaceColor;

  /// Called with a tapped link. When null the platform handler opens it
  /// (browser, mail app, dialer) via `url_launcher`.
  final ElcOpenLink? onOpenLink;

  /// Direction of the article itself — pass it when the article's language
  /// differs from the app's (an Arabic article in an English app). Defaults to
  /// the ambient direction.
  final TextDirection? textDirection;

  const ElcHelpMarkdown({
    super.key,
    required this.markdown,
    required this.textColor,
    required this.linkColor,
    required this.surfaceColor,
    this.onOpenLink,
    this.textDirection,
  });

  @override
  State<ElcHelpMarkdown> createState() => _ElcHelpMarkdownState();
}

class _ElcHelpMarkdownState extends State<ElcHelpMarkdown> {
  late List<HelpBlock> _blocks = parseHelpMarkdown(widget.markdown);

  /// Every recognizer must be disposed, so they are owned here rather than
  /// built inline — one created in `build` and dropped leaks.
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void didUpdateWidget(covariant ElcHelpMarkdown old) {
    super.didUpdateWidget(old);
    if (old.markdown != widget.markdown) {
      _blocks = parseHelpMarkdown(widget.markdown);
    }
  }

  @override
  void dispose() {
    _releaseRecognizers();
    super.dispose();
  }

  void _releaseRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  Future<void> _open(String href) async {
    final uri = Uri.tryParse(href);
    if (uri == null) return;
    final hook = widget.onOpenLink;
    try {
      if (hook != null) {
        await hook(uri);
      } else {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // No handler / refused: a link that cannot open is a no-op, not a crash.
    }
  }

  TextStyle get _body => TextStyle(
        color: widget.textColor,
        fontSize: 15,
        height: 1.5,
      );

  @override
  Widget build(BuildContext context) {
    // Rebuilt every build (the spans are), so release the last generation.
    _releaseRecognizers();
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _blocksToWidgets(_blocks),
    );
    final dir = widget.textDirection;
    return dir == null ? column : Directionality(textDirection: dir, child: column);
  }

  List<Widget> _blocksToWidgets(List<HelpBlock> blocks) {
    final out = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      if (i > 0) out.add(const SizedBox(height: 12));
      out.add(_block(blocks[i]));
    }
    return out;
  }

  Widget _block(HelpBlock b) {
    switch (b) {
      case HelpHeading(:final level, :final children):
        final size = switch (level) { 1 => 21.0, 2 => 18.0, _ => 16.0 };
        return Semantics(
          header: true,
          child: Text.rich(
            TextSpan(children: _inline(children)),
            style: _body.copyWith(
                fontSize: size, fontWeight: FontWeight.w700, height: 1.3),
          ),
        );
      case HelpParagraph(:final children):
        return Text.rich(TextSpan(children: _inline(children)), style: _body);
      case HelpList(:final ordered, :final start, :final items):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var n = 0; n < items.length; n++)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4, bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: ordered ? 28 : 18,
                      child: Text(
                        ordered ? '${start + n}.' : '•',
                        style: _body,
                      ),
                    ),
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: _inline(items[n])),
                        style: _body,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      case HelpQuote(:final children):
        return Container(
          padding: const EdgeInsetsDirectional.only(start: 12, top: 2, bottom: 2),
          decoration: BoxDecoration(
            border: BorderDirectional(
              start: BorderSide(
                  color: widget.textColor.withValues(alpha: 0.25), width: 3),
            ),
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: widget.textColor.withValues(alpha: 0.8)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _blocksToWidgets(children),
            ),
          ),
        );
      case HelpCodeBlock(:final text):
        // Code reads left to right whatever the article's language.
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.surfaceColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                text,
                style: _body.copyWith(
                    fontFamily: 'monospace', fontSize: 13, height: 1.4),
              ),
            ),
          ),
        );
      case HelpRule():
        return Divider(
            height: 1, color: widget.textColor.withValues(alpha: 0.12));
    }
  }

  List<InlineSpan> _inline(List<HelpInline> nodes, {TextStyle? style}) {
    final out = <InlineSpan>[];
    for (final n in nodes) {
      switch (n) {
        case HelpText(:final text):
          out.add(TextSpan(text: text, style: style));
        case HelpBreak():
          out.add(TextSpan(text: '\n', style: style));
        case HelpStrong(:final children):
          final s = (style ?? const TextStyle())
              .copyWith(fontWeight: FontWeight.w700);
          out.add(TextSpan(style: s, children: _inline(children, style: s)));
        case HelpEm(:final children):
          final s =
              (style ?? const TextStyle()).copyWith(fontStyle: FontStyle.italic);
          out.add(TextSpan(style: s, children: _inline(children, style: s)));
        case HelpCode(:final text):
          out.add(TextSpan(
            text: text,
            style: (style ?? const TextStyle()).copyWith(
              fontFamily: 'monospace',
              fontSize: 13.5,
              backgroundColor: widget.surfaceColor,
            ),
          ));
        case HelpLink(:final href, :final children):
          final recognizer = TapGestureRecognizer()
            ..onTap = () => unawaited(_open(href));
          _recognizers.add(recognizer);
          final s = (style ?? const TextStyle()).copyWith(
            color: widget.linkColor,
            decoration: TextDecoration.underline,
            decorationColor: widget.linkColor,
            fontWeight: FontWeight.w600,
          );
          out.add(TextSpan(
            text: helpInlineText(children),
            style: s,
            recognizer: recognizer,
            mouseCursor: SystemMouseCursors.click,
          ));
        case HelpImage(:final src, :final alt):
          out.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Semantics(
              image: true,
              label: alt.isEmpty ? null : alt,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: src,
                    fit: BoxFit.contain,
                    errorWidget: (_, __, ___) => Text(alt, style: _body),
                  ),
                ),
              ),
            ),
          ));
      }
    }
    return out;
  }
}
