import 'package:easylivechat/easylivechat.dart';
import 'package:flutter/widgets.dart';

/// Resolved, Flutter-native theme for the EasyLiveChat UI.
///
/// All values originate from the server-driven [WidgetConfigModel] — the native
/// analog of the web CSS vars `--widget-accent/--widget-bg/--widget-text`. Hosts
/// may pass an [EasyLiveChatTheme] `override`; any non-null field on the override
/// wins over the server config.
///
/// Colors arrive as `#RRGGBB` (or `#RGB`/`#AARRGGBB`) hex strings and are parsed
/// to [Color]. [direction] derives from `WidgetConfig.direction` (`ar`/`ku` →
/// RTL) and is fed to a [Directionality] wrapping the chat subtree.
///
/// Light or dark follows the workspace's `colorScheme` — light, dark, or the
/// device's own appearance (`auto`); see [EasyLiveChatTheme.fromConfig]. The
/// dark look is derived from the workspace's one light look the way the web
/// widget derives it (`packages/shared/src/widget-theme.ts`), never designed
/// twice.
///
/// `customCss` is intentionally not represented here — raw CSS cannot map to
/// Flutter and is ignored (a documented no-op). Hosts customize via `override`.
class EasyLiveChatTheme {
  /// Accent — send button, launcher bubble, active controls.
  final Color primary;

  /// Page / screen background.
  final Color background;

  /// Raised surfaces (message bubbles, composer, sheets).
  final Color surface;

  /// Body / foreground text.
  final Color text;

  /// Layout direction (LTR/RTL) for the chat subtree.
  final TextDirection direction;

  /// Optional header logo (absolute URL, served by the tenant).
  final String? logoUrl;

  /// Optional launcher-bubble icon (absolute URL); falls back to a chat glyph.
  final String? bubbleIconUrl;

  final Color? _primaryInk;
  final Color? _danger;
  final Brightness? _brightness;

  const EasyLiveChatTheme({
    required this.primary,
    required this.background,
    required this.surface,
    required this.text,
    this.direction = TextDirection.ltr,
    this.logoUrl,
    this.bubbleIconUrl,
    Color? primaryInk,
    Color? danger,
    Brightness? brightness,
  })  : _primaryInk = primaryInk,
        _danger = danger,
        _brightness = brightness;

  /// The brand used as INK — links in the team's bubbles, outlined buttons,
  /// the AI badge, an icon on a surface — as opposed to [primary] used as a
  /// FILL (the send button, the visitor's own bubble, the launcher).
  ///
  /// The two differ only where the brand would not read as text: a yellow on
  /// white, a mid-tone on the dark surfaces. This is then the least step
  /// darker (on light) or lighter (on dark) that does read. A brand blue on
  /// white stays exactly the brand blue. Defaults to [primary] on a theme
  /// built by hand.
  Color get primaryInk => _primaryInk ?? primary;

  /// Errors and the failed-send marker: a red that reads on [background].
  Color get danger =>
      _danger ?? (brightness == Brightness.dark ? _darkDanger : _lightDanger);

  /// Light or dark. Set by [EasyLiveChatTheme.fromConfig]; on a theme built by
  /// hand it is read off [background] unless given.
  Brightness get brightness => _brightness ?? _estimateBrightness(background);

  /// The chat is drawn dark.
  bool get isDark => brightness == Brightness.dark;

  /// Text and icons on a [primary] fill: near-black on a light brand, white
  /// on a dark one.
  Color get onPrimary => primary.computeLuminance() > 0.5
      ? const Color(0xFF0F172A)
      : const Color(0xFFFFFFFF);

