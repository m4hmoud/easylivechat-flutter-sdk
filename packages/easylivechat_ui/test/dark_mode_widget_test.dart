import 'package:easylivechat/easylivechat.dart';
import 'package:easylivechat_ui/src/l10n.dart';
import 'package:easylivechat_ui/src/launcher.dart';
import 'package:easylivechat_ui/src/theme.dart';
import 'package:easylivechat_ui/src/views/bubble_shape.dart';
import 'package:easylivechat_ui/src/views/closed_notice_view.dart';
import 'package:easylivechat_ui/src/views/thread_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dark mode (C2): the workspace's `colorScheme` — light, dark, or the
/// device's appearance — and the dark look derived from its one light look,
/// as `packages/shared/src/widget-theme.ts` derives it for the web.
///
/// The promises pinned here are the web's: light is exactly the look it was;
/// in dark the brand stays where the visitor sees it as a fill, and every
/// text on the dark surfaces reads at AA or better whatever the brand; a
/// workspace that designed a dark chat keeps it; a host's explicit theme wins.
void main() {
  const brands = [
    '#2563EB', '#1e3a8a', '#000000', '#facc15', '#d96e17', //
    '#16a34a', '#ffffff', '#7c3aed', '#e11d48', '#0f766e',
  ];

  WidgetConfigModel config(String scheme,
          {String primary = '#2563EB',
          String background = '#FFFFFF',
          String text = '#111827',
          Map<String, dynamic> extra = const {}}) =>
      WidgetConfigModel.fromJson({
        'id': 'w1',
        'tenantId': 't1',
        'colorScheme': scheme,
        'primaryColor': primary,
        'backgroundColor': background,
        'textColor': text,
        ...extra,
      });

  Color hex(String h) => EasyLiveChatTheme.parseHexColor(h);
  double contrast(Color a, Color b) => EasyLiveChatTheme.contrastRatio(a, b);

  group('the palette', () {
    test('light is the look it always was', () {
      final t = EasyLiveChatTheme.fromConfig(
          config('light', primary: '#d96e17'),
          platformBrightness: Brightness.dark);
      expect(t.background, hex('#FFFFFF'));
      expect(t.text, hex('#111827'));
      expect(t.primary, hex('#d96e17'));
      expect(t.isDark, isFalse);
      expect(t.danger, const Color(0xFFDC2626));
    });

    test('a legible brand is its own ink; one that washes out is rescued', () {
      final blue = EasyLiveChatTheme.fromConfig(config('light'));
      expect(blue.primaryInk, blue.primary);
      final yellow =
          EasyLiveChatTheme.fromConfig(config('light', primary: '#facc15'));
      expect(yellow.primary, hex('#facc15'));
      expect(yellow.primaryInk, isNot(hex('#facc15')));
      expect(contrast(yellow.primaryInk, yellow.background),
          greaterThanOrEqualTo(3));
    });

    test('dark: our ground and card, the brand kept as a fill', () {
      final t = EasyLiveChatTheme.fromConfig(config('dark', primary: '#d96e17'));
      expect(t.isDark, isTrue);
      expect(t.primary, hex('#d96e17'));
      // The card sits ON the ground, so it is the lighter of the two.
      expect(t.surface.computeLuminance(),
          greaterThan(t.background.computeLuminance()));
      expect(t.background.computeLuminance(), lessThan(0.02));
      expect(t.danger, const Color(0xFFF87171));
    });

    test('dark reads at AA or better for every text on it, whatever the brand',
        () {
      for (final brand in brands) {
        final t = EasyLiveChatTheme.fromConfig(config('dark', primary: brand));
        expect(contrast(t.text, t.surface), greaterThanOrEqualTo(7),
            reason: '$brand text on the card');
        expect(contrast(t.text, t.background), greaterThanOrEqualTo(7),
            reason: '$brand text on the ground');
        expect(contrast(t.primaryInk, t.surface), greaterThanOrEqualTo(4.5),
            reason: '$brand ink on the card');
      }
    });

    test('auto follows the device, and only auto does', () {
      expect(
          EasyLiveChatTheme.fromConfig(config('auto'),
                  platformBrightness: Brightness.dark)
              .isDark,
          isTrue);
      expect(
          EasyLiveChatTheme.fromConfig(config('auto'),
                  platformBrightness: Brightness.light)
              .isDark,
          isFalse);
      expect(
          EasyLiveChatTheme.fromConfig(config('dark'),
                  platformBrightness: Brightness.light)
              .isDark,
          isTrue);
    });

    test('an older server, with no scheme, stays light on a dark phone', () {
      final cfg =
          WidgetConfigModel.fromJson({'id': 'w1', 'tenantId': 't1'});
      expect(
          EasyLiveChatTheme.fromConfig(cfg, platformBrightness: Brightness.dark)
              .isDark,
          isFalse);
    });

    test('a workspace that designed a dark chat keeps its own colours', () {
      final t = EasyLiveChatTheme.fromConfig(
          config('dark', background: '#0B1020', text: '#F5F5F5'));
      expect(t.background, hex('#0B1020'));
      expect(t.text, hex('#F5F5F5'));
      expect(t.isDark, isTrue);
    });

    test("a host's explicit theme still wins, in dark too", () {
      const host = EasyLiveChatTheme(
        primary: Color(0xFF0E7C66),
        background: Color(0xFFFFFFFF),
        surface: Color(0xFFF2F0EB),
        text: Color(0xFF1B1B1B),
      );
      final t = EasyLiveChatTheme.fromConfig(config('dark'),
          override: host, platformBrightness: Brightness.dark);
      expect(t.background, host.background);
      expect(t.primary, host.primary);
      expect(t.isDark, isFalse);
    });

    test('the colour maths is the shared one', () {
      expect(EasyLiveChatTheme.mixColors(hex('#000000'), hex('#ffffff'), 0.5),
          hex('#808080'));
      expect(contrast(hex('#000000'), hex('#ffffff')), closeTo(21, 0.01));
      expect(
          EasyLiveChatTheme.inkOn(hex('#2563EB'), hex('#ffffff'), 3),
          hex('#2563EB'));
    });
  });

  group('on screen', () {
    setUpAll(() async {
      await EasyLiveChat.instance.boot(const EasyLiveChatConfig(
        apiBase: 'https://api.example.com',
        tenantSlug: 'acme',
      ));
    });

    tearDownAll(() => EasyLiveChat.instance.shutdown());

    setUp(() => ElcStrings.setLocale('en'));

    final dark = EasyLiveChatTheme.fromConfig(config('dark'));

    testWidgets("the team's bubble, its text and its links on the dark card",
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: dark.background,
          body: MessageBubble(
            message: ChatMessage(
              id: 'a1',
              conversationId: 'c1',
              body: 'See https://example.com',
              senderType: SenderType.agent,
              contentType: MessageContentType.text,
              createdAt: DateTime.utc(2026, 10, 18, 9),
            ),
            theme: dark,
            showAgentName: false,
            showAgentAvatar: false,
            strings: ElcStrings.of('en'),
          ),
        ),
      ));

      final bubble = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.color == dark.surface);
      expect(bubble.border, ElcBubbleShape.teamBorder(dark));

      final rich = tester.widget<RichText>(find.byType(RichText).first);
      final spans = <TextSpan>[];
      rich.text.visitChildren((s) {
        if (s is TextSpan && s.text != null) spans.add(s);
        return true;
      });
      final link = spans.firstWhere((s) => s.text!.contains('example.com'));
      expect(link.style?.color, dark.primaryInk);
    });

    testWidgets('the closed banner on the dark card', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ClosedNoticeBanner(config: config('dark'), theme: dark),
        ),
      ));
      final box = tester.widget<Container>(find.byType(Container).first);
      expect((box.decoration as BoxDecoration).color, dark.surface);
      final text = tester.widget<Text>(find.text(ElcStrings.of('en').closedNotice));
      expect(contrast(text.style!.color!.withValues(alpha: 1), dark.surface),
          greaterThanOrEqualTo(4.5));
    });

    testWidgets('the launcher is the brand in light and dark alike',
        (tester) async {
      final configs =
          EasyLiveChat.instance.widgetConfig as ValueNotifier<WidgetConfigModel?>;
      addTearDown(() => configs.value = null);
      configs.value = config('auto', primary: '#d96e17');

      Future<void> pumpOn(Brightness device) => tester.pumpWidget(MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(platformBrightness: device),
              child: const Scaffold(body: EasyLiveChatLauncher()),
            ),
          ));

      await pumpOn(Brightness.dark);
      final material = tester.widget<Material>(find
          .descendant(
              of: find.byType(EasyLiveChatLauncher),
              matching: find.byType(Material))
          .first);
      expect(material.color, hex('#d96e17'));
      expect(find.bySemanticsLabel('Open chat'), findsOneWidget);

      // As on the web: the launcher is the workspace's colour in both.
      await pumpOn(Brightness.light);
      expect(
          tester
              .widget<Material>(find
                  .descendant(
                      of: find.byType(EasyLiveChatLauncher),
                      matching: find.byType(Material))
                  .first)
              .color,
          hex('#d96e17'));
    });

    testWidgets("the launcher's words and size", (tester) async {
      final configs =
          EasyLiveChat.instance.widgetConfig as ValueNotifier<WidgetConfigModel?>;
      addTearDown(() => configs.value = null);
      configs.value = config('light',
          extra: {'launcherLabel': '  Chat   with us ', 'launcherSize': 'large'});

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: EasyLiveChatLauncher()),
      ));
      expect(find.text('Chat with us'), findsOneWidget);
      expect(find.bySemanticsLabel('Chat with us'), findsOneWidget);
      final material = find
          .descendant(
              of: find.byType(EasyLiveChatLauncher),
              matching: find.byType(Material))
          .first;
      expect(tester.getSize(material).height, 64);
      expect(tester.widget<Material>(material).shape, isA<StadiumBorder>());

      configs.value = config('light', extra: {'launcherSize': 'small'});
      await tester.pump();
      expect(find.text('Chat with us'), findsNothing);
      expect(tester.getSize(material), const Size(48, 48));
    });
  });
}
