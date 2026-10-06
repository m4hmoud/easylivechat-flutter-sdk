import 'package:easylivechat/easylivechat.dart';
import 'package:easylivechat_ui/src/l10n.dart';
import 'package:easylivechat_ui/src/theme.dart';
import 'package:easylivechat_ui/src/views/thread_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// An agent may change a reply after sending it; the visitor is told so, quietly,
/// beside the time — in their own language, on the leading side of the time in
/// either direction.
void main() {
  const theme = EasyLiveChatTheme(
    primary: Color(0xFF2563EB),
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF3F4F6),
    text: Color(0xFF111827),
  );

  final sentAt = DateTime(2026, 10, 6, 10, 1);

  ChatMessage agent({DateTime? editedAt}) => ChatMessage(
        id: 'a1',
        conversationId: 'conv-1',
        body: 'Your order ships Tuesday',
        senderType: SenderType.agent,
        contentType: MessageContentType.text,
        createdAt: sentAt,
        editedAt: editedAt,
      );

  Future<void> pump(
    WidgetTester tester,
    ChatMessage message, {
    String locale = 'en',
    TextDirection direction = TextDirection.ltr,
  }) async {
    ElcStrings.setLocale(locale);
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: MessageBubble(
            message: message,
            theme: theme,
            showAgentName: false,
            showAgentAvatar: false,
            strings: ElcStrings.of(locale),
          ),
        ),
      ),
    ));
  }

  tearDown(() => ElcStrings.setLocale(null));

  testWidgets('an edited message says so beside its time', (tester) async {
    await pump(tester, agent(editedAt: sentAt.add(const Duration(minutes: 2))));
    expect(find.text('edited'), findsOneWidget);
    expect(find.text('10:01'), findsOneWidget);
  });

  testWidgets('a message as first sent says nothing extra', (tester) async {
    await pump(tester, agent());
    expect(find.text('edited'), findsNothing);
  });

  testWidgets('in Arabic it is translated and leads the time from the right',
      (tester) async {
    await pump(
      tester,
      agent(editedAt: sentAt.add(const Duration(minutes: 2))),
      locale: 'ar',
      direction: TextDirection.rtl,
    );
    final label = find.text('معدّلة');
    expect(label, findsOneWidget);
    expect(tester.getCenter(label).dx,
        greaterThan(tester.getCenter(find.text('10:01')).dx));
  });
}
