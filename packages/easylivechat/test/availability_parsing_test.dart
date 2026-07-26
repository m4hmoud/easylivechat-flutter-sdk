/// The availability verdict must survive the trip from JSON into the models.
///
/// It did not: `ConfigResponse.fromJson` parsed `isOpen`/`agentsAccepting` and
/// silently dropped `visitorMode`, so every response fell back to the `CHAT`
/// default. A tenant set to "show a notice, take nothing" was still shown the
/// pre-chat form, because the client never learned otherwise — the widget and
/// the server disagreed while both were "working".
///
/// These are pinned against real payload shapes for that reason: the failure
/// mode is a field going missing, which no amount of exercising the surrounding
/// logic will catch.
library;

import 'package:easylivechat/easylivechat.dart';
import 'package:test/test.dart';

/// A trimmed copy of the live `GET /api/widget/zirak/config` response.
Map<String, dynamic> configPayload({
  String visitorMode = 'NOTICE_ONLY',
  String reason = 'AFTER_HOURS',
  Object? nextOpenAt = '2026-07-26T06:00:00.000Z',
  Object? closureLabel,
}) =>
    {
      'tenantId': 'cmqjhgkdb091wd9ob9haknw5j',
      'config': {
        'id': 'w1',
        'tenantId': 'cmqjhgkdb091wd9ob9haknw5j',
        'primaryColor': '#1F97B8',
        'backgroundColor': '#111827',
        'textColor': '#F9FAFB',
        'logoUrl': 'https://api.livechattools.com/uploads/t/2026-07/logo.jpg',
        'welcomeTitle': 'Hi there 👋',
        'welcomeSubtitle': 'How can we help?',
        'offlineMessage': "We're closed right now.",
        'position': 'bottom-right',
        'locale': 'en',
      },
      'isOpen': false,
      'agentsAccepting': false,
      'visitorMode': visitorMode,
      'reason': reason,
      'closureLabel': closureLabel,
      'nextOpenAt': nextOpenAt,
      'chatAvailabilityMode': 'ALWAYS',
      'asyncEnabled': false,
    };

void main() {
  group('ConfigResponse.fromJson', () {
    test('carries the server verdict instead of defaulting to CHAT', () {
      final res = ConfigResponse.fromJson(configPayload());

      expect(res.visitorMode, 'NOTICE_ONLY');
      expect(res.noticeOnly, isTrue);
      expect(res.reason, 'AFTER_HOURS');
      expect(res.isOpen, isFalse);
      expect(res.agentsAccepting, isFalse);
    });

    test('parses nextOpenAt as a real instant', () {
      final res = ConfigResponse.fromJson(configPayload());

      expect(res.nextOpenAt, isNotNull);
      expect(res.nextOpenAt!.toUtc(), DateTime.utc(2026, 7, 26, 6));
    });

    test('keeps a named closure and drops a blank one', () {
      expect(
        ConfigResponse.fromJson(
          configPayload(reason: 'HOLIDAY', closureLabel: 'Eid al-Adha'),
        ).closureLabel,
        'Eid al-Adha',
      );
      // '' and null both mean "no name" — neither should reach the UI as text.
      expect(
        ConfigResponse.fromJson(configPayload(closureLabel: '  ')).closureLabel,
        isNull,
      );
      expect(ConfigResponse.fromJson(configPayload()).closureLabel, isNull);
    });

    test('an older server that omits the fields stays permissive', () {
      final legacy = configPayload()
        ..remove('visitorMode')
        ..remove('reason')
        ..remove('nextOpenAt');

      final res = ConfigResponse.fromJson(legacy);

      // Never close the widget because a field is missing.
      expect(res.visitorMode, 'CHAT');
      expect(res.noticeOnly, isFalse);
      expect(res.reason, 'OPEN');
      expect(res.nextOpenAt, isNull);
    });

    test('a garbled nextOpenAt is ignored rather than thrown on', () {
      final res =
          ConfigResponse.fromJson(configPayload(nextOpenAt: 'not-a-date'));
      expect(res.nextOpenAt, isNull);
    });
  });

  group('WorkspaceAvailability.fromJson — the socket path', () {
    test('reads the same verdict off workspace:availability', () {
      final a = WorkspaceAvailability.fromJson({
        'isOpen': false,
        'agentsAccepting': false,
        'visitorMode': 'NOTICE_ONLY',
        'reason': 'HOLIDAY',
        'closureLabel': 'Eid al-Adha',
        'nextOpenAt': '2026-07-26T06:00:00.000Z',
      });

      expect(a.visitorMode, 'NOTICE_ONLY');
      expect(a.reason, 'HOLIDAY');
      expect(a.closureLabel, 'Eid al-Adha');
      expect(a.nextOpenAt!.toUtc(), DateTime.utc(2026, 7, 26, 6));
    });

    test('an older server sending only the two booleans stays permissive', () {
      final a = WorkspaceAvailability.fromJson({'isOpen': true});

      expect(a.isOpen, isTrue);
      expect(a.agentsAccepting, isTrue); // absent must not close the widget
      expect(a.visitorMode, 'CHAT');
      expect(a.reason, 'OPEN');
    });
  });
}
