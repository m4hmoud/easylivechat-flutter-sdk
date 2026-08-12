import 'package:easylivechat_ui/src/views/linkified_text.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart' show LinkDelegate;
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Captures what `launchUrl` was asked to open instead of hitting a platform
/// channel. A plain subclass is enough — [UrlLauncherPlatform]'s constructor
/// passes the verification token itself.
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

/// Pump a bubble-like host around [LinkifiedText].
Widget _host(String body) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: LinkifiedText(
            text: body,
            style: const TextStyle(fontSize: 15, color: Color(0xFF0F172A)),
            linkColor: const Color(0xFF2563EB),
          ),
        ),
      ),
    );

void main() {
  late _FakeUrlLauncher launcher;
  late UrlLauncherPlatform original;

  setUp(() {
    original = UrlLauncherPlatform.instance;
    launcher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
  });

  tearDown(() => UrlLauncherPlatform.instance = original);

  /// Tap the character at [index] of the rendered rich text.
  Future<void> tapAt(WidgetTester tester, String body, int index) async {
    final text = tester.widget<Text>(find.byType(Text));
    final span = text.textSpan!;
    // Walk the span tree for the recognizer covering `index`.
    var cursor = 0;
    GestureRecognizer? found;
    span.visitChildren((InlineSpan child) {
      if (child is TextSpan) {
        final len = child.text?.length ?? 0;
        if (index >= cursor &&
            index < cursor + len &&
            child.recognizer != null) {
          found = child.recognizer;
          return false;
        }
        cursor += len;
      }
      return true;
    });
    expect(found, isNotNull,
        reason: 'no tappable span covers index $index of "$body"');
    (found! as TapGestureRecognizer).onTap!();
    await tester.pump();
  }

  testWidgets('plain text renders without any tappable span', (tester) async {
    await tester.pumpWidget(_host('Hello, how can I help?'));
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.data, 'Hello, how can I help?');
    expect(text.textSpan, isNull);
  });

  testWidgets('tapping a URL opens it in the browser', (tester) async {
    const body = 'Docs are at https://livechattools.com/docs — enjoy';
    await tester.pumpWidget(_host(body));
    await tapAt(tester, body, body.indexOf('https://') + 2);
    expect(launcher.launched, ['https://livechattools.com/docs']);
  });

  testWidgets('tapping a scheme-less domain opens it over https',
      (tester) async {
    const body = 'see livechattools.com';
    await tester.pumpWidget(_host(body));
    await tapAt(tester, body, body.indexOf('livechattools'));
    expect(launcher.launched, ['https://livechattools.com']);
  });

  testWidgets('tapping an email opens the mail composer', (tester) async {
    const body = 'write to hello@livechattools.com any time';
    await tester.pumpWidget(_host(body));
    await tapAt(tester, body, body.indexOf('hello@'));
    expect(launcher.launched, ['mailto:hello@livechattools.com']);
  });

  testWidgets('tapping a phone number opens the dialer', (tester) async {
    const body = 'call +964 750 123 4567 today';
    await tester.pumpWidget(_host(body));
    await tapAt(tester, body, body.indexOf('+964'));
    expect(launcher.launched, ['tel:+9647501234567']);
  });

  testWidgets('link runs are underlined in the link color', (tester) async {
    await tester.pumpWidget(_host('go to https://example.com now'));
    final text = tester.widget<Text>(find.byType(Text));
    TextSpan? link;
    text.textSpan!.visitChildren((child) {
      if (child is TextSpan && child.recognizer != null) {
        link = child;
        return false;
      }
      return true;
    });
    expect(link, isNotNull);
    expect(link!.style!.color, const Color(0xFF2563EB));
    expect(link!.style!.decoration, TextDecoration.underline);
  });

  testWidgets('non-link text around a link is preserved verbatim',
      (tester) async {
    const body = 'ping https://example.com then reply';
    await tester.pumpWidget(_host(body));
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.textSpan!.toPlainText(), body);
  });
}
