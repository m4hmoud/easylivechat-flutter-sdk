/// The config fields the chat's look and its closed notice are read from.
///
/// `colorScheme` is the workspace's light / dark / follow-the-device choice
/// (C2). Existing workspaces were kept on light and new ones start on auto, so
/// what decides an older server is the absence of the field: it must read as
/// light, never as auto, or every chat built before the setting would turn
/// dark on a dark phone. `offlineInfoText` is the business's own closed
/// notice, which wins over every built-in wording when it is set.
library;

import 'package:easylivechat/easylivechat.dart';
import 'package:test/test.dart';

WidgetConfigModel _cfg(Map<String, dynamic> extra) =>
    WidgetConfigModel.fromJson({'id': 'w', 'tenantId': 't', ...extra});

void main() {
  group('colorScheme', () {
    test('reads the three choices', () {
      expect(_cfg({'colorScheme': 'light'}).colorScheme,
          WidgetColorScheme.light);
      expect(
          _cfg({'colorScheme': 'dark'}).colorScheme, WidgetColorScheme.dark);
      expect(
          _cfg({'colorScheme': 'auto'}).colorScheme, WidgetColorScheme.auto);
    });

    test('absent or unknown reads as light — nobody\'s look changes', () {
      expect(_cfg({}).colorScheme, WidgetColorScheme.light);
      expect(_cfg({'colorScheme': null}).colorScheme, WidgetColorScheme.light);
      expect(_cfg({'colorScheme': 'DARK'}).colorScheme,
          WidgetColorScheme.light);
      expect(_cfg({'colorScheme': 1}).colorScheme, WidgetColorScheme.light);
    });

    test('only auto asks the device', () {
      expect(WidgetColorScheme.auto.resolveDark(deviceDark: true), isTrue);
      expect(WidgetColorScheme.auto.resolveDark(deviceDark: false), isFalse);
      expect(WidgetColorScheme.light.resolveDark(deviceDark: true), isFalse);
      expect(WidgetColorScheme.dark.resolveDark(deviceDark: false), isTrue);
    });
  });

  group('the launcher', () {
    test('its words, one line, capped at 40 characters', () {
      expect(_cfg({'launcherLabel': '  Chat \n with   us '}).launcherLabel,
          'Chat with us');
      expect(_cfg({'launcherLabel': 'x' * 60}).launcherLabel, 'x' * 40);
      expect(_cfg({'launcherLabel': '   '}).launcherLabel, isNull);
      expect(_cfg({}).launcherLabel, isNull);
    });

    test('its size; medium — the 56 it always was — otherwise', () {
      expect(_cfg({'launcherSize': 'small'}).launcherSize.diameter, 48);
      expect(_cfg({'launcherSize': 'large'}).launcherSize.diameter, 64);
      expect(_cfg({}).launcherSize, LauncherSize.medium);
      expect(_cfg({'launcherSize': 'huge'}).launcherSize.diameter, 56);
    });
  });

  group('offlineInfoText', () {
    test('the business\'s own notice, trimmed', () {
      expect(_cfg({'offlineInfoText': '  Back on Monday.  '}).offlineInfoText,
          'Back on Monday.');
    });

    test('null when nobody wrote one', () {
      expect(_cfg({}).offlineInfoText, isNull);
      expect(_cfg({'offlineInfoText': null}).offlineInfoText, isNull);
      expect(_cfg({'offlineInfoText': '   '}).offlineInfoText, isNull);
    });

    test('is not the leave-a-message prompt', () {
      final c = _cfg({'offlineMessage': "We're offline — leave us a message."});
      expect(c.offlineInfoText, isNull);
      expect(c.offlineMessage, "We're offline — leave us a message.");
    });
  });
}
