/// Link previews: the compact card (site, title, a line of description, a
/// picture) under a message that carries a link.
///
/// The server makes them. It fetches the linked page once, through its SSRF
/// guard, and stores what it found on the message as `metadata.linkPreview` —
/// so the widget, the dashboard and the apps draw the same card from the same
/// data, and no visitor's device ever fetches the linked page to find out what
/// it is. The picture is re-hosted into the workspace's own uploads, so showing
/// it tells the linked site nothing either. A preview usually lands a moment
/// after the message itself, as a `message:updated` that adds it.
///
/// Everything in a preview came from a page someone else wrote, so it is read
/// through [LinkPreview.tryParse] — a port of `parseLinkPreview` in
/// `packages/shared/src/link-preview.ts`: lengths capped, the link `http:` or
/// `https:` only, the picture our own upload or `https:`. Draw the text as
/// text.
library;

import 'package:meta/meta.dart';

import 'web_url.dart';

/// A message's link preview. Read it with `ChatMessage.linkPreview`.
@immutable
class LinkPreview {
  /// The link as it appears in the message: what the card opens. Always one
  /// the web would open as `http:` or `https:` — see [uri].
  final String url;

  /// The page's title, on one line. Never empty.
  final String title;

  /// A line about the page, or null — also when it only repeated the title.
  final String? description;

  /// The site's own name (`og:site_name`), else its host without `www.`.
  final String siteName;

  /// The picture: `/uploads/…` (re-hosted by the server; resolve it with
  /// `EasyLiveChat.resolveUrl`) or an `https:` URL. Null when there is none.
  /// It can still fail to load — draw the card without it then.
  final String? imageUrl;

  const LinkPreview({
    required this.url,
    required this.title,
    this.description,
    required this.siteName,
    this.imageUrl,
  });

  /// The server's caps, in code points (the URL in UTF-16 units, as on the
  /// web).
  static const int maxTitleLength = 200;
  static const int maxDescriptionLength = 300;
  static const int maxSiteNameLength = 80;
  static const int maxUrlLength = 2048;

  /// [url] as the platform should be asked to open it, or null when it is not
  /// a link the web would open. The difference from [url] is only what a
  /// browser quietly repairs (see `MessageCardButton.uri`).
  Uri? get uri {
    final normalized = parseWebUrl(url);
    if (normalized == null) return null;
    final parsed = Uri.tryParse(normalized);
    if (parsed == null) return null;
    return parsed.isScheme('http') || parsed.isScheme('https') ? parsed : null;
  }

  /// A stored preview, checked; null for anything malformed or with nothing
  /// to show (no usable link, no title).
  static LinkPreview? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final rawUrl = raw['url'];
    if (!_isWebUrl(rawUrl)) return null;
    final url = rawUrl as String;
    final title = _clip(raw['title'], maxTitleLength);
    if (title == null) return null;
    final siteName =
        _clip(raw['siteName'], maxSiteNameLength) ?? previewHost(url);
    final description = _clip(raw['description'], maxDescriptionLength);
    final image = raw['imageUrl'];
    return LinkPreview(
      url: url,
      title: title,
      siteName: siteName,
      description:
          description != null && description != title ? description : null,
      imageUrl: isSafeImage(image) ? image as String : null,
    );
  }

  /// A picture a client may load: our own re-hosted upload, or `https:`.
  static bool isSafeImage(Object? v) {
    if (v is! String || v.length > maxUrlLength) return false;
    if (_upload.hasMatch(v) && !v.contains('..')) return true;
    final normalized = parseWebUrl(v);
    return normalized != null && normalized.startsWith('https:');
  }

  /// The host a card names when the site gave no name of its own, `www.`
  /// dropped; empty for something that is not a link.
  static String previewHost(String url) {
    final normalized = parseWebUrl(url);
    if (normalized == null) return '';
    final host = Uri.tryParse(normalized)?.host ?? '';
    return host.replaceFirst(RegExp('^www\\.', caseSensitive: false), '');
  }

  static final RegExp _upload = RegExp(r'^/uploads/[A-Za-z0-9_./-]+$');
  static final RegExp _controls = RegExp('[\u0000-\u001f\u007f]+');
  static final RegExp _spaces = RegExp(r'\s+');
  static final RegExp _trailing = RegExp(r'\s+$');

  static bool _isWebUrl(Object? v) =>
      v is String && v.length <= maxUrlLength && parseWebUrl(v) != null;

  /// One line, capped at [max] code points with an ellipsis — the shared
  /// `clip`, exactly: a page title with a newline in it is still one title.
  static String? _clip(Object? v, int max) {
    if (v is! String) return null;
    final one = v
        .replaceAll(_controls, ' ')
        .replaceAll(_spaces, ' ')
        .replaceAll(RegExp(r'^\s+|\s+$'), '');
    if (one.isEmpty) return null;
    final chars = one.runes.toList();
    if (chars.length <= max) return one;
    final head = String.fromCharCodes(chars.take(max - 1));
    return '${head.replaceAll(_trailing, '')}…';
  }

  @override
  bool operator ==(Object other) =>
      other is LinkPreview &&
      other.url == url &&
      other.title == title &&
      other.description == description &&
      other.siteName == siteName &&
      other.imageUrl == imageUrl;

  @override
  int get hashCode => Object.hash(url, title, description, siteName, imageUrl);

  @override
  String toString() => 'LinkPreview($siteName: $title → $url)';
}
