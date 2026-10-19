/// The markdown a help article is written in, parsed to a tree.
///
/// A Dart port of `packages/shared/src/help-markdown.ts` — keep the two in
/// step. Every surface draws this tree with its own elements and none builds
/// markup from a string: an article is tenant-typed (or pasted from somewhere),
/// so raw HTML in it is shown as the characters it is, and there is no WebView.
///
/// A deliberately small dialect: headings, paragraphs (a single newline is a
/// line break, as people expect from a text box), bulleted and numbered lists,
/// quotes, fenced code, a rule, **bold**, *italic*, `code`, [links](https://…)
/// and ![images](https://…). Links are http(s), mailto: and tel: only, images
/// http(s) only — anything else stays text, so `javascript:` can never become
/// something to tap.
///
/// Linear in the input apart from the delimiter look-ahead, which is capped,
/// so a pathological article cannot stall the UI thread.
library;

import 'package:flutter/foundation.dart' show immutable;

// ── tree ─────────────────────────────────────────────────────────────────────

@immutable
sealed class HelpInline {
  const HelpInline();
}

final class HelpText extends HelpInline {
  final String text;
  const HelpText(this.text);
}

final class HelpStrong extends HelpInline {
  final List<HelpInline> children;
  const HelpStrong(this.children);
}

final class HelpEm extends HelpInline {
  final List<HelpInline> children;
  const HelpEm(this.children);
}

final class HelpCode extends HelpInline {
  final String text;
  const HelpCode(this.text);
}

final class HelpLink extends HelpInline {
  /// Already checked by [safeHelpHref].
  final String href;
  final List<HelpInline> children;
  const HelpLink(this.href, this.children);
}

final class HelpImage extends HelpInline {
  /// Already checked by [safeHelpImage].
  final String src;
  final String alt;
  const HelpImage(this.src, this.alt);
}

final class HelpBreak extends HelpInline {
  const HelpBreak();
}

@immutable
sealed class HelpBlock {
  const HelpBlock();
}

final class HelpHeading extends HelpBlock {
  /// 1–3; deeper markdown headings are drawn as 3.
  final int level;
  final List<HelpInline> children;
  const HelpHeading(this.level, this.children);
}

final class HelpParagraph extends HelpBlock {
  final List<HelpInline> children;
  const HelpParagraph(this.children);
}

final class HelpList extends HelpBlock {
  final bool ordered;
  final int start;
  final List<List<HelpInline>> items;
  const HelpList({required this.ordered, required this.start, required this.items});
}

final class HelpQuote extends HelpBlock {
  final List<HelpBlock> children;
  const HelpQuote(this.children);
}

final class HelpCodeBlock extends HelpBlock {
  final String text;
  const HelpCodeBlock(this.text);
}

final class HelpRule extends HelpBlock {
  const HelpRule();
}

// ── limits + safety ──────────────────────────────────────────────────────────

/// How far ahead a closing `**` / `]` / `)` is looked for.
const _lookahead = 2000;

/// Emphasis inside emphasis inside a link… stops here and is shown as text.
const _maxInlineDepth = 4;
const _maxQuoteDepth = 2;

const _linkSchemes = {'http', 'https', 'mailto', 'tel'};

/// [url] when it is safe to put behind a link (http(s), mailto:, tel:), else
/// null.
String? safeHelpHref(String url) {
  final u = url.trim();
  if (u.isEmpty) return null;
  final parsed = Uri.tryParse(u);
  if (parsed == null || !parsed.hasScheme) return null;
  final scheme = parsed.scheme.toLowerCase();
  if (!_linkSchemes.contains(scheme)) return null;
  if ((scheme == 'http' || scheme == 'https') && parsed.host.isEmpty) {
    return null;
  }
  if ((scheme == 'mailto' || scheme == 'tel') && parsed.path.isEmpty) {
    return null;
  }
  return u;
}

/// [url] when it is safe to load as an image (http(s) only), else null.
String? safeHelpImage(String url) {
  final u = url.trim();
  final parsed = Uri.tryParse(u);
  if (parsed == null || !parsed.hasScheme) return null;
  final scheme = parsed.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  return parsed.host.isEmpty ? null : u;
}

