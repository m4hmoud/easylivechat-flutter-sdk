import 'package:easylivechat_ui/src/l10n.dart';
import 'package:easylivechat_ui/src/theme.dart';
import 'package:easylivechat_ui/src/views/emoji_search.dart';
import 'package:easylivechat_ui/src/views/reactions_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The picker's search — the web widget's (apps/widget EmojiPicker.tsx, over
/// `searchEmoji` in packages/shared/src/emoji.ts): every query word must start
/// one of the emoji's English words, exact beats prefix, the shared order
/// breaks ties, and an emoji typed in finds itself. The expectations below are
/// the shared package's own (emoji.test.ts), so both pickers find the same.
void main() {
  group('searchEmoji', () {
    test('finds by word start, every word, best match first', () {
      expect(searchEmoji('joy').first, '😂');
      expect(searchEmoji('thumbs up'), contains('👍'));
      expect(searchEmoji('pizz'), contains('🍕'));
      expect(searchEmoji('germany'), contains('🇩🇪'));
      expect(searchEmoji('🍕').first, '🍕');
      expect(searchEmoji('   '), isEmpty);
      expect(searchEmoji('zzzqqq'), isEmpty);
    });

    test('case and spacing do not matter', () {
      expect(searchEmoji('  JOY ').first, '😂');
      expect(searchEmoji('Thumbs   UP'), contains('👍'));
    });

    test('an exact word outranks a word it merely starts', () {
      // "cat" is a word of 🐈 and only the start of "catch"-like words
      // elsewhere: the exact ones come first.
      final cats = searchEmoji('cat');
      expect(cats.take(3), anyElement(anyOf('🐱', '🐈')));
    });

    test('at most 120, as on the web', () {
      // "s" starts a word of most of the table.
      expect(searchEmoji('s'), hasLength(120));
      expect(searchEmoji('s', limit: 5), hasLength(5));
    });

    test('every category still reads its emoji in order', () {
      expect(emojiOf('smileys').first, '😀');
      expect(emojiOf('flags'), contains('🏁'));
      expect(emojiOf('nope'), isEmpty);
    });
  });

  group('the picker\'s search field', () {
    const theme = EasyLiveChatTheme(
      primary: Color(0xFF2563EB),
      background: Color(0xFFFFFFFF),
      surface: Color(0xFFF1F5F9),
      text: Color(0xFF0F172A),
    );

    setUp(() {
      ElcStrings.overrideAll(const {});
      ElcStrings.overrideByLocale(const {});
      ElcStrings.setLocale(null);
      elcRecentEmoji = [];
    });

    Future<List<String>> pump(WidgetTester tester,
        {String locale = 'en',
        TextDirection direction = TextDirection.ltr}) async {
      final picked = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: SizedBox(
              height: 360,
              child: ElcEmojiPicker(
                theme: theme,
                strings: ElcStrings.of(locale),
                onPick: picked.add,
              ),
            ),
          ),
        ),
      ));
      return picked;
    }

    testWidgets('a query swaps the categories for its matches', (tester) async {
      await pump(tester);
      expect(find.text('Search emoji'), findsOneWidget);
      expect(find.text('Smileys & emotion'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'pizza');
      await tester.pump();
      expect(find.text('🍕'), findsOneWidget);
      expect(find.text('Smileys & emotion'), findsNothing,
          reason: 'the section headings go while there are results');
      expect(find.bySemanticsLabel('Results'), findsOneWidget);
    });

    testWidgets('nothing found says so', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'zzzqqq');
      await tester.pump();
      expect(find.text('No emoji found'), findsOneWidget);
    });

    testWidgets('submitting picks the first match, as Enter does on the web',
        (tester) async {
      final picked = await pump(tester);
      await tester.enterText(find.byType(TextField), 'joy');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(picked, ['😂']);
      expect(elcRecentEmoji, ['😂']);
    });

    testWidgets('a match tapped is picked', (tester) async {
      final picked = await pump(tester);
      await tester.enterText(find.byType(TextField), 'pizza');
      await tester.pump();
      await tester.tap(find.text('🍕'));
      expect(picked, ['🍕']);
    });

    testWidgets('the × empties it; a tab leaves the search', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'pizza');
      await tester.pump();
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(find.text('Smileys & emotion'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'pizza');
      await tester.pump();
      await tester.tap(find.byTooltip('Flags'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Flags'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty);
    });

    testWidgets('in Arabic: its words, and the field\'s start on the right',
        (tester) async {
      await pump(tester, locale: 'ar', direction: TextDirection.rtl);
      expect(find.text('ابحث عن رمز تعبيري'), findsOneWidget);
      final field = tester.getRect(find.byType(TextField));
      final icon = tester.getRect(find.byIcon(Icons.search_rounded));
      expect(icon.center.dx, greaterThan(field.center.dx),
          reason: 'the search icon leads, on the right in RTL');
    });
  });
}
