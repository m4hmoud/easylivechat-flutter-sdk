/// Rich cards, as the SDK reads them.
///
/// A port of `packages/shared/src/message-card.test.ts`, plus what a port has
/// to pin that the original does not: that Dart's own string and URL handling
/// hasn't crept back in. Every expectation marked "web" below was taken from
/// running the TypeScript validator itself, so a card this package accepts is a
/// card the widget and the dashboard accept.
library;

import 'package:easylivechat/easylivechat.dart';
import 'package:test/test.dart';

void main() {
  group('MessageCard.tryParse', () {
    test('keeps a well-formed card', () {
      expect(
        MessageCard.tryParse({
          'imageUrl': 'https://shop.example/parcel.png',
          'title': 'Order #1042 is on its way',
          'text': 'Arriving Friday, between 9 and 12.',
          'buttons': [
            {'label': 'Track parcel', 'url': 'https://shop.example/track/1042'},
          ],
        }),
        const MessageCard(
          imageUrl: 'https://shop.example/parcel.png',
          title: 'Order #1042 is on its way',
          text: 'Arriving Friday, between 9 and 12.',
          buttons: [
            MessageCardButton(
              label: 'Track parcel',
              url: 'https://shop.example/track/1042',
            ),
          ],
        ),
      );
    });

    test('needs a title — without one there is no card', () {
      expect(MessageCard.tryParse({'text': 'hi', 'buttons': []}), isNull);
      expect(MessageCard.tryParse({'title': '   '}), isNull);
      expect(MessageCard.tryParse({'title': 42}), isNull);
      expect(MessageCard.tryParse(null), isNull);
      expect(MessageCard.tryParse(['title']), isNull);
      expect(MessageCard.tryParse('title'), isNull);
    });

    test('refuses javascript: and other schemes on buttons, dropping just that button', () {
      final card = MessageCard.tryParse({
        'title': 'x',
        'buttons': [
          {'label': 'Bad', 'url': 'javascript:alert(1)'},
          {'label': 'Data', 'url': 'data:text/html,<script>'},
          {'label': 'Good', 'url': 'https://ok.example'},
        ],
      });
      expect(card?.buttons,
          const [MessageCardButton(label: 'Good', url: 'https://ok.example')]);
    });

    test('accepts our own uploads and https images, and drops anything else', () {
      String? image(Object? url) =>
          MessageCard.tryParse({'title': 'x', 'imageUrl': url})?.imageUrl;
      expect(image('/uploads/t1/2026-09/a.png'), '/uploads/t1/2026-09/a.png');
      expect(image('/uploads/../../etc/passwd'), isNull);
      expect(image('/uploads/a..b.png'), isNull);
      expect(image('javascript:alert(1)'), isNull);
      // web: an upload path is matched as written — no spaces, no padding.
      expect(image('/uploads/a b.png'), isNull);
      expect(image(' /uploads/a.png'), isNull);
      // web: a URL is trimmed.
      expect(image(' https://shop.example/p.png '), 'https://shop.example/p.png');
      expect(image('uploads/a.png'), isNull);
      expect(image(7), isNull);
    });

    test('caps the buttons and trims long fields', () {
      final many = [
        for (var i = 0; i < 6; i++)
          {'label': 'B$i', 'url': 'https://e.example/$i'},
      ];
      final card = MessageCard.tryParse({'title': 'T' * 200, 'buttons': many});
      expect(card?.buttons, hasLength(MessageCard.maxButtons));
      expect(card?.buttons.map((b) => b.label), ['B0', 'B1', 'B2']);
      expect(card?.title, hasLength(MessageCard.maxTitleLength));
    });

    test('drops a button with no label', () {
      expect(
        MessageCard.tryParse({
          'title': 'x',
          'buttons': [
            {'label': ' ', 'url': 'https://e.example'},
          ],
        })?.buttons,
        isEmpty,
      );
    });

    test('collapses whitespace in the title and labels, but keeps line breaks in the text', () {
      final card = MessageCard.tryParse({
        'title': '  Order\n\t #1042   is  on its way ',
        'text': '  Line one\n\nLine two  ',
        'buttons': [
          {'label': ' Track \n parcel ', 'url': '  https://e.example/a  '},
        ],
      })!;
      expect(card.title, 'Order #1042 is on its way');
      expect(card.text, 'Line one\n\nLine two');
      expect(card.buttons.single,
          const MessageCardButton(label: 'Track parcel', url: 'https://e.example/a'));
    });

    test('trims again after cutting, so a cap never leaves a trailing space', () {
      // web: 79 x, a space, then y — cut at 80 lands on the space.
      expect(MessageCard.tryParse({'title': '${'x' * 79} y'})?.title, 'x' * 79);
      expect(
        MessageCard.tryParse({'title': 'x', 'text': '${'y' * 299} z'})?.text,
        hasLength(299),
      );
      expect(
        MessageCard.tryParse({
          'title': 'x',
          'buttons': [
            {'label': '${'L' * 29} M', 'url': 'https://e.example'},
          ],
        })?.buttons.single.label,
        'L' * 29,
      );
    });

    test('reads whitespace the way JavaScript does, not the way Dart trims', () {
      // U+0085 is whitespace to Dart's String.trim() and not to JavaScript.
      // web: the server keeps it, so this must too.
      final card = MessageCard.tryParse({
        'title': ' Hi ',
        'text': 'x',
        'buttons': [
          {'label': '', 'url': 'https://e.example'},
        ],
      })!;
      expect(card.title, ' Hi ');
      expect(card.text, 'x');
      expect(card.buttons.single.label, '');
    });

    test('an empty text is no text', () {
      expect(MessageCard.tryParse({'title': 'x', 'text': '   '})?.text, isNull);
      expect(MessageCard.tryParse({'title': 'x', 'text': 5})?.text, isNull);
    });

    test('ignores entries that are not buttons, and buttons that are not a list', () {
      final card = MessageCard.tryParse({
        'title': 'x',
        'buttons': [
          {'label': 'A', 'url': 'https://e.example/a'},
          null,
          'b',
          ['label'],
          {'label': 42, 'url': 'https://e.example'},
          {'label': 'No url'},
        ],
      });
      expect(card?.buttons,
          const [MessageCardButton(label: 'A', url: 'https://e.example/a')]);
      expect(MessageCard.tryParse({'title': 'x', 'buttons': 'nope'})?.buttons, isEmpty);
    });

    test('the parsed buttons cannot be changed afterwards', () {
      final card = MessageCard.tryParse({
        'title': 'x',
        'buttons': [
          {'label': 'A', 'url': 'https://e.example'},
        ],
      })!;
      expect(() => card.buttons.add(card.buttons.first), throwsUnsupportedError);
    });
  });

  group('MessageCard.isSafeUrl', () {
    test('allows http and https only', () {
      expect(MessageCard.isSafeUrl('https://e.example'), isTrue);
      expect(MessageCard.isSafeUrl('http://e.example'), isTrue);
      expect(MessageCard.isSafeUrl('javascript:alert(1)'), isFalse);
      expect(MessageCard.isSafeUrl('mailto:a@b.c'), isFalse);
      expect(MessageCard.isSafeUrl('/relative'), isFalse);
      expect(MessageCard.isSafeUrl(42), isFalse);
      expect(MessageCard.isSafeUrl(null), isFalse);
    });

    test('holds links to 1000 characters', () {
      final url = 'https://e.example/${'a' * (MessageCard.maxUrlLength - 'https://e.example/'.length)}';
      expect(url, hasLength(MessageCard.maxUrlLength));
      expect(MessageCard.isSafeUrl(url), isTrue);
      expect(MessageCard.isSafeUrl('${url}b'), isFalse);
    });

    // Every row: what `isSafeCardUrl` in packages/shared returns for it.
    const web = <String, bool>{
      'HTTPS://E.EXAMPLE/x': true,
      '  https://e.example  ': true,
      'https:e.example': true,
      'https:///e.example': true,
      'https://user:pass@e.example': true,
      'https://e.exa@mple@x.com': true,
      'https://[::1]/': true,
      'https://127.0.0.1': true,
      'https://0x7f.1': true,
      'https://e.example:65535': true,
      'https://e.example:': true,
      'https://bücher.de/pfad': true,
      'https://%65xample.com': true,
      'https://e.example/path with space': true,
      'JavaScript:alert(1)': false,
      ' javascript:alert(1)': false,
      'data:text/html,<script>': false,
      'tel:+1234': false,
      'ftp://e.example': false,
      '//e.example': false,
      'https:': false,
      'https://': false,
      'https://@': false,
      'https://exa mple.com': false,
      'https://ex<ample.com': false,
      'https://ex%2Fample.com': false,
      'https://e.example:65536': false,
      'https://e.example:99999': false,
      'https://999.1.1.1': false,
      'https://4294967296': false,
      'https://[::1': false,
      'https://e.example': false,
    };
    for (final entry in web.entries) {
      test('agrees with the web on ${entry.key.replaceAll('', r'')}', () {
        expect(MessageCard.isSafeUrl(entry.key), entry.value);
      });
    }
  });

  group('MessageCardButton.uri', () {
    Uri? uri(String url) => MessageCardButton(label: 'x', url: url).uri;

    test('is the link itself for an ordinary link', () {
      expect(uri('https://shop.example/track/1042?ref=chat#top').toString(),
          'https://shop.example/track/1042?ref=chat#top');
      expect(uri('http://e.example').toString(), 'http://e.example');
    });

    test('is the link a browser would visit for one it repairs', () {
      expect(uri('https:e.example/p').toString(), 'https://e.example/p');
      expect(uri(r'https:\\e.example\p').toString(), 'https://e.example/p');
      expect(uri('HTTPS://E.EXAMPLE/x').toString(), 'https://e.example/x');
      expect(uri('https://0x7f.1/x').toString(), 'https://127.0.0.1/x');
      expect(uri('https://e.example:0443/x').toString(), 'https://e.example/x');
    });

    test('is null for anything that is not http or https', () {
      expect(uri('javascript:alert(1)'), isNull);
      expect(uri('mailto:a@b.c'), isNull);
    });
  });

  group('ChatMessage.card', () {
    Map<String, dynamic> row({String contentType = 'CARD', Object? card}) => {
          'id': 'm1',
          'conversationId': 'c1',
          'senderType': 'AGENT',
          'contentType': contentType,
          'body': 'Order #1042 is on its way\n\nTrack parcel: https://shop.example/t',
          'attachmentUrls': ['/uploads/t1/2026-09/parcel.png'],
          'createdAt': '2026-09-16T09:00:00Z',
          'metadata': {'card': card},
        };
    const valid = {
      'imageUrl': '/uploads/t1/2026-09/parcel.png',
      'title': 'Order #1042 is on its way',
      'buttons': [
        {'label': 'Track parcel', 'url': 'https://shop.example/t'},
      ],
    };

    test('is read from a CARD row off the socket or out of history', () {
      final m = ChatMessage.fromAny(row(card: valid));
      expect(m.contentType, MessageContentType.card);
      expect(m.card?.title, 'Order #1042 is on its way');
      expect(m.card?.imageUrl, '/uploads/t1/2026-09/parcel.png');
      expect(m.card?.buttons.single.url, 'https://shop.example/t');
    });

    test('is null on a CARD row whose card does not validate, so it reads as its text', () {
      expect(ChatMessage.fromAny(row(card: {'text': 'no title'})).card, isNull);
      expect(ChatMessage.fromAny(row(card: null)).card, isNull);
      expect(ChatMessage.fromAny(row()..remove('metadata')).card, isNull);
    });

    test('is null on any other kind of message, whatever its metadata says', () {
      expect(ChatMessage.fromAny(row(contentType: 'TEXT', card: valid)).card, isNull);
    });

    test('survives the copies a send and a receipt make of a message', () {
      final m = ChatMessage.fromAny(row(card: valid));
      expect(m.copyWith(deliveryStatus: MessageDeliveryStatus.read).card, m.card);
    });
  });
}
