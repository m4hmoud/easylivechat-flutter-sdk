/// The help screen: list → search → article → "Was this helpful?" → chat.
///
/// Driven through a fake [ElcHelpApi] so it needs neither a booted SDK nor a
/// network. Also covers the renderer's link handling (only checked schemes
/// are tappable) and RTL: an Arabic visitor gets the Arabic chrome laid out
/// right-to-left.
library;

import 'package:easylivechat/easylivechat.dart';
import 'package:easylivechat_ui/src/help_screen.dart';
import 'package:easylivechat_ui/src/l10n.dart';
import 'package:easylivechat_ui/src/views/help_markdown_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';

class _FakeApi extends ElcHelpApi {
  final List<String> queries = [];
  final List<String> opened = [];
  final List<(String, bool)> ratings = [];

  @override
  Future<HelpArticleList> list(String query) async {
    queries.add(query);
    if (query.isEmpty) {
      return const HelpArticleList(enabled: true, articles: [
        HelpArticleSummary(
            id: 'a1', title: 'Reset your password', excerpt: 'Open Settings'),
        HelpArticleSummary(id: 'a2', title: 'Shipping times'),
      ]);
    }
    if (query == 'zzz') return const HelpArticleList(enabled: true);
    return const HelpArticleList(enabled: true, articles: [
      HelpArticleSummary(id: 'a2', title: 'Shipping times'),
    ]);
  }

  @override
  Future<HelpArticle> article(String id) async {
    opened.add(id);
    if (id == 'gone') {
      throw const EasyLiveChatError(EasyLiveChatErrorCode.notFound,
          httpStatus: 404);
    }
    return HelpArticle(
      id: id,
      title: 'Reset your password',
      body: '## Steps\n\n1. Open **Settings**\n2. Read [the guide](https://acme.com/guide)',
      locale: 'en',
    );
  }

  @override
  Future<void> rate(String id, bool helpful) async => ratings.add((id, helpful));
}

Widget _host(Widget child) => MaterialApp(home: child);

/// The recognizer behind the first span whose text contains [needle].
TapGestureRecognizer? _recognizerFor(WidgetTester tester, String needle) {
  TapGestureRecognizer? found;
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    rich.text.visitChildren((span) {
      if (found == null &&
          span is TextSpan &&
          (span.text ?? '').contains(needle) &&
          span.recognizer is TapGestureRecognizer) {
        found = span.recognizer! as TapGestureRecognizer;
      }
      return found == null;
    });
  }
  return found;
}