const _escapable = r'\`*_[]()#!>+-.~|{}';
final _word = RegExp(r'[\p{L}\p{N}]', unicode: true);
final _space = RegExp(r'\s');

bool _isSpace(String? ch) => ch != null && _space.hasMatch(ch);
bool _isWord(String? ch) => ch != null && _word.hasMatch(ch);
String? _at(String s, int i) => (i >= 0 && i < s.length) ? s[i] : null;

// ── bare links (shared linkify.ts) ───────────────────────────────────────────

/// Only `http(s)` with an explicit scheme: `javascript:` and `data:` never
/// match at all, rather than matching and then being filtered.
final _urlPattern = RegExp(r'''https?://[^\s<>"'`]+''', caseSensitive: false);

bool _unbalanced(String s, String open, String close) =>
    close.allMatches(s).length > open.allMatches(s).length;

/// Trailing characters that read as punctuation rather than address.
String _trimTrailing(String url) {
  var out = url;
  while (out.isNotEmpty) {
    final last = out[out.length - 1];
    if ('.,;:!?"\''.contains(last)) {
      out = out.substring(0, out.length - 1);
      continue;
    }
    if (last == ')' && _unbalanced(out, '(', ')')) {
      out = out.substring(0, out.length - 1);
      continue;
    }
    if (last == ']' && _unbalanced(out, '[', ']')) {
      out = out.substring(0, out.length - 1);
      continue;
    }
    break;
  }
  return out;
}

bool _safeBareHref(String url) {
  final u = Uri.tryParse(url);
  return u != null &&
      (u.scheme == 'http' || u.scheme == 'https') &&
      u.host.isNotEmpty;
}

void _pushText(List<HelpInline> out, String text, bool inLink) {
  if (text.isEmpty) return;
  if (inLink || !text.contains('://')) {
    out.add(HelpText(text));
    return;
  }
  var last = 0;
  var linked = false;
  for (final m in _urlPattern.allMatches(text)) {
    final href = _trimTrailing(m.group(0)!);
    if (!_safeBareHref(href)) continue;
    if (m.start > last) out.add(HelpText(text.substring(last, m.start)));
    out.add(HelpLink(href, [HelpText(href)]));
    // Whatever was trimmed is punctuation and belongs to the sentence.
    last = m.start + href.length;
    linked = true;
  }
  if (!linked) {
    out.add(HelpText(text));
    return;
  }
  if (last < text.length) out.add(HelpText(text.substring(last)));
}

// ── inline ───────────────────────────────────────────────────────────────────

class _LinkMatch {
  final String text;
  final String url;
  final int end;
  const _LinkMatch(this.text, this.url, this.end);
}

/// `[text](url)` starting at [i] (which holds `[`), or null.
_LinkMatch? _matchLink(String s, int i) {
  var depth = 0;
  var close = -1;
  final limit = s.length < i + _lookahead ? s.length : i + _lookahead;
  for (var j = i; j < limit; j++) {
    final ch = s[j];
    if (ch == r'\') {
      j++;
      continue;
    }
    if (ch == '[') {
      depth++;
    } else if (ch == ']') {
      depth--;
      if (depth == 0) {
        close = j;
        break;
      }
    }
  }
  if (close < 0 || _at(s, close + 1) != '(') return null;
  var parens = 0;
  var end = -1;
  final urlLimit = s.length < close + 2 + _lookahead
      ? s.length
      : close + 2 + _lookahead;
  for (var j = close + 2; j < urlLimit; j++) {
    final ch = s[j];
    if (ch == '\n') return null;
    if (ch == '(') {
      parens++;
    } else if (ch == ')') {
      if (parens == 0) {
        end = j;
        break;
      }
      parens--;
    }
  }
  if (end < 0) return null;
  // `(url "title")` — the title is dropped; the address is the first word.
  final words = s.substring(close + 2, end).trim().split(RegExp(r'\s+'));
  final url = words.isEmpty ? '' : words.first;
  return _LinkMatch(
    s.substring(i + 1, close),
    url.replaceAll(RegExp(r'^<|>$'), ''),
    end + 1,
  );
}

