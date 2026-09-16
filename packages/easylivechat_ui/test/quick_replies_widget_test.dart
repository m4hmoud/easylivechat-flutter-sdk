import 'dart:async';

import 'package:easylivechat/easylivechat.dart';
import 'package:easylivechat_ui/src/l10n.dart';
import 'package:easylivechat_ui/src/theme.dart';
import 'package:easylivechat_ui/src/views/quick_replies_view.dart';
import 'package:easylivechat_ui/src/views/thread_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Quick replies in the thread: the greeting's suggested answers and the
/// assistant's Yes / No, as one-tap buttons.
///
/// Which message offers them is unit-tested in the core package. What is
/// pinned here is the part that only exists on screen: that the thread draws
/// them under that message and nowhere else, takes them away the moment the
/// visitor answers, and that a tap sends the reply once — as the visitor's own
/// message — however fast they tap.
void main() {
  setUpAll(() async {
    // A booted client with no session: the thread binds to its listenables,
    // and a send with no socket fails locally rather than reaching a network.
    await EasyLiveChat.instance.boot(const EasyLiveChatConfig(
      apiBase: 'https://api.example.com',
      tenantSlug: 'acme',
    ));
  });

  tearDownAll(() => EasyLiveChat.instance.shutdown());

  // The controller's own notifiers, behind the read-only listenables the
  // client exposes — the way to put a transcript on screen without a server.
  ValueNotifier<List<ChatMessage>> messages() =>
      EasyLiveChat.instance.messages as ValueNotifier<List<ChatMessage>>;
  ValueNotifier<String> visitorMode() =>
      EasyLiveChat.instance.visitorMode as ValueNotifier<String>;

  setUp(() {
    ElcStrings.overrideAll(const {});
    ElcStrings.overrideByLocale(const {});
    ElcStrings.setLocale('en');
  });

  tearDown(() {
    messages().value = const [];
    visitorMode().value = 'CHAT';
  });

  const theme = EasyLiveChatTheme(
    primary: Color(0xFF7C3AED),
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF3F4F6),
    text: Color(0xFF111827),
  );

  var minute = 0;
  ChatMessage msg(
    String id,
    SenderType senderType, {
    String body = 'x',
    List<String>? replies,
    bool assistant = false,
  }) =>
      ChatMessage(
        id: id,
        conversationId: 'c1',
        body: body,
        senderType: senderType,
        contentType: MessageContentType.text,
        createdAt: DateTime.utc(2026, 9, 16, 9, minute++),
        metadata: {
          if (replies != null) 'quickReplies': replies,
          if (assistant) 'assistant': true,
        },
      );

  ChatMessage greeting({String id = 'greeting'}) => msg(
        id,
        SenderType.bot,
        body: 'Hi! How can we help?',
        replies: const ['Track my order', 'Talk to a person'],
      );

  Future<void> pump(
    WidgetTester tester, {
    Future<void> Function(String reply)? onQuickReply,
    bool withSendPath = true,
    TextDirection direction = TextDirection.ltr,
    String locale = 'en',
  }) async {
    ElcStrings.setLocale(locale);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ThreadView(
          theme: theme.copyWith(direction: direction),
          onQuickReply: withSendPath
              ? (onQuickReply ?? (_) async {})
              : null,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder repliesUnder(String messageId) => find.descendant(
        of: find.byKey(ValueKey(messageId)),
        matching: find.byType(ElcQuickReplies),
      );

  OutlinedButton button(WidgetTester tester, String label) =>
      tester.widget<OutlinedButton>(
          find.ancestor(of: find.text(label), matching: find.byType(OutlinedButton)));

  testWidgets('draws them under the newest message that offers them', (tester) async {
    messages().value = [msg('hi', SenderType.customer, body: 'hi'), greeting()];
    await pump(tester);

    expect(find.byType(ElcQuickReplies), findsOneWidget);
    expect(repliesUnder('greeting'), findsOneWidget);
    expect(find.text('Track my order'), findsOneWidget);
    expect(find.text('Talk to a person'), findsOneWidget);
    expect(button(tester, 'Track my order').onPressed, isNotNull);
  });

  testWidgets("draws the assistant's Yes / No under its handover offer", (tester) async {
    messages().value = [
      msg('q', SenderType.customer, body: 'Can I speak to someone?'),
      msg('offer', SenderType.bot,
          body: 'Shall I pass you to the team?',
          replies: const ['Yes, please', 'No, thanks'],
          assistant: true),
    ];
    await pump(tester);
    expect(repliesUnder('offer'), findsOneWidget);
    expect(find.text('Yes, please'), findsOneWidget);
    expect(find.text('No, thanks'), findsOneWidget);
  });

  testWidgets('never under an older message once the team has said more', (tester) async {
    messages().value = [greeting(), msg('a1', SenderType.agent, body: 'Sam here.')];
    await pump(tester);
    expect(find.byType(ElcQuickReplies), findsNothing);
    expect(find.text('Track my order'), findsNothing);
  });

  testWidgets('stay put through a system notice', (tester) async {
    messages().value = [greeting(), msg('sys', SenderType.system, body: 'Transferred')];
    await pump(tester);
    expect(repliesUnder('greeting'), findsOneWidget);
  });

  testWidgets('go the moment the visitor answers', (tester) async {
    messages().value = [greeting()];
    await pump(tester);
    expect(find.byType(ElcQuickReplies), findsOneWidget);

    messages().value = [
      ...messages().value,
      msg('answer', SenderType.customer, body: 'Where is my parcel?'),
    ];
    await tester.pumpAndSettle();
    expect(find.byType(ElcQuickReplies), findsNothing);
    expect(find.text('Track my order'), findsNothing);
  });

  testWidgets('a tap sends the reply once, however fast the second tap comes',
      (tester) async {
    final sent = <String>[];
    final server = Completer<void>();
    messages().value = [greeting()];
    await pump(tester, onQuickReply: (reply) {
      sent.add(reply);
      return server.future;
    });

    // Two taps inside one frame — the second lands before any rebuild.
    final onPressed = button(tester, 'Track my order').onPressed!;
    onPressed();
    onPressed();
    // And a third on the other reply, after the thread has rebuilt.
    await tester.pump();
    await tester.tap(find.text('Talk to a person'));
    await tester.pump();

    expect(sent, ['Track my order']);
    // Visible but disabled while that send is in flight.
    expect(button(tester, 'Track my order').onPressed, isNull);
    expect(button(tester, 'Talk to a person').onPressed, isNull);

    server.complete();
    await tester.pumpAndSettle();
    expect(button(tester, 'Talk to a person').onPressed, isNotNull);
  });

  testWidgets("the chat screen's send path puts the reply in the thread as the visitor's message",
      (tester) async {
    messages().value = [greeting()];
    await pump(tester, onQuickReply: ThreadView.sendReplyAsMessage);

    await tester.tap(find.text('Talk to a person'));
    await tester.tap(find.text('Talk to a person'), warnIfMissed: false);
    await tester.pumpAndSettle();

    final fromVisitor = messages().value.where((m) => m.isFromCustomer).toList();
    expect(fromVisitor, hasLength(1));
    expect(fromVisitor.single.body, 'Talk to a person');
    expect(fromVisitor.single.contentType, MessageContentType.text);
    // Answered, so nothing is on offer any more.
    expect(find.byType(ElcQuickReplies), findsNothing);
    // With no connection the send fails like any other — the visitor's own
    // bubble with its retry, not a silent drop.
    expect(find.text(ElcStrings.of('en').sendFailedRetry), findsOneWidget);
  });

  testWidgets('disabled while the workspace takes no messages, and back when it does',
      (tester) async {
    messages().value = [greeting()];
    visitorMode().value = 'NOTICE_ONLY';
    await pump(tester);
    expect(find.text('Track my order'), findsOneWidget);
    expect(button(tester, 'Track my order').onPressed, isNull);

    visitorMode().value = 'CHAT';
    await tester.pump();
    expect(button(tester, 'Track my order').onPressed, isNotNull);
  });

  testWidgets('a thread with no send path draws none', (tester) async {
    messages().value = [greeting()];
    await pump(tester, withSendPath: false);
    expect(find.byType(ElcQuickReplies), findsNothing);
  });

  testWidgets('announced as a group of suggested replies, in the visitor\'s language',
      (tester) async {
    final handle = tester.ensureSemantics();
    messages().value = [greeting()];
    await pump(tester, locale: 'ar', direction: TextDirection.rtl);

    expect(tester.getSemantics(find.byType(ElcQuickReplies)).label, 'ردود مقترحة');
    // Each reply is a button of its own, not folded into the group's label.
    expect(
      find.bySemanticsLabel('Track my order'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('in RTL they wrap from the right, under the team\'s bubble', (tester) async {
    messages().value = [greeting()];
    await pump(tester, direction: TextDirection.rtl);

    final first = tester.getRect(find.ancestor(
        of: find.text('Track my order'), matching: find.byType(OutlinedButton)));
    final second = tester.getRect(find.ancestor(
        of: find.text('Talk to a person'), matching: find.byType(OutlinedButton)));
    // First reply on the leading (right) edge, the next one to its left.
    expect(first.right, greaterThan(second.right));
    final screen = tester.getRect(find.byType(Scaffold));
    expect(screen.right - first.right, lessThan(second.left - screen.left));
  });

  testWidgets('wear the workspace accent, and no default Material colour', (tester) async {
    messages().value = [greeting()];
    await pump(tester);

    final style = button(tester, 'Track my order').style!;
    const idle = <WidgetState>{};
    expect(style.side!.resolve(idle)!.color, theme.primary);
    expect(style.foregroundColor!.resolve(idle), theme.primary);
    expect(style.backgroundColor!.resolve(idle), theme.background);
    expect(style.backgroundColor!.resolve({WidgetState.pressed}), theme.primary);
    expect(style.shape!.resolve(idle), isA<StadiumBorder>());
  });

  testWidgets('a long reply wraps inside the bubble width instead of overflowing',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    messages().value = [
      msg('g', SenderType.bot,
          body: 'Hi!',
          replies: const [
            'I would like to change the delivery address on my last order please',
          ]),
    ];
    await pump(tester);
    expect(tester.takeException(), isNull);
    final pill = tester.getRect(find.byType(OutlinedButton));
    expect(pill.width, lessThanOrEqualTo(320 * 0.68 + 0.01));
    expect(pill.height, greaterThan(40));
  });
}
