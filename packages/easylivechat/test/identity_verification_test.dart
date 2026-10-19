/// Identity verification: `identify(userId:, userHash:)`.
///
/// The host's BACKEND signs its own user id with the workspace secret and the
/// app passes both. They have to reach the server on every session call — the
/// silent resume as well as the start, because a long-lived visitor only ever
/// resumes — and a workspace that ENFORCES verification answers a bad claim
/// with a 403 the host must be able to tell apart from any other failure.
///
/// The part that matters most is the person changing. The visitorId lives in
/// this device's storage and a verified identity is attached to it, so without
/// the line-up a second person signing in on the same phone would open the
/// first person's conversation.
library;

import 'package:dio/dio.dart' show RequestOptions;
import 'package:easylivechat/easylivechat.dart';
import 'package:easylivechat/src/session_controller.dart';
import 'package:test/test.dart';

import 'support/fake_http.dart';

const _config = EasyLiveChatConfig(
  apiBase: 'https://api.example.test',
  tenantSlug: 'acme',
  // No sockets in a unit test: open() must not dial out.
  enablePresenceSocket: false,
  enableHeartbeat: false,
);

/// `/config` → open; `/session` → no conversation to resume, and a start that
/// mints no token (so no chat socket is connected either).
FakeReply _serverReply(RequestOptions request) {
  final path = request.path;
  if (path.endsWith('/config')) {
    return const FakeReply(200, {
      'tenantId': 't1',
      'isOpen': true,
      'config': {'id': 'w1', 'tenantId': 't1'},
    });
  }
  if (path.endsWith('/session')) {
    return const FakeReply(200, {
      'resumed': false,
      'hasActiveConversation': false,
    });
  }
  return const FakeReply(404, {'error': 'NOT_FOUND'});
}

Future<(SessionController, FakeHttp)> _controller(
    EasyLiveChatStorage storage) async {
  final http = FakeHttp(_serverReply);
  final c = SessionController(config: _config, storage: storage);
  c.rest = fakeRest(_config, http);
  await c.boot();
  return (c, http);
}

