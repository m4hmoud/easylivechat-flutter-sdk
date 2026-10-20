import 'package:easylivechat/easylivechat.dart';
import 'package:easylivechat_ui/src/l10n.dart';
import 'package:easylivechat_ui/src/views/thread_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// New team messages, said to a screen reader as they arrive — the web
/// widget's polite live region (apps/widget/src/lib/announce.ts).
void main() {
  setUp(() {
    ElcStrings.overrideAll(const {});
    ElcStrings.overrideByLocale(const {});
    ElcStrings.setLocale(null);
  });

  ChatMessage m(String senderType, {String? body = 'Hello  there', String? name}) =>
      ChatMessage.fromAny({
        'id': 'x',
        'conversationId': 'c1',
        'senderType': senderType,
        'contentType': 'TEXT',
        'body': body,
        'senderName': name,
        'createdAt': '2026-10-18T10:00:00.000Z',
      });

  test("the team's words, with the name the thread shows", () {
    final en = ElcStrings.of('en');
    expect(ElcThreadAnnouncer.announcementFor(m('AGENT', name: 'Sara'), en),
        'Sara: Hello there');
    expect(ElcThreadAnnouncer.announcementFor(m('BOT'), en),
        'New message: Hello there');
    expect(ElcThreadAnnouncer.announcementFor(m('AUTOMATED'), en),
        'New message: Hello there');
  });

  test("never the visitor's own words, a system line or an empty one", () {
    final en = ElcStrings.of('en');
    expect(ElcThreadAnnouncer.announcementFor(m('CUSTOMER'), en), isNull);
    expect(ElcThreadAnnouncer.announcementFor(m('SYSTEM'), en), isNull);
    expect(ElcThreadAnnouncer.announcementFor(m('AGENT', body: '  '), en),
        isNull);
  });

  test('a long reply is cut', () {
    final said = ElcThreadAnnouncer.announcementFor(
        m('AGENT', body: 'a' * 900), ElcStrings.of('en'))!;
    expect(said, 'New message: ${'a' * 300}');
  });

  test("in the visitor's language", () {
    expect(ElcThreadAnnouncer.announcementFor(m('AGENT'), ElcStrings.of('ar')),
        'رسالة جديدة: Hello there');
  });

  testWidgets('a live region that draws nothing', (tester) async {
    // Where the chat screen puts it: in the column above the thread.
    await tester.pumpWidget(MaterialApp(
      home: Column(children: [
        ElcThreadAnnouncer(
            strings: ElcStrings.of('en'), direction: TextDirection.ltr),
      ]),
    ));
    final semantics = tester.widget<Semantics>(find
        .descendant(
            of: find.byType(ElcThreadAnnouncer),
            matching: find.byType(Semantics))
        .first);
    expect(semantics.properties.liveRegion, isTrue);
    expect(tester.getSize(find.byType(ElcThreadAnnouncer)).height, 0);
  });
}
