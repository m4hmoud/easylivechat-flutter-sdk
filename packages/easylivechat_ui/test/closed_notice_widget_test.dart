import 'package:easylivechat/easylivechat.dart';
import 'package:easylivechat_ui/src/l10n.dart';
import 'package:easylivechat_ui/src/theme.dart';
import 'package:easylivechat_ui/src/views/closed_notice_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The notice while the workspace is shut, worded by the web widget's rule
/// (`closedBannerText`, apps/widget/src/app/embed/Embed.tsx): the business's
/// own notice ALWAYS wins; without one, the assistant's wording while it
/// covers; the reopening time stays — on the banner AND on the closed screen.
///
/// Before this the banner dropped the tenant's notice whenever the assistant
/// covered, and the closed screen never said the assistant could help.
void main() {
  final en = ElcStrings.of('en');

  setUp(() {
    ElcStrings.overrideAll(const {});
    ElcStrings.overrideByLocale(const {});
    ElcStrings.setLocale('en');
  });

  group('closedNoticeText', () {
    final reopens = DateTime(2026, 10, 20, 9);

    test("the business's own notice always wins", () {
      for (final covers in [false, true]) {
        for (final locked in [false, true]) {
          for (final reason in ['AFTER_HOURS', 'NO_AGENTS', 'HOLIDAY']) {
            expect(
              closedNoticeText(en,
                  tenantNotice: '  Back on Monday — call 0750 if urgent.  ',
                  assistantCovers: covers,
                  composerLocked: locked,
                  reason: reason,
                  nextOpenAt: reopens,
                  nextOpenLocal: '09:00'),
              'Back on Monday — call 0750 if urgent.',
            );
          }
        }
      }
    });

    test('without one: closed, then when a person is back', () {
      expect(
        closedNoticeText(en,
            reason: 'AFTER_HOURS', nextOpenAt: reopens, nextOpenLocal: '09:00'),
        '${en.closedNotice} ${en.backAt.replaceAll('{time}', '09:00')}',
      );
      expect(closedNoticeText(en, reason: 'AFTER_HOURS'), en.closedNotice);
    });

    test('the assistant covering: its wording, and the reopening time stays',
        () {
      expect(
        closedNoticeText(en,
            reason: 'AFTER_HOURS',
            assistantCovers: true,
            nextOpenAt: reopens,
            nextOpenLocal: '09:00'),
        '${en.closedAssistantNotice} ${en.backAt.replaceAll('{time}', '09:00')}',
      );
    });

    test('busy rather than shut', () {
      expect(closedNoticeText(en, reason: 'NO_AGENTS'), en.noAgentsNotice);
      expect(closedNoticeText(en, reason: 'NO_AGENTS', assistantCovers: true),
          en.noAgentsAssistantNotice);
    });

    test('a locked composer is told when the team is back, or that it will be',
        () {
      expect(
        closedNoticeText(en,
            composerLocked: true,
            assistantCovers: true,
            nextOpenAt: reopens,
            nextOpenLocal: '06:00'),
        en.backAt.replaceAll('{time}', '06:00'),
      );
      expect(closedNoticeText(en, composerLocked: true), en.closedReadOnly);
    });

    test("the business's clock; the device's only for an older server", () {
      expect(
          closedNoticeText(en, nextOpenAt: reopens, nextOpenLocal: '12:00'),
          endsWith('12:00.'));
      expect(closedNoticeText(en, nextOpenAt: reopens), endsWith('09:00.'));
      // No instant, no time — as on the web.
      expect(closedNoticeText(en, nextOpenLocal: '12:00'), en.closedNotice);
    });

    test('a named closure, when the assistant is not covering', () {
      expect(closedNoticeText(en, reason: 'HOLIDAY', closureLabel: 'Eid'),
          en.closedForLabel.replaceAll('{label}', 'Eid'));
      expect(
          closedNoticeText(en,
              reason: 'HOLIDAY', closureLabel: 'Eid', assistantCovers: true),
          en.closedAssistantNotice);
    });

    test('in the visitor\'s language', () {
      ElcStrings.setLocale(null);
      final ckb = ElcStrings.of('ckb');
      expect(closedNoticeText(ckb, reason: 'NO_AGENTS', assistantCovers: true),
          'ئێستا هەموو خەریکن، بەڵام یاریدەدەرەکەمان دەتوانێت لەم ماوەیەدا یارمەتیت بدات.');
    });
  });

  group('on screen', () {
    setUpAll(() async {
      await EasyLiveChat.instance.boot(const EasyLiveChatConfig(
        apiBase: 'https://api.example.com',
        tenantSlug: 'acme',
      ));
    });

    tearDownAll(() => EasyLiveChat.instance.shutdown());

    const theme = EasyLiveChatTheme(
      primary: Color(0xFF2563EB),
      background: Color(0xFFFFFFFF),
      surface: Color(0xFFF1F5F9),
      text: Color(0xFF0F172A),
    );

    WidgetConfigModel config({String? notice}) => WidgetConfigModel.fromJson({
          'id': 'w1',
          'tenantId': 't1',
          'locale': 'en',
          // The schema default nobody typed — never the notice.
          'offlineMessage': "We're offline — leave us a message.",
          if (notice != null) 'offlineInfoText': notice,
        });

    ValueNotifier<bool> covers() =>
        EasyLiveChat.instance.assistantCovers as ValueNotifier<bool>;
    ValueNotifier<String> reason() =>
        EasyLiveChat.instance.availabilityReason as ValueNotifier<String>;

    setUp(() {
      covers().value = false;
      reason().value = 'AFTER_HOURS';
    });

    Future<void> pump(WidgetTester tester, Widget child) =>
        tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

    testWidgets("the banner keeps the business's notice while the assistant "
        'covers', (tester) async {
      covers().value = true;
      await pump(tester,
          ClosedNoticeBanner(config: config(notice: 'Closed for stocktake.'), theme: theme));
      expect(find.text('Closed for stocktake.'), findsOneWidget);
      expect(find.text(en.closedAssistantNotice), findsNothing);
    });

    testWidgets('the closed screen keeps it too', (tester) async {
      covers().value = true;
      await pump(tester,
          ClosedNoticeView(config: config(notice: 'Closed for stocktake.'), theme: theme));
      expect(find.text('Closed for stocktake.'), findsOneWidget);
    });

    testWidgets('without one, both say the assistant can help — not the '
        'leave-a-message default', (tester) async {
      covers().value = true;
      await pump(tester, ClosedNoticeView(config: config(), theme: theme));
      expect(find.text(en.closedAssistantNotice), findsOneWidget);
      expect(find.textContaining('leave us a message'), findsNothing);

      await pump(tester, ClosedNoticeBanner(config: config(), theme: theme));
      expect(find.text(en.closedAssistantNotice), findsOneWidget);
      expect(find.textContaining('leave us a message'), findsNothing);
    });

    testWidgets('follows the availability live', (tester) async {
      await pump(tester, ClosedNoticeBanner(config: config(), theme: theme));
      expect(find.text(en.closedNotice), findsOneWidget);

      covers().value = true;
      await tester.pump();
      expect(find.text(en.closedAssistantNotice), findsOneWidget);

      reason().value = 'NO_AGENTS';
      await tester.pump();
      expect(find.text(en.noAgentsAssistantNotice), findsOneWidget);
    });

    testWidgets('fills in the visitor variables of the business\'s notice',
        (tester) async {
      await pump(
        tester,
        ClosedNoticeBanner(
          config: WidgetConfigModel.fromJson({
            'id': 'w1',
            'tenantId': 't1',
            'offlineInfoText': 'Sorry %name%, we are closed.',
            'defaultCustomerName': 'friend',
          }),
          theme: theme,
        ),
      );
      expect(find.text('Sorry friend, we are closed.'), findsOneWidget);
    });

    testWidgets('mirrors in RTL', (tester) async {
      ElcStrings.setLocale(null);
      await tester.pumpWidget(MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: ClosedNoticeBanner(
              config: WidgetConfigModel.fromJson(
                  {'id': 'w1', 'tenantId': 't1', 'locale': 'ar'}),
              theme: theme,
            ),
          ),
        ),
      ));
      final text = find.text(ElcStrings.of('ar').closedNotice);
      expect(text, findsOneWidget);
      expect(tester.widget<Text>(text).textAlign, TextAlign.start);
      // Starts at the right edge.
      expect(tester.getTopRight(text).dx, closeTo(800 - 16, 1));
    });
  });
}