/// The index of the [delim] that closes an emphasis opened before [from], or
/// -1.
int _findClose(String s, int from, String delim) {
  final limit = s.length < from + _lookahead ? s.length : from + _lookahead;
  var j = s.indexOf(delim, from + 1);
  while (j != -1 && j < limit) {
    final before = _at(s, j - 1);
    final after = _at(s, j + delim.length);
    final rightFlanking = before != null && !_isSpace(before);
    // `**` is not closed by the first half of a `***`, nor `*` by half a `**`.
    final clean = delim.length == 2 ||
        (_at(s, j + 1) != delim[0] && before != delim[0]);
    final wordEnd = delim[0] != '_' || after == null || !_isWord(after);
    if (rightFlanking &&
        clean &&
        wordEnd &&
        !s.substring(from, j).contains('\n\n')) {
      return j;
    }
    j = s.indexOf(delim, j + 1);
  }
  return -1;
}

List<HelpInline> _parseInline(String s, int depth, bool inLink) {
  final out = <HelpInline>[];
  final buf = StringBuffer();
  void flush() {
    _pushText(out, buf.toString(), inLink);
    buf.clear();
  }

  List<HelpInline> nested(String text, bool link) => depth < _maxInlineDepth
      ? _parseInline(text, depth + 1, link)
      : [HelpText(text)];

  var i = 0;
  while (i < s.length) {
    final ch = s[i];

    if (ch == r'\' && i + 1 < s.length && _escapable.contains(s[i + 1])) {
      buf.write(s[i + 1]);
      i += 2;
      continue;
    }

    if (ch == '`') {
      final end = s.indexOf('`', i + 1);
      if (end > i + 1 && end - i < _lookahead) {
        flush();
        out.add(HelpCode(s.substring(i + 1, end)));
        i = end + 1;
        continue;
      }
    }

    if (ch == '!' && _at(s, i + 1) == '[') {
      final m = _matchLink(s, i + 1);
      final src = m == null ? null : safeHelpImage(m.url);
      if (m != null && src != null) {
        flush();
        out.add(HelpImage(src, m.text.trim()));
        i = m.end;
        continue;
      }
    }

    if (ch == '[' && !inLink) {
      final m = _matchLink(s, i);
      final href = m == null ? null : safeHelpHref(m.url);
      if (m != null && href != null) {
        flush();
        final children = nested(m.text, true);
        out.add(HelpLink(href, children.isEmpty ? [HelpText(href)] : children));
        i = m.end;
        continue;
      }
    }

    if (ch == '*' || ch == '_') {
      final isDouble = _at(s, i + 1) == ch;
      final delim = isDouble ? '$ch$ch' : ch;
      final after = _at(s, i + delim.length);
      final before = _at(s, i - 1);
      // snake_case and 2*3*4 are words and sums, not emphasis.
      final intraword = ch == '_' && _isWord(before);
      if (after != null && !_isSpace(after) && !intraword) {
        final close = _findClose(s, i + delim.length - 1, delim);
        if (close > i + delim.length - 1) {
          flush();
          final inner = nested(s.substring(i + delim.length, close), inLink);
          out.add(isDouble ? HelpStrong(inner) : HelpEm(inner));
          i = close + delim.length;
          continue;
        }
      }
      // An unmatched delimiter is just a character; a run stays together.
      buf.write(delim);
      i += delim.length;
      continue;
    }

    if (ch == '\n') {
      flush();
      out.add(const HelpBreak());
      i++;
      continue;
    }

    buf.write(ch);
    i++;
  }
  flush();
  return out;
}

// ── blocks ───────────────────────────────────────────────────────────────────

final _fence = RegExp(r'^\s{0,3}(```|~~~)');
final _heading = RegExp(r'^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$');
final _rule = RegExp(r'^\s{0,3}([-*_])(\s*\1){2,}\s*$');
final _quote = RegExp(r'^\s{0,3}>\s?(.*)$');
final _bullet = RegExp(r'^\s{0,3}[-*+]\s+(.*)$');
final _numbered = RegExp(r'^\s{0,3}(\d{1,9})[.)]\s+(.*)$');
final _indented = RegExp(r'^\s{2,}');

