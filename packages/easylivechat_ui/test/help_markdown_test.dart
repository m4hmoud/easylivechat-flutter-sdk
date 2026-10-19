/// The Dart port of the help-article markdown dialect.
///
/// Mirrors `packages/shared/src/help-markdown.test.ts` case for case — the two
/// parsers must agree, or an article reads differently in the app and on the
/// web — plus the safety rules that matter most on a device: nothing but
/// http(s)/mailto:/tel: becomes something to tap, and raw HTML stays text.
library;

import 'package:easylivechat_ui/src/help/help_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

String _kind(HelpBlock b) => switch (b) {
      HelpHeading() => 'heading',
      HelpParagraph() => 'paragraph',
      HelpList() => 'list',
      HelpQuote() => 'quote',
      HelpCodeBlock() => 'code',
      HelpRule() => 'rule',
    };

bool _containsLink(List<HelpInline> nodes) => nodes.any((n) => switch (n) {
      HelpLink() => true,
      HelpStrong(:final children) || HelpEm(:final children) =>
        _containsLink(children),
      _ => false,
    });

bool _containsImage(List<HelpInline> nodes) =>
    nodes.any((n) => n is HelpImage);

void main() {
  test('reads headings, paragraphs with line breaks, lists, quotes, code, rules',
      () {
    final blocks = parseHelpMarkdown([
      '# Returns',
      'You can send it back',
      'within 30 days.',
      '',
      '- Pack it',
      '- Print the label',
      '',
      '2. Second',
      '3. Third',
      '',
      '> Keep the receipt',
      '',
      '```',
      'ORDER-123',
      '```',
      '---',
    ].join('\n'));
    expect(blocks.map(_kind).toList(),
        ['heading', 'paragraph', 'list', 'list', 'quote', 'code', 'rule']);

    final p = blocks[1] as HelpParagraph;
    expect(p.children, hasLength(3));
    expect((p.children[0] as HelpText).text, 'You can send it back');
    expect(p.children[1], isA<HelpBreak>());
    expect((p.children[2] as HelpText).text, 'within 30 days.');

    final bullets = blocks[2] as HelpList;
    expect(bullets.ordered, isFalse);
    expect(bullets.items, hasLength(2));

    final numbered = blocks[3] as HelpList;
    expect(numbered.ordered, isTrue);
    expect(numbered.start, 2);

    expect((blocks[5] as HelpCodeBlock).text, 'ORDER-123');
  });

  test('deep headings draw as level 3', () {
    final h = parseHelpMarkdown('##### Small').single as HelpHeading;
    expect(h.level, 3);
  });

  test('reads emphasis, code, links and images', () {
    final p = parseHelpMarkdown(
      '**Bold** and *it* and `x` and [the page](https://acme.com/a) '
      '![shot](https://acme.com/s.png)',
    ).single as HelpParagraph;
    final c = p.children;
    expect(((c[0] as HelpStrong).children.single as HelpText).text, 'Bold');
    expect((c[1] as HelpText).text, ' and ');
    expect(((c[2] as HelpEm).children.single as HelpText).text, 'it');
    expect((c[4] as HelpCode).text, 'x');
    final link = c[6] as HelpLink;
    expect(link.href, 'https://acme.com/a');
    expect((link.children.single as HelpText).text, 'the page');
    final image = c[8] as HelpImage;
    expect(image.src, 'https://acme.com/s.png');
    expect(image.alt, 'shot');
  });

  test('mailto: and tel: links are allowed', () {
    final p = parseHelpMarkdown(
            'Write to [us](mailto:help@acme.com) or [call](tel:+9647501234567)')
        .single as HelpParagraph;
    final hrefs =
        p.children.whereType<HelpLink>().map((l) => l.href).toList();
    expect(hrefs, ['mailto:help@acme.com', 'tel:+9647501234567']);
  });

  test('never turns another scheme into a link or an image', () {
    final p = parseHelpMarkdown(
            '[click](javascript:alert(1)) ![x](data:image/png;base64,AAA) '
            '[rel](/relative) ![ftp](ftp://acme.com/a.png)')
        .single as HelpParagraph;
    expect(_containsLink(p.children), isFalse);
    expect(_containsImage(p.children), isFalse);
    expect(safeHelpHref('javascript:alert(1)'), isNull);
    expect(safeHelpHref('JavaScript:alert(1)'), isNull);
    expect(safeHelpHref('mailto:help@acme.com'), 'mailto:help@acme.com');
    expect(safeHelpImage('https://acme.com/a.png'), 'https://acme.com/a.png');
    expect(safeHelpImage('mailto:a@b.c'), isNull);
  });

  test('shows raw HTML as the characters it is', () {
    final p = parseHelpMarkdown('<img src=x onerror=alert(1)>').single
        as HelpParagraph;
    expect(p.children, hasLength(1));
    expect((p.children.single as HelpText).text, '<img src=x onerror=alert(1)>');
  });

  test('links bare URLs, trimming the sentence punctuation', () {
    final p = parseHelpMarkdown('See https://acme.com/help.').single
        as HelpParagraph;
    expect((p.children[0] as HelpText).text, 'See ');
    expect((p.children[1] as HelpLink).href, 'https://acme.com/help');
    expect((p.children[2] as HelpText).text, '.');
  });

  test('leaves snake_case, sums and lone stars alone', () {
    final p = parseHelpMarkdown('use order_id_here and 2*3 is * fine').single
        as HelpParagraph;
    expect(helpInlineText(p.children), 'use order_id_here and 2*3 is * fine');
    expect(p.children.whereType<HelpEm>(), isEmpty);
  });

  test('a backslash escapes markup', () {
    final p = parseHelpMarkdown(r'\*not bold\*').single as HelpParagraph;
    expect(helpInlineText(p.children), '*not bold*');
  });

  test('an indented line carries on the list item above it', () {
    final list = parseHelpMarkdown('- First\n  still first\n- Second').single
        as HelpList;
    expect(list.items, hasLength(2));
    expect(helpInlineText(list.items.first), 'First still first');
  });

  test('stays fast on pathological input', () {
    final evil = '**a ' * 10000 + '[(' * 5000;
    final watch = Stopwatch()..start();
    parseHelpMarkdown(evil);
    expect(watch.elapsedMilliseconds, lessThan(2000));
  });

  test('empty input is no blocks', () {
    expect(parseHelpMarkdown(null), isEmpty);
    expect(parseHelpMarkdown(''), isEmpty);
    expect(parseHelpMarkdown('\n\n  \n'), isEmpty);
  });
}