  /// Build a theme from the server [WidgetConfigModel].
  ///
  /// Light or dark is the workspace's `colorScheme`; `auto` follows
  /// [platformBrightness] — pass `MediaQuery.platformBrightnessOf(context)`,
  /// which also rebuilds the caller when the device switches. Light is the
  /// workspace's own colours, as it always was. Dark keeps the brand where the
  /// visitor sees it as a fill (the send button, their own bubble, the
  /// launcher) and swaps the light surfaces for a dark ground and card,
  /// tinted a little toward the brand, with every text on them reading at AA
  /// or better. A workspace whose own background is already dark designed a
  /// dark chat, and keeps it in both.
  ///
  /// When [override] is supplied its colors take precedence — in either
  /// scheme: a host's explicit theme still wins. `logoUrl` / `bubbleIconUrl`
  /// use the override value when present, otherwise the config.
  ///
  /// [direction] is intentionally NOT taken from the override: layout direction
  /// is a function of locale/content, not branding, and always follows the
  /// server/locale-resolved config. Otherwise a colors-only override (whose
  /// `direction` defaults to LTR) would silently force a RTL workspace to LTR.
  factory EasyLiveChatTheme.fromConfig(
    WidgetConfigModel c, {
    EasyLiveChatTheme? override,
    Brightness platformBrightness = Brightness.light,
  }) {
    final dark = c.colorScheme
        .resolveDark(deviceDark: platformBrightness == Brightness.dark);
    final primary =
        parseHexColor(c.primaryColor, fallback: const Color(0xFF2563EB));
    final ownBackground =
        parseHexColor(c.backgroundColor, fallback: const Color(0xFFFFFFFF));
    final ownText =
        parseHexColor(c.textColor, fallback: const Color(0xFF0F172A));
    final direction = c.direction == LocaleDirection.rtl
        ? TextDirection.rtl
        : TextDirection.ltr;

    final EasyLiveChatTheme base;
    if (!dark || ownBackground.computeLuminance() < _darkThemeLuminance) {
      // Light — and a workspace's own dark design, in either scheme. The
      // server has no dedicated surface color; derive it from the background
      // so bubbles/composer read as a subtle raised layer.
      final surface = _deriveSurface(ownBackground);
      final ownDark = _estimateBrightness(ownBackground) == Brightness.dark;
      base = EasyLiveChatTheme(
        primary: primary,
        background: ownBackground,
        surface: surface,
        text: ownText,
        direction: direction,
        logoUrl: c.logoUrl,
        bubbleIconUrl: c.bubbleIconUrl,
        // As text, the brand reads at 3:1 on a light page — the web's light
        // rule — and at AA on the bubbles of a dark one.
        primaryInk: ownDark
            ? inkOn(primary, surface, 4.5)
            : inkOn(primary, ownBackground, 3),
      );
    } else {
      // Our dark ground and card, leaning a little toward the brand: enough
      // to feel theirs, not enough to colour the text.
      final card = mixColors(_darkCard, primary, _brandTint);
      final ground = mixColors(_darkGround, primary, _brandTint);
      base = EasyLiveChatTheme(
        primary: primary,
        background: ground,
        surface: card,
        // Their own text colour only if it is already made for a dark card.
        text: contrastRatio(ownText, card) >= 7 ? ownText : _darkText,
        direction: direction,
        logoUrl: c.logoUrl,
        bubbleIconUrl: c.bubbleIconUrl,
        primaryInk: inkOn(primary, card, 4.5),
        brightness: Brightness.dark,
      );
    }
    if (override == null) return base;
    return EasyLiveChatTheme(
      primary: override.primary,
      background: override.background,
      surface: override.surface,
      text: override.text,
      // Direction follows the server/locale config, never the branding override.
      direction: base.direction,
      logoUrl: override.logoUrl ?? base.logoUrl,
      bubbleIconUrl: override.bubbleIconUrl ?? base.bubbleIconUrl,
      primaryInk: override._primaryInk,
      danger: override._danger,
      brightness: override._brightness,
    );
  }

  /// Copy with selective overrides (e.g. force [direction] from the host's
  /// app locale, independent of the server workspace direction).
  EasyLiveChatTheme copyWith({
    Color? primary,
    Color? background,
    Color? surface,
    Color? text,
    TextDirection? direction,
    String? logoUrl,
    String? bubbleIconUrl,
    Color? primaryInk,
    Color? danger,
    Brightness? brightness,
  }) {
    return EasyLiveChatTheme(
      primary: primary ?? this.primary,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      text: text ?? this.text,
      direction: direction ?? this.direction,
      logoUrl: logoUrl ?? this.logoUrl,
      bubbleIconUrl: bubbleIconUrl ?? this.bubbleIconUrl,
      // A new primary without a new ink inks with itself: the old ink was
      // worked out for a different colour.
      primaryInk: primaryInk ?? (primary == null ? _primaryInk : null),
      danger: danger ?? _danger,
      brightness: brightness ?? _brightness,
    );
  }

