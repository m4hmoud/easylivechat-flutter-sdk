import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Auto-linking for message bodies: URLs, email addresses and phone numbers
/// inside plain text become tappable.
///
/// Message bodies are **untrusted visitor/agent text**, never markup — the web
/// widget renders them as text nodes for exactly that reason. So instead of
/// parsing anything, we scan the string for entity shapes and hand back spans;
/// the text itself is still rendered verbatim.
///
/// Tapping opens the platform handler (`https:` → browser, `mailto:` → mail
/// app, `tel:` → dialer). We deliberately do **not** call `canLaunchUrl` first:
/// it would force every host app to declare `LSApplicationQueriesSchemes` in
/// its `Info.plist` just to make a link tappable. `launchUrl` alone needs no
/// host configuration, and a device with no handler simply does nothing.

/// What kind of entity a detected span is.
enum ElcLinkKind { url, email, phone }

/// One auto-detected entity, as a half-open `[start, end)` range over the
/// original body plus the resolved [uri] to open.
@immutable
class ElcLinkSpan {
  final int start;
  final int end;
  final ElcLinkKind kind;

  /// The matched text exactly as it appears in the body (what we display).
  final String text;

  const ElcLinkSpan({
    required this.start,
    required this.end,
    required this.kind,
    required this.text,
  });

  /// The URI to hand to the platform. `null` when the match cannot be turned
  /// into a launchable URI (malformed input) — such a span renders as plain
  /// text rather than a dead link.
  Uri? get uri {
    switch (kind) {
      case ElcLinkKind.url:
        final hasScheme = text.startsWith('http://') || text.startsWith('https://');
        return Uri.tryParse(hasScheme ? text : 'https://$text');
      case ElcLinkKind.email:
        return Uri.tryParse('mailto:$text');
      case ElcLinkKind.phone:
        // Keep only what a dialer accepts: a leading `+` and digits.
        final digits = text.replaceAll(RegExp(r'[^\d+]'), '');
        final normalized = digits.startsWith('+')
            ? '+${digits.substring(1).replaceAll('+', '')}'
            : digits.replaceAll('+', '');
        if (normalized.replaceAll('+', '').isEmpty) return null;
        return Uri.tryParse('tel:$normalized');
    }
  }

  @override
  String toString() => 'ElcLinkSpan($kind, $start..$end, "$text")';
}

// ─────────────────────────────────────────────────────────────────────────────
//  Detection
// ─────────────────────────────────────────────────────────────────────────────

/// TLDs we are willing to auto-link **without** a scheme or `www.` prefix.
///
/// A bare-domain rule of "label dot 2+ letters" turns `main.py`, `photo.png`
/// and `notes.txt` into links, so scheme-less matching is restricted to an
/// explicit list. Anything outside it still links when written as
/// `https://…` or `www.…`. Extend as needed — order is irrelevant.
const Set<String> _bareLinkTlds = {
  // generic
  'com', 'net', 'org', 'info', 'biz', 'edu', 'gov', 'mil', 'int',
  'io', 'co', 'ai', 'app', 'dev', 'me', 'tv', 'cc', 'xyz', 'online',
  'site', 'shop', 'store', 'tech', 'cloud', 'live', 'link', 'page',
  'blog', 'news', 'space', 'website', 'agency', 'company', 'digital',
  'email', 'group', 'life', 'media', 'network', 'services', 'solutions',
  'support', 'systems', 'today', 'tools', 'world', 'zone', 'chat',
  // country / regional codes in common use for the product's markets
  'uk', 'de', 'fr', 'es', 'it', 'nl', 'se', 'dk', 'fi', 'no', 'ie',
  'pt', 'gr', 'ch', 'at', 'be', 'cz', 'hu', 'ro', 'bg', 'ua', 'ru',
  'tr', 'iq', 'ir', 'sa', 'ae', 'qa', 'kw', 'bh', 'om', 'jo', 'lb',
  'eg', 'ma', 'dz', 'tn', 'ly', 'sd', 'ye', 'ps', 'il',
  'in', 'pk', 'bd', 'lk', 'np', 'cn', 'jp', 'kr', 'hk', 'tw', 'sg',
  'my', 'th', 'vn', 'ph', 'id', 'au', 'nz', 'ca', 'us', 'mx', 'br',
  'ar', 'cl', 'pe', 'za', 'ng', 'ke', 'gh', 'et', 'tz', 'ug', 'eu',
};

