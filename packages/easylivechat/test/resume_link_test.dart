/// "Reply in the chat" from an email (apps/api/src/services/visitor-email.ts).
///
/// The link opens the workspace's page with `#elc_chat=<token>` (or our own
/// chat page with `#resume=<token>`); the web widget trades the token for the
/// visitor id that reaches the conversation (`POST /resume-link`) and adopts it,
/// dropping the last visitor's stored profile (apps/widget lib/visitor.ts
/// `adoptVisitorId`). `resumeFromLink` does the same for an app's deep link,
/// plus one rule of the SDK's identity model: a signed-in user is never moved
/// into another visitor's chat.
library;

import 'dart:convert';

import 'package:easylivechat/easylivechat.dart';
import 'package:easylivechat/src/session_controller.dart';
import 'package:test/test.dart';

import 'support/fake_http.dart';

const _config = EasyLiveChatConfig(
  apiBase: 'https://api.example.test',
  tenantSlug: 'acme',
);

const _jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJ0ZW5hbnRJZCI6InQxIn0.c2lnbmF0dXJl';

/// A server that answers the trade with [linkedVisitor] (or [tradeStatus]),
/// and resumes a session for whichever visitor asks.
FakeHttp _server({
  String linkedVisitor = 'v-linked',
  int tradeStatus = 200,
  bool tradeThrows = false,
}) {
  return FakeHttp((r) {
    if (r.path.endsWith('/resume-link')) {
      if (tradeThrows) throw Exception('offline');
      if (tradeStatus != 200) {
        return FakeReply(tradeStatus, const {'error': 'LINK_INVALID'});
      }
      return FakeReply(200, {
        'visitorId': linkedVisitor,
        'conversationId': 'conv-linked',
      });
    }
    if (r.path.endsWith('/config')) {
      return const FakeReply(200, {
        'tenantId': 't1',
        'isOpen': true,
        'config': {'id': 'w1', 'tenantId': 't1'},
      });
    }
    if (r.path.endsWith('/session')) {
      final vid = FakeHttp.bodyOf(r)['visitorId'];
      return FakeReply(200, {
        'token': 'jwt-for-$vid',
        'conversationId': vid == 'v-linked' ? 'conv-linked' : 'conv-own',
        'resumed': true,
        'hasActiveConversation': true,
        'messages': [],
      });
    }
    return const FakeReply(404);
  });
}

Future<(SessionController, FakeHttp, InMemoryStorage)> _device(
  FakeHttp http, {
  String visitorId = 'v-own',
  String? identifiedUserId,
}) async {
  final storage = InMemoryStorage();
  await storage.write(StorageKeys.visitorId, visitorId);
  await storage.write(StorageKeys.profile,
      jsonEncode({'name': 'Previous visitor', 'email': 'prev@example.com'}));
  await storage.write(StorageKeys.token, 'stale-token');
  await storage.write(StorageKeys.conversationId, 'conv-own');
  if (identifiedUserId != null) {
    await storage.write(StorageKeys.identifiedUserId, identifiedUserId);
  }
  final c = SessionController(config: _config, storage: storage);
  c.rest = fakeRest(_config, http);
  await c.boot();
  return (c, http, storage);
}

