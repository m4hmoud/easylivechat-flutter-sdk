/// Host string overrides.
///
/// A host embedding the SDK may want its own wording. `overrideAll` applies to
/// EVERY locale, which is fine for a single-language app and wrong for a
/// multilingual one — it would show a Kurdish and an Arabic visitor the same
/// words. `overrideByLocale` is the per-language form.
library;

import 'package:easylivechat_ui/src/l10n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    ElcStrings.overrideAll(const {});
    ElcStrings.overrideByLocale(const {});
    ElcStrings.setLocale(null);
  });

  test('per-locale overrides apply only to their own locale', () {
    ElcStrings.overrideByLocale(const {
      'ckb': {'send': 'ناردنی سۆرانی'},
      'ar': {'send': 'إرسال عربي'},
    });
    expect(ElcStrings.of('ckb').send, 'ناردنی سۆرانی');
    expect(ElcStrings.of('ar').send, 'إرسال عربي');
    // Untouched locale keeps the shipped translation.
    expect(ElcStrings.of('en').send, 'Send');
  });

  test('a per-locale override beats the all-locale one', () {
    ElcStrings.overrideAll(const {'send': 'EVERYWHERE'});
    ElcStrings.overrideByLocale(const {
      'ckb': {'send': 'ONLY SORANI'},
    });
    expect(ElcStrings.of('ckb').send, 'ONLY SORANI');
    // …and the flat override still covers locales it doesn't name.
    expect(ElcStrings.of('ar').send, 'EVERYWHERE');
  });

  test('keys the host omits fall back to the shipped translation', () {
    ElcStrings.overrideByLocale(const {
      'ckb': {'send': 'X'},
    });
    expect(ElcStrings.of('ckb').send, 'X');
    expect(ElcStrings.of('ckb').submit, isNot('X'));
    expect(ElcStrings.of('ckb').submit.isNotEmpty, isTrue);
  });

  test('locale codes are normalized like everywhere else', () {
    ElcStrings.overrideByLocale(const {
      'KU': {'send': 'via old code'},
    });
    // `ku` is the deprecated Sorani code; it must land on the ckb table.
    expect(ElcStrings.of('ckb').send, 'via old code');
    expect(ElcStrings.of('ckb-IQ').send, 'via old code');
  });

  test('a language the SDK does not ship can be added by the host', () {
    ElcStrings.overrideByLocale(const {
      'fa': {'send': 'ارسال'},
    });
    final fa = ElcStrings.of('fa');
    expect(fa.send, 'ارسال');
    // Anything they didn't translate falls back to English, not to a blank.
    expect(fa.submit, 'Submit');
  });

  test('an empty override does not blank a string', () {
    ElcStrings.overrideByLocale(const {
      'ckb': {'send': ''},
    });
    expect(ElcStrings.of('ckb').send.isNotEmpty, isTrue);
  });
}