/// Matched in priority order at each position: scheme/`www.` URL, then email,
/// then bare domain, then phone. Ordering matters — it stops the domain half
/// of `a@b.com` being linked separately, and stops a URL's digits being read
/// as a phone number.
final RegExp _entityPattern = RegExp(
  // 1 — URL with an explicit scheme or a `www.` prefix.
  r'(?<surl>(?:https?://|www\.)[^\s<>"' "'" r'`‏‎]+)'
  r'|'
  // 2 — email address.
  r'(?<email>[A-Za-z0-9._%+\-]+@[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?)*\.[A-Za-z]{2,24})'
  r'|'
  // 3 — bare domain (TLD validated against `_bareLinkTlds` below), optional
  //     path/query/fragment. Not preceded by `@` or a word char so the tail of
  //     an unmatched email or a filename mid-word is left alone.
  r'(?<!(?:[\w@.\-]))'
  r'(?<bare>(?:[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?\.)+(?<tld>[A-Za-z]{2,24})'
  r'(?![A-Za-z0-9\-])'
  r'(?:[/?#][^\s<>"' "'" r'`‏‎]*)?)'
  r'|'
  // 4 — phone number: optional `+` or area-code bracket, then digits with
  //     common separators. Shape validated in `_isPhoneLike`.
  r'(?<!\w)(?<!\+)(?<phone>\+?\(?\d[\d\s().\-]{5,20}\d)(?!\w)',
  unicode: true,
);

/// Trailing characters that are almost always sentence punctuation rather than
/// part of the link (`See https://x.com/a.` → the `.` is not in the path).
const String _trailingPunctuation = '.,;:!?"\'`»”’)]}>*_~';

/// Find every auto-linkable entity in [input].
///
/// Pure and side-effect free so the matching rules can be unit-tested without
/// a widget tree. Returns spans in ascending, non-overlapping order.
List<ElcLinkSpan> detectLinks(String input) {
  if (input.isEmpty) return const [];
  final spans = <ElcLinkSpan>[];

  for (final m in _entityPattern.allMatches(input)) {
    final surl = m.namedGroup('surl');
    final email = m.namedGroup('email');
    final bare = m.namedGroup('bare');
    final phone = m.namedGroup('phone');

    String raw;
    ElcLinkKind kind;
    if (surl != null) {
      raw = surl;
      kind = ElcLinkKind.url;
    } else if (email != null) {
      raw = email;
      kind = ElcLinkKind.email;
    } else if (bare != null) {
      final tld = (m.namedGroup('tld') ?? '').toLowerCase();
      if (!_bareLinkTlds.contains(tld)) continue;
      raw = bare;
      kind = ElcLinkKind.url;
    } else if (phone != null) {
      if (!_isPhoneLike(phone)) continue;
      raw = phone;
      kind = ElcLinkKind.phone;
    } else {
      continue;
    }

    // Every alternative spans the whole match (the lookarounds are zero-width
    // and `tld` nests inside `bare`), so the match start is the span start —
    // adjusted below if we shave a leading character off.
    var start = m.start;
    var text = raw;
    if (kind == ElcLinkKind.url) {
      text = _trimUrlTail(text);
    } else if (kind == ElcLinkKind.phone && text.startsWith('(') && !text.contains(')')) {
      // `(555-1234)` — the opening bracket is the sentence's, not an area
      // code's, since its partner fell outside the match.
      text = text.substring(1);
      start += 1;
    }
    if (text.isEmpty) continue;

    spans.add(ElcLinkSpan(
      start: start,
      end: start + text.length,
      kind: kind,
      text: text,
    ));
  }
  return spans;
}

/// Strip trailing punctuation that belongs to the sentence, keeping a closing
/// bracket when the link itself opened one (`…/Foo_(bar)`).
String _trimUrlTail(String url) {
  var end = url.length;
  while (end > 0) {
    final ch = url[end - 1];
    if (!_trailingPunctuation.contains(ch)) break;
    if (ch == ')' || ch == ']' || ch == '}') {
      final open = ch == ')' ? '(' : (ch == ']' ? '[' : '{');
      final body = url.substring(0, end);
      final opens = body.split(open).length - 1;
      final closes = body.split(ch).length - 1;
      if (opens >= closes) break; // balanced — the bracket is part of the URL
    }
    end--;
  }
  return url.substring(0, end);
}

