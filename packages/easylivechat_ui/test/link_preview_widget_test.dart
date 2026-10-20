import 'package:cached_network_image/cached_network_image.dart';
import 'package:easylivechat/easylivechat.dart';
import 'package:easylivechat_ui/src/l10n.dart';
import 'package:easylivechat_ui/src/theme.dart';
import 'package:easylivechat_ui/src/views/link_preview_view.dart';
import 'package:easylivechat_ui/src/views/thread_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart' show LinkDelegate;
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Link previews (C2), drawn the way the web widget draws them
/// (apps/widget/src/components/LinkPreview.tsx): a card under the bubble with
/// the site, the title, a line of description and the picture; it opens the
/// link in the browser; a picture that will not load goes; the workspace
/// switch hides it; a card message never gets one.
class _FakeUrlLauncher extends UrlLauncherPlatform {
  final List<(String, PreferredLaunchMode)> launched = [];

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
  }) async =>
      true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add((url, options.mode));
    return true;
  }
}

void main() {
  late _FakeUrlLauncher launcher;
  late UrlLauncherPlatform original;

  setUpAll(() async {
    await EasyLiveChat.instance.boot(const EasyLiveChatConfig(
      apiBase: 'https://api.example.com',
      tenantSlug: 'acme',
    ));
  });

  tearDownAll(() => EasyLiveChat.instance.shutdown());

  setUp(() {
    ElcStrings.setLocale('en');
    original = UrlLauncherPlatform.instance;
    launcher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
  });

  tearDown(() => UrlLauncherPlatform.instance = original);

  const theme = EasyLiveChatTheme(
    primary: Color(0xFF2563EB),
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF1F5F9),
    text: Color(0xFF0F172A),
  );

  ChatMessage message({
    Map<String, dynamic>? preview = const {
      'url': 'https://shop.example/blog/autumn',
      'title': 'The autumn collection',
      'description': 'Coats, boots and scarves for the cold months.',
      'siteName': 'Shop Example',
      'imageUrl': '/uploads/t1/previews/autumn.jpg',
    },
    MessageContentType contentType = MessageContentType.text,
    Map<String, dynamic> extra = const {},
  }) =>
      ChatMessage(
        id: 'a1',
        conversationId: 'c1',
        body: 'Have a look: https://shop.example/blog/autumn',
        senderType: SenderType.agent,
        contentType: contentType,
        createdAt: DateTime.utc(2026, 10, 18, 9),
        metadata: {if (preview != null) 'linkPreview': preview, ...extra},
      );

  Future<void> pump(WidgetTester tester, ChatMessage m,
          {bool showLinkPreview = true}) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MessageBubble(
              message: m,
              theme: theme,
              showAgentName: false,
              strings: ElcStrings.of('en'),
              showLinkPreview: showLinkPreview,
            ),
          ),
        ),
      ));

  testWidgets('draws the site, the title and a line of the description',
      (tester) async {
    await pump(tester, message());

    expect(find.byType(ElcLinkPreviewCard), findsOneWidget);
    expect(find.text('Shop Example'), findsOneWidget);
    expect(find.text('The autumn collection'), findsOneWidget);
    expect(find.text('Coats, boots and scarves for the cold months.'),
        findsOneWidget);
    // Under the bubble, not inside it.
    expect(
      tester.getTopLeft(find.text('The autumn collection')).dy,
      greaterThan(tester
          .getBottomLeft(find.textContaining('Have a look'))
          .dy),
    );
  });

  testWidgets('its picture is our own upload, resolved against the API',
      (tester) async {
    await pump(tester, message());
    final image =
        tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(image.imageUrl,
        'https://api.example.com/uploads/t1/previews/autumn.jpg');
  });

  testWidgets('a picture that will not load goes, and the words stay',
      (tester) async {
    await pump(tester, message());
    final image =
        tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    // What the image cache does when the fetch fails.
    image.errorWidget!(tester.element(find.byType(CachedNetworkImage)),
        image.imageUrl, Exception('404'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.text('The autumn collection'), findsOneWidget);
  });

  testWidgets('a tap opens the link in the browser, not inside the app',
      (tester) async {
    await pump(tester, message());
    await tester.tap(find.text('The autumn collection'));
    await tester.pump();
    expect(launcher.launched, [
      ('https://shop.example/blog/autumn', PreferredLaunchMode.externalApplication),
    ]);
  });

  testWidgets('without a picture or a description, still a card',
      (tester) async {
    await pump(
      tester,
      message(preview: const {
        'url': 'https://www.example.com/a',
        'title': 'Example',
      }),
    );
    expect(find.byType(CachedNetworkImage), findsNothing);
    // The host, when the site gave no name.
    expect(find.text('example.com'), findsOneWidget);
  });

  testWidgets('a link that is not http(s) draws nothing', (tester) async {
    await pump(
      tester,
      message(preview: const {'url': 'javascript:alert(1)', 'title': 'x'}),
    );
    expect(find.byType(ElcLinkPreviewCard), findsNothing);
  });

  testWidgets('the workspace switch hides it', (tester) async {
    await pump(tester, message(), showLinkPreview: false);
    expect(find.byType(ElcLinkPreviewCard), findsNothing);
  });

  testWidgets('a card message has its own picture, and no preview',
      (tester) async {
    await pump(
      tester,
      message(contentType: MessageContentType.card, extra: const {
        'card': {
          'title': 'Order #1042',
          'buttons': [
            {'label': 'Track', 'url': 'https://shop.example/t/1042'},
          ],
        },
      }),
    );
    expect(find.text('Order #1042'), findsOneWidget);
    expect(find.byType(ElcLinkPreviewCard), findsNothing);
  });

  testWidgets('each line faces the way its own words read', (tester) async {
    await pump(
      tester,
      message(preview: const {
        'url': 'https://example.iq/a',
        'title': 'مجموعة الخريف',
        'siteName': 'Example',
      }),
    );
    final title = tester.widget<Text>(find.text('مجموعة الخريف'));
    expect(title.textDirection, TextDirection.rtl);
    final site = tester.widget<Text>(find.text('Example'));
    expect(site.textDirection, TextDirection.ltr);
  });
}
