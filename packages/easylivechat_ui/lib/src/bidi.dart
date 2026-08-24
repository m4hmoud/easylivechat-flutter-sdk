import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';

/// The direction a piece of text wants to be laid out in, from its own
/// content — the rule HTML calls `dir="auto"`.
///
/// A composer takes the workspace's direction, which is right until somebody
/// types in another language. An Arabic sentence in an English workspace was
/// laid out left-to-right: the caret sat on the wrong end, punctuation landed
/// on the wrong side, and the text hugged the wrong edge of the box. The
/// keyboard's language is not something iOS or Android tells an app, so the
/// first strongly-directional character the visitor types is the signal — the
/// same one every messenger uses.
///
/// Returns null for text with nothing strong in it (empty, digits, emoji,
/// punctuation), where the caller should keep whatever direction it had.
TextDirection? textDirectionOf(String text) {
  for (final rune in text.runes) {
    if (_isStrongRtl(rune)) return TextDirection.rtl;
    if (_isStrongLtr(rune)) return TextDirection.ltr;
  }
  return null;
}

/// Right-to-left scripts, by Unicode block.
///
/// Arabic covers Persian, Urdu and Kurdish Sorani — the three the product
/// ships and the reason this exists. Hebrew, Syriac, Thaana and N'Ko are here
/// because a visitor writing in them has the same problem and the ranges cost
/// nothing; the Arabic Presentation Forms blocks catch text that arrives
/// already shaped.
bool _isStrongRtl(int c) =>
    (c >= 0x0590 && c <= 0x05FF) || // Hebrew
    (c >= 0x0600 && c <= 0x06FF) || // Arabic
    (c >= 0x0700 && c <= 0x074F) || // Syriac
    (c >= 0x0750 && c <= 0x077F) || // Arabic Supplement
    (c >= 0x0780 && c <= 0x07BF) || // Thaana
    (c >= 0x07C0 && c <= 0x07FF) || // N'Ko
    (c >= 0x0860 && c <= 0x08FF) || // Syriac Supplement + Arabic Extended-A
    (c >= 0xFB1D && c <= 0xFDFF) || // Hebrew + Arabic Presentation Forms-A
    (c >= 0xFE70 && c <= 0xFEFF); // Arabic Presentation Forms-B

/// Left-to-right: the Latin/Greek/Cyrillic range plus everything above the
/// RTL blocks. Deliberately coarse — this only has to answer "is the first
/// strong character RTL or not", and anything that is neither returns null
/// above and leaves the caller's direction alone.
bool _isStrongLtr(int c) =>
    (c >= 0x0041 && c <= 0x005A) || // A-Z
    (c >= 0x0061 && c <= 0x007A) || // a-z
    (c >= 0x00C0 && c <= 0x058F) || // Latin-1 supplement … Armenian
    (c >= 0x0900 && c <= 0x1FFF) || // Devanagari … Greek Extended
    (c >= 0x2C00 && c <= 0xD7FF) || // Glagolitic … Hangul
    (c >= 0xF900 && c <= 0xFB17) || // CJK compatibility … Alphabetic pres.
    (c >= 0x10000 && c <= 0x10FFF); // Linear B and friends

/// The languages that are written right-to-left, by subtag.
///
/// `ckb` and `kmr` are the product's two Kurdish codes and `ku` the
/// deprecated macrolanguage some platforms still report for Sorani.
const _rtlLanguages = <String>{
  'ar', 'fa', 'he', 'iw', 'ur', 'ps', 'sd', 'ug', 'yi', 'ji', 'dv', 'ku',
  'ckb', 'kmr', 'arc', 'syr', 'nqo', 'rhg',
};

bool isRtlLanguage(String languageCode) =>
    _rtlLanguages.contains(languageCode.trim().toLowerCase().split(RegExp(r'[-_]')).first);

/// Which way the visitor's PHONE is written, for an empty composer.
///
/// The keyboard's language would be the right answer and there is no way to
/// ask for it: Flutter surfaces no API for the active input method, and
/// reading `UITextInputMode` / `InputMethodManager` means native code, which
/// would make this package a plugin and change the build of every app that
/// embeds it. The device's own language is the closest thing that costs
/// nothing — someone whose phone is in Kurdish is typing Kurdish.
///
/// Only the PRIMARY locale counts. Someone with an English phone who also has
/// an Arabic keyboard installed has Arabic somewhere in their locale list, and
/// turning their composer around on that would be wrong more often than right.
TextDirection? deviceTextDirection() {
  final code = PlatformDispatcher.instance.locale.languageCode;
  return isRtlLanguage(code) ? TextDirection.rtl : null;
}
