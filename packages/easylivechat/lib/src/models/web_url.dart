/// Whether a string is a link the web would open as `http:` or `https:`.
///
/// `packages/shared/src/message-card.ts` accepts a card link when
/// `new URL(url.trim())` succeeds with one of those two protocols, and refuses
/// it otherwise. That is the WHATWG URL Standard's parser — which a card
/// rendered in a browser is also opened through — and Dart's `Uri.parse` is not
/// it: `Uri.parse` takes `https://exa mple.com`, `https://999.1.1.1` and a port
/// of `99999`, all of which the web throws out, and refuses `https:host`, which
/// the web opens. So a card could show a button here that the widget and the
/// dashboard do not, and hide one they show.
///
/// This is the Standard's parser reduced to the part that can FAIL for those
/// two schemes: the scheme, the authority, the host and the port. Everything
/// after the host (path, query, fragment) is percent-encoded by the Standard,
/// never refused, so it is carried through as written.
///
/// One piece is approximate, and deliberately so: a host name written in a
/// non-Latin script goes through Unicode IDNA (UTS #46) in a browser, which is a
/// mapping table of tens of thousands of entries. Here such a host is refused
/// for the code points IDNA refuses outright — controls, spaces, noncharacters,
/// private use, anything that maps onto a character forbidden in a host — and
/// otherwise accepted. Everything ASCII, which is every link a card has ever
/// carried in practice, follows the Standard exactly.
library;

import 'dart:convert' show utf8;

