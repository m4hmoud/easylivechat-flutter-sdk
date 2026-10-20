/// Waiting for a person — the web widget's queue notice
/// (apps/widget/src/lib/queue-phase.ts, Embed.tsx `queued` / `queueInfo`).
///
/// A notice above the conversation, never a screen of its own: the session
/// says `queued` with a place, the expected minutes and the workspace's text;
/// `queue:update` moves it; and anything that means somebody is here now ends
/// it — the chat assigned, a team message, someone starting to type.
library;

import 'package:easylivechat/easylivechat.dart';
import 'package:easylivechat/src/session_controller.dart';
import 'package:test/test.dart';

const _config = EasyLiveChatConfig(
  apiBase: 'https://api.example.test',
  tenantSlug: 'acme',
);

ChatMessage _row(String id, String senderType) => ChatMessage.fromAny({
      'id': id,
      'conversationId': 'c1',
      'senderType': senderType,
      'contentType': 'TEXT',
      'body': 'hi',
      'createdAt': '2026-10-18T10:00:00.000Z',
    });

SessionController _waiting() {
  final c = SessionController(config: _config, storage: InMemoryStorage());
  c.handleQueueUpdate(
      const QueueStatus(position: 2, minutes: 4, text: "You're 2nd in line."));
  return c;
}

void main() {
  group('the session', () {
    test('queued: the place, the wait and the text', () {
      final res = SessionResult.fromJson({
        'token': 't',
        'conversationId': 'c1',
        'resumed': false,
        'hasActiveConversation': true,
        'queued': true,
        'queuePosition': 3,
        'queueMinutes': 6,
        'queueInfoText': '  Hi Ava, you are number 3.  ',
      });
      expect(res.queue,
          const QueueStatus(position: 3, minutes: 6, text: 'Hi Ava, you are number 3.'));
    });

    test('not queued — or an older server — is nobody waiting', () {
      expect(
          SessionResult.fromJson({
            'resumed': false,
            'hasActiveConversation': true,
            'queued': false,
            'queuePosition': 3,
          }).queue,
          isNull);
      expect(
          SessionResult.fromJson(
              {'resumed': false, 'hasActiveConversation': true}).queue,
          isNull);
    });

    test('a place the server could not work out reads as none', () {
      final res = SessionResult.fromJson({
        'resumed': false,
        'hasActiveConversation': true,
        'queued': true,
        'queuePosition': 'x',
        'queueMinutes': -1,
      });
      expect(res.queue, const QueueStatus());
    });
  });

  group('queue:update', () {
    test('moves the place along', () {
      expect(
          QueueStatus.fromUpdate(
              {'position': 1, 'minutes': 2, 'text': 'You are next.'}),
          const QueueStatus(position: 1, minutes: 2, text: 'You are next.'));
    });

    test('assigned ends the wait', () {
      expect(QueueStatus.fromUpdate({'assigned': true, 'position': 0}), isNull);
      final c = _waiting();
      c.handleQueueUpdate(null);
      expect(c.queue.value, isNull);
      c.dispose();
    });
  });

  group('somebody is here now', () {
    test('a message from the team, the assistant or an automated line', () {
      for (final from in ['AGENT', 'BOT', 'AUTOMATED']) {
        final c = _waiting();
        c.handleMessageNew(_row('a1', from));
        expect(c.queue.value, isNull, reason: from);
        c.dispose();
      }
    });

    test('but not the visitor\'s own words, or a system line', () {
      for (final from in ['CUSTOMER', 'SYSTEM']) {
        final c = _waiting();
        c.handleMessageNew(_row('m1', from));
        expect(c.queue.value, isNotNull, reason: from);
        c.dispose();
      }
    });

    test('the assistant starting to type', () {
      final c = _waiting();
      c.handleAssistantTyping(true);
      expect(c.queue.value, isNull);
      c.dispose();
    });
  });
}
