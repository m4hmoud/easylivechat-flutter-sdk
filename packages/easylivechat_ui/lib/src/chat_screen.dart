import 'package:easylivechat/easylivechat.dart';
import 'package:flutter/material.dart';

import 'theme.dart';
import 'views/composer_bar.dart';
import 'views/feedback_prompt_view.dart';
import 'views/offline_form_view.dart';
import 'views/pre_chat_form_view.dart';
import 'views/thread_view.dart';

/// Full chat surface — a phase router bound to `EasyLiveChat.instance.phase`.
///
/// Maps each [ChatPhase] to the matching view:
///  • `idle` / `loading` / `resuming` → centered spinner (and triggers
///    `open()` from `idle` so the bubble can present this directly);
///  • `offline` → [OfflineFormView];
///  • `prechat` → [PreChatFormView];
///  • `chat` → a [Column] of [ThreadView] + [ComposerBar];
///  • `feedback` → [FeedbackPromptView].
///
/// The subtree is wrapped in a [Directionality] driven by `theme.direction` so
/// `ar`/`ku` tenants flip bubbles + composer. A [WidgetsBindingObserver] relays
/// foreground/background transitions to `EasyLiveChat.instance.setAppLifecycle`
/// to gate heartbeat + presence.
class EasyLiveChatScreen extends StatefulWidget {
  /// Host theme override; non-null fields win over the server config.
  final EasyLiveChatTheme? themeOverride;

  const EasyLiveChatScreen({super.key, this.themeOverride});

  @override
  State<EasyLiveChatScreen> createState() => _EasyLiveChatScreenState();
}

class _EasyLiveChatScreenState extends State<EasyLiveChatScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // If the host pushed the screen without going through the launcher, kick
    // the session machine after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOpen());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!EasyLiveChat.instance.isBooted) return;
    switch (state) {
      case AppLifecycleState.resumed:
        EasyLiveChat.instance.setAppLifecycle(EasyLiveChatLifecycle.resumed);
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        EasyLiveChat.instance.setAppLifecycle(EasyLiveChatLifecycle.paused);
    }
  }

  void _maybeOpen() {
    if (!EasyLiveChat.instance.isBooted) return;
    if (EasyLiveChat.instance.phase.value == ChatPhase.idle) {
      // Fire-and-forget; the phase listenable drives the UI as it progresses.
      EasyLiveChat.instance.open();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!EasyLiveChat.instance.isBooted) {
      return const _BootRequiredScaffold();
    }
    return ValueListenableBuilder<WidgetConfigModel?>(
      valueListenable: EasyLiveChat.instance.widgetConfig,
      builder: (context, config, _) {
        final theme = config != null
            ? EasyLiveChatTheme.fromConfig(config, override: widget.themeOverride)
            : (widget.themeOverride ?? _fallbackTheme);
        return Directionality(
          textDirection: theme.direction,
          child: Material(
            color: theme.background,
            child: SafeArea(
              child: ValueListenableBuilder<ChatPhase>(
                valueListenable: EasyLiveChat.instance.phase,
                builder: (context, phase, _) =>
                    _buildPhase(context, phase, config, theme),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPhase(
    BuildContext context,
    ChatPhase phase,
    WidgetConfigModel? config,
    EasyLiveChatTheme theme,
  ) {
    switch (phase) {
      case ChatPhase.idle:
      case ChatPhase.loading:
      case ChatPhase.resuming:
        // Re-trigger open() if we landed in idle (e.g. host pushed us directly).
        if (phase == ChatPhase.idle) _maybeOpen();
        return _Centered(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(theme.primary),
          ),
        );

      case ChatPhase.offline:
        if (config == null) {
          return _Centered(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(theme.primary),
            ),
          );
        }
        return OfflineFormView(config: config, theme: theme);

      case ChatPhase.prechat:
        if (config == null) {
          return _Centered(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(theme.primary),
            ),
          );
        }
        return PreChatFormView(config: config, theme: theme);

      case ChatPhase.chat:
        return Column(
          children: [
            Expanded(child: ThreadView(theme: theme)),
            ComposerBar(theme: theme),
          ],
        );

      case ChatPhase.feedback:
        return FeedbackPromptView(theme: theme);
    }
  }

  static const EasyLiveChatTheme _fallbackTheme = EasyLiveChatTheme(
    primary: Color(0xFF2563EB),
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF1F5F9),
    text: Color(0xFF0F172A),
  );
}

/// Centers a single child against the inherited [Directionality]/[Material].
class _Centered extends StatelessWidget {
  final Widget child;
  const _Centered({required this.child});

  @override
  Widget build(BuildContext context) => Center(child: child);
}

/// Shown if the screen is presented before `EasyLiveChat.boot()` was called.
class _BootRequiredScaffold extends StatelessWidget {
  const _BootRequiredScaffold();

  @override
  Widget build(BuildContext context) {
    return const Material(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'EasyLiveChat is not initialized.\n'
            'Call EasyLiveChat.instance.boot(...) before opening the chat.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
