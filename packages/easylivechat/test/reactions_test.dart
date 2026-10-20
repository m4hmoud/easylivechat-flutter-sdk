/// Reactions (C1), the visitor's side.
///
/// The server sends the visitor's view only — their own reaction on the
/// team's messages, the team's on theirs — on history, on `message:updated`
/// and on the live `message:reactions`. The visitor reacts to the team's
/// messages over `message:react`; the same emoji again takes it back, and a
/// refusal puts the thread back as it was. These pin each of those rules to
/// the web widget's (apps/widget/src/lib/reactions.ts).
library;

import 'dart:async';

import 'package:easylivechat/easylivechat.dart';
import 'package:easylivechat/src/session_controller.dart';
import 'package:easylivechat/src/widget_socket.dart';
import 'package:test/test.dart';

const _config = EasyLiveChatConfig(
  apiBase: 'https://api.example.test',
  tenantSlug: 'acme',
);

ChatMessage _row(
  String id, {
  String senderType = 'AGENT',
  String createdAt = '2026-10-18T10:00:00.000Z',
  Map<String, dynamic> extra = const {},
}) =>
    ChatMessage.fromAny({
      'id': id,
      'conversationId': 'c1',
      'senderType': senderType,
      'contentType': 'TEXT',
      'body': 'hello',
      'createdAt': createdAt,
      ...extra,
    });

const _mine = MessageReaction(emoji: '👍', by: ReactionBy.customer);
const _team = MessageReaction(emoji: '❤️', by: ReactionBy.agent);

/// A socket that never connects: it answers `message:react` from [reply] and
/// records what it was asked.
class _FakeSocket extends WidgetSocket {
  _FakeSocket() : super(apiBase: 'https://api.example.test', token: 't');

  bool connected = true;
  final List<(String, String?)> sent = [];
  Future<ReactionAck> Function(String messageId, String? emoji) reply =
      (_, __) async => const ReactionAck(ok: true);

  @override
  bool get isConnected => connected;

  @override
  Future<ReactionAck> react({required String messageId, String? emoji}) {
    sent.add((messageId, emoji));
    return reply(messageId, emoji);
  }
}

(SessionController, _FakeSocket) _controllerWith(List<ChatMessage> thread) {
  final c = SessionController(config: _config, storage: InMemoryStorage());
  c.messages.value = List<ChatMessage>.unmodifiable(thread);
  final socket = _FakeSocket();
  c.attachSocketForTesting(socket);
  return (c, socket);
}

