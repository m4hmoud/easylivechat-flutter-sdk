import 'package:easylivechat_ui/src/views/linkified_text.dart';
import 'package:flutter_test/flutter_test.dart';

/// Convenience: the detected substrings, in order.
List<String> texts(String input) =>
    detectLinks(input).map((s) => s.text).toList();

List<ElcLinkKind> kinds(String input) =>
    detectLinks(input).map((s) => s.kind).toList();

void main() {
  group('URLs', () {
    test('detects an https URL', () {
      expect(texts('see https://livechattools.com/pricing now'),
          ['https://livechattools.com/pricing']);
      expect(kinds('see https://livechattools.com/pricing now'),
          [ElcLinkKind.url]);
    });

    test('detects http and www forms', () {
      expect(texts('http://example.com'), ['http://example.com']);
      expect(texts('www.example.co.uk/help'), ['www.example.co.uk/help']);
    });

    test('detects a bare domain with an allowlisted TLD', () {
      expect(texts('visit livechattools.com'), ['livechattools.com']);
      expect(texts('docs.easylivechat.io/start'), ['docs.easylivechat.io/start']);
    });

    test('leaves filenames and version numbers alone', () {
      expect(texts('open main.py please'), isEmpty);
      expect(texts('the photo.png is attached'), isEmpty);
      expect(texts('see notes.txt'), isEmpty);
      expect(texts('e.g. that one'), isEmpty);
      expect(texts('running 1.2.3'), isEmpty);
    });

    test('strips trailing sentence punctuation', () {
      expect(texts('go to https://example.com/a.'), ['https://example.com/a']);
      expect(texts('(see https://example.com/a)'), ['https://example.com/a']);
      expect(texts('read https://example.com!'), ['https://example.com']);
    });

    test('keeps a balanced bracket that belongs to the path', () {
      expect(texts('https://en.wikipedia.org/wiki/Foo_(bar)'),
          ['https://en.wikipedia.org/wiki/Foo_(bar)']);
    });

    test('resolves a scheme-less URL to https', () {
      final span = detectLinks('livechattools.com').single;
      expect(span.uri.toString(), 'https://livechattools.com');
    });

    test('keeps an explicit scheme as-is', () {
      final span = detectLinks('http://example.com').single;
      expect(span.uri.toString(), 'http://example.com');
    });
  });

  group('emails', () {
    test('detects an address and does not split off its domain', () {
      expect(texts('mail hello@livechattools.com today'),
          ['hello@livechattools.com']);
      expect(kinds('mail hello@livechattools.com today'), [ElcLinkKind.email]);
    });

    test('builds a mailto URI', () {
      final span = detectLinks('hello@livechattools.com').single;
      expect(span.uri.toString(), 'mailto:hello@livechattools.com');
    });

    test('handles plus-addressing and dots', () {
      expect(texts('a.b+tag@sub.example.com'), ['a.b+tag@sub.example.com']);
    });
  });

  group('phone numbers', () {
    test('detects an international number', () {
      expect(texts('call +964 750 123 4567 now'), ['+964 750 123 4567']);
      expect(kinds('call +964 750 123 4567 now'), [ElcLinkKind.phone]);
    });

    test('detects separated local formats', () {
      expect(texts('ring 555-1234 today'), ['555-1234']);
      expect(texts('(212) 555-0199'), ['(212) 555-0199']);
    });

    test('detects a long unseparated run', () {
      expect(texts('my number is 07501234567'), ['07501234567']);
    });

    test('builds a tel URI with dial characters only', () {
      final span = detectLinks('+964 (750) 123-4567').single;
      expect(span.uri.toString(), 'tel:+9647501234567');
    });

    test('ignores short numbers and quantities', () {
      expect(texts('order 123456'), isEmpty);
      expect(texts('I need 25 units'), isEmpty);
      expect(texts('ref 1234567'), isEmpty, reason: '7 bare digits is ambiguous');
    });

    test('ignores ISO dates', () {
      expect(texts('ordered on 2026-07-30'), isEmpty);
    });

    test('ignores digits inside a URL', () {
      expect(texts('https://example.com/order/1234567890'),
          ['https://example.com/order/1234567890']);
    });
  });

  group('mixed and edge cases', () {
    test('detects several entities in order with correct offsets', () {
      const body =
          'Hi, see https://livechattools.com or mail me@acme.com or call +1 202 555 0143.';
      final spans = detectLinks(body);
      expect(spans.map((s) => s.kind).toList(), [
        ElcLinkKind.url,
        ElcLinkKind.email,
        ElcLinkKind.phone,
      ]);
      // Offsets must index back into the original string exactly.
      for (final s in spans) {
        expect(body.substring(s.start, s.end), s.text);
      }
    });

    test('returns nothing for plain prose', () {
      expect(detectLinks('Hello, how can I help you today?'), isEmpty);
      expect(detectLinks(''), isEmpty);
    });

    test('works inside RTL text', () {
      expect(texts('سەردانی livechattools.com بکە'), ['livechattools.com']);
      expect(texts('اتصل على +964 750 123 4567'), ['+964 750 123 4567']);
    });
  });
}
