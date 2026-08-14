import 'package:easylivechat/easylivechat.dart';
import 'package:easylivechat_ui/src/l10n.dart';
import 'package:easylivechat_ui/src/theme.dart';
import 'package:easylivechat_ui/src/views/thread_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The ticks a visitor reads their own send by.
///
/// `receiptFor` is unit-tested next door; what this pins is the half that only
/// exists on screen — that the bubble asks for a receipt at all, that the read
/// state is visually distinct from sent rather than the same glyph in the same
/// colour, and that a screen reader is given something to say about a control
/// whose entire content is a 13px icon.
void main() {
  const theme = EasyLiveChatTheme(
    primary: Color(0xFF2563EB),
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF3F4F6),
    text: Color(0xFF111827),
  );

  final sentAt = DateTime.utc(2026, 8, 14, 10, 0, 0);

  ChatMessage customer({
    String id = 'm1',
    bool isOptimistic = false,
    bool failed = false,
    MessageDeliveryStatus status = MessageDeliveryStatus.sent,
  }) =>
      ChatMessage(
        id: id,
        conversationId: 'conv-1',
        body: 'hello',
        senderType: SenderType.customer,
        contentType: MessageContentType.text,
        deliveryStatus: status,
        isOptimistic: isOptimistic,
        failed: failed,
        createdAt: sentAt,
      );

  Future<void> pump(
    WidgetTester tester,
    ChatMessage message, {
    DateTime? agentLastReadAt,
  }) async {
    ElcStrings.setLocale('en');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MessageBubble(
          message: message,
          theme: theme,
          showAgentName: false,
          strings: ElcStrings.of('en'),
          agentLastReadAt: agentLastReadAt,
        ),
      ),
    ));
  }

  testWidgets('an unread send shows a single tick', (tester) async {
    await pump(tester, customer());
    expect(find.byIcon(Icons.done_rounded), findsOneWidget);
    expect(find.byIcon(Icons.done_all_rounded), findsNothing);
  });

  testWidgets('a read send shows the double tick in the accent colour',
      (tester) async {
    await pump(tester, customer(),
        agentLastReadAt: sentAt.add(const Duration(minutes: 1)));

    expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
    expect(find.byIcon(Icons.done_rounded), findsNothing);

    // The colour is the signal that separates read from sent — a double tick
    // rendered in the muted colour would read as "sent" at a glance.
    final icon = tester.widget<Icon>(find.byIcon(Icons.done_all_rounded));
    expect(icon.color, theme.primary);
  });

  testWidgets('an in-flight send shows a clock, not a tick', (tester) async {
    await pump(
      tester,
      customer(isOptimistic: true, status: MessageDeliveryStatus.pending),
    );
    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    expect(find.byIcon(Icons.done_rounded), findsNothing);
  });

  testWidgets('a failed send keeps its worded retry affordance', (tester) async {
    // The one state the visitor can act on: it must stay a tappable sentence
    // rather than becoming an icon they would have to interpret.
    await pump(tester, customer(failed: true));
    expect(find.text(ElcStrings.of('en').sendFailedRetry), findsOneWidget);
    expect(find.byIcon(Icons.done_rounded), findsNothing);
    expect(find.byIcon(Icons.done_all_rounded), findsNothing);
  });

  testWidgets('an agent message carries no receipt', (tester) async {
    await pump(
      tester,
      ChatMessage(
        id: 'a1',
        conversationId: 'conv-1',
        body: 'hi there',
        senderType: SenderType.agent,
        contentType: MessageContentType.text,
        createdAt: sentAt,
      ),
      agentLastReadAt: sentAt.add(const Duration(minutes: 1)),
    );
    expect(find.byIcon(Icons.done_rounded), findsNothing);
    expect(find.byIcon(Icons.done_all_rounded), findsNothing);
    expect(find.byIcon(Icons.schedule_rounded), findsNothing);
  });

  testWidgets('each state is announced to a screen reader', (tester) async {
    final handle = tester.ensureSemantics();
    final s = ElcStrings.of('en');

    await pump(tester, customer());
    expect(find.bySemanticsLabel(s.messageSent), findsOneWidget);

    await pump(tester, customer(),
        agentLastReadAt: sentAt.add(const Duration(minutes: 1)));
    expect(find.bySemanticsLabel(s.messageRead), findsOneWidget);

    await pump(
      tester,
      customer(isOptimistic: true, status: MessageDeliveryStatus.pending),
    );
    expect(find.bySemanticsLabel(s.sending), findsOneWidget);

    handle.dispose();
  });

  testWidgets('the labels follow the chat language', (tester) async {
    // Every other string in the thread is localised; a tick announced in
    // English inside an Arabic chat is the one piece of the UI that is not.
    //
    // No host-forced locale here, so the conversation's own code decides —
    // which is how the thread resolves strings in production.
    ElcStrings.setLocale(null);
    final arabic = ElcStrings.of('ar');
    expect(arabic.messageRead, isNot(equals(ElcStrings.of('en').messageRead)),
        reason: 'the Arabic table must actually carry its own translation');

    final handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MessageBubble(
          message: customer(),
          theme: theme,
          showAgentName: false,
          strings: arabic,
          agentLastReadAt: sentAt.add(const Duration(minutes: 1)),
        ),
      ),
    ));

    expect(find.bySemanticsLabel(arabic.messageRead), findsOneWidget);

    handle.dispose();
  });
}