/// ISO-ish dates (`2026-07-30`) have a phone's digit count and separators but
/// are never phone numbers.
final RegExp _isoDate = RegExp(r'^\d{4}-\d{1,2}-\d{1,2}$');

/// Is this digit run actually dialable?
///
/// E.164 allows up to 15 digits; below 7 we are looking at an order number or
/// a quantity. A bare digit run with no `+` and no separator is too ambiguous
/// to link unless it is long enough to only plausibly be a phone number.
bool _isPhoneLike(String candidate) {
  final trimmed = candidate.trim();
  // The date check runs on the digits themselves — a match may have swallowed
  // a sentence bracket (`(2026-07-30`) that would otherwise defeat it.
  if (_isoDate.hasMatch(trimmed.replaceAll(RegExp(r'^[(\s]+|[)\s]+$'), ''))) {
    return false;
  }

  final digitCount = trimmed.replaceAll(RegExp(r'\D'), '').length;
  if (digitCount < 7 || digitCount > 15) return false;

  final hasPlus = trimmed.startsWith('+');
  final hasSeparator = RegExp(r'[\s().\-]').hasMatch(trimmed);
  if (!hasPlus && !hasSeparator && digitCount < 9) return false;

  // `1.5.3` / `10.20.30` — version-ish runs separated only by single dots.
  if (!hasPlus && RegExp(r'^\d{1,3}(?:\.\d{1,3}){2,}$').hasMatch(trimmed)) {
    return false;
  }
  return true;
}

/// Open [span]'s target with the platform handler. Never throws — a link that
/// cannot be opened is a no-op, not a crash inside a message bubble.
Future<void> openElcLink(ElcLinkSpan span) async {
  final uri = span.uri;
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // No handler installed / platform refused — nothing useful to show.
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Widget
// ─────────────────────────────────────────────────────────────────────────────

/// Renders [text] with detected URLs / emails / phone numbers as tappable,
/// underlined runs styled by [linkColor]. Plain text renders identically to a
/// bare [Text] when nothing is detected.
class LinkifiedText extends StatefulWidget {
  final String text;
  final TextStyle style;

  /// Color for the tappable runs. Kept separate from [style] so a bubble can
  /// keep its own foreground contrast (a link on the accent-colored customer
  /// bubble must not switch to the accent color).
  final Color linkColor;

  const LinkifiedText({
    super.key,
    required this.text,
    required this.style,
    required this.linkColor,
  });

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  /// Recognizers are owned here (not built inline) because every one of them
  /// must be disposed — a `TapGestureRecognizer` created in `build` and dropped
  /// leaks and trips the framework's debug leak assert.
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  void _handleTap(ElcLinkSpan span) => unawaited(openElcLink(span));

  @override
  Widget build(BuildContext context) {
    final spans = detectLinks(widget.text);
    if (spans.isEmpty) {
      return Text(widget.text, style: widget.style);
    }

    // Rebuilt on every build (the span set can change when the body does), so
    // the previous generation is released first.
    _disposeRecognizers();

    final linkStyle = widget.style.copyWith(
      color: widget.linkColor,
      decoration: TextDecoration.underline,
      decorationColor: widget.linkColor,
      fontWeight: FontWeight.w600,
    );

    final children = <InlineSpan>[];
    var cursor = 0;
    for (final span in spans) {
      if (span.start > cursor) {
        children.add(TextSpan(text: widget.text.substring(cursor, span.start)));
      }
      final recognizer = TapGestureRecognizer()..onTap = () => _handleTap(span);
      _recognizers.add(recognizer);
      children.add(TextSpan(
        text: span.text,
        style: linkStyle,
        recognizer: recognizer,
        mouseCursor: SystemMouseCursors.click,
        semanticsLabel: span.text,
      ));
      cursor = span.end;
    }
    if (cursor < widget.text.length) {
      children.add(TextSpan(text: widget.text.substring(cursor)));
    }

    return Text.rich(TextSpan(style: widget.style, children: children));
  }
}
