/// Which way a composer should face.
///
/// The workspace's direction is the wrong answer the moment somebody types in
/// another language: an Arabic sentence in an English workspace was laid out
/// left-to-right, caret on the wrong end and text against the wrong edge. The
/// keyboard's language is not something the OS tells an app, so the first
/// strongly-directional character is the signal.
library;

import 'package:easylivechat_ui/src/bidi.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Arabic, Kurdish Sorani and Urdu all read right-to-left', () {
    // The three RTL locales the product ships, in their own scripts.
    expect(textDirectionOf('مرحبا'), TextDirection.rtl);
    expect(textDirectionOf('سڵاو چۆنی'), TextDirection.rtl);
    expect(textDirectionOf('السلام علیکم'), TextDirection.rtl);
    expect(textDirectionOf('שלום'), TextDirection.rtl);
  });

  test('Latin text reads left-to-right', () {
    expect(textDirectionOf('hello'), TextDirection.ltr);
    expect(textDirectionOf('Größe'), TextDirection.ltr);
    expect(textDirectionOf('привет'), TextDirection.ltr);
  });

  test('the FIRST strong character decides, not the majority', () {
    // A sentence that opens in Arabic stays right-to-left even with a Latin
    // word in it, and the reverse. This is the `dir="auto"` rule, and picking
    // the majority instead would make the box flip about mid-sentence.
    expect(textDirectionOf('مرحبا hello world'), TextDirection.rtl);
    expect(textDirectionOf('hello مرحبا'), TextDirection.ltr);
  });

  test('nothing strong leaves the direction to the caller', () {
    // An empty box keeps the workspace's direction, and so does one holding
    // only a number, an emoji or punctuation — flipping on a digit would turn
    // the field around before the visitor has said anything.
    expect(textDirectionOf(''), isNull);
    expect(textDirectionOf('12345'), isNull);
    expect(textDirectionOf('!…'), isNull);
    expect(textDirectionOf('😀 🎉'), isNull);
    expect(textDirectionOf('  '), isNull);
  });

  test('Arabic punctuation is Arabic', () {
    // `؟` and `،` look like punctuation but Unicode classes them as strong
    // Arabic letters, so the box turns around on them — which is what
    // `dir="auto"` does too, and what someone typing an Arabic sentence
    // wants.
    expect(textDirectionOf('؟'), TextDirection.rtl);
    expect(textDirectionOf('، hello'), TextDirection.rtl);
  });

  test('Arabic-Indic digits count as Arabic', () {
    // Strictly these are bidi class AN rather than strong, so `dir="auto"`
    // would leave them neutral. Treated as RTL here on purpose: in a product
    // whose RTL locales are Arabic, Sorani and Urdu, somebody opening with
    // `٥` is writing Arabic, and waiting for the next character to turn the
    // field around is a flicker they can see.
    expect(textDirectionOf('٥٠٠'), TextDirection.rtl);
  });

  test('leading punctuation does not hide the language behind it', () {
    expect(textDirectionOf('«مرحبا»'), TextDirection.rtl);
    expect(textDirectionOf('"hello"'), TextDirection.ltr);
    expect(textDirectionOf('123 مرحبا'), TextDirection.rtl);
  });

  test('text that arrives already shaped is still Arabic', () {
    // Arabic Presentation Forms — what some keyboards and older systems emit.
    expect(textDirectionOf('ﻟﺎ'), TextDirection.rtl);
  });
}
