/// Emails to the visitor — the web widget's "Email me this chat" and "Get the
/// reply by email" (apps/api/src/routes/widget.ts, `/visitor-email` and
/// `/conversations/:id/transcript`), over the same endpoints and with the
/// same masked answers. Also the queue state a real session response sets.
library;

import 'package:easylivechat/easylivechat.dart';
import 'package:easylivechat/src/session_controller.dart';
import 'package:test/test.dart';

import 'support/fake_http.dart';

const _config = EasyLiveChatConfig(
  apiBase: 'https://api.example.test',
  tenantSlug: 'acme',
);

Future<(SessionController, FakeHttp)> _session(
    FakeReply Function(String path, Map<String, dynamic>? body) answer) async {
  final http = FakeHttp((r) {
    if (r.path.endsWith('/session')) {
      return const FakeReply(200, {
        'token': 'widget-jwt',
        'conversationId': 'conv-1',
        'resumed': true,
        'hasActiveConversation': true,
        'messages': [],
        'queued': true,
        'queuePosition': 2,
        'queueMinutes': 3,
        'queueInfoText': 'You are 2nd.',
      });
    }
    return answer(r.path, r.data is Map ? FakeHttp.bodyOf(r) : null);
  });
  final c = SessionController(config: _config, storage: InMemoryStorage());
  c.rest = fakeRest(_config, http);
  await c.boot();
  await c.silentResume();
  return (c, http);
}

void main() {
  test('a queued session says where the visitor stands', () async {
    final (c, _) = await _session((_, __) => const FakeReply(404));
    expect(c.queue.value,
        const QueueStatus(position: 2, minutes: 3, text: 'You are 2nd.'));
    c.dispose();
  });

  group('email me this chat', () {
    test('to the address on the contact; the answer comes back masked',
        () async {
      final (c, http) = await _session((path, body) =>
          const FakeReply(200, {'ok': true, 'sentTo': 'a•••@example.com'}));
      expect(await c.emailTranscript(), 'a•••@example.com');

      final sent = http.to('/conversations/conv-1/transcript').single;
      expect(sent.method, 'POST');
      expect(sent.headers['authorization'], 'Bearer widget-jwt');
      expect(FakeHttp.bodyOf(sent), isEmpty);
      c.dispose();
    });

    test('to an address the visitor typed', () async {
      final (c, http) = await _session((path, body) =>
          const FakeReply(200, {'ok': true, 'sentTo': 'm•••@example.com'}));
      await c.emailTranscript(email: '  me@example.com ');
      expect(FakeHttp.bodyOf(http.to('/transcript').single),
          {'email': 'me@example.com'});
      c.dispose();
    });

    test('no address on file is a typed refusal to ask for one', () async {
      final (c, _) = await _session(
          (_, __) => const FakeReply(400, {'error': 'NO_CONTACT_EMAIL'}));
      await expectLater(
        c.emailTranscript(),
        throwsA(isA<EasyLiveChatError>()
            .having((e) => e.code, 'code', 'NO_CONTACT_EMAIL')),
      );
      c.dispose();
    });

    test('too many in a row is TRANSCRIPT_RATE_LIMITED', () async {
      final (c, _) = await _session(
          (_, __) => const FakeReply(429, {'error': 'TRANSCRIPT_RATE_LIMITED'}));
      await expectLater(
        c.emailTranscript(),
        throwsA(isA<EasyLiveChatError>()
            .having((e) => e.code, 'code', 'TRANSCRIPT_RATE_LIMITED')),
      );
      c.dispose();
    });

    test('after the survey, it still goes for the chat that just ended',
        () async {
      // Submitting the post-chat survey lets the session go (so the next
      // message starts a new chat). The web widget still offers the copy of
      // the chat that ended, under the survey; so must this.
      final (c, http) = await _session((path, body) {
        if (path.endsWith('/post-chat')) return const FakeReply(200, {'ok': true});
        if (path.endsWith('/visitor-email')) {
          return const FakeReply(200, {'emailHint': 'a•••@example.com'});
        }
        return const FakeReply(200, {'ok': true, 'sentTo': 'a•••@example.com'});
      });
      await c.submitPostChat({'q1': 'Great'});
      expect(c.conversationId, isNull);

      expect((await c.visitorEmail()).emailHint, 'a•••@example.com');
      expect(await c.emailTranscript(), 'a•••@example.com');
      final sent = http.to('/conversations/conv-1/transcript').single;
      expect(sent.headers['authorization'], 'Bearer widget-jwt');
      expect(http.to('/session'), hasLength(1),
          reason: 'never re-minted: a resume would reattach the closed chat');
      c.dispose();
    });

    test('needs a session', () {
      final c = SessionController(config: _config, storage: InMemoryStorage());
      expect(() => c.emailTranscript(),
          throwsA(isA<EasyLiveChatError>()
              .having((e) => e.code, 'code', EasyLiveChatErrorCode.noToken)));
      c.dispose();
    });
  });

  group('get the reply by email', () {
    test('what is on file, and what is on offer', () async {
      final (c, http) = await _session((path, body) => const FakeReply(200, {
            'emailHint': null,
            'unsubscribed': false,
            'transcriptEnabled': true,
            'replyEmailEnabled': true,
          }));
      final state = await c.visitorEmail();
      expect(state.emailHint, isNull);
      expect(state.transcriptEnabled, isTrue);
      expect(state.replyEmailEnabled, isTrue);
      expect(http.to('/acme/visitor-email').single.method, 'GET');
      c.dispose();
    });

    test('an older server offers neither', () {
      final state = VisitorEmailState.fromJson({'emailHint': 'a•••@b.co'});
      expect(state.emailHint, 'a•••@b.co');
      expect(state.transcriptEnabled, isFalse);
      expect(state.replyEmailEnabled, isFalse);
    });

    test('saves the address and answers it masked', () async {
      final (c, http) = await _session((path, body) =>
          const FakeReply(200, {'ok': true, 'emailHint': 'a•••@example.com'}));
      expect(await c.setVisitorEmail(' ava@example.com '), 'a•••@example.com');
      final sent = http.to('/acme/visitor-email').single;
      expect(sent.method, 'POST');
      expect(FakeHttp.bodyOf(sent), {'email': 'ava@example.com'});
      c.dispose();
    });

    test('an unsubscribed address is refused, typed', () async {
      final (c, _) = await _session(
          (_, __) => const FakeReply(409, {'error': 'EMAIL_UNSUBSCRIBED'}));
      await expectLater(
        c.setVisitorEmail('ava@example.com'),
        throwsA(isA<EasyLiveChatError>()
            .having((e) => e.code, 'code', 'EMAIL_UNSUBSCRIBED')),
      );
      c.dispose();
    });
  });

  group('the config says what is on offer', () {
    test('both switches, off when an older server leaves them out', () {
      ConfigResponse res(Map<String, dynamic> extra) => ConfigResponse.fromJson(
          {'tenantId': 't', 'config': {'id': 'w', 'tenantId': 't'}, ...extra});
      expect(res({}).transcriptEmailEnabled, isFalse);
      expect(res({}).replyEmailEnabled, isFalse);
      final on = res({'transcriptEmailEnabled': true, 'replyEmailEnabled': true});
      expect(on.transcriptEmailEnabled, isTrue);
      expect(on.replyEmailEnabled, isTrue);
    });
  });
}
