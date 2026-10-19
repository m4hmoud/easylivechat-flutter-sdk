/// The consent checkbox in the pre-chat form.
///
/// A box, the tenant's sentence beside it and an optional privacy-policy link.
/// A required one blocks the chat until it is ticked; the link opens outside
/// the app and never ticks anything; and the whole row reads from the start
/// edge in either direction.
library;

import 'package:easylivechat_ui/easylivechat_ui.dart';
import 'package:easylivechat_ui/src/views/pre_chat_form_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart' show LinkDelegate;
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _FakeUrlLauncher extends UrlLauncherPlatform {
  final List<String> launched = <String>[];

  @override
  final LinkDelegate? linkDelegate = null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) async {
    launched.add(url);
    return true;
  }

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

const _sentence = 'I agree that this workspace may store what I write here.';

Map<String, dynamic> _consent({
  bool required = true,
  Object? policyUrl = 'https://example.com/privacy',
  String label = _sentence,
}) =>
    {
      'id': 'privacy',
      'label': label,
      'type': 'consent',
      'required': required,
      'policyUrl': policyUrl,
    };

Future<void> _pump(
  WidgetTester tester, {
  required Map<String, dynamic> field,
  String locale = 'en',
  TextDirection direction = TextDirection.ltr,
}) async {
  await EasyLiveChat.instance.boot(const EasyLiveChatConfig(
    apiBase: 'https://api.example.test',
    tenantSlug: 'acme',
    enablePresenceSocket: false,
    enableHeartbeat: false,
  ));
  final config = WidgetConfigModel.fromJson({
    'locale': locale,
    'welcomeTitle': 'Hello',
    'welcomeSubtitle': ' ',
    'preChatForm': {
      'enabled': true,
      'fields': [field],
    },
  });
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: PreChatFormView(
        config: config,
        theme: EasyLiveChatTheme(
          primary: const Color(0xFF2563EB),
          background: const Color(0xFFFFFFFF),
          surface: const Color(0xFFF1F5F9),
          text: const Color(0xFF0F172A),
          direction: direction,
        ),
      ),
    ),
  ));
}

bool _ticked(WidgetTester tester) =>
    tester.widget<Checkbox>(find.byType(Checkbox)).value ?? false;

void main() {
  late _FakeUrlLauncher launcher;
  late UrlLauncherPlatform original;

  setUp(() {
    ElcStrings.overrideAll(const {});
    ElcStrings.overrideByLocale(const {});
    ElcStrings.setLocale(null);
    original = UrlLauncherPlatform.instance;
    launcher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
  });

  tearDown(() {
    UrlLauncherPlatform.instance = original;
    EasyLiveChat.instance.shutdown();
  });

  testWidgets('draws a box, the sentence verbatim and the policy link',
      (tester) async {
    await _pump(tester, field: _consent());
    expect(find.byType(Checkbox), findsOneWidget);
    expect(find.text('$_sentence *'), findsOneWidget);
    expect(find.text('Privacy policy'), findsOneWidget);
    // A checkbox is never a text box.
    expect(find.byType(TextFormField), findsNothing);
    expect(_ticked(tester), isFalse);
  });

  testWidgets('a required box left unticked blocks the chat', (tester) async {
    await _pump(tester, field: _consent());
    await tester.tap(find.text('Start chat'));
    await tester.pump();
    expect(find.text('Please tick this box to continue'), findsOneWidget);
    // Nothing was sent: startSession would have moved the phase on.
    expect(EasyLiveChat.instance.phase.value, ChatPhase.idle);
  });

  testWidgets('tapping the sentence ticks the box and clears the error',
      (tester) async {
    await _pump(tester, field: _consent());
    await tester.tap(find.text('Start chat'));
    await tester.pump();
    expect(find.text('Please tick this box to continue'), findsOneWidget);

    await tester.tap(find.text('$_sentence *'));
    await tester.pump();
    expect(_ticked(tester), isTrue);
    expect(find.text('Please tick this box to continue'), findsNothing);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(_ticked(tester), isFalse);
  });

  testWidgets('the policy opens outside the app and ticks nothing',
      (tester) async {
    await _pump(tester, field: _consent());
    await tester.tap(find.text('Privacy policy'));
    await tester.pump();
    expect(launcher.launched, ['https://example.com/privacy']);
    expect(_ticked(tester), isFalse);
  });

  testWidgets('no link without a policy, and never a javascript: one',
      (tester) async {
    await _pump(tester, field: _consent(policyUrl: 'javascript:alert(1)'));
    expect(find.text('Privacy policy'), findsNothing);
  });

  testWidgets('an optional box can stay unticked', (tester) async {
    await _pump(tester, field: _consent(required: false));
    expect(find.text(_sentence), findsOneWidget, reason: 'no required marker');
    await tester.tap(find.text('Start chat'));
    await tester.pump();
    expect(find.text('Please tick this box to continue'), findsNothing);
    // Not blocked: the session start went out.
    expect(EasyLiveChat.instance.phase.value, ChatPhase.loading);
    // The test binding answers every HTTP request with a 400; let it.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a 500-character sentence wraps instead of overflowing',
      (tester) async {
    final long = List.filled(50, 'I agree.').join(' ');
    await _pump(tester, field: _consent(label: long));
    expect(tester.takeException(), isNull);
    final box = tester.getSize(find.text('$long *'));
    expect(box.height, greaterThan(100), reason: 'many lines, not one');
  });

  testWidgets('RTL: the box leads from the right; chrome is translated',
      (tester) async {
    const sentence = 'أوافق على أن تحتفظ مساحة العمل هذه بما أكتبه هنا.';
    await _pump(
      tester,
      field: _consent(label: sentence),
      locale: 'ar',
      direction: TextDirection.rtl,
    );
    final boxLeft = tester.getTopLeft(find.byType(Checkbox)).dx;
    final textLeft = tester.getTopLeft(find.text('$sentence *')).dx;
    expect(boxLeft, greaterThan(textLeft),
        reason: 'the checkbox sits at the start edge, which is the right');
    expect(find.text('سياسة الخصوصية'), findsOneWidget);

    await tester.tap(find.text('بدء المحادثة'));
    await tester.pump();
    expect(find.text('يُرجى تحديد هذا المربع للمتابعة'), findsOneWidget);
  });

  test('CONSENT_REQUIRED maps to its own message in every locale', () {
    for (final locale in ['en', 'ar', 'ckb', 'de', 'kmr', 'ur', 'zh']) {
      final s = ElcStrings.of(locale);
      expect(s.forErrorCode('CONSENT_REQUIRED'), s.consentRequired);
      expect(s.consentRequired, isNot(s.somethingWentWrong));
      expect(s.privacyPolicy, isNotEmpty);
    }
  });
}
