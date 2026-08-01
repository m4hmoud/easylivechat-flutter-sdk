/// The compiled table must match `l10n/sdk_strings.json`.
///
/// That JSON is the editable source and the Dart map is generated from it by
/// `l10n/apply.py`. Nothing forces anyone to run the script, and the two have
/// already drifted once: a release shipped a JSON full of corrected Sorani
/// that never reached the strings the app rendered, and the only symptom was
/// the old wording quietly staying put.
///
/// So the check lives here rather than in a habit.
library;

import 'dart:convert';
import 'dart:io';

import 'package:easylivechat_ui/src/l10n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every string in sdk_strings.json is in the compiled table', () {
    ElcStrings.overrideAll(const {});
    ElcStrings.overrideByLocale(const {});
    ElcStrings.setLocale(null);

    final file = File('l10n/sdk_strings.json');
    expect(file.existsSync(), isTrue,
        reason: 'run from the package root: '
            'cd flutter-sdk/packages/easylivechat_ui && flutter test');

    final data = json.decode(file.readAsStringSync()) as Map<String, dynamic>;
    data.remove('_readme');

    final drift = <String>[];
    data.forEach((locale, block) {
      final strings = ElcStrings.of(locale);
      (block as Map<String, dynamic>).forEach((key, value) {
        final want = (value as String).trim();
        if (want.isEmpty) return; // deliberately falls back to English
        final got = strings.stringFor(key);
        if (got != want) drift.add('$locale.$key\n  json: $want\n  dart: $got');
      });
    });

    expect(
      drift,
      isEmpty,
      reason: 'l10n.dart is stale — run:\n'
          '  python3 l10n/apply.py\n\n${drift.join('\n\n')}',
    );
  });
}
