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

  const EasyLiveChatTheme({
    required this.primary,
    required this.background,
    required this.surface,
    required this.text,
    this.direction = TextDirection.ltr,
    this.logoUrl,
    this.bubbleIconUrl,
  });

  /// Build a theme from the server [WidgetConfigModel].
  ///
  /// When [override] is supplied its colors take precedence, and `logoUrl` /
  /// `bubbleIconUrl` use the override value when present, otherwise the config.
  ///
  /// [direction] is intentionally NOT taken from the override: layout direction
  /// is a function of locale/content, not branding, and always follows the
  /// server/locale-resolved config. Otherwise a colors-only override (whose
  /// `direction` defaults to LTR) would silently force a RTL workspace to LTR.
  factory EasyLiveChatTheme.fromConfig(
    WidgetConfigModel c, {
    EasyLiveChatTheme? override,
  }) {
    final base = EasyLiveChatTheme(
      primary: parseHexColor(c.primaryColor, fallback: const Color(0xFF2563EB)),
      background:
          parseHexColor(c.backgroundColor, fallback: const Color(0xFFFFFFFF)),
      // The server has no dedicated surface color; derive it from the
      // background so bubbles/composer read as a subtle raised layer.
      surface: _deriveSurface(
        parseHexColor(c.backgroundColor, fallback: const Color(0xFFFFFFFF)),
      ),
      text: parseHexColor(c.textColor, fallback: const Color(0xFF0F172A)),
      direction: c.direction == LocaleDirection.rtl
          ? TextDirection.rtl
          : TextDirection.ltr,
      logoUrl: c.logoUrl,
      bubbleIconUrl: c.bubbleIconUrl,
    );
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
  }) {
    return EasyLiveChatTheme(
      primary: primary ?? this.primary,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      text: text ?? this.text,
      direction: direction ?? this.direction,
      logoUrl: logoUrl ?? this.logoUrl,
      bubbleIconUrl: bubbleIconUrl ?? this.bubbleIconUrl,
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

  // Channel accessors using the 32-bit packed ARGB value. `toARGB32()` replaces
  // the deprecated `Color.value` (removed-in-future) and is available since
  // Flutter 3.27 (the SDK's declared floor).
  static int _alpha(Color c) => (c.toARGB32() >> 24) & 0xFF;
  static int _red(Color c) => (c.toARGB32() >> 16) & 0xFF;
  static int _green(Color c) => (c.toARGB32() >> 8) & 0xFF;
  static int _blue(Color c) => c.toARGB32() & 0xFF;
}
