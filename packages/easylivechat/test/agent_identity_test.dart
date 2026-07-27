/// Who the visitor sees replying to them.
///
/// The workspace has two switches — "Show agent avatars" and "Show agent
/// names" — and the server enforces both BEFORE the message crosses the wire:
/// it nulls `senderAvatarUrl` / `senderName` / `senderJobTitle` when they are
/// off. So the SDK's job is only to carry whatever it is handed.
///
/// It wasn't: `senderAvatarUrl` and `senderJobTitle` were never parsed, so the
/// agent's face never appeared in the app no matter what the dashboard said.
library;

import 'package:easylivechat/easylivechat.dart';
import 'package:test/test.dart';

Map<String, dynamic> agentMessage({
  String? name = 'Ava',
  String? avatar = '/uploads/t1/ava.jpg',
  String? jobTitle = 'Support Lead',
}) =>
    {
      'id': 'm1',
      'conversationId': 'c1',
      'senderType': 'AGENT',
      'contentType': 'TEXT',
      'body': 'Yes sure',
      'createdAt': '2026-07-27T10:00:00.000Z',
      if (name != null) 'senderName': name,
      if (avatar != null) 'senderAvatarUrl': avatar,
      if (jobTitle != null) 'senderJobTitle': jobTitle,
    };

void main() {
  group('ChatMessage — the replying agent', () {
    test('carries the avatar, name and job title the server sent', () {
      final m = ChatMessage.fromAny(agentMessage());
      expect(m.senderName, 'Ava');
      expect(m.senderAvatarUrl, '/uploads/t1/ava.jpg');
      expect(m.senderJobTitle, 'Support Lead');
    });

    test('a workspace with the switches OFF yields nulls, not blanks', () {
      // The server sends the keys as null rather than omitting them.
      final m = ChatMessage.fromAny({
        ...agentMessage(),
        'senderName': null,
        'senderAvatarUrl': null,
        'senderJobTitle': null,
      });
      expect(m.senderName, isNull);
      expect(m.senderAvatarUrl, isNull);
      expect(m.senderJobTitle, isNull);
    });

    test('an older server that omits the fields does not crash', () {
      final m = ChatMessage.fromAny(
          agentMessage(name: null, avatar: null, jobTitle: null));
      expect(m.senderName, isNull);
      expect(m.senderAvatarUrl, isNull);
      expect(m.senderJobTitle, isNull);
      expect(m.body, 'Yes sure');
    });

    test('an agent with no job title still has a name to show', () {
      final m = ChatMessage.fromAny(agentMessage(jobTitle: null));
      expect(m.senderName, 'Ava');
      expect(m.senderJobTitle, isNull);
    });

    // copyWith runs on every optimistic-message reconcile; dropping these
    // would blank the agent's face the moment a delivery status changed.
    test('copyWith preserves them', () {
      final m = ChatMessage.fromAny(agentMessage())
          .copyWith(deliveryStatus: MessageDeliveryStatus.delivered);
      expect(m.senderName, 'Ava');
      expect(m.senderAvatarUrl, '/uploads/t1/ava.jpg');
      expect(m.senderJobTitle, 'Support Lead');
    });
  });
}