void main() {
  group('reading reactions off the wire', () {
    test('a well-formed list, in order', () {
      final m = _row('a1', extra: {
        'reactions': [
          {'emoji': '👍', 'by': 'customer'},
          {'emoji': '❤️', 'by': 'agent'},
        ],
      });
      expect(m.reactions, [_mine, _team]);
      expect(m.myReaction, '👍');
    });

    test('malformed entries are dropped, never guessed at', () {
      final m = _row('a1', extra: {
        'reactions': [
          {'emoji': '', 'by': 'customer'},
          {'emoji': '👍', 'by': 'someone'},
          {'emoji': 7, 'by': 'agent'},
          'nope',
          null,
          {'emoji': '🙏', 'by': 'agent', 'agentId': 'x', 'name': 'Ava'},
        ],
      });
      expect(m.reactions,
          [const MessageReaction(emoji: '🙏', by: ReactionBy.agent)]);
    });

    test('absent, null or not a list reads as none', () {
      expect(_row('a1').reactions, isEmpty);
      expect(_row('a1', extra: {'reactions': null}).reactions, isEmpty);
      expect(_row('a1', extra: {'reactions': 'x'}).reactions, isEmpty);
      expect(_row('a1').myReaction, isNull);
    });

    test('survive copyWith and withIdentityFrom', () {
      final m = _row('a1', extra: {
        'reactions': [_mine.toJson()],
      });
      expect(m.copyWith(deliveryStatus: MessageDeliveryStatus.read).reactions,
          [_mine]);
      final held = _row('a1', extra: {'senderName': 'Ava'});
      expect(m.withIdentityFrom(held).reactions, [_mine]);
    });
  });

  group('who may react to what', () {
    test("the team's messages, once the server has them", () {
      expect(_row('a1').canReact, isTrue);
      expect(_row('b1', senderType: 'BOT').canReact, isTrue);
      // An automated line reaches the visitor as AUTOMATED.
      expect(_row('g1', senderType: 'AUTOMATED').canReact, isTrue);
    });

    test('never their own, a system notice, a survey or a local send', () {
      expect(_row('m1', senderType: 'CUSTOMER').canReact, isFalse);
      expect(_row('s1', senderType: 'SYSTEM').canReact, isFalse);
      expect(
          _row('p1', extra: {
            'metadata': {
              'postChat': {'rating': 5}
            }
          }).canReact,
          isFalse);
      expect(_row('tmp-1').canReact, isFalse);
    });

    test('the same emoji again takes it back; ❤ and ❤️ are one', () {
      final m = _row('a1', extra: {
        'reactions': [
          {'emoji': '❤', 'by': 'customer'}
        ],
      });
      expect(m.toggledReaction('❤️'), isNull);
      expect(m.toggledReaction('👍'), '👍');
      expect(_row('a2').toggledReaction('👍'), '👍');
    });

    test("the visitor's own replaced, the team's left alone", () {
      final m = _row('a1', extra: {
        'reactions': [_mine.toJson(), _team.toJson()],
      });
      expect(m.withMyReaction('😂').reactions, [
        _team,
        const MessageReaction(emoji: '😂', by: ReactionBy.customer),
      ]);
      expect(m.withMyReaction(null).reactions, [_team]);
    });
  });

  group('chips', () {
    test('one per emoji, first use first, the visitor\'s marked', () {
      final groups = groupReactions(const [
        MessageReaction(emoji: '❤', by: ReactionBy.agent),
        MessageReaction(emoji: '👍', by: ReactionBy.agent),
        MessageReaction(emoji: '❤️', by: ReactionBy.customer),
      ]);
      expect(groups, const [
        ReactionGroup(emoji: '❤', count: 2, mine: true),
        ReactionGroup(emoji: '👍', count: 1, mine: false),
      ]);
      expect(groupReactions(const []), isEmpty);
    });

    test('sameEmoji', () {
      expect(sameEmoji('❤', '❤️'), isTrue);
      expect(sameEmoji('👍', '👍'), isTrue);
      expect(sameEmoji('👍', '👎'), isFalse);
      expect(sameEmoji(null, '👍'), isFalse);
      expect(sameEmoji('', ''), isFalse);
    });

    test('the quick row is the one every client shows', () {
      expect(quickReactions, ['👍', '❤️', '😂', '😮', '😢', '🙏']);
    });
  });

  group('live: message:reactions', () {
    test('replaces one message\'s list and nothing else', () async {
      final (c, _) = _controllerWith([
        _row('m1', senderType: 'CUSTOMER'),
        _row('a2', createdAt: '2026-10-18T10:01:00.000Z'),
      ]);
      final arrivals = <ChatMessage>[];
      final sub = c.onMessage.listen(arrivals.add);

      c.handleReactions('m1', const [_team]);

      expect(c.messages.value.first.reactions, [_team]);
      expect(c.messages.value.last.reactions, isEmpty);
      // Not a message: nothing unread, nothing announced.
      expect(c.unreadCount.value, 0);
      await Future<void>.delayed(Duration.zero);
      expect(arrivals, isEmpty);
      await sub.cancel();
      c.dispose();
    });

    test('a message this client does not hold changes nothing', () {
      final (c, _) = _controllerWith([_row('a1')]);
      final before = c.messages.value;
      c.handleReactions('nope', const [_team]);
      expect(identical(c.messages.value, before), isTrue);
      c.dispose();
    });

    test('the payload is read whole', () {
      final e = ReactionsEvent.tryParse({
        'conversationId': 'c1',
        'messageId': 'a1',
        'reactions': [
          {'emoji': '👍', 'by': 'customer'}
        ],
      });
      expect(e?.messageId, 'a1');
      expect(e?.conversationId, 'c1');
      expect(e?.reactions, [_mine]);
      expect(ReactionsEvent.tryParse({'reactions': []}), isNull);
    });
  });

  group('message:updated', () {
    test('one that leaves reactions out keeps the chips on screen', () {
      final (c, _) = _controllerWith([
        _row('a1', extra: {
          'reactions': [_mine.toJson()]
        }),
      ]);
      // A read receipt or a link preview landing: the raw row, sometimes
      // without the field.
      c.handleMessageUpdated(_row('a1', extra: {'deliveryStatus': 'READ'}));
      expect(c.messages.value.single.reactions, [_mine]);
      c.dispose();
    });

    test('one that says [] means they are gone', () {
      final (c, _) = _controllerWith([
        _row('a1', extra: {
          'reactions': [_mine.toJson()]
        }),
      ]);
      c.handleMessageUpdated(_row('a1', extra: {'reactions': []}));
      expect(c.messages.value.single.reactions, isEmpty);
      c.dispose();
    });

    test('a repeated message:new keeps them too', () {
      final (c, _) = _controllerWith([
        _row('a1', extra: {
          'reactions': [_team.toJson()]
        }),
      ]);
      c.handleMessageNew(_row('a1'));
      expect(c.messages.value.single.reactions, [_team]);
      c.dispose();
    });
  });

  group('react()', () {
    test('shows the reaction at once, then takes the server\'s list', () async {
      final (c, socket) = _controllerWith([_row('a1')]);
      final answer = Completer<ReactionAck>();
      socket.reply = (_, __) => answer.future;

      final done = c.react('a1', '👍');
      expect(c.messages.value.single.myReaction, '👍');
      expect(socket.sent, [('a1', '👍')]);

      answer.complete(const ReactionAck(
          ok: true,
          reactions: [MessageReaction(emoji: '👍', by: ReactionBy.customer)]));
      expect(await done, isTrue);
      expect(c.messages.value.single.reactions, [_mine]);
      c.dispose();
    });

    test('a refusal puts the thread back as it was', () async {
      final (c, socket) = _controllerWith([
        _row('a1', extra: {
          'reactions': [
            {'emoji': '😂', 'by': 'customer'}
          ]
        }),
      ]);
      socket.reply =
          (_, __) async => const ReactionAck(ok: false, error: 'RATE_LIMITED');
      expect(await c.react('a1', '👍'), isFalse);
      expect(c.messages.value.single.myReaction, '😂');
      c.dispose();
    });

    test('null takes it back, and goes on the wire as null', () async {
      final (c, socket) = _controllerWith([
        _row('a1', extra: {
          'reactions': [_mine.toJson()]
        }),
      ]);
      expect(await c.react('a1', null), isTrue);
      expect(socket.sent, [('a1', null)]);
      expect(c.messages.value.single.reactions, isEmpty);
      // An empty string is the same as null, as the server reads it.
      await c.react('a1', '');
      expect(socket.sent.last, ('a1', null));
      c.dispose();
    });

    test('toggle: the same emoji again takes it back', () async {
      final (c, socket) = _controllerWith([
        _row('a1', extra: {
          'reactions': [
            {'emoji': '❤', 'by': 'customer'}
          ]
        }),
      ]);
      await c.toggleReaction('a1', '❤️');
      expect(socket.sent.single, ('a1', null));
      await c.toggleReaction('a1', '👍');
      expect(socket.sent.last, ('a1', '👍'));
      c.dispose();
    });

    test('nothing is sent with no connection, or to a message not to react to',
        () async {
      final (c, socket) = _controllerWith([
        _row('m1', senderType: 'CUSTOMER'),
        _row('a2', createdAt: '2026-10-18T10:01:00.000Z'),
      ]);
      expect(await c.react('m1', '👍'), isFalse);
      expect(await c.react('missing', '👍'), isFalse);
      socket.connected = false;
      expect(await c.react('a2', '👍'), isFalse);
      expect(socket.sent, isEmpty);
      expect(c.messages.value.last.reactions, isEmpty);
      c.dispose();
    });
  });

  group('the ack', () {
    test('ok only when it says so', () {
      expect(ReactionAck.fromAck({'ok': true}).ok, isTrue);
      expect(ReactionAck.fromAck({'reactions': []}).ok, isFalse);
      expect(ReactionAck.fromAck(null).ok, isFalse);
      final refused =
          ReactionAck.fromAck({'ok': false, 'error': 'NOT_REACTABLE'});
      expect(refused.error, 'NOT_REACTABLE');
    });
  });
}