/// The link as the Standard reads it — `scheme://authority/rest` — or null when
/// the web would refuse it or it is not `http:`/`https:`.
///
/// For an ordinary link this is the input with its scheme and host lowercased.
/// Beyond that it differs only where a browser quietly repairs what it was
/// given: `https:host` and `https:\\host` gain their slashes, a backslash in
/// the path becomes `/`, a tab or newline inside the link is dropped, empty
/// credentials and a port's leading zeros go, and an IPv4 address written as
/// `0x7f.1` reads `127.0.0.1`. That is the form to hand to the platform, which
/// would otherwise be asked to open something no browser actually visits.
String? parseWebUrl(String input) {
  // Leading/trailing C0 controls and spaces go, then every tab and newline.
  var start = 0;
  var end = input.length;
  while (start < end && input.codeUnitAt(start) <= 0x20) {
    start++;
  }
  while (end > start && input.codeUnitAt(end - 1) <= 0x20) {
    end--;
  }
  final s = input.substring(start, end).replaceAll(RegExp('[\t\n\r]'), '');

  final schemeMatch = _scheme.firstMatch(s);
  if (schemeMatch == null) return null;
  final scheme = schemeMatch.group(1)!.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;

  // A special scheme with no base skips any run of `/` and `\` before the
  // authority, which is why `https:host` and `https:///host` both open `host`.
  var i = schemeMatch.end;
  while (i < s.length && (s[i] == '/' || s[i] == r'\')) {
    i++;
  }
  var j = i;
  while (j < s.length && !_authorityEnd.contains(s[j])) {
    j++;
  }
  final authority = s.substring(i, j);
  final rest = s.substring(j);

  // Credentials run to the LAST `@`; an earlier one is part of them.
  final at = authority.lastIndexOf('@');
  final hostAndPort = authority.substring(at + 1);
  if (hostAndPort.isEmpty) return null;

  // A `:` outside `[…]` starts the port.
  var colon = -1;
  var inBrackets = false;
  for (var k = 0; k < hostAndPort.length; k++) {
    final c = hostAndPort[k];
    if (c == '[') {
      inBrackets = true;
    } else if (c == ']') {
      inBrackets = false;
    } else if (c == ':' && !inBrackets) {
      colon = k;
      break;
    }
  }
  final host = colon == -1 ? hostAndPort : hostAndPort.substring(0, colon);
  if (host.isEmpty) return null;
  final port = colon == -1 ? '' : hostAndPort.substring(colon + 1);
  if (!_isValidPort(port)) return null;
  final hostOut = _parseHost(host);
  if (hostOut == null) return null;

  // Serialized the way the Standard serializes: no empty credentials, the
  // host as it resolved, the port without leading zeros.
  final rawCredentials = at == -1 ? '' : authority.substring(0, at);
  final credentials = rawCredentials.isEmpty || rawCredentials == ':'
      ? ''
      : '${rawCredentials.replaceAll('@', '%40')}@';
  final portOut = port.isEmpty ? '' : ':${int.parse(port)}';
  final pathEnd = rest.indexOf(RegExp('[?#]'));
  final path = pathEnd == -1 ? rest : rest.substring(0, pathEnd);
  final tail = pathEnd == -1 ? '' : rest.substring(pathEnd);
  return '$scheme://$credentials$hostOut$portOut'
      '${path.replaceAll(r'\', '/')}$tail';
}

final RegExp _scheme = RegExp(r'^([A-Za-z][A-Za-z0-9+\-.]*):');
const String _authorityEnd = r'/\?#';

bool _isValidPort(String port) {
  if (port.isEmpty) return true; // `https://host:/` is the default port.
  if (!RegExp(r'^[0-9]+$').hasMatch(port)) return false;
  final digits = port.replaceFirst(RegExp('^0+'), '');
  return digits.length <= 5 && (digits.isEmpty || int.parse(digits) <= 65535);
}

/// The host as the Standard resolves it, or null when it refuses it.
///
/// An ASCII name comes back lowercased (with full-width letters folded and
/// invisible IDNA-ignored code points gone); an IPv4 address in its dotted
/// form, however it was written (`0x7f.1` is `127.0.0.1`). A bracketed IPv6
/// address and a name in another script come back as written — both open as
/// they are.
String? _parseHost(String input) {
  if (input.startsWith('[')) {
    return input.endsWith(']') &&
            _isValidIpv6(input.substring(1, input.length - 1))
        ? input
        : null;
  }
  // Percent-decoded as UTF-8; bytes that aren't UTF-8 decode to U+FFFD, which
  // IDNA refuses. A lone surrogate is encoded as U+FFFD first, same outcome.
  final bytes = _percentDecode(utf8.encode(input));
  final domain = utf8.decode(bytes, allowMalformed: true);
  final mapped = _toAsciiDomain(domain);
  if (mapped == null || mapped.isEmpty) return null;
  for (final c in mapped.codeUnits) {
    if (_isForbiddenDomainCodeUnit(c)) return null;
  }
  if (_endsInNumber(mapped)) return _ipv4(mapped);
  return mapped.codeUnits.every((c) => c <= 0x7F) ? mapped : input;
}

List<int> _percentDecode(List<int> bytes) {
  final out = <int>[];
  for (var i = 0; i < bytes.length; i++) {
    final b = bytes[i];
    if (b == 0x25 && i + 2 < bytes.length) {
      final hi = _hexValue(bytes[i + 1]);
      final lo = _hexValue(bytes[i + 2]);
      if (hi != -1 && lo != -1) {
        out.add(hi * 16 + lo);
        i += 2;
        continue;
      }
    }
    out.add(b);
  }
  return out;
}

int _hexValue(int c) {
  if (c >= 0x30 && c <= 0x39) return c - 0x30;
  if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
  if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
  return -1;
}

/// UTS #46 ToASCII, exact for ASCII input and approximate otherwise — see the
/// library comment. Returns the domain with any `xn--` labels verified, or null
/// when IDNA would refuse it. Non-ASCII labels are returned as written: only
/// their validity matters here, never their Punycode form.
String? _toAsciiDomain(String domain) {
  final out = StringBuffer();
  for (final rune in domain.runes) {
    // Full-width ASCII is IDNA-mapped onto ASCII, and three other dots are
    // label separators — so `ｅ．ｅｘａｍｐｌｅ` is `e.example`.
    if (rune >= 0xFF01 && rune <= 0xFF5E) {
      out.writeCharCode(rune - 0xFF01 + 0x21);
    } else if (rune == 0x3002 || rune == 0xFF0E || rune == 0xFF61) {
      out.write('.');
    } else if (_idnaIgnored(rune)) {
      continue;
    } else if (rune > 0x7F && _idnaDisallowed(rune)) {
      return null;
    } else {
      out.writeCharCode(rune);
    }
  }
  final mapped = out.toString().toLowerCase();
  for (final label in mapped.split('.')) {
    if (label.startsWith('xn--') && !_isValidPunycodeLabel(label.substring(4))) {
      return null;
    }
  }
  return mapped;
}

/// Code points IDNA maps to nothing (soft hyphen, zero-width space, word
/// joiner, byte-order mark, variation selectors).
bool _idnaIgnored(int c) =>
    c == 0x00AD ||
    c == 0x034F ||
    c == 0x200B ||
    c == 0x2060 ||
    c == 0xFEFF ||
    (c >= 0x180B && c <= 0x180D) ||
    (c >= 0xFE00 && c <= 0xFE0F);

/// Non-ASCII code points IDNA refuses outright, or maps onto a space (which a
/// host may not contain).
bool _idnaDisallowed(int c) =>
    (c >= 0x80 && c <= 0x9F) || // C1 controls
    c == 0x00A0 ||
    c == 0x1680 ||
    (c >= 0x2000 && c <= 0x200A) ||
    c == 0x2028 ||
    c == 0x2029 ||
    c == 0x202F ||
    c == 0x205F ||
    c == 0x3000 ||
    (c >= 0xD800 && c <= 0xDFFF) ||
    (c >= 0xE000 && c <= 0xF8FF) || // private use
    (c >= 0xFDD0 && c <= 0xFDEF) || // noncharacters
    (c & 0xFFFE) == 0xFFFE ||
    c == 0xFFFD ||
    c >= 0xF0000; // supplementary private use

/// The URL Standard's forbidden domain code points.
bool _isForbiddenDomainCodeUnit(int c) =>
    c <= 0x20 ||
    c == 0x7F ||
    c == 0x23 || // #
    c == 0x25 || // %
    c == 0x2F || // /
    c == 0x3A || // :
    c == 0x3C || // <
    c == 0x3E || // >
    c == 0x3F || // ?
    c == 0x40 || // @
    c == 0x5B || // [
    c == 0x5C || // \
    c == 0x5D || // ]
    c == 0x5E || // ^
    c == 0x7C; // |

/// RFC 3492 decode, for validity only.
bool _isValidPunycodeLabel(String input) {
  const base = 36, tMin = 1, tMax = 26, skew = 38, damp = 700;
  const maxInt = 0x7FFFFFFF;
  if (input.isEmpty || input.codeUnits.any((c) => c > 0x7F)) return false;
  final delimiter = input.lastIndexOf('-');
  var length = delimiter > 0 ? delimiter : 0;
  var n = 0x80, i = 0, bias = 72;
  var nonAscii = false;
  var pos = delimiter > 0 ? delimiter + 1 : 0;

  int adapt(int delta, int points, bool first) {
    var d = first ? delta ~/ damp : delta ~/ 2;
    d += d ~/ points;
    var k = 0;
    while (d > ((base - tMin) * tMax) ~/ 2) {
      d ~/= base - tMin;
      k += base;
    }
    return k + ((base - tMin + 1) * d) ~/ (d + skew);
  }

  while (pos < input.length) {
    final oldI = i;
    var w = 1;
    for (var k = base;; k += base) {
      if (pos >= input.length) return false;
      final c = input.codeUnitAt(pos++);
      final digit = c >= 0x30 && c <= 0x39
          ? c - 22
          : c >= 0x41 && c <= 0x5A
              ? c - 0x41
              : c >= 0x61 && c <= 0x7A
                  ? c - 0x61
                  : base;
      if (digit >= base) return false;
      if (digit > (maxInt - i) ~/ w) return false;
      i += digit * w;
      final t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias);
      if (digit < t) break;
      if (w > maxInt ~/ (base - t)) return false;
      w *= base - t;
    }
    length++;
    bias = adapt(i - oldI, length, oldI == 0);
    if (i ~/ length > maxInt - n) return false;
    n += i ~/ length;
    i %= length;
    if (n < 0x80 || n > 0x10FFFF || (n >= 0xD800 && n <= 0xDFFF)) {
      return false;
    }
    if (_idnaDisallowed(n)) return false;
    nonAscii = true;
    i++;
  }
  // A label that decodes to nothing but ASCII was never Punycode.
  return nonAscii;
}

