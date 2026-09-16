import 'package:cached_network_image/cached_network_image.dart';
import 'package:easylivechat/easylivechat.dart';
import 'package:easylivechat_ui/src/l10n.dart';
import 'package:easylivechat_ui/src/theme.dart';
import 'package:easylivechat_ui/src/views/bubble_shape.dart';
import 'package:easylivechat_ui/src/views/linkified_text.dart';
import 'package:easylivechat_ui/src/views/message_card_view.dart';
import 'package:easylivechat_ui/src/views/thread_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart' show LinkDelegate;
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Records what the card asked the platform to open.
class _FakeUrlLauncher extends UrlLauncherPlatform {
  final List<String> launched = <String>[];
  final List<PreferredLaunchMode> modes = <PreferredLaunchMode>[];

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
    modes.add(options.mode);
    return true;
  }
}

/// A card is a message from the team with an image, a title, text and link
/// buttons in it.
///
/// Before this the SDK drew a card as its plain-text fallback — the title, the
/// text and every link spelled out as `Label: https://…` — while the widget
/// and the dashboard drew the card. What is pinned here: the card replaces that
/// text rather than joining it, its buttons open their links and nothing but
/// http(s), and it wears the workspace's bubble rather than a look of its own.
void main() {
  setUpAll(() async {
    // resolveUrl needs a booted client; boot only touches in-memory storage.
    await EasyLiveChat.instance.boot(const EasyLiveChatConfig(
      apiBase: 'https://api.example.com',
      tenantSlug: 'acme',
    ));
  });

  tearDownAll(() => EasyLiveChat.instance.shutdown());

  late _FakeUrlLauncher launcher;
  late UrlLauncherPlatform original;

  setUp(() {
    ElcStrings.overrideAll(const {});
    ElcStrings.overrideByLocale(const {});
    ElcStrings.setLocale('en');
    original = UrlLauncherPlatform.instance;
    launcher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
  });

  tearDown(() => UrlLauncherPlatform.instance = original);

  const theme = EasyLiveChatTheme(
    primary: Color(0xFF0E7C66),
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF2F0EB),
    text: Color(0xFF1B1B1B),
  );

  const fallback = 'Order #1042 is on its way\nArriving Friday.\n\n'
      'Track parcel: https://shop.example/t/1042\nHelp: https://shop.example/help';

  ChatMessage cardMessage({
    Map<String, dynamic>? card,
    List<String> attachmentUrls = const ['/uploads/t1/2026-09/parcel.png'],
    MessageContentType contentType = MessageContentType.card,
  }) =>
      ChatMessage(
        id: 'card-1',
        conversationId: 'c1',
        body: fallback,
        senderType: SenderType.agent,
        senderName: 'Sam',
        contentType: contentType,
        attachmentUrls: attachmentUrls,
        createdAt: DateTime.utc(2026, 9, 16, 9),
        metadata: {
          'card': card ??
              {
                'imageUrl': '/uploads/t1/2026-09/parcel.png',
                'title': 'Order #1042 is on its way',
                'text': 'Arriving Friday.',
                'buttons': [
                  {'label': 'Track parcel', 'url': 'https://shop.example/t/1042'},
                  {'label': 'Help', 'url': 'https://shop.example/help'},
                ],
              },
        },
      );

  Future<void> pump(
    WidgetTester tester,
    ChatMessage message, {
    TextDirection direction = TextDirection.ltr,
    EasyLiveChatTheme t = theme,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: SingleChildScrollView(
            child: MessageBubble(
              message: message,
              theme: t,
              showAgentName: true,
              strings: ElcStrings.of('en'),
            ),
          ),
        ),
      ),
    ));
  }

  testWidgets('draws the title, text and buttons — and not the text version it carries',
      (tester) async {
    await pump(tester, cardMessage());

    expect(find.byType(ElcMessageCardView), findsOneWidget);
    expect(find.text('Order #1042 is on its way'), findsOneWidget);
    expect(find.text('Arriving Friday.'), findsOneWidget);
    expect(find.text('Track parcel'), findsOneWidget);
    expect(find.text('Help'), findsOneWidget);

    // The plain-text version is for clients that can't draw a card.
    expect(find.byType(LinkifiedText), findsNothing);
    expect(find.textContaining('https://shop.example'), findsNothing);
    expect(find.textContaining('Track parcel:'), findsNothing);
  });

  testWidgets('shows its image once, on top, 16:9 — not again as an attachment',
      (tester) async {
    await pump(tester, cardMessage());

    final images = tester.widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(images, hasLength(1));
    // Our own upload, resolved against the API like every attachment.
    expect(images.single.imageUrl, 'https://api.example.com/uploads/t1/2026-09/parcel.png');
    expect(images.single.fit, BoxFit.cover);

    final ratio = find.ancestor(
      of: find.byType(CachedNetworkImage),
      matching: find.byType(AspectRatio),
    );
    expect(tester.widget<AspectRatio>(ratio).aspectRatio, 16 / 9);
    // Above the title.
    expect(tester.getBottomLeft(ratio).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.text('Order #1042 is on its way')).dy));
  });

  testWidgets('a card without an image draws none, and still no attachment', (tester) async {
    await pump(
      tester,
      cardMessage(card: {
        'title': 'Your refund is on its way',
        'buttons': [
          {'label': 'See details', 'url': 'https://shop.example/r/7'},
        ],
      }, attachmentUrls: const []),
    );
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.byType(AspectRatio), findsNothing);
    expect(find.text('See details'), findsOneWidget);
  });

  testWidgets('a button opens its link in the browser', (tester) async {
    await pump(tester, cardMessage());

    await tester.tap(find.text('Track parcel'));
    await tester.pump();

    expect(launcher.launched, ['https://shop.example/t/1042']);
    expect(launcher.modes, [PreferredLaunchMode.externalApplication]);
  });

  testWidgets('each button is a link of its own to a screen reader', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, cardMessage());

    for (final label in ['Track parcel', 'Help']) {
      final link = find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate(
            (w) => w is Semantics && (w.properties.link ?? false)),
      );
      expect(tester.widget<Semantics>(link).container, isTrue);
      final node = tester.getSemantics(link);
      expect(node.label, label);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    }
    handle.dispose();
  });

  testWidgets('a javascript: link in the row is never drawn, let alone opened',
      (tester) async {
    await pump(
      tester,
      cardMessage(card: {
        'title': 'Hello',
        'buttons': [
          {'label': 'Bad', 'url': 'javascript:alert(1)'},
          {'label': 'Good', 'url': 'https://ok.example'},
        ],
      }),
    );

    expect(find.text('Bad'), findsNothing);
    await tester.tap(find.text('Good'));
    await tester.pump();
    expect(launcher.launched, ['https://ok.example']);
  });

  testWidgets('a CARD message whose card does not validate reads as its text',
      (tester) async {
    await pump(tester, cardMessage(card: {'text': 'no title'}, attachmentUrls: const []));

    expect(find.byType(ElcMessageCardView), findsNothing);
    expect(find.byType(LinkifiedText), findsOneWidget);
    expect(find.textContaining('Track parcel: https://shop.example/t/1042'), findsOneWidget);
  });

  testWidgets('card metadata on a message that is not a CARD is ignored', (tester) async {
    await pump(tester, cardMessage(contentType: MessageContentType.text, attachmentUrls: const []));
    expect(find.byType(ElcMessageCardView), findsNothing);
    expect(find.byType(LinkifiedText), findsOneWidget);
  });

  testWidgets('wears the team bubble: the same surface, corners, tail and outline',
      (tester) async {
    await pump(tester, cardMessage());

    final box = tester.widget<Container>(find.descendant(
      of: find.byType(ElcMessageCardView),
      matching: find.byWidgetPredicate(
          (w) => w is Container && w.decoration is BoxDecoration),
    ).first);
    final decoration = box.decoration! as BoxDecoration;
    final outline = box.foregroundDecoration! as BoxDecoration;

    expect(decoration.color, theme.surface);
    expect(decoration.borderRadius, ElcBubbleShape.radius(fromCustomer: false));
    expect(outline.border, ElcBubbleShape.teamBorder(theme));
    expect(box.clipBehavior, Clip.antiAlias);

    // …which is exactly what a text message from the team is drawn in.
    await tester.pumpWidget(const SizedBox());
    await pump(
      tester,
      ChatMessage(
        id: 't1',
        conversationId: 'c1',
        body: 'hello',
        senderType: SenderType.agent,
        contentType: MessageContentType.text,
        createdAt: DateTime.utc(2026, 9, 16, 9),
      ),
    );
    final bubble = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.color == theme.surface);
    expect(bubble.borderRadius, decoration.borderRadius);
    expect(bubble.border, outline.border);
  });

  testWidgets('the tail sits on the team side in RTL too', (tester) async {
    await pump(tester, cardMessage(), direction: TextDirection.rtl);
    final radius = ElcBubbleShape.radius(fromCustomer: false).resolve(TextDirection.rtl);
    expect(radius.bottomRight, const Radius.circular(4));
    expect(radius.bottomLeft, const Radius.circular(16));

    // And the card itself stands on the team's (leading, so right) edge.
    final card = tester.getRect(find.byType(ElcMessageCardView));
    final screen = tester.getRect(find.byType(Scaffold));
    expect(screen.right - card.right, lessThan(card.left - screen.left));
  });

  testWidgets('its buttons wear the workspace accent', (tester) async {
    const pink = EasyLiveChatTheme(
      primary: Color(0xFFDB2777),
      background: Color(0xFF111827),
      surface: Color(0xFF1F2937),
      text: Color(0xFFF9FAFB),
    );
    await pump(tester, cardMessage(), t: pink);

    final label = tester.widget<Text>(find.text('Track parcel'));
    expect(label.style?.color, pink.primary);
    final title = tester.widget<Text>(find.text('Order #1042 is on its way'));
    expect(title.style?.color, pink.text);
  });

  testWidgets('is 280 wide, or narrower on a phone that cannot fit that',
      (tester) async {
    await pump(tester, cardMessage());
    expect(tester.getSize(find.byType(ElcMessageCardView)).width, 280);

    tester.view.physicalSize = const Size(300, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, cardMessage());
    // 68% of the width beside an avatar — and nothing overflows.
    expect(tester.getSize(find.byType(ElcMessageCardView)).width, closeTo(300 * 0.68, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('each run of text faces the way it reads', (tester) async {
    await pump(
      tester,
      cardMessage(card: {
        'title': 'داواکاریەکەت نێردرا',
        'text': 'Arriving Friday.',
        'buttons': [
          {'label': 'بەدواداچوون', 'url': 'https://shop.example/t'},
        ],
      }),
    );
    expect(tester.widget<Text>(find.text('داواکاریەکەت نێردرا')).textDirection,
        TextDirection.rtl);
    expect(tester.widget<Text>(find.text('Arriving Friday.')).textDirection,
        TextDirection.ltr);
    expect(tester.widget<Text>(find.text('بەدواداچوون')).textDirection,
        TextDirection.rtl);
  });
}
