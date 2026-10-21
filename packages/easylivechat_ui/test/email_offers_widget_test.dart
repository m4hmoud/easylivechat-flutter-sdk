import 'package:easylivechat/easylivechat.dart';
import 'package:easylivechat_ui/src/email_offers.dart';
import 'package:easylivechat_ui/src/l10n.dart';
import 'package:easylivechat_ui/src/theme.dart';
import 'package:easylivechat_ui/src/views/email_card_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The web widget's two email offers (apps/widget EmailCard.tsx, Header.tsx,
/// and their rules in Embed.tsx): "Email me this chat" from the ⋯ menu and
/// under the survey, "Get the reply by email" once the visitor has written
/// while nobody can answer and we hold no address for them.
void main() {
  final en = ElcStrings.of('en');
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
  });

  ChatMessage msg(String id, SenderType from) => ChatMessage(
        id: id,
        conversationId: 'c1',
        body: 'Hello',
        senderType: from,
        contentType: MessageContentType.text,
        createdAt: DateTime.utc(2026, 10, 21, 9),
      );

  group('when "Email me this chat" is on the menu', () {
    final greeting = [msg('s1', SenderType.system)];
    final written = [...greeting, msg('a1', SenderType.agent)];

    test('a chat with something in it, the switch on', () {
      expect(
          elcCanEmailTranscript(
              transcriptEmailEnabled: true,
              phase: ChatPhase.chat,
              conversationId: 'c1',
              messages: written),
          isTrue);
    });

    test('not with the switch off, no chat, or only system lines', () {
      expect(
          elcCanEmailTranscript(
              transcriptEmailEnabled: false,
              phase: ChatPhase.chat,
              conversationId: 'c1',
              messages: written),
          isFalse);
      expect(
          elcCanEmailTranscript(
              transcriptEmailEnabled: true,
              phase: ChatPhase.prechat,
              conversationId: 'c1',
              messages: written),
          isFalse);
      expect(
          elcCanEmailTranscript(
              transcriptEmailEnabled: true,
              phase: ChatPhase.chat,
              conversationId: null,
              messages: written),
          isFalse);
      expect(
          elcCanEmailTranscript(
              transcriptEmailEnabled: true,
              phase: ChatPhase.chat,
              conversationId: 'c1',
              messages: greeting),
          isFalse);
    });
  });

  group('when "Get the reply by email" is asked', () {
    bool offer({
      bool enabled = true,
      ChatPhase phase = ChatPhase.chat,
      bool locked = false,
      String? conversationId = 'c1',
      bool hintKnown = true,
      String? hint,
      bool wrote = true,
      bool closed = true,
      bool queued = false,
      bool accepting = true,
      String? asked,
      String? dismissed,
    }) =>
        elcShouldOfferReplyEmail(
          replyEmailEnabled: enabled,
          phase: phase,
          composerLocked: locked,
          conversationId: conversationId,
          hintKnown: hintKnown,
          emailHint: hint,
          messages: [if (wrote) msg('m1', SenderType.customer)],
          workspaceClosed: closed,
          queued: queued,
          agentsAccepting: accepting,
          alreadyAskedFor: asked,
          dismissedFor: dismissed,
        );

    test('they wrote, nobody can answer, no address on file', () {
      expect(offer(), isTrue);
      expect(offer(closed: false, queued: true), isTrue);
      expect(offer(closed: false, accepting: false), isTrue);
    });

    test('not while somebody can answer', () {
      expect(offer(closed: false), isFalse);
    });

    test('not before they wrote, nor to someone we can already email', () {
      expect(offer(wrote: false), isFalse);
      expect(offer(hint: 'a•••@example.com'), isFalse);
      expect(offer(hintKnown: false), isFalse,
          reason: 'unknown is not "none": wait for the server');
    });

    test('once per conversation, and never again once dismissed', () {
      expect(offer(asked: 'c1'), isFalse);
      expect(offer(dismissed: 'c1'), isFalse);
      expect(offer(dismissed: 'c0'), isTrue);
    });

    test('not with the switch off, a locked composer, or off the thread', () {
      expect(offer(enabled: false), isFalse);
      expect(offer(locked: true), isFalse);
      expect(offer(phase: ChatPhase.feedback), isFalse);
      expect(offer(conversationId: null), isFalse);
    });
  });

  group('refusals, in words', () {
    test('the web widget\'s mapping', () {
      EasyLiveChatError e(String code, [int? status]) =>
          EasyLiveChatError(code, httpStatus: status);
      expect(elcEmailErrorText(e('TRANSCRIPT_RATE_LIMITED', 429), en),
          en.emailRateLimited);
      expect(elcEmailErrorText(e('UNKNOWN', 429), en), en.emailRateLimited);
      expect(
          elcEmailErrorText(e('EMAIL_UNSUBSCRIBED'), en), en.emailUnsubscribed);
      expect(elcEmailErrorText(e('INVALID_EMAIL'), en), en.invalidEmail);
      expect(elcEmailErrorText(e('NO_CONTACT_EMAIL'), en), en.invalidEmail);
      expect(elcEmailErrorText(e('NETWORK'), en), en.emailFailed);
      expect(elcEmailErrorText(Exception('boom'), en), en.emailFailed);
    });
  });

  group('the card', () {
    Future<List<String?>> pump(
      WidgetTester tester, {
      required ElcEmailCardMode mode,
      String? hint,
      ElcEmailResult result = const ElcEmailResult.sent('a•••@example.com'),
      VoidCallback? onClose,
      String locale = 'en',
      TextDirection direction = TextDirection.ltr,
    }) async {
      final submitted = <String?>[];
      await tester.pumpWidget(MaterialApp(
        home: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: ElcEmailCard(
              mode: mode,
              emailHint: hint,
              theme: theme.copyWith(direction: direction),
              strings: ElcStrings.of(locale),
              onSubmit: (email) async {
                submitted.add(email);
                return result;
              },
              onClose: onClose ?? () {},
            ),
          ),
        ),
      ));
      return submitted;
    }

    testWidgets('with an address on file: one tap, then it says where',
        (tester) async {
      var closed = 0;
      final submitted = await pump(tester,
          mode: ElcEmailCardMode.transcript,
          hint: 'a•••@example.com',
          onClose: () => closed++);
      expect(find.text('Email me this chat'), findsOneWidget);
      expect(find.text("We'll send a copy to \u2068a•••@example.com\u2069."),
          findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text('Send'));
      await tester.pump();
      expect(submitted, [null], reason: 'null = the address on file');
      expect(
          find.text('Sent to \u2068a•••@example.com\u2069.'), findsOneWidget);

      // Said for a moment, then out of the way.
      await tester.pump(const Duration(seconds: 4));
      expect(closed, 1);
    });

    testWidgets('another address: checked here first, then sent',
        (tester) async {
      final submitted = await pump(tester,
          mode: ElcEmailCardMode.transcript, hint: 'a•••@example.com');
      await tester.tap(find.text('Use another address'));
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'not-an-address');
      await tester.tap(find.text('Send'));
      await tester.pump();
      expect(find.text(en.invalidEmail), findsOneWidget);
      expect(submitted, isEmpty);

      await tester.enterText(find.byType(TextField), 'me@example.com');
      await tester.tap(find.text('Send'));
      await tester.pump();
      expect(submitted, ['me@example.com']);
    });

    testWidgets('no address on file: the field straight away', (tester) async {
      await pump(tester, mode: ElcEmailCardMode.transcript);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Use another address'), findsNothing);
    });

    testWidgets('a refusal is said in the card', (tester) async {
      await pump(tester,
          mode: ElcEmailCardMode.transcript,
          hint: 'a•••@example.com',
          result: ElcEmailResult.failed(en.emailRateLimited));
      await tester.tap(find.text('Send'));
      await tester.pump();
      expect(find.text(en.emailRateLimited), findsOneWidget);
      expect(find.text('Email me this chat'), findsOneWidget,
          reason: 'still the form, to try again later');
    });

    testWidgets('get the reply by email: asks, keeps, and says so',
        (tester) async {
      var closed = 0;
      final submitted = await pump(tester,
          mode: ElcEmailCardMode.notify, onClose: () => closed++);
      expect(find.text('Get the reply by email'), findsOneWidget);
      expect(find.text(en.notifyBody), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'ava@example.com');
      await tester.tap(find.text('Email me'));
      await tester.pump();
      expect(submitted, ['ava@example.com']);
      expect(
          find.text("We'll email \u2068a•••@example.com\u2069 if you've left "
              'by the time we reply.'),
          findsOneWidget);
      // Stays said until dismissed.
      await tester.pump(const Duration(seconds: 5));
      expect(closed, 0);
      await tester.tap(find.byTooltip('Dismiss'));
      expect(closed, 1);
    });

    testWidgets('"Not now" puts it away', (tester) async {
      var closed = 0;
      await pump(tester,
          mode: ElcEmailCardMode.notify, onClose: () => closed++);
      await tester.tap(find.text('Not now'));
      expect(closed, 1);
    });

    testWidgets('right to left: its words, the buttons from the left',
        (tester) async {
      await pump(tester,
          mode: ElcEmailCardMode.notify,
          locale: 'ckb',
          direction: TextDirection.rtl);
      final ckb = ElcStrings.of('ckb');
      expect(find.text(ckb.notifyTitle), findsOneWidget);
      final send = tester.getCenter(find.text(ckb.notifyButton));
      final dismiss = tester.getCenter(find.text(ckb.notifyDismiss));
      expect(send.dx, lessThan(dismiss.dx),
          reason: 'the action comes last, which in RTL is further left');
      // An address is typed left to right in every language.
      expect(tester.widget<TextField>(find.byType(TextField)).textDirection,
          TextDirection.ltr);
    });

    testWidgets('left to right: the action on the right', (tester) async {
      await pump(tester, mode: ElcEmailCardMode.notify);
      final send = tester.getCenter(find.text('Email me'));
      final dismiss = tester.getCenter(find.text('Not now'));
      expect(send.dx, greaterThan(dismiss.dx));
    });
  });

  test('the address check is the web widget\'s', () {
    expect(elcLooksLikeEmail('ava@example.com'), isTrue);
    expect(elcLooksLikeEmail(' ava@example.co.uk '), isTrue);
    expect(elcLooksLikeEmail('ava@example'), isFalse);
    expect(elcLooksLikeEmail('ava@@example.com'), isFalse);
    expect(elcLooksLikeEmail('a va@example.com'), isFalse);
    expect(elcLooksLikeEmail('ava@example.c'), isFalse);
  });

  group('the ⋯ menu', () {
    setUpAll(() async {
      await EasyLiveChat.instance.boot(const EasyLiveChatConfig(
        apiBase: 'https://api.example.com',
        tenantSlug: 'acme',
      ));
    });
    tearDownAll(() => EasyLiveChat.instance.shutdown());

    testWidgets('is not drawn with nothing in it', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          appBar: AppBar(actions: const [EasyLiveChatMenuButton()]),
        ),
      ));
      expect(EasyLiveChatMenuButton.hasItems, isFalse);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      expect(await EasyLiveChatMenuButton.emailTranscript(), isFalse,
          reason: 'a callback-slot item stays harmless');
    });
  });
}
