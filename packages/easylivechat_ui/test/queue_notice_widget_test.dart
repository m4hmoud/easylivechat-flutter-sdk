import 'package:easylivechat/easylivechat.dart';
import 'package:easylivechat_ui/src/l10n.dart';
import 'package:easylivechat_ui/src/theme.dart';
import 'package:easylivechat_ui/src/views/queue_notice_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The queue notice above the thread — the web widget's `QueueView`: "Queue",
/// the workspace's words, and the place and the wait when the server knows
/// them.
void main() {
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

  Future<void> pump(WidgetTester tester, QueueStatus status, String locale,
          {TextDirection direction = TextDirection.ltr}) =>
      tester.pumpWidget(MaterialApp(
        home: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: ElcQueueNotice(
              status: status,
              theme: theme,
              strings: ElcStrings.of(locale),
            ),
          ),
        ),
      ));

  testWidgets('the words, the place and the wait', (tester) async {
    await pump(
        tester,
        const QueueStatus(
            position: 2, minutes: 4, text: 'Thanks Ava — someone will be with you shortly.'),
        'en');
    expect(find.text('Queue'), findsOneWidget);
    expect(find.text('Thanks Ava — someone will be with you shortly.'),
        findsOneWidget);
    expect(find.text('#2 · ~4 min'), findsOneWidget);
  });

  testWidgets('no place, no line for it', (tester) async {
    await pump(tester, const QueueStatus(text: 'Hold on.'), 'en');
    expect(find.text('Hold on.'), findsOneWidget);
    expect(find.textContaining('#'), findsNothing);
  });

  testWidgets("in the visitor's language, the right way round", (tester) async {
    await pump(tester, const QueueStatus(position: 3, minutes: 5, text: 'انتظر قليلاً'),
        'ar',
        direction: TextDirection.rtl);
    expect(find.text('قائمة الانتظار'), findsOneWidget);
    expect(find.text('الدور 3 · نحو 5 دقيقة'), findsOneWidget);
    expect(tester.widget<Text>(find.text('انتظر قليلاً')).textDirection,
        TextDirection.rtl);
  });

  testWidgets('Sorani and Badini have their own words', (tester) async {
    await pump(tester, const QueueStatus(position: 1, minutes: 2), 'ckb');
    expect(find.text('ڕیز'), findsOneWidget);
    expect(find.text('ژمارە 1 · نزیکەی 2 خولەک'), findsOneWidget);
    await pump(tester, const QueueStatus(position: 1, minutes: 2), 'kmr');
    expect(find.text('ڕێز'), findsOneWidget);
  });
}