bool _endsInNumber(String input) {
  final parts = input.split('.');
  if (parts.last.isEmpty) {
    if (parts.length == 1) return false;
    parts.removeLast();
  }
  final last = parts.last;
  if (last.isNotEmpty && RegExp(r'^[0-9]+$').hasMatch(last)) return true;
  return _ipv4Number(last) != null;
}

/// The URL Standard's IPv4 parser: the dotted address, or null.
String? _ipv4(String input) {
  final parts = input.split('.');
  if (parts.last.isEmpty && parts.length > 1) parts.removeLast();
  if (parts.length > 4) return null;
  final numbers = <BigInt>[];
  for (final part in parts) {
    final n = _ipv4Number(part);
    if (n == null) return null;
    numbers.add(n);
  }
  final byte = BigInt.from(255);
  for (var k = 0; k < numbers.length - 1; k++) {
    if (numbers[k] > byte) return null;
  }
  if (numbers.last >= BigInt.from(256).pow(5 - numbers.length)) return null;
  var address = numbers.last;
  for (var k = 0; k < numbers.length - 1; k++) {
    address += numbers[k] * BigInt.from(256).pow(3 - k);
  }
  final octets = <int>[];
  for (var k = 0; k < 4; k++) {
    octets.insert(0, (address % BigInt.from(256)).toInt());
    address = address ~/ BigInt.from(256);
  }
  return octets.join('.');
}

