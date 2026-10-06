/// An agent may edit or unsend a reply for a few minutes after sending it.
///
/// The visitor's copy has to follow: an edit is the same message with new
/// words, in the same place, marked as edited; an unsent message simply
/// leaves, Telegram-style, with no placeholder — and nothing that arrives
/// late (a read-receipt update, a backfill page) may bring it back.
library;

import 'package:easylivechat/easylivechat.dart';
import 'package:easylivechat/src/rest_client.dart';
import 'package:easylivechat/src/session_controller.dart';
import 'package:test/test.dart';

const _config = EasyLiveChatConfig(
  apiBase: 'https://api.example.test',
  tenantSlug: 'acme',
);

ChatMessage _row(
  String id,
  String createdAt, {
  String senderType = 'AGENT',
  String body = 'hello',
  Map<String, dynamic> extra = const {},
}) =>
    ChatMessage.fromAny({
      'id': id,
      'conversationId': 'c1',
      'senderType': senderType,
      'contentType': 'TEXT',
      'body': body,
      'createdAt': createdAt,
      ...extra,
    });

SessionController _controllerWith(List<ChatMessage> thread) {
  final c = SessionController(config: _config, storage: InMemoryStorage());
  c.messages.value = List<ChatMessage>.unmodifiable(thread);
  return c;
}