void main() {
  group('resumeTokenFromLink', () {
    test('the email\'s link to the workspace\'s page', () {
      expect(
          resumeTokenFromLink(
              'https://shop.example.com/pricing#elc_chat=$_jwt'),
          _jwt);
      expect(
          resumeTokenFromLink(
              'https://shop.example.com/?ref=mail#elc_chat=$_jwt&other=1'),
          _jwt);
    });

    test('our own chat page\'s, beside the identity or on its own', () {
      expect(
          resumeTokenFromLink('https://widget.livechattools.com/embed'
              '?tenant=acme&api=https%3A%2F%2Fapi.livechattools.com&locale=en'
              '#resume=$_jwt'),
          _jwt);
      expect(resumeTokenFromLink('#identity=%7B%7D&resume=$_jwt'), _jwt);
    });

    test('the bare token, and a host scheme that moved it into the query', () {
      expect(resumeTokenFromLink('  $_jwt  '), _jwt);
      expect(resumeTokenFromLink('myapp://support?elc_chat=$_jwt'), _jwt);
      expect(
          resumeTokenFromLink('elc_chat=${Uri.encodeComponent(_jwt)}'), _jwt);
    });

    test('anything that is not a token of ours', () {
      for (final link in [
        '',
        '   ',
        'https://shop.example.com/pricing',
        'https://shop.example.com/#pricing',
        '#resume=',
        '#elc_chat=',
        '#resume=<script>',
        '#noresume=a.b.c',
        '#xelc_chat=a.b.c',
        '#resume=a.b',
        '#resume=a.b.c.d',
        '#resume=%E0%A4%A',
        'not.a.jwt!',
      ]) {
        expect(resumeTokenFromLink(link), isNull, reason: link);
      }
    });
  });

  group('resumeFromLink', () {
    test('becomes the linked visitor, drops the last one\'s profile, resumes',
        () async {
      final (c, http, storage) = await _device(_server());

      expect(await c.resumeFromLink('https://shop.example.com/#elc_chat=$_jwt'),
          isTrue);

      final trade = http.to('/acme/resume-link').single;
      expect(trade.method, 'POST');
      expect(FakeHttp.bodyOf(trade), {'token': _jwt});

      expect(c.visitorId, 'v-linked');
      expect(await storage.read(StorageKeys.visitorId), 'v-linked');
      expect(await storage.read(StorageKeys.profile), isNull,
          reason: 'the previous visitor\'s profile goes with their id');

      final session = FakeHttp.bodyOf(http.to('/acme/session').single);
      expect(session['visitorId'], 'v-linked');
      expect(session['resumeOnly'], isTrue);
      expect(session.containsKey('name'), isFalse);
      expect(session.containsKey('email'), isFalse);

      expect(c.phase.value, ChatPhase.chat);
      expect(c.conversationId, 'conv-linked');
      expect(await storage.read(StorageKeys.token), 'jwt-for-v-linked');
      c.dispose();
    });

    test('a link the server refuses changes nothing', () async {
      final (c, http, storage) = await _device(_server(tradeStatus: 410));

      expect(await c.resumeFromLink('#elc_chat=$_jwt'), isFalse);
      expect(c.visitorId, 'v-own');
      expect(await storage.read(StorageKeys.profile), isNotNull);
      expect(http.to('/session'), isEmpty);
      c.dispose();
    });

    test('a link that is not ours makes no request at all', () async {
      final (c, http, _) = await _device(_server());
      expect(
          await c.resumeFromLink('https://shop.example.com/pricing'), isFalse);
      expect(http.requests, isEmpty);
      c.dispose();
    });

    test('offline: false, not a throw', () async {
      final (c, _, _) = await _device(_server(tradeThrows: true));
      expect(await c.resumeFromLink(_jwt), isFalse);
      expect(c.visitorId, 'v-own');
      c.dispose();
    });

    test('a signed-in user is never moved into another visitor\'s chat',
        () async {
      final (c, http, storage) =
          await _device(_server(), identifiedUserId: 'user-1');
      c.identify(name: 'Ava', userId: 'user-1', userHash: 'hash-1');

      expect(await c.resumeFromLink('#elc_chat=$_jwt'), isFalse);

      expect(c.visitorId, 'v-own');
      expect(await storage.read(StorageKeys.visitorId), 'v-own');
      expect(await storage.read(StorageKeys.identifiedUserId), 'user-1');
      expect(http.to('/session'), isEmpty,
          reason: 'no claim of user-1 may reach the linked contact');
      c.dispose();
    });

    test('…but their own chat opens', () async {
      final (c, http, _) = await _device(_server(linkedVisitor: 'v-own'),
          identifiedUserId: 'user-1');
      c.identify(name: 'Ava', userId: 'user-1', userHash: 'hash-1');

      expect(await c.resumeFromLink('#elc_chat=$_jwt'), isTrue);
      expect(c.visitorId, 'v-own');
      final session = FakeHttp.bodyOf(http.to('/session').single);
      expect(session['visitorId'], 'v-own');
      expect(session['userId'], 'user-1');
      expect(c.phase.value, ChatPhase.chat);
      c.dispose();
    });

    test('nobody signed in any more: the line-up runs first, then the link',
        () async {
      // The device's visitor was user-1's; this launch declared nobody. The
      // identity rule forgets that visitor before the link is followed.
      final (c, _, storage) =
          await _device(_server(), identifiedUserId: 'user-1');

      expect(await c.resumeFromLink(_jwt), isTrue);
      expect(c.visitorId, 'v-linked');
      expect(await storage.read(StorageKeys.identifiedUserId), isNull);
      c.dispose();
    });

    test('already in the linked chat: nothing to redo', () async {
      final (c, http, _) = await _device(_server(linkedVisitor: 'v-own'));
      expect(await c.silentResume(), isTrue);
      expect(c.conversationId, 'conv-own');
      http.requests.clear();

      // The server names the conversation this device is already in.
      http.handler = (r) => r.path.endsWith('/resume-link')
          ? const FakeReply(
              200, {'visitorId': 'v-own', 'conversationId': 'conv-own'})
          : const FakeReply(500);
      expect(await c.resumeFromLink(_jwt), isTrue);
      expect(http.to('/resume-link'), hasLength(1));
      expect(http.to('/session'), isEmpty);
      expect(http.to('/config'), isEmpty);
      c.dispose();
    });
  });
}
