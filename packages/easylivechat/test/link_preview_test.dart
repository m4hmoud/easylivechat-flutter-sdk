/// A link preview is a stranger's page, summarised by the server and stored
/// on the message (`metadata.linkPreview`). Clients draw it from that stored
/// data, so the reader is where a hostile or broken one stops — the same
/// cases as packages/shared/src/link-preview.test.ts, plus how it reaches a
/// message.
library;

import 'package:easylivechat/easylivechat.dart';
import 'package:test/test.dart';

ChatMessage _message(Map<String, dynamic>? metadata,
        {String contentType = 'TEXT'}) =>
    ChatMessage.fromAny({
      'id': 'a1',
      'conversationId': 'c1',
      'senderType': 'AGENT',
      'contentType': contentType,
      'body': 'See https://example.com/a',
      'createdAt': '2026-10-18T10:00:00.000Z',
      if (metadata != null) 'metadata': metadata,
    });

void main() {
  group('LinkPreview.tryParse', () {
    test('reads a good one', () {
      expect(
        LinkPreview.tryParse({
          'url': 'https://example.com/a',
          'title': 'An  article\n title',
          'description': 'About it',
          'siteName': 'Example',
          'imageUrl': '/uploads/t1/previews/abc.jpg',
        }),
        const LinkPreview(
          url: 'https://example.com/a',
          title: 'An article title',
          description: 'About it',
          siteName: 'Example',
          imageUrl: '/uploads/t1/previews/abc.jpg',
        ),
      );
    });

    test('refuses links that are not http(s), and cards with nothing to say',
        () {
      expect(LinkPreview.tryParse({'url': 'javascript:alert(1)', 'title': 'x'}),
          isNull);
      expect(LinkPreview.tryParse({'url': 'https://example.com', 'title': '   '}),
          isNull);
      expect(LinkPreview.tryParse({'url': 'https://example.com'}), isNull);
      expect(LinkPreview.tryParse('nope'), isNull);
      expect(LinkPreview.tryParse(null), isNull);
      expect(
          LinkPreview.tryParse(
              {'url': 'https://e.com/${'a' * 2100}', 'title': 'x'}),
          isNull);
    });

    test('names the host when the site gave no name, and drops a description '
        'that only repeats the title', () {
      final p = LinkPreview.tryParse({
        'url': 'https://www.Example.com/x',
        'title': 'Same',
        'description': 'Same',
      });
      expect(p?.siteName, 'example.com');
      expect(p?.description, isNull);
    });

    test('clips what it is given, by code points, with an ellipsis', () {
      final p = LinkPreview.tryParse({
        'url': 'https://example.com',
        'title': 't' * 500,
        'description': 'd' * 900,
      })!;
      expect(p.title.runes.length, 200);
      expect(p.title.endsWith('…'), isTrue);
      expect(p.description!.runes.length, 300);
      // An emoji is one character, not two halves of one.
      final e = LinkPreview.tryParse(
          {'url': 'https://example.com', 'title': '😀' * 250})!;
      expect(e.title.runes.length, 200);
      expect(e.title.runes.where((r) => r == 0x1F600).length, 199);
    });

    test('loads a picture only from our uploads or https', () {
      expect(LinkPreview.isSafeImage('/uploads/t/previews/a.png'), isTrue);
      expect(LinkPreview.isSafeImage('https://cdn.example.com/a.png'), isTrue);
      expect(LinkPreview.isSafeImage('http://cdn.example.com/a.png'), isFalse);
      expect(LinkPreview.isSafeImage('/uploads/../secret'), isFalse);
      expect(LinkPreview.isSafeImage('data:image/png;base64,AA'), isFalse);
      expect(LinkPreview.isSafeImage(null), isFalse);
      expect(
          LinkPreview.tryParse({
            'url': 'https://e.com',
            'title': 'x',
            'imageUrl': 'http://e.com/a.png',
          })?.imageUrl,
          isNull);
    });

    test('opens through the web\'s own reading of the link', () {
      final p = LinkPreview.tryParse(
          {'url': 'https://Example.com/a?b=1', 'title': 'x'})!;
      expect(p.uri, Uri.parse('https://example.com/a?b=1'));
      expect(p.url, 'https://Example.com/a?b=1');
    });

    test('names hosts plainly', () {
      expect(LinkPreview.previewHost('https://www.Example.com/a'),
          'example.com');
      expect(LinkPreview.previewHost('not a url'), '');
    });
  });

  group('ChatMessage.linkPreview', () {
    test('is found on the message\'s metadata', () {
      final m = _message({
        'linkPreview': {'url': 'https://e.com', 'title': 'E'}
      });
      expect(m.linkPreview?.title, 'E');
      expect(m.linkPreview?.siteName, 'e.com');
    });

    test('is absent when there is none, or it is malformed', () {
      expect(_message(null).linkPreview, isNull);
      expect(_message({'card': {}}).linkPreview, isNull);
      expect(
          _message({
            'linkPreview': {'url': 'ftp://e.com', 'title': 'E'}
          }).linkPreview,
          isNull);
    });
  });

  group('the workspace switch', () {
    test('on unless the server says off', () {
      WidgetConfigModel cfg(Map<String, dynamic> extra) =>
          WidgetConfigModel.fromJson({'id': 'w', 'tenantId': 't', ...extra});
      expect(cfg({}).linkPreviews, isTrue);
      expect(cfg({'linkPreviews': true}).linkPreviews, isTrue);
      expect(cfg({'linkPreviews': false}).linkPreviews, isFalse);
    });
  });
}