  /// Parse a CSS-style hex string (`#RGB`, `#RRGGBB`, `#AARRGGBB`, with or
  /// without the leading `#`) into a [Color]. Returns [fallback] (default
  /// opaque black) on any malformed input — theming must never crash the UI.
  static Color parseHexColor(String? hex,
      {Color fallback = const Color(0xFF000000)}) {
    if (hex == null) return fallback;
    var h = hex.trim();
    if (h.isEmpty) return fallback;
    if (h.startsWith('#')) h = h.substring(1);
    // Expand shorthand #RGB → #RRGGBB.
    if (h.length == 3) {
      h = h.split('').map((ch) => '$ch$ch').join();
    }
    if (h.length == 6) h = 'FF$h'; // assume opaque
    if (h.length != 8) return fallback;
    final value = int.tryParse(h, radix: 16);
    if (value == null) return fallback;
    return Color(value);
  }

  /// Pick a surface tint a hair off the background: nudge dark backgrounds
  /// lighter and light backgrounds darker so raised layers stay legible.
  static Color _deriveSurface(Color bg) {
    final luminance = bg.computeLuminance();
    const delta = 0x0D; // ~5% nudge
    int shift(int channel, bool lighten) {
      final v = lighten ? channel + delta : channel - delta;
      return v.clamp(0, 255);
    }

    final lighten = luminance < 0.5;
    return Color.fromARGB(
      _alpha(bg),
      shift(_red(bg), lighten),
      shift(_green(bg), lighten),
      shift(_blue(bg), lighten),
    );
  }

  // ── Dark (C2) ─────────────────────────────────────────────────────────────
  //
  // The web widget's own values (packages/shared/src/widget-theme.ts), so a
  // visitor who meets the business on its site and in its app sees one dark.

  /// Our dark ground and card, before the brand tint, and the text on them.
  static const Color _darkGround = Color(0xFF121316);
  static const Color _darkCard = Color(0xFF1E1F23);
  static const Color _darkText = Color(0xFFECEDEF);

  /// How far the dark surfaces lean toward the brand.
  static const double _brandTint = 0.05;

  /// A background a workspace has already made this dark is its dark theme.
  static const double _darkThemeLuminance = 0.2;

  static const Color _lightDanger = Color(0xFFDC2626);
  static const Color _darkDanger = Color(0xFFF87171);

  /// Flutter's own threshold (`ThemeData.estimateBrightnessForColor`), so a
  /// host's hand-built theme is judged the way Material would judge it.
  static Brightness _estimateBrightness(Color c) {
    final l = c.computeLuminance();
    return (l + 0.05) * (l + 0.05) > 0.15 ? Brightness.light : Brightness.dark;
  }

  /// [a] moved [t] (0…1) of the way toward [b], in sRGB, opaque — the
  /// shared `mixColors`.
  @visibleForTesting
  static Color mixColors(Color a, Color b, double t) {
    int mix(int x, int y) => (x + (y - x) * t).round().clamp(0, 255);
    return Color.fromARGB(
      0xFF,
      mix(_red(a), _red(b)),
      mix(_green(a), _green(b)),
      mix(_blue(a), _blue(b)),
    );
  }

  /// WCAG contrast ratio, 1…21.
  @visibleForTesting
  static double contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// [color] itself when it already reads at [ratio] against [ground];
  /// otherwise the least step toward white (on a dark ground) or near-black
  /// (on a light one) that does — the shared `inkOn`.
  @visibleForTesting
  static Color inkOn(Color color, Color ground, double ratio) {
    if (contrastRatio(color, ground) >= ratio) return color;
    final toward = ground.computeLuminance() > 0.5
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
    for (var step = 1; step <= 20; step++) {
      final next = mixColors(color, toward, step / 20);
      if (contrastRatio(next, ground) >= ratio) return next;
    }
    return toward;
  }

  // Channel accessors using the 32-bit packed ARGB value. `toARGB32()` replaces
  // the deprecated `Color.value` (removed-in-future) and is available since
  // Flutter 3.27 (the SDK's declared floor).
  static int _alpha(Color c) => (c.toARGB32() >> 24) & 0xFF;
  static int _red(Color c) => (c.toARGB32() >> 16) & 0xFF;
  static int _green(Color c) => (c.toARGB32() >> 8) & 0xFF;
  static int _blue(Color c) => c.toARGB32() & 0xFF;
}