bool _startsBlock(String line) =>
    _fence.hasMatch(line) ||
    _heading.hasMatch(line) ||
    _rule.hasMatch(line) ||
    _quote.hasMatch(line) ||
    _bullet.hasMatch(line) ||
    _numbered.hasMatch(line);

List<HelpBlock> _parseBlocks(List<String> lines, int quoteDepth) {
  final blocks = <HelpBlock>[];
  var i = 0;
  while (i < lines.length) {
    final line = lines[i];

    if (line.trim().isEmpty) {
      i++;
      continue;
    }

    final fence = _fence.firstMatch(line);
    if (fence != null) {
      final marker = fence.group(1)!;
      final body = <String>[];
      i++;
      while (i < lines.length && !lines[i].trimLeft().startsWith(marker)) {
        body.add(lines[i++]);
      }
      i++; // the closing fence, or the end
      blocks.add(HelpCodeBlock(body.join('\n')));
      continue;
    }

    final heading = _heading.firstMatch(line);
    if (heading != null) {
      final level = heading.group(1)!.length.clamp(1, 3);
      blocks.add(HelpHeading(level, _parseInline(heading.group(2)!, 0, false)));
      i++;
      continue;
    }

    if (_rule.hasMatch(line)) {
      blocks.add(const HelpRule());
      i++;
      continue;
    }

    if (_quote.hasMatch(line)) {
      final inner = <String>[];
      while (i < lines.length) {
        final m = _quote.firstMatch(lines[i]);
        if (m == null) break;
        inner.add(m.group(1)!);
        i++;
      }
      blocks.add(HelpQuote(quoteDepth < _maxQuoteDepth
          ? _parseBlocks(inner, quoteDepth + 1)
          : [HelpParagraph(_parseInline(inner.join('\n'), 0, false))]));
      continue;
    }

    final bullet = _bullet.firstMatch(line);
    final numbered = bullet == null ? _numbered.firstMatch(line) : null;
    if (bullet != null || numbered != null) {
      final ordered = numbered != null;
      final pattern = ordered ? _numbered : _bullet;
      final start = numbered != null
          ? (int.parse(numbered.group(1)!).clamp(0, 999999))
          : 1;
      final items = <String>[];
      while (i < lines.length) {
        final m = pattern.firstMatch(lines[i]);
        if (m != null) {
          items.add(ordered ? m.group(2)! : m.group(1)!);
          i++;
          continue;
        }
        // An indented line carries on the item above it.
        if (items.isNotEmpty &&
            lines[i].trim().isNotEmpty &&
            _indented.hasMatch(lines[i]) &&
            !_startsBlock(lines[i])) {
          items[items.length - 1] += '\n${lines[i].trim()}';
          i++;
          continue;
        }
        break;
      }
      blocks.add(HelpList(
        ordered: ordered,
        start: start,
        items: items.map((t) => _parseInline(t, 0, false)).toList(),
      ));
      continue;
    }

    final para = <String>[];
    while (i < lines.length &&
        lines[i].trim().isNotEmpty &&
        (para.isEmpty || !_startsBlock(lines[i]))) {
      para.add(lines[i].trim());
      i++;
    }
    blocks.add(HelpParagraph(_parseInline(para.join('\n'), 0, false)));
  }
  return blocks;
}

/// An article body as blocks, ready to draw.
List<HelpBlock> parseHelpMarkdown(String? src) {
  if (src == null || src.isEmpty) return const [];
  final lines = src.replaceAll(RegExp(r'\r\n?'), '\n').split('\n');
  return _parseBlocks(lines, 0);
}

/// The words of [nodes] with the markup gone — for screen-reader labels.
String helpInlineText(List<HelpInline> nodes) {
  final out = StringBuffer();
  for (final n in nodes) {
    switch (n) {
      case HelpText(:final text):
        out.write(text);
      case HelpCode(:final text):
        out.write(text);
      case HelpBreak():
        out.write(' ');
      case HelpImage(:final alt):
        out.write(alt);
      case HelpStrong(:final children):
        out.write(helpInlineText(children));
      case HelpEm(:final children):
        out.write(helpInlineText(children));
      case HelpLink(:final children):
        out.write(helpInlineText(children));
    }
  }
  return out.toString();
}
