import 'package:cached_network_image/cached_network_image.dart';
import 'package:easylivechat/easylivechat.dart';
import 'package:flutter/material.dart';

import 'chat_screen.dart';
import 'picked_file.dart';
import 'theme.dart';

/// Floating launcher bubble — the native replacement for the web widget loader.
///
/// Renders a circular [FloatingActionButton]-style bubble tinted with
/// `theme.primary`, showing the tenant's [WidgetConfigModel.bubbleIconUrl] (via
/// `cached_network_image`) or a fallback chat glyph. An unread badge is bound to
/// `EasyLiveChat.instance.unreadCount`. Alignment is taken from [alignment] when
/// provided, otherwise from `WidgetConfig.position` (`bottom-left`/`bottom-right`).
///
/// Drop it into a [Stack] over your app:
/// ```dart
/// Stack(children: [ MyApp(), const EasyLiveChatLauncher() ]);
/// ```
/// On tap it lazily opens the session (`EasyLiveChat.instance.open()`) and
/// pushes an [EasyLiveChatScreen].
class EasyLiveChatLauncher extends StatefulWidget {
  /// Host theme override; non-null fields win over the server config.
  final EasyLiveChatTheme? themeOverride;

  /// Explicit alignment. When null, derived from `WidgetConfig.position`.
  final Alignment? alignment;

  /// Present the chat screen as a modal bottom sheet instead of a full route.
  final bool useBottomSheet;

  /// Force the chat layout direction (e.g. from the host app locale),
  /// independent of the server workspace direction.
  final TextDirection? directionOverride;

  /// Host hook that fully owns attachment picking (passed to the chat screen).
  final ElcAttachmentPicker? onPickAttachments;

  /// Host overrides for the SDK chrome strings (passed to the chat screen).
  final Map<String, String>? strings;

  /// Force the chrome locale from the host app (passed to the chat screen).
  final String? locale;

  const EasyLiveChatLauncher({
    super.key,
    this.themeOverride,
    this.alignment,
    this.useBottomSheet = false,
    this.directionOverride,
    this.onPickAttachments,
    this.strings,
    this.locale,
  });

  @override
  State<EasyLiveChatLauncher> createState() => _EasyLiveChatLauncherState();
}

class _EasyLiveChatLauncherState extends State<EasyLiveChatLauncher> {
  bool _opening = false;
  bool _presented = false;

  Alignment _alignmentFromConfig(WidgetConfigModel? config) {
    if (widget.alignment != null) return widget.alignment!;
    final position = config?.position ?? 'bottom-right';
    return position.contains('left')
        ? Alignment.bottomLeft
        : Alignment.bottomRight;
  }

  EasyLiveChatTheme _resolveTheme(WidgetConfigModel? config) {
    if (config != null) {
      return EasyLiveChatTheme.fromConfig(config,
          override: widget.themeOverride);
    }
    // Pre-boot fallback so the bubble can paint before config loads.
    return widget.themeOverride ??
        const EasyLiveChatTheme(
          primary: Color(0xFF2563EB),
          background: Color(0xFFFFFFFF),
          surface: Color(0xFFF1F5F9),
          text: Color(0xFF0F172A),
        );
  }

  Future<void> _onTap() async {
    // Re-entrancy guard: `_opening` covers the boot window, `_presented` covers
    // the whole time the screen/sheet is on top — the bubble stays mounted
    // behind a non-fullscreen route/sheet and a second tap would otherwise
    // boot again and stack a duplicate chat surface.
    if (_opening || _presented) return;
    setState(() => _opening = true);
    try {
      // Lazily boot the session machine (config → resume → prechat/anonymous).
      await EasyLiveChat.instance.open();
    } catch (_) {
      // Surfaced via EasyLiveChat.instance.onError / the screen's phase router;
      // still present the screen so the error/offline state is visible.
    }
    if (!mounted) return;
    // Capture the navigator before the present-await so we never touch a stale
    // BuildContext across the async gap.
    final navigator = Navigator.of(context);
    setState(() {
      _opening = false;
      _presented = true;
    });

    final screen = EasyLiveChatScreen(
      themeOverride: widget.themeOverride,
      directionOverride: widget.directionOverride,
      onPickAttachments: widget.onPickAttachments,
      strings: widget.strings,
      locale: widget.locale,
    );
    try {
      if (widget.useBottomSheet) {
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          builder: (_) => FractionallySizedBox(
            heightFactor: 0.92,
            child: screen,
          ),
        );
      } else {
        await navigator.push(
          MaterialPageRoute<void>(builder: (_) => screen),
        );
      }
    } finally {
      // Returning from the screen clears local unread and re-arms the bubble.
      EasyLiveChat.instance.markRead();
      if (mounted) {
        setState(() => _presented = false);
      } else {
        _presented = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Config drives both alignment and theme; rebuild when it arrives. Before
    // boot there is no config notifier to listen to, so paint the fallback
    // bubble directly (a later rebuild re-reads `isBooted`).
    if (!EasyLiveChat.instance.isBooted) {
      return _buildScaffold(null);
    }
    return ValueListenableBuilder<WidgetConfigModel?>(
      valueListenable: EasyLiveChat.instance.widgetConfig,
      builder: (context, config, _) => _buildScaffold(config),
    );
  }

  Widget _buildScaffold(WidgetConfigModel? config) {
    final theme = _resolveTheme(config);
    final alignment = _alignmentFromConfig(config);
    return SafeArea(
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _buildBubble(theme),
        ),
      ),
    );
  }

  Widget _buildBubble(EasyLiveChatTheme theme) {
    final onPrimary = _onColor(theme.primary);
    final bubble = Material(
      color: theme.primary,
      shape: const CircleBorder(),
      elevation: 6,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _onTap,
        child: SizedBox(
          width: 56,
          height: 56,
          child: Center(child: _buildIcon(onPrimary)),
        ),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        bubble,
        Positioned(
          top: -2,
          right: -2,
          child: _UnreadBadge(background: theme.background, text: theme.text),
        ),
      ],
    );
  }

  Widget _buildIcon(Color onPrimary) {
    if (_opening) {
      return SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation<Color>(onPrimary),
        ),
      );
    }
    final iconUrl = widget.themeOverride?.bubbleIconUrl ??
        (EasyLiveChat.instance.isBooted
            ? EasyLiveChat.instance.widgetConfig.value?.bubbleIconUrl
            : null);
    if (iconUrl != null && iconUrl.trim().isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: iconUrl,
          width: 32,
          height: 32,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) =>
              Icon(Icons.chat_bubble, color: onPrimary, size: 26),
        ),
      );
    }
    return Icon(Icons.chat_bubble, color: onPrimary, size: 26);
  }

  /// Black or white text/icon depending on the bubble color's luminance.
  static Color _onColor(Color background) =>
      background.computeLuminance() > 0.5 ? Colors.black : Colors.white;
}

/// Unread count pill bound to `EasyLiveChat.instance.unreadCount`. Hidden at 0.
class _UnreadBadge extends StatelessWidget {
  final Color background;
  final Color text;
  const _UnreadBadge({required this.background, required this.text});

  @override
  Widget build(BuildContext context) {
    if (!EasyLiveChat.instance.isBooted) return const SizedBox.shrink();
    return ValueListenableBuilder<int>(
      valueListenable: EasyLiveChat.instance.unreadCount,
      builder: (context, count, _) {
        if (count <= 0) return const SizedBox.shrink();
        final label = count > 99 ? '99+' : '$count';
        return Container(
          constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: background, width: 2),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        );
      },
    );
  }
}
