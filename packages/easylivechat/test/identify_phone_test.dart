/// A phone number the host supplies has to reach the agent.
///
/// `identify()` kept it in memory alone: the create path sent it, the RESUME
/// path did not, and nothing persisted it. So a visitor who already had a live
/// conversation when the host identified them — opened the chat from a login
/// screen, signed in, came back — arrived at the agent with a name and no
/// phone number, and the number was gone entirely after an app restart.
library;

import 'package:easylivechat/easylivechat.dart';
import 'package:easylivechat/src/rest_client.dart';
import 'package:easylivechat/src/session_controller.dart';
import 'package:test/test.dart';

void main() {
  group('StoredProfile', () {
    test('carries the phone across a save/load round trip', () {
      const profile = StoredProfile(
        name: 'Mahmoud',
        email: 'm@example.com',
        phone: '07823651875',
      );
      final restored = StoredProfile.fromJson(profile.toJson());
      expect(restored.phone, '07823651875');
      expect(restored.name, 'Mahmoud');
    });

    // Caches written by an older SDK have no `phone` key at all.
    test('decodes an older cache that predates the field', () {
      final restored = StoredProfile.fromJson({'name': 'Mahmoud'});
      expect(restored.name, 'Mahmoud');
      expect(restored.phone, isNull);
    });
  });

  group('resume', () {
    test('sends the identified phone, not just the name and email', () async {
      final rest = _RecordingRest(_config);
      final controller = SessionController(
        config: _config,
        storage: InMemoryStorage(),
      );
      controller.rest = rest;
      // Mints the visitorId from storage; no network involved.
      await controller.boot();

      controller.identify(
        name: 'Mahmoud',
        email: 'm@example.com',
        phone: '07823651875',
      );
      await controller.silentResume();

      expect(rest.lastResume, isNotNull);
      expect(rest.lastResume!['resumeOnly'], isTrue);
      expect(rest.lastResume!['name'], 'Mahmoud');
      // The one that was missing. The server adopts what a resume carries and
      // can adopt only what is sent.
      expect(rest.lastResume!['phone'], '07823651875');
    });
  });
}

const _config = EasyLiveChatConfig(
  apiBase: 'https://api.example.test',
  tenantSlug: 'acme',
);

/// Records what the controller asked for instead of going to the network.
class _RecordingRest extends RestClient {
  _RecordingRest(super.config);

  Map<String, dynamic>? lastResume;

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
  }) async {
    lastResume = {
      'name': name,
      'email': email,
      'phone': phone,
      'resumeOnly': resumeOnly,
    };
    return const SessionResult(resumed: false, hasActiveConversation: false);
  }
}