void main() {
  group('ChatMessage.editedAt', () {
    test('parses the edit stamp from the socket and from history', () {
      final m = _row('a1', '2026-10-06T10:00:00.000Z',
          extra: {'editedAt': '2026-10-06T10:03:00.000Z'});
      expect(m.editedAt, DateTime.utc(2026, 10, 6, 10, 3).toLocal());
      expect(m.isEdited, isTrue);
    });

    test('is null when absent, null or malformed — never the epoch', () {
      expect(_row('a1', '2026-10-06T10:00:00.000Z').editedAt, isNull);
      expect(
          _row('a1', '2026-10-06T10:00:00.000Z', extra: {'editedAt': null})
              .editedAt,
          isNull);
      final bad = _row('a1', '2026-10-06T10:00:00.000Z',
          extra: {'editedAt': 'not a date'});
      expect(bad.editedAt, isNull);
      expect(bad.isEdited, isFalse);
    });

    test('survives copyWith and withIdentityFrom', () {
      final edited = _row('a1', '2026-10-06T10:00:00.000Z',
          extra: {'editedAt': '2026-10-06T10:03:00.000Z'});
      expect(
          edited
              .copyWith(deliveryStatus: MessageDeliveryStatus.read)
              .isEdited,
          isTrue);
      final held = _row('a1', '2026-10-06T10:00:00.000Z',
          extra: {'senderName': 'Ava'});
      final merged = edited.withIdentityFrom(held);
      expect(merged.senderName, 'Ava');
      expect(merged.editedAt, edited.editedAt);
    });
  });

  group('message:updated — an edit', () {
    test('replaces the message by id in place, taking the new words', () {
      final c = _controllerWith([
        _row('m1', '2026-10-06T10:00:00.000Z', senderType: 'CUSTOMER'),
        _row('a2', '2026-10-06T10:01:00.000Z',
            body: 'Ships Monday', extra: {'senderName': 'Ava'}),
        _row('m3', '2026-10-06T10:02:00.000Z', senderType: 'CUSTOMER'),
      ]);

      c.handleMessageUpdated(_row('a2', '2026-10-06T10:01:00.000Z',
          body: 'Ships Tuesday',
          extra: {'editedAt': '2026-10-06T10:03:00.000Z'}));

      final thread = c.messages.value;
      expect(thread.map((m) => m.id), ['m1', 'a2', 'm3']);
      expect(thread[1].body, 'Ships Tuesday');
      expect(thread[1].isEdited, isTrue);
      // The bare update did not wipe the face the bubble already had.
      expect(thread[1].senderName, 'Ava');
      c.dispose();
    });
  });

  group('message:deleted — an unsend', () {
    test('removes the message and leaves the rest in order', () {
      final c = _controllerWith([
        _row('m1', '2026-10-06T10:00:00.000Z', senderType: 'CUSTOMER'),
        _row('a2', '2026-10-06T10:01:00.000Z'),
        _row('m3', '2026-10-06T10:02:00.000Z', senderType: 'CUSTOMER'),
      ]);
      c.handleMessageDeleted('a2');
      expect(c.messages.value.map((m) => m.id), ['m1', 'm3']);
      c.dispose();
    });

    test('an unknown id changes nothing', () {
      final c = _controllerWith([_row('a1', '2026-10-06T10:00:00.000Z')]);
      final before = c.messages.value;
      c.handleMessageDeleted('nope');
      c.handleMessageDeleted('');
      expect(identical(c.messages.value, before), isTrue);
      c.dispose();
    });

    test('a late update or echo does not bring it back', () {
      final c = _controllerWith([_row('a1', '2026-10-06T10:00:00.000Z')]);
      c.handleMessageDeleted('a1');
      // The visitor's read receipt travels a slower path than the delete.
      c.handleMessageUpdated(_row('a1', '2026-10-06T10:00:00.000Z',
          extra: {'readByVisitorAt': '2026-10-06T10:00:05.000Z'}));
      c.handleMessageNew(_row('a1', '2026-10-06T10:00:00.000Z'));
      expect(c.messages.value, isEmpty);
      c.dispose();
    });

    test('comes off the unread badge if it was counted there', () {
      final c = _controllerWith(const []);
      c.handleMessageNew(_row('a1', '2026-10-06T10:00:00.000Z'));
      c.handleMessageNew(_row('a2', '2026-10-06T10:01:00.000Z'));
      expect(c.unreadCount.value, 2);
      c.handleMessageDeleted('a2');
      expect(c.unreadCount.value, 1);
      // Once read, the badge is clear and an unsend cannot push it negative.
      c.markRead();
      c.handleMessageDeleted('a1');
      expect(c.unreadCount.value, 0);
      c.dispose();
    });
  });

  // The server remembers a week of unsent ids and lists them on every history
  // response, so a visitor who was away when an agent took a reply back —
  // socket down, app suspended or closed — still sees it go.
  group('unsentIds on history responses', () {
    test('are parsed from the session and from a page', () {
      final session = SessionResult.fromJson({
        'resumed': true,
        'hasActiveConversation': true,
        'messages': const [],
        'unsentIds': ['a2', 7, '', 'a3'],
      });
      expect(session.unsentIds, ['a2', 'a3']);
      final page = MessagePage.fromJson({
        'messages': const [],
        'nextCursor': null,
        'unsentIds': ['a2'],
      });
      expect(page.unsentIds, ['a2']);
    });

    test('a server that predates the field reads as none', () {
      expect(
          SessionResult.fromJson({'resumed': true, 'messages': const []})
              .unsentIds,
          isEmpty);
      expect(MessagePage.fromJson({'messages': const []}).unsentIds, isEmpty);
    });

    test('a restore drops them and announces each one', () async {
      final rest = _HistoryRest(_config,
          session: [
            _wire('m1', '2026-10-06T10:00:00.000Z', senderType: 'CUSTOMER'),
            _wire('a2', '2026-10-06T10:01:00.000Z'),
          ],
          sessionUnsent: ['a2', 'a9']);
      final c = SessionController(config: _config, storage: InMemoryStorage())
        ..rest = rest;
      final deleted = <DeletedMessage>[];
      final sub = c.onMessageDeleted.listen(deleted.add);
      await c.boot();
      await c.silentResume();
      await Future<void>.delayed(Duration.zero);

      expect(c.messages.value.map((m) => m.id), ['m1']);
      expect(deleted, const [
        DeletedMessage(id: 'a2', conversationId: 'conv-1'),
        DeletedMessage(id: 'a9', conversationId: 'conv-1'),
      ]);
      await sub.cancel();
      c.dispose();
    });

    test('a page of older history takes down a message already on screen',
        () async {
      final rest = _HistoryRest(_config,
          session: [
            _wire('m1', '2026-10-06T10:00:00.000Z', senderType: 'CUSTOMER'),
            _wire('a2', '2026-10-06T10:01:00.000Z'),
            _wire('m3', '2026-10-06T10:02:00.000Z', senderType: 'CUSTOMER'),
          ],
          page: [_wire('m0', '2026-10-06T09:00:00.000Z')],
          pageUnsent: ['a2']);
      final c = SessionController(config: _config, storage: InMemoryStorage())
        ..rest = rest;
      final deleted = <String>[];
      final sub = c.onMessageDeleted.listen((d) => deleted.add(d.id));
      await c.boot();
      await c.silentResume();
      expect(c.messages.value.map((m) => m.id), ['m1', 'a2', 'm3']);

      await c.loadOlderMessages();
      await Future<void>.delayed(Duration.zero);
      expect(c.messages.value.map((m) => m.id), ['m0', 'm1', 'm3']);

      // Remembered: the live event for the same unsend, or a late update,
      // neither re-announces it nor brings it back.
      c.handleMessageDeleted('a2');
      c.handleMessageUpdated(_row('a2', '2026-10-06T10:01:00.000Z'));
      await Future<void>.delayed(Duration.zero);
      expect(c.messages.value.map((m) => m.id), ['m0', 'm1', 'm3']);
      expect(deleted, ['a2']);
      await sub.cancel();
      c.dispose();
    });
  });

  group('onMessageDeleted — the live event', () {
    test('fires once per id, with the conversation it was in', () async {
      final c = _controllerWith([_row('a1', '2026-10-06T10:00:00.000Z')]);
      final deleted = <DeletedMessage>[];
      final sub = c.onMessageDeleted.listen(deleted.add);
      c.handleMessageDeleted('a1', conversationId: 'c1');
      c.handleMessageDeleted('a1', conversationId: 'c1');
      await Future<void>.delayed(Duration.zero);
      expect(deleted, const [DeletedMessage(id: 'a1', conversationId: 'c1')]);
      await sub.cancel();
      c.dispose();
    });
  });
}

