/// String rules the server writes in TypeScript, reproduced exactly.
///
/// Dart's `String.trim()` is not JavaScript's: it also strips U+0085 (NEXT
/// LINE), which JS does not treat as whitespace. Dart's `RegExp` `\s`, on the
/// other hand, is the ECMAScript class code point for code point. Validation
/// ported from `packages/shared` goes through these so a string the server kept
/// is never one this client drops, or the other way round.
library;

final RegExp _edges = RegExp(r'^\s+|\s+$');
final RegExp _runs = RegExp(r'\s+');

/// JavaScript's `s.trim()`.
String jsTrim(String s) => s.replaceAll(_edges, '');

/// JavaScript's `s.replace(/\s+/g, ' ')`.
String jsCollapseWhitespace(String s) => s.replaceAll(_runs, ' ');

/// JavaScript's `s.slice(0, max)` for a non-negative [max]: UTF-16 code units,
/// exactly like `String.substring`, clamped to the length.
String jsSlice(String s, int max) => s.length <= max ? s : s.substring(0, max);
