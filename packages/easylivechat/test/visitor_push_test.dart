/// `setPushToken` is a deprecated no-op.
///
/// The owner's decision (2026-10): workspaces no longer hand EasyLiveChat their
/// Firebase key, so EasyLiveChat no longer notifies an app's users — the
/// workspace's own server does, on the `message.created` webhook. What stays is
/// the signature, so a host built against 0.1.54–0.1.57 still compiles. What
/// must hold: the call makes no request and holds nothing for later — a token
/// handed over before a chat existed used to be queued and sent the moment a
/// session arrived, and that must not happen any more either.
library;

// The point of this file is the deprecated call.
// ignore_for_file: deprecated_member_use_from_same_package

import 'package:easylivechat/easylivechat.dart';
import 'package:easylivechat/src/session_controller.dart';
import 'package:test/test.dart';

import 'support/fake_http.dart';

const _config = EasyLiveChatConfig(
  apiBase: 'https://api.example.test',
  tenantSlug: 'acme',
);

void main() {
  group('setPushToken', () {
    tearDown(() => EasyLiveChat.instance.shutdown());

    test('is safe before boot, and does nothing', () async {
      expect(EasyLiveChat.instance.isBooted, isFalse);
      await EasyLiveChat.instance.setPushToken('fcm-1', platform: 'ANDROID');
      await EasyLiveChat.instance.setPushToken(null, platform: 'IOS');
      expect(EasyLiveChat.instance.isBooted, isFalse,
          reason: 'a no-op must not boot or touch the controller');
    });

    test('after boot too: completes, and throws nothing', () async {
      await EasyLiveChat.instance.boot(_config);
      await expectLater(
        EasyLiveChat.instance
            .setPushToken('fcm-1', platform: 'IOS', appVersion: '2.0.0'),
        completes,
      );
    });
  });

  test('a session no longer registers any device', () async {
    final http = FakeHttp((r) {
      if (r.path.endsWith('/session')) {
        return const FakeReply(200, {
          'token': 'widget-jwt',
          'conversationId': 'conv-1',
          'resumed': true,
          'hasActiveConversation': true,
          'messages': [],
        });
      }
      return const FakeReply(404);
    });
    final c = SessionController(config: _config, storage: InMemoryStorage());
    c.rest = fakeRest(_config, http);
    await c.boot();
    expect(await c.silentResume(), isTrue);
    await Future<void>.delayed(Duration.zero);

    expect(http.requests.map((r) => r.path).where((p) => p.contains('/push/')),
        isEmpty,
        reason: 'no /push/register or /push/unregister, ever');
    expect(http.requests, hasLength(1));
    c.dispose();
  });
}