void main() {
  group('POST /session body', () {
    test('carries userId and userHash as top-level keys', () async {
      final http = FakeHttp(_serverReply);
      await fakeRest(_config, http).postSession(
        visitorId: 'v1',
        userId: ' user-42 ',
        userHash: 'abc123',
      );
      final body = FakeHttp.bodyOf(http.to('/session').single);
      expect(body['userId'], 'user-42');
      expect(body['userHash'], 'abc123');
    });

    test('omits both for an anonymous visitor', () async {
      final http = FakeHttp(_serverReply);
      await fakeRest(_config, http).postSession(visitorId: 'v1');
      final body = FakeHttp.bodyOf(http.to('/session').single);
      expect(body.containsKey('userId'), isFalse);
      expect(body.containsKey('userHash'), isFalse);
    });

    // A hash proves nothing without the id it signs.
    test('never sends a hash without an id', () async {
      final http = FakeHttp(_serverReply);
      await fakeRest(_config, http)
          .postSession(visitorId: 'v1', userId: '  ', userHash: 'abc123');
      final body = FakeHttp.bodyOf(http.to('/session').single);
      expect(body.containsKey('userId'), isFalse);
      expect(body.containsKey('userHash'), isFalse);
    });

    test('both the silent resume and the start carry the claim', () async {
      final (c, http) = await _controller(InMemoryStorage());
      c.identify(userId: 'user-42', userHash: 'abc123');
      await c.open();

      final sessions = http.to('/session').map(FakeHttp.bodyOf).toList();
      expect(sessions, hasLength(2));
      expect(sessions.first['resumeOnly'], isTrue);
      expect(sessions.last.containsKey('resumeOnly'), isFalse);
      for (final body in sessions) {
        expect(body['userId'], 'user-42');
        expect(body['userHash'], 'abc123');
      }
      c.dispose();
    });
  });

  group('403 IDENTITY_NOT_VERIFIED', () {
    test('surfaces as a typed error that keeps the reason', () async {
      final http = FakeHttp((_) => const FakeReply(403, {
            'error': 'IDENTITY_NOT_VERIFIED',
            'reason': 'BAD_HASH',
          }));
      final rest = fakeRest(_config, http);
      await expectLater(
        rest.postSession(visitorId: 'v1', userId: 'u1', userHash: 'nope'),
        throwsA(isA<EasyLiveChatError>()
            .having((e) => e.isIdentityNotVerified, 'isIdentityNotVerified',
                isTrue)
            .having((e) => e.code, 'code',
                EasyLiveChatErrorCode.identityNotVerified)
            .having((e) => e.reason, 'reason', IdentityNotVerifiedReason.badHash)
            .having((e) => e.httpStatus, 'httpStatus', 403)
            // Not an auth error: re-minting a token cannot fix a bad hash, and
            // treating it as one would loop on the same refusal.
            .having((e) => e.isAuthError, 'isAuthError', isFalse)),
      );
    });

    test('open() throws it for an identified visitor and reports it on onError',
        () async {
      final http = FakeHttp((r) => r.path.endsWith('/session')
          ? const FakeReply(
              403, {'error': 'IDENTITY_NOT_VERIFIED', 'reason': 'NO_HASH'})
          : _serverReply(r));
      final c = SessionController(config: _config, storage: InMemoryStorage());
      c.rest = fakeRest(_config, http);
      await c.boot();
      final reported = <EasyLiveChatError>[];
      final sub = c.onError.listen(reported.add);

      c.identify(userId: 'u1');
      await expectLater(
        c.open(),
        throwsA(isA<EasyLiveChatError>()
            .having((e) => e.reason, 'reason', IdentityNotVerifiedReason.noHash)),
      );
      expect(reported.where((e) => e.isIdentityNotVerified), isNotEmpty);

      await sub.cancel();
      c.dispose();
    });
  });

  group('visitorChangeFor — the web widget rule', () {
    test('nobody, then nobody', () {
      expect(visitorChangeFor(stored: null, next: null), VisitorChange.same);
    });
    test('the same person again', () {
      expect(visitorChangeFor(stored: 'u1', next: 'u1'), VisitorChange.same);
    });
    test('an anonymous visitor signs in', () {
      expect(
          visitorChangeFor(stored: null, next: 'u1'), VisitorChange.upgraded);
    });
    test('someone else signs in', () {
      expect(
          visitorChangeFor(stored: 'u1', next: 'u2'), VisitorChange.switched);
    });
    test('nobody, after someone was', () {
      expect(
          visitorChangeFor(stored: 'u1', next: null), VisitorChange.switched);
    });
  });

  group('the person changing', () {
    Future<InMemoryStorage> previousPerson(String userId) async {
      final s = InMemoryStorage();
      await s.write(StorageKeys.visitorId, 'v-old');
      await s.write(StorageKeys.identifiedUserId, userId);
      await s.write(StorageKeys.profile, '{"name":"Previous Person"}');
      await s.write(StorageKeys.token, 'old-jwt');
      await s.write(StorageKeys.conversationId, 'c-old');
      return s;
    }

    test('anonymous → identified keeps the visitor and its conversation',
        () async {
      final storage = InMemoryStorage();
      await storage.write(StorageKeys.visitorId, 'v-anon');
      await storage.write(StorageKeys.conversationId, 'c-anon');
      final (c, http) = await _controller(storage);

      c.identify(userId: 'u1', userHash: 'h1');
      await c.silentResume();

      expect(c.visitorId, 'v-anon');
      expect(await storage.read(StorageKeys.visitorId), 'v-anon');
      expect(await storage.read(StorageKeys.conversationId), 'c-anon');
      expect(await storage.read(StorageKeys.identifiedUserId), 'u1');
      final body = FakeHttp.bodyOf(http.to('/session').single);
      expect(body['visitorId'], 'v-anon');
      expect(body['userId'], 'u1');
      c.dispose();
    });

    test('a different userId forgets the stored visitor', () async {
      final storage = await previousPerson('u1');
      final (c, http) = await _controller(storage);

      c.identify(userId: 'u2', userHash: 'h2', name: 'Next Person');
      await c.silentResume();

      expect(c.visitorId, isNot('v-old'));
      expect(await storage.read(StorageKeys.visitorId), c.visitorId);
      expect(await storage.read(StorageKeys.identifiedUserId), 'u2');
      expect(await storage.read(StorageKeys.token), isNull);
      expect(await storage.read(StorageKeys.conversationId), isNull);
      expect(await storage.read(StorageKeys.profile), isNull);
      // The resume speaks for the NEW visitor, as the new person — never the
      // old visitorId with the new claim, which would verify u2 onto u1's
      // contact.
      final body = FakeHttp.bodyOf(http.to('/session').single);
      expect(body['visitorId'], c.visitorId);
      expect(body['userId'], 'u2');
      expect(body['name'], 'Next Person');
      expect(c.visitorName, 'Next Person');
      c.dispose();
    });

    // A launch that opens the chat without declaring anybody, after someone
    // was identified on this device, is a sign-out — the web page-load rule.
    test('opening with no identity after one was set forgets the visitor',
        () async {
      final storage = await previousPerson('u1');
      final (c, http) = await _controller(storage);
      expect(c.visitorName, 'Previous Person', reason: 'loaded from storage');

      await c.silentResume();

      expect(c.visitorId, isNot('v-old'));
      expect(await storage.read(StorageKeys.identifiedUserId), isNull);
      expect(c.visitorName, isNull, reason: "the previous person's name");
      final body = FakeHttp.bodyOf(http.to('/session').single);
      expect(body['visitorId'], c.visitorId);
      expect(body.containsKey('userId'), isFalse);
      expect(body.containsKey('name'), isFalse);
      c.dispose();
    });

    test('clearIdentity() after a userId forgets the visitor', () async {
      final storage = InMemoryStorage();
      await storage.write(StorageKeys.visitorId, 'v-1');
      final (c, _) = await _controller(storage);
      c.identify(userId: 'u1', userHash: 'h1');
      await c.silentResume();
      expect(c.visitorId, 'v-1');

      c.clearIdentity();
      await c.silentResume();

      expect(c.visitorId, isNot('v-1'));
      expect(await storage.read(StorageKeys.identifiedUserId), isNull);
      c.dispose();
    });

    test('the same userId again keeps everything', () async {
      final storage = await previousPerson('u1');
      final (c, _) = await _controller(storage);

      c.identify(userId: 'u1', userHash: 'h1');
      await c.silentResume();

      expect(c.visitorId, 'v-old');
      expect(await storage.read(StorageKeys.conversationId), 'c-old');
      expect(await storage.read(StorageKeys.identifiedUserId), 'u1');
      c.dispose();
    });

    test('a host that never uses userId is unaffected', () async {
      final storage = InMemoryStorage();
      await storage.write(StorageKeys.visitorId, 'v-plain');
      final (c, http) = await _controller(storage);

      c.identify(name: 'Mahmoud', email: 'm@example.com');
      await c.silentResume();
      c.identify(name: 'Someone Else');
      await c.silentResume();

      expect(c.visitorId, 'v-plain');
      expect(await storage.read(StorageKeys.identifiedUserId), isNull);
      for (final body in http.to('/session').map(FakeHttp.bodyOf)) {
        expect(body.containsKey('userId'), isFalse);
      }
      c.dispose();
    });
  });

  group('EasyLiveChat.identify', () {
    tearDown(EasyLiveChat.instance.shutdown);

    // Hosts restore the signed-in user at launch, often before the SDK boots.
    test('before boot is applied by boot', () async {
      final storage = InMemoryStorage();
      EasyLiveChat.instance.identify(userId: 'u1', userHash: 'h1');
      await EasyLiveChat.instance.boot(_config, storage: storage);
      await pumpEventQueue();

      expect(await storage.read(StorageKeys.identifiedUserId), 'u1');
    });
  });
}