BigInt? _ipv4Number(String input) {
  if (input.isEmpty) return null;
  var s = input;
  var radix = 10;
  if (s.length >= 2 && (s.startsWith('0x') || s.startsWith('0X'))) {
    s = s.substring(2);
    radix = 16;
  } else if (s.length >= 2 && s.startsWith('0')) {
    s = s.substring(1);
    radix = 8;
  }
  if (s.isEmpty) return BigInt.zero;
  final digits = switch (radix) {
    16 => RegExp(r'^[0-9A-Fa-f]+$'),
    8 => RegExp(r'^[0-7]+$'),
    _ => RegExp(r'^[0-9]+$'),
  };
  if (!digits.hasMatch(s)) return null;
  return BigInt.parse(s, radix: radix);
}

/// The URL Standard's IPv6 parser, for validity only.
bool _isValidIpv6(String input) {
  final c = input.codeUnits;
  int at(int p) => p < c.length ? c[p] : -1;
  bool isHex(int x) =>
      (x >= 0x30 && x <= 0x39) ||
      (x >= 0x41 && x <= 0x46) ||
      (x >= 0x61 && x <= 0x66);
  bool isDigit(int x) => x >= 0x30 && x <= 0x39;
  const colon = 0x3A, dot = 0x2E;

  var pieceIndex = 0;
  var compress = -1;
  var p = 0;
  if (at(p) == colon) {
    if (at(p + 1) != colon) return false;
    p += 2;
    pieceIndex++;
    compress = pieceIndex;
  }
  while (at(p) != -1) {
    if (pieceIndex == 8) return false;
    if (at(p) == colon) {
      if (compress != -1) return false;
      p++;
      pieceIndex++;
      compress = pieceIndex;
      continue;
    }
    var length = 0;
    while (length < 4 && isHex(at(p))) {
      p++;
      length++;
    }
    if (at(p) == dot) {
      if (length == 0) return false;
      p -= length;
      if (pieceIndex > 6) return false;
      var numbersSeen = 0;
      while (at(p) != -1) {
        int? piece;
        if (numbersSeen > 0) {
          if (at(p) == dot && numbersSeen < 4) {
            p++;
          } else {
            return false;
          }
        }
        if (!isDigit(at(p))) return false;
        while (isDigit(at(p))) {
          final number = at(p) - 0x30;
          if (piece == null) {
            piece = number;
          } else if (piece == 0) {
            return false;
          } else {
            piece = piece * 10 + number;
          }
          if (piece > 255) return false;
          p++;
        }
        numbersSeen++;
        if (numbersSeen == 2 || numbersSeen == 4) pieceIndex++;
      }
      return numbersSeen == 4 && (compress != -1 || pieceIndex == 8);
    } else if (at(p) == colon) {
      p++;
      if (at(p) == -1) return false;
    } else if (at(p) != -1) {
      return false;
    }
    pieceIndex++;
  }
  return compress != -1 || pieceIndex == 8;
}
