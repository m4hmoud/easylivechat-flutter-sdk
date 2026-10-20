import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easylivechat/easylivechat.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../bidi.dart';
import '../theme.dart';

/// The card under a message with a link in it — the native analog of the web
/// widget's `components/LinkPreview.tsx`: the site, the page's title, a line
/// of its description, and its picture when the server could re-host one.
///
/// Made by the server and read through `LinkPreview.tryParse`, because the
/// page it describes is a stranger's: text is drawn as text, the link is only
/// ever `http:`/`https:` and opens in the visitor's browser — never inside the
/// host app — and the picture is our own upload or `https:`. A picture that
/// will not load simply goes, and the card reads as words alone.
class ElcLinkPreviewCard extends StatefulWidget {
  final LinkPreview preview;
  final EasyLiveChatTheme theme;

  /// The widest a bubble may be on this screen; the card is 300 wide, or this
  /// when the screen is narrower — the web's `min(300px, 100%)`.
  final double maxWidth;

  const ElcLinkPreviewCard({
    super.key,
    required this.preview,
    required this.theme,
    required this.maxWidth,
  });

  @override
  State<ElcLinkPreviewCard> createState() => _ElcLinkPreviewCardState();
}

class _ElcLinkPreviewCardState extends State<ElcLinkPreviewCard> {
  bool _imageFailed = false;

  @override
  void didUpdateWidget(ElcLinkPreviewCard old) {
    super.didUpdateWidget(old);
    if (old.preview.imageUrl != widget.preview.imageUrl) _imageFailed = false;
  }

  Future<void> _open() async {
    final uri = widget.preview.uri;
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // No browser, or the platform refused — nothing useful to show.
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final p = widget.preview;
    final muted = t.text.withValues(alpha: t.isDark ? 0.72 : 0.62);
    final image = p.imageUrl != null && !_imageFailed ? p.imageUrl : null;
    final radius = BorderRadius.circular(10);

    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Each line faces the way its own words read (`dir="auto"`).
        Text(
          p.siteName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textDirection: textDirectionOf(p.siteName),
          style: TextStyle(fontSize: 12, height: 1.3, color: muted),
        ),
        const SizedBox(height: 2),
        Text(
          p.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textDirection: textDirectionOf(p.title),
          style: TextStyle(
            fontSize: 14,
            height: 1.35,
            fontWeight: FontWeight.w600,
            color: t.text,
          ),
        ),
        if (p.description != null) ...[
          const SizedBox(height: 2),
          Text(
            p.description!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textDirection: textDirectionOf(p.description!),
            style: TextStyle(fontSize: 13, height: 1.4, color: muted),
          ),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SizedBox(
        width: math.min(300, widget.maxWidth),
        child: Semantics(
          link: true,
          child: Material(
            color: t.surface,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(color: t.text.withValues(alpha: 0.12)),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => unawaited(_open()),
              highlightColor: t.text.withValues(alpha: 0.05),
              splashColor: t.text.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (image != null) ...[
                      // Decorative, as on the web (`alt=""`): the title says
                      // what the page is.
                      ExcludeSemantics(child: _image(image)),
                      const SizedBox(width: 10),
                    ],
                    Expanded(child: text),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _image(String url) {
    final tint = ColoredBox(
        color: widget.theme.text.withValues(alpha: 0.06),
        child: const SizedBox(width: 64, height: 64));
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 64,
        height: 64,
        child: CachedNetworkImage(
          // Our own uploads arrive as `/uploads/…`, resolved against the API
          // the same way every attachment is.
          imageUrl: EasyLiveChat.instance.resolveUrl(url),
          fit: BoxFit.cover,
          placeholder: (context, _) => tint,
          errorWidget: (context, _, __) {
            // The picture goes, and the words take its room.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_imageFailed) setState(() => _imageFailed = true);
            });
            return tint;
          },
        ),
      ),
    );
  }
}
