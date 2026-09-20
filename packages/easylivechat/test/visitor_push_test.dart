/// A push token handed over before there is a chat must not be dropped.
///
/// The host app gets its FCM token at launch, long before anyone opens the
/// conversation — and a registration can only be authenticated with a session
/// token, which does not exist yet. So the registration is held and sent when
/// a session arrives. The other half is rotation: a new token must replace the
/// old one, or the dead row keeps receiving this person's replies.
library;

import 'package:easylivechat/easylivechat.dart';
import 'package:easylivechat/src/rest_client.dart';
import 'package:easylivechat/src/session_controller.dart';
import 'package:test/test.dart';

const _config = EasyLiveChatConfig(
  apiBase: 'https://api.example.test',
  tenantSlug: 'acme',
);

void main() {
  group('setPushToken', () {
    test('holds the registration until a session can authenticate it', () async {
      final rest = _RecordingRest(_config);
      final controller = SessionController(config: _config, storage: InMemoryStorage());
      controller.rest = rest;
      await controller.boot();

      await controller.setPushToken('fcm-1', platform: 'ANDROID');
      expect(rest.registered, isEmpty, reason: 'nothing to authenticate with yet');

      // A session arrives: the held registration goes out by itself.
      await controller.silentResume();
      await Future<void>.delayed(Duration.zero);
      expect(rest.registered, [
        {'token': 'fcm-1', 'platform': 'ANDROID'},
      ]);
    });

    test('moves the registration when the device rotates its token', () async {
      final rest = _RecordingRest(_config);
      final controller = SessionController(config: _config, storage: InMemoryStorage());
      controller.rest = rest;
      await controller.boot();
      await controller.silentResume();

      await controller.setPushToken('fcm-1', platform: 'IOS');
      await controller.setPushToken('fcm-2', platform: 'IOS');

      expect(rest.registered.map((r) => r['token']), ['fcm-1', 'fcm-2']);
      expect(rest.unregistered, ['fcm-1'], reason: 'the old row must not outlive the swap');
    });

    test('registers once for a token the server already has', () async {
      final rest = _RecordingRest(_config);
      final controller = SessionController(config: _config, storage: InMemoryStorage());
      controller.rest = rest;
      await controller.boot();
      await controller.silentResume();

      await controller.setPushToken('fcm-1', platform: 'ANDROID');
      await controller.setPushToken('fcm-1', platform: 'ANDROID');
      expect(rest.registered, hasLength(1));
    });

    test('null stops the notifications', () async {
      final rest = _RecordingRest(_config);
      final controller = SessionController(config: _config, storage: InMemoryStorage());
      controller.rest = rest;
      await controller.boot();
      await controller.silentResume();

      await controller.setPushToken('fcm-1', platform: 'ANDROID');
      await controller.setPushToken(null, platform: 'ANDROID');
      expect(rest.unregistered, ['fcm-1']);
    });

    test('a failed registration stays queued for the next session', () async {
      final rest = _RecordingRest(_config, failRegister: true);
      final controller = SessionController(config: _config, storage: InMemoryStorage());
      controller.rest = rest;
      await controller.boot();
      await controller.silentResume();

      await controller.setPushToken('fcm-1', platform: 'ANDROID');
      expect(rest.registered, hasLength(1));

      rest.failRegister = false;
      await controller.silentResume();
      await Future<void>.delayed(Duration.zero);
      expect(rest.registered, hasLength(2), reason: 'retried when a session came back');
    });
  });
}

class _RecordingRest extends RestClient {
  _RecordingRest(super.config, {this.failRegister = false});

  bool failRegister;
  final List<Map<String, String?>> registered = [];
  final List<String> unregistered = [];

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
      const SessionResult(
        resumed: true,
        hasActiveConversation: true,
        token: 'widget-jwt',
        conversationId: 'conv-1',
      );

  @override
  Future<void> registerPush({
    required String token,
    required String pushToken,
    required String platform,
    String? locale,
    String? appVersion,
  }) async {
    registered.add({'token': pushToken, 'platform': platform});
    if (failRegister) throw Exception('network');
  }

  @override
  Future<void> unregisterPush({
    required String token,
    required String pushToken,
  }) async {
    unregistered.add(pushToken);
  }
}
