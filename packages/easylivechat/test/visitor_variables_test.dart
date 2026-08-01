/// Tenant copy that greets the visitor by name.
///
/// The server resolves these tokens for text it PERSISTS (the auto-greeting);
/// copy delivered through `GET /config` arrives unresolved, because at that
/// moment nobody knows who is asking. So the same rules have to hold here.
library;

import 'package:easylivechat/easylivechat.dart';
import 'package:test/test.dart';

void main() {
  group('substituteVisitorVariables', () {
    test('accepts both syntaxes the platform already shipped', () {
      expect(substituteVisitorVariables('سلاڤ %name%', name: 'Mahmoud'),
          'سلاڤ Mahmoud');
      expect(substituteVisitorVariables('Hi {{name}}', name: 'Mahmoud'),
          'Hi Mahmoud');
      expect(substituteVisitorVariables('Hi {{ name }}', name: 'Mahmoud'),
          'Hi Mahmoud');
      expect(substituteVisitorVariables('Hi %NAME%', name: 'Mahmoud'),
          'Hi Mahmoud');
    });

    test('first_name is the first word only', () {
      expect(
        substituteVisitorVariables('Hi %first_name%', name: 'Ada Lovelace'),
        'Hi Ada',
      );
    });

    test('an anonymous visitor gets the tenant default', () {
      expect(
        substituteVisitorVariables('Hi %name%', name: null, defaultName: 'بەرێز'),
        'Hi بەرێز',
      );
      expect(
        substituteVisitorVariables('Hi %name%', name: '   ', defaultName: 'there'),
        'Hi there',
      );
    });

    // The one outcome a visitor must never be shown.
    test('never leaves the raw token on screen', () {
      final out = substituteVisitorVariables('Hi %name%!');
      expect(out, 'Hi !');
      expect(out.contains('%name%'), isFalse);
    });

    test('leaves queue tokens for the server to fill', () {
      expect(
        substituteVisitorVariables('You are %number% in queue', name: 'A'),
        'You are %number% in queue',
      );
    });
  });
}
