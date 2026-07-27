/// Switching the app language between chat opens.
///
/// `boot()` is a singleton and used to return early once booted, so the config
/// the host rebuilt from its CURRENT language was thrown away. The visitor got
/// Arabic SDK chrome around Kurdish tenant copy — a Kurdish greeting, and a
/// post-chat survey still asking its questions in Kurdish — because both are
/// fetched with `contentLocale`.
library;

import 'package:easylivechat/easylivechat.dart';
import 'package:easylivechat/src/session_controller.dart';
import 'package:easylivechat/src/storage.dart';
import 'package:test/test.dart';

SessionController controllerFor(String contentLocale) => SessionController(
      config: EasyLiveChatConfig(
        apiBase: 'https://api.example.com',
        tenantSlug: 'acme',
        locale: 'Kurdish (Sorani)',
        contentLocale: contentLocale,
      ),
      storage: InMemoryStorage(),
    );

void main() {
  group('applyConfig', () {
    test('adopts a new content locale', () {
      final c = controllerFor('ku');
      final rest = c.rest;
      c.applyConfig(const EasyLiveChatConfig(
        apiBase: 'https://api.example.com',
        tenantSlug: 'acme',
        locale: 'Arabic',
        contentLocale: 'ar',
      ));
      expect(c.config.contentLocale, 'ar');
      expect(c.config.locale, 'Arabic');
      // The REST client bakes in base URL and headers, so it must be rebuilt.
      expect(identical(c.rest, rest), isFalse);
    });

    test('adopts a new channel — the login inbox is a different config', () {
      final c = controllerFor('ku');
      c.applyConfig(const EasyLiveChatConfig(
        apiBase: 'https://api.example.com',
        tenantSlug: 'acme',
        contentLocale: 'ku',
        channel: 'user-login',
      ));
      expect(c.config.channel, 'user-login');
    });

    test('an identical config is a no-op, so reopening does not churn Dio', () {
      final c = controllerFor('ku');
      final rest = c.rest;
      c.applyConfig(const EasyLiveChatConfig(
        apiBase: 'https://api.example.com',
        tenantSlug: 'acme',
        locale: 'Kurdish (Sorani)',
        contentLocale: 'ku',
      ));
      expect(identical(c.rest, rest), isTrue);
    });
  });
}