void main() {
  tearDown(() => ElcStrings.setLocale(null));

  testWidgets('lists the top articles before anything is typed',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(_host(EasyLiveChatHelpScreen(api: api)));
    await tester.pumpAndSettle();

    expect(api.queries, ['']);
    expect(find.text('Popular articles'), findsOneWidget);
    expect(find.text('Reset your password'), findsOneWidget);
    expect(find.text('Shipping times'), findsOneWidget);
    expect(find.text('Still need help?'), findsOneWidget);
  });

  testWidgets('searches once typing pauses, and says when nothing matches',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(_host(EasyLiveChatHelpScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'ship');
    // Debounced: nothing yet.
    expect(api.queries, ['']);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(api.queries, ['', 'ship']);
    expect(find.text('Reset your password'), findsNothing);
    expect(find.text('Shipping times'), findsOneWidget);
    expect(find.bySemanticsLabel('Articles found: 1'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('No articles match your search.'), findsOneWidget);

    // Clearing goes back to the top list.
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(api.queries.last, '');
    expect(find.text('Popular articles'), findsOneWidget);
  });

  testWidgets('a one-character query is still the top list', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(_host(EasyLiveChatHelpScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 's');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(api.queries, [''], reason: 'nothing new to ask the server');
  });

  testWidgets('opens an article, records the answer, and starts a chat',
      (tester) async {
    final api = _FakeApi();
    var startedChat = 0;
    await tester.pumpWidget(_host(EasyLiveChatHelpScreen(
      api: api,
      onStartChat: () => startedChat++,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reset your password'));
    await tester.pumpAndSettle();
    expect(api.opened, ['a1']);
    expect(find.text('Steps'), findsOneWidget);
    expect(find.text('Was this helpful?'), findsOneWidget);

    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    expect(api.ratings, [('a1', true)]);
    expect(find.text('Thanks for your feedback.'), findsOneWidget);
    expect(find.text('Was this helpful?'), findsNothing);

    await tester.tap(find.text('Start a chat'));
    expect(startedChat, 1);

    // Back returns to the list, not out of help.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Popular articles'), findsOneWidget);
  });

  testWidgets('an article that has gone says so', (tester) async {
    await tester.pumpWidget(_host(EasyLiveChatHelpScreen(
      api: _FakeApi(),
      initialArticleId: 'gone',
    )));
    await tester.pumpAndSettle();
    expect(find.text('This article is no longer available.'), findsOneWidget);
  });

  testWidgets('Arabic chrome, laid out right to left', (tester) async {
    await tester.pumpWidget(_host(EasyLiveChatHelpScreen(
      api: _FakeApi(),
      locale: 'ar',
      directionOverride: TextDirection.rtl,
    )));
    await tester.pumpAndSettle();

    expect(find.text('المقالات الأكثر قراءة'), findsOneWidget);
    expect(find.text('ابدأ محادثة'), findsOneWidget);
    final header = tester.element(find.text('مقالات المساعدة'));
    expect(Directionality.of(header), TextDirection.rtl);
    // The back arrow sits on the reading side: the right edge in RTL.
    final back = tester.getCenter(find.byTooltip('رجوع'));
    expect(back.dx, greaterThan(400));
  });

  testWidgets('the list rows are buttons a screen reader can name',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host(EasyLiveChatHelpScreen(api: _FakeApi())));
    await tester.pumpAndSettle();
    final node = tester.getSemantics(find.text('Shipping times'));
    expect(node.label, 'Shipping times');
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(
      find.ancestor(
        of: find.text('Shipping times'),
        matching: find.byWidgetPredicate(
            (w) => w is Semantics && (w.properties.button ?? false)),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  group('ElcHelpMarkdown links', () {
    Widget body(String md, List<Uri> opened) => _host(Scaffold(
          body: ElcHelpMarkdown(
            markdown: md,
            textColor: const Color(0xFF0F172A),
            linkColor: const Color(0xFF2563EB),
            surfaceColor: const Color(0xFFF1F5F9),
            onOpenLink: (uri) async => opened.add(uri),
          ),
        ));

    testWidgets('a checked link opens through onOpenLink', (tester) async {
      final opened = <Uri>[];
      await tester.pumpWidget(body('Read [the guide](https://acme.com/g)', opened));
      _recognizerFor(tester, 'the guide')!.onTap!();
      await tester.pump();
      expect(opened, [Uri.parse('https://acme.com/g')]);
    });

    testWidgets('a javascript: link is plain text', (tester) async {
      final opened = <Uri>[];
      await tester
          .pumpWidget(body('[click me](javascript:alert(1))', opened));
      expect(_recognizerFor(tester, 'click'), isNull);
      expect(find.textContaining('javascript:alert(1)'), findsOneWidget);
    });

    testWidgets('a heading is announced as one', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(body('# Returns', []));
      expect(tester.getSemantics(find.text('Returns')).label, 'Returns');
      expect(
        find.ancestor(
          of: find.text('Returns'),
          matching: find.byWidgetPredicate(
              (w) => w is Semantics && (w.properties.header ?? false)),
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  group('offerHelpEntry', () {
    final on = WidgetConfigModel.fromJson(const {'helpArticlesEnabled': true});
    final off = WidgetConfigModel.fromJson(const {});
    ChatMessage msg(String senderType) => ChatMessage.fromAny({
          'id': 'm-$senderType',
          'conversationId': 'c1',
          'senderType': senderType,
          'contentType': 'TEXT',
          'body': 'hi',
          'createdAt': '2026-10-17T10:00:00.000Z',
        });

    test('only when the workspace shows help', () {
      expect(offerHelpEntry(off, const []), isFalse);
      expect(offerHelpEntry(null, const []), isFalse);
      expect(offerHelpEntry(on, const []), isTrue);
    });

    test('until the visitor has written', () {
      expect(offerHelpEntry(on, [msg('AGENT')]), isTrue);
      expect(offerHelpEntry(on, [msg('AGENT'), msg('CUSTOMER')]), isFalse);
    });
  });
}
