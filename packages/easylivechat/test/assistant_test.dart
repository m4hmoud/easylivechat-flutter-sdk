/// The AI assistant, as the SDK sees it.
///
/// The server has answered SDK visitors with the assistant since it shipped —
/// the SDK talks to the same `/widgets` namespace as the web widget — but the
/// SDK read none of what the widget reads about it: every assistant reply
/// looked like a person's, the closed notice told a visitor to leave a message
/// while the assistant was about to answer, and the typing row vanished four
/// seconds into a reply that takes ten.
library;

import 'package:easylivechat/easylivechat.dart';
import 'package:easylivechat/src/session_controller.dart';
import 'package:test/test.dart';

void main() {
  group('assistantCovers', () {
    Map<String, dynamic> config({Object? covers}) => {
          'tenantId': 't1',
          'config': {'id': 'w1', 'tenantId': 't1', 'locale': 'en'},
          'isOpen': false,
          'reason': 'AFTER_HOURS',
          'visitorMode': 'CHAT',
          if (covers != null) 'assistantCovers': covers,
        };

    test('is read from the config response', () {
      expect(ConfigResponse.fromJson(config(covers: true)).assistantCovers, isTrue);
      expect(ConfigResponse.fromJson(config(covers: false)).assistantCovers, isFalse);
    });

    test('reads as false from a server that does not send it', () {
      expect(ConfigResponse.fromJson(config()).assistantCovers, isFalse);
    });

    test('is read from a live availability push', () {
      final a = WorkspaceAvailability.fromJson(
          {'isOpen': false, 'reason': 'NO_AGENTS', 'assistantCovers': true});
      expect(a.assistantCovers, isTrue);
      expect(WorkspaceAvailability.fromJson({'isOpen': true}).assistantCovers, isFalse);
    });
  });

  group('isFromAssistant', () {
    ChatMessage m(SenderType type, [Map<String, dynamic>? metadata]) => ChatMessage(
          id: 'm1',
          conversationId: 'c1',
          body: 'hi',
          senderType: type,
          contentType: MessageContentType.text,
          createdAt: DateTime.utc(2026, 9, 13),
          metadata: metadata,
        );

    test('is true for a reply the server marked as the assistant\'s', () {
      expect(m(SenderType.bot, {'assistant': true}).isFromAssistant, isTrue);
    });

    test('is false for the automatic greeting, which is a BOT message too', () {
      // Seen on zirak, which never switched the assistant on: its greeting
      // arrived badged "AI".
      expect(m(SenderType.bot).isFromAssistant, isFalse);
      expect(m(SenderType.bot, {'i18n': {'key': 'x'}}).isFromAssistant, isFalse);
      expect(m(SenderType.bot, {'assistant': 'true'}).isFromAssistant, isFalse);
    });

    test('is false for people', () {
      expect(m(SenderType.agent, {'assistant': true}).isFromAssistant, isFalse);
      expect(m(SenderType.customer).isFromAssistant, isFalse);
    });

    test('survives the wire: parsed from the JSON the server sends', () {
      final reply = ChatMessage.fromAny({
        'id': 'm2',
        'conversationId': 'c1',
        'body': 'The Pro plan is \$15.',
        'senderType': 'BOT',
        'contentType': 'TEXT',
        'createdAt': '2026-09-13T10:00:00.000Z',
        'metadata': {'assistant': true},
      });
      final greeting = ChatMessage.fromAny({
        'id': 'm3',
        'conversationId': 'c1',
        'body': 'Hello, how can I help?',
        'senderType': 'BOT',
        'contentType': 'TEXT',
        'createdAt': '2026-09-13T10:00:00.000Z',
      });
      expect(reply.isFromAssistant, isTrue);
      expect(greeting.isFromAssistant, isFalse);
    });
  });

  group('assistant typing', () {
    SessionController controller() => SessionController(
          config: const EasyLiveChatConfig(
              apiBase: 'https://api.example.com', tenantSlug: 'acme'),
          storage: InMemoryStorage(),
        );

    test('shows the typing row, named for the assistant', () {
      final c = controller();
      c.handleAssistantTyping(true);
      expect(c.agentTyping.value, isTrue);
      expect(c.assistantTyping.value, isTrue);
    });

    test('clears on the explicit stop the assistant sends', () {
      final c = controller();
      c.handleAssistantTyping(true);
      c.handleAssistantTyping(false);
      expect(c.agentTyping.value, isFalse);
      expect(c.assistantTyping.value, isFalse);
    });
  });
}
