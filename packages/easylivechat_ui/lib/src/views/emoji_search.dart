import 'emoji_catalog.dart';

/// One emoji in the picker, with its lower-case English search words.
class ElcEmojiEntry {
  final String emoji;
  final List<String> words;
  const ElcEmojiEntry(this.emoji, this.words);
}

/// The picker's categories in tab order, `recent` aside — the web's
/// `EMOJI_CATEGORIES` without the device's own list.
const List<String> elcEmojiCategories = [
  'smileys',
  'people',
  'animals',
  'food',
  'travel',
  'activities',
  'objects',
  'symbols',
  'flags',
];

/// [emojiTable] read into entries, once, on first use — the shared
/// `emojiCatalog()` (packages/shared/src/emoji.ts).
final Map<String, List<ElcEmojiEntry>> _catalog = {
  for (final category in elcEmojiCategories)
    category: [
      for (final raw in (emojiTable[category] ?? '').split('|'))
        if (raw.isNotEmpty) _entry(raw),
    ],
};

ElcEmojiEntry _entry(String raw) {
  final space = raw.indexOf(' ');
  if (space == -1) return ElcEmojiEntry(raw, const []);
  return ElcEmojiEntry(
    raw.substring(0, space),
    raw.substring(space + 1).split(' ').where((w) => w.isNotEmpty).toList(),
  );
}

/// One category's emoji, in the shared order.
List<String> emojiOf(String category) =>
    [for (final e in _catalog[category] ?? const <ElcEmojiEntry>[]) e.emoji];

/// The emoji whose words match every word of [query], best first — the web
/// picker's search, ported from `searchEmoji` (packages/shared/src/emoji.ts)
/// so both find the same emoji in the same order:
///
///  • each query word must START one of the emoji's words ("hap" finds 😀
///    for "happy"); an exact word beats a prefix, an earlier word beats a
///    later one, and the table's own order breaks ties;
///  • a query that is itself an emoji finds it, first;
///  • the words are the emoji's English names and tags — the only words the
///    shared table has, on the web too — matched case-insensitively.
///
/// Empty for a blank query. At most [limit] results.
List<String> searchEmoji(String query, {int limit = 120}) {
  final trimmed = query.trim();
  final terms = trimmed
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();
  if (terms.isEmpty) return const [];
  final scored = <(String, int, int)>[];
  var order = 0;
  for (final category in elcEmojiCategories) {
    for (final entry in _catalog[category]!) {
      order++;
      if (entry.emoji == trimmed) {
        scored.add((entry.emoji, -1, order));
        continue;
      }
      var score = 0;
      var all = true;
      for (final term in terms) {
        final exact = entry.words.indexOf(term);
        if (exact != -1) {
          score += exact;
          continue;
        }
        final prefix = entry.words.indexWhere((w) => w.startsWith(term));
        if (prefix == -1) {
          all = false;
          break;
        }
        score += 10 + prefix;
      }
      if (all) scored.add((entry.emoji, score, order));
    }
  }
  scored.sort((a, b) {
    final byScore = a.$2.compareTo(b.$2);
    return byScore != 0 ? byScore : a.$3.compareTo(b.$3);
  });
  return [for (final s in scored.take(limit)) s.$1];
}