Map<String, dynamic> _wire(String id, String createdAt,
        {String senderType = 'AGENT'}) =>
    {
      'id': id,
      'conversationId': 'conv-1',
      'senderType': senderType,
      'contentType': 'TEXT',
      'body': 'hello',
      'createdAt': createdAt,
    };

/// Answers the session open and one page of history from fixed rows.
class _HistoryRest extends RestClient {
  _HistoryRest(
    super.config, {
    this.session = const [],
    this.sessionUnsent = const [],
    this.page = const [],
    this.pageUnsent = const [],
  });

  final List<Map<String, dynamic>> session;
  final List<String> sessionUnsent;
  final List<Map<String, dynamic>> page;
  final List<String> pageUnsent;

  @override
  Future<SessionResult> postSession({
    required String visitorId,
    String? name,
    String? email,
    String? phone,
    String? page,
    String? locale,
    String? contentLocale,
    bool resumeOnly = false,
    Map<String, String>? fields,
    Map<String, String>? attributes,
  }) async =>
      SessionResult.fromJson({
        'token': 'widget-jwt',
        'conversationId': 'conv-1',
        'resumed': true,
        'hasActiveConversation': true,
        'nextCursor': session.isEmpty ? null : session.first['id'],
        'messages': session,
        'unsentIds': sessionUnsent,
      });

  @override
  Future<MessagePage> getMessages({
    required String token,
    String? cursor,
    int limit = 50,
  }) async =>
      MessagePage.fromJson({
        'messages': page,
        'nextCursor': null,
        'unsentIds': pageUnsent,
      });
}
