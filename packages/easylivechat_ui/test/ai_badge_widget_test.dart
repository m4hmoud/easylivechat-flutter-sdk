import 'package:easylivechat/easylivechat.dart';
import 'package:easylivechat_ui/src/l10n.dart';
import 'package:easylivechat_ui/src/theme.dart';
import 'package:easylivechat_ui/src/views/thread_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every assistant reply says it is automated.
///
/// The SDK drew BOT messages exactly like a colleague's, and with agent names
/// switched off — a common tenant choice — like nobody's at all. The web widget
/// badges them; a visitor decides whether to trust an answer, wait for a person
/// or repeat themselves based on who they think is talking.
void main() {
  const theme = EasyLiveChatTheme(
    primary: Color(0xFF2563EB),
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF3F4F6),
    text: Color(0xFF111827),
  );

  ChatMessage message(SenderType type, {String? name}) => ChatMessage(
        id: 'm1',
        conversationId: 'c1',
        body: 'The Pro plan is \$15 per month.',
        senderType: type,
        senderName: name,
        contentType: MessageContentType.text,
        createdAt: DateTime.utc(2026, 9, 13, 10),
      );

  Future<void> pump(WidgetTester tester, ChatMessage m,
      {bool showAgentName = false, String locale = 'en'}) async {
    ElcStrings.setLocale(locale);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MessageBubble(
          message: m,
          theme: theme,
          showAgentName: showAgentName,
          strings: ElcStrings.of(locale),
        ),
      ),
    ));
  }

  testWidgets('an assistant reply carries its name and an AI badge, names off or not',
      (tester) async {
    await pump(tester, message(SenderType.bot, name: 'eMenu Assistant'));
    expect(find.byType(AiBadge), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
    expect(find.text('eMenu Assistant'), findsOneWidget);
  });

  testWidgets('the badge stands on its own when the assistant has no name',
      (tester) async {
    await pump(tester, message(SenderType.bot));
    expect(find.byType(AiBadge), findsOneWidget);
  });

  testWidgets('a person is never badged', (tester) async {
    await pump(tester, message(SenderType.agent, name: 'Sam'), showAgentName: true);
    expect(find.byType(AiBadge), findsNothing);
    expect(find.text('Sam'), findsOneWidget);
  });

  testWidgets('the badge is in the visitor\'s language', (tester) async {
    await pump(tester, message(SenderType.bot, name: 'eMenu'), locale: 'ar');
    expect(find.text('ذكاء اصطناعي'), findsOneWidget);
  });
}
