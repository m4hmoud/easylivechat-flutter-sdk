/// Quick replies, and which message offers them.
///
/// A port of `apps/widget/src/lib/quick-replies.test.ts`: the widget, the
/// prebuilt UI and a host's own UI must agree on when the buttons are there,
/// because a late tap on a handover offer reads to the team as a brand-new
/// "Yes".
library;

import 'package:easylivechat/easylivechat.dart';
import 'package:test/test.dart';

void main() {
  var ids = 0;
  ChatMessage msg(
    SenderType senderType, {
    String body = 'x',
    Map<String, dynamic>? metadata,
  }) =>
      ChatMessage(
        id: 'm${ids++}',
        conversationId: 'c1',
        senderType: senderType,
        contentType: MessageContentType.text,
        body: body,
        createdAt: DateTime.utc(2026, 9, 16, 9),
        metadata: metadata,
      );

  // The greeting is a BOT row, or AGENT-attributed when a person greets.
  ChatMessage greeting(List<Object?> replies, {SenderType as = SenderType.bot}) =>
      msg(as, metadata: {'quickReplies': replies});

  group('quickRepliesOnOffer', () {
    test('offers the replies of the newest message', () {
      final g = greeting(['Track my order', 'Talk to a person']);
      expect(
        quickRepliesOnOffer([g]),
        QuickReplyOffer(messageId: g.id, replies: const ['Track my order', 'Talk to a person']),
      );
    });

    test('offers a greeting sent in a person\'s name the same way', () {
      final g = greeting(['Track my order'], as: SenderType.agent);
      expect(quickRepliesOnOffer([g])?.messageId, g.id);
    });

    test("offers the assistant's Yes / No under its handover question", () {
      final offer = msg(SenderType.bot, metadata: {
        'assistant': true,
        'quickReplies': ['Yes, please', 'No, thanks'],
      });
      expect(quickRepliesOnOffer([msg(SenderType.customer), offer])?.replies,
          ['Yes, please', 'No, thanks']);
    });

    test('withdraws them once the visitor has answered — by tap or by typing', () {
      expect(
        quickRepliesOnOffer([
          greeting(['Track my order']),
          msg(SenderType.customer, body: 'Track my order'),
        ]),
        isNull,
      );
    });

    test('withdraws them the moment a send is on screen, before the server has it', () {
      final optimistic = ChatMessage.optimistic(
        tempId: 'tmp-1',
        conversationId: 'c1',
        body: 'Track my order',
        createdAt: DateTime.utc(2026, 9, 16, 9, 1),
      );
      expect(quickRepliesOnOffer([greeting(['Track my order']), optimistic]), isNull);
    });

    test('withdraws them once the team has said something newer', () {
      expect(
        quickRepliesOnOffer([greeting(['Track my order']), msg(SenderType.agent)]),
        isNull,
      );
    });

    test('keeps them through a system notice, which is not the conversation moving on', () {
      final g = greeting(['Track my order']);
      expect(quickRepliesOnOffer([g, msg(SenderType.system)])?.messageId, g.id);
    });

    test('offers nothing without replies, and ignores blanks', () {
      expect(quickRepliesOnOffer([msg(SenderType.agent)]), isNull);
      expect(quickRepliesOnOffer([greeting(['  ', ''])]), isNull);
      expect(quickRepliesOnOffer(const []), isNull);
    });

    test('never offers an older message\'s replies, even when the newest has none', () {
      expect(
        quickRepliesOnOffer([greeting(['Track my order']), greeting(const [])]),
        isNull,
      );
    });
  });

  group('ChatMessage.quickReplies', () {
    test('keeps each reply exactly as sent, dropping blanks and non-strings', () {
      final m = msg(SenderType.bot, metadata: {
        'quickReplies': ['Yes, please', '  ', '', 42, null, ' No ', ''],
      });
      // U+0085 is not whitespace to JavaScript, so the widget keeps it too.
      expect(m.quickReplies, ['Yes, please', ' No ', '']);
    });

    test('is empty when the metadata has none, or not a list of them', () {
      expect(msg(SenderType.bot).quickReplies, isEmpty);
      expect(msg(SenderType.bot, metadata: {'quickReplies': 'Yes'}).quickReplies, isEmpty);
    });

    test('is read off a row from the socket', () {
      final m = ChatMessage.fromAny({
        'id': 'm1',
        'conversationId': 'c1',
        'senderType': 'BOT',
        'contentType': 'TEXT',
        'body': 'Hi! How can we help?',
        'createdAt': '2026-09-16T09:00:00Z',
        'metadata': {
          'quickReplies': ['Track my order', 'Talk to a person'],
        },
      });
      expect(m.quickReplies, ['Track my order', 'Talk to a person']);
      expect(() => m.quickReplies.add('x'), throwsUnsupportedError);
    });
  });
}
