import 'package:easylivechat/easylivechat.dart';
import 'package:easylivechat/src/session_controller.dart';
import 'package:test/test.dart';

/// The post-chat survey is offered once per VISIT, not once per conversation.
///
/// A returning customer lands back in the thread they already have, so the
/// "already rated" bookkeeping — keyed by conversation id — has to be released
/// when a new visit opens inside that thread. It wasn't: the clearing was
/// described in a doc comment and never written, so rating a chat once
/// suppressed the survey for the life of the conversation. The visitor tapped
/// "Close chat", `endChat()` reported there was nothing left to ask, and the
/// host UI dismissed its confirmation having done nothing visible.
///
/// The subtle half is that the rule keys on the marker's IDENTITY, not on its
/// presence: the same marker comes back on every resume, backfill and
/// reconnect, and treating that as a new visit re-asks someone who just rated.
void main() {
  ChatMessage marker(String id, DateTime at) => ChatMessage(
        id: id,
        conversationId: 'conv-1',
        body: '',
        senderType: SenderType.system,
        contentType: MessageContentType.text,
        createdAt: at,
        metadata: const {
          'i18n': {'key': 'conversation.session.started'},
        },
      );

  ChatMessage chat(String id, DateTime at) => ChatMessage(
        id: id,
        conversationId: 'conv-1',
        body: 'hello',
        senderType: SenderType.agent,
        contentType: MessageContentType.text,
        createdAt: at,
      );

  final t0 = DateTime.utc(2026, 8, 12, 14, 0);

  group('newestSessionStartMarker', () {
    test('a thread with no boundary has none — a first visit never clears',
        () {
      expect(
        newestSessionStartMarker([chat('a', t0), chat('b', t0)]),
        isNull,
      );
    });

    test('ordinary messages are never mistaken for a boundary', () {
      expect(newestSessionStartMarker([chat('a', t0)]), isNull);
    });

    test('picks the newest boundary, not the first one it walks past', () {
      final first = marker('m1', t0);
      final second = marker('m2', t0.add(const Duration(hours: 1)));
      // Deliberately out of order: the transcript is merged from a live socket
      // and a paged backfill, so arrival order is not chronological order.
      expect(newestSessionStartMarker([second, chat('x', t0), first])?.id,
          'm2');
    });

    test('the same visit resolves to the same marker however it arrives', () {
      final m = marker('m1', t0);
      // A resume re-delivers the whole page; the id must not drift, or the
      // caller reads it as a new visit and re-arms a survey already answered.
      expect(newestSessionStartMarker([m])?.id,
          newestSessionStartMarker([chat('x', t0), m])?.id);
    });
  });
}
