import 'dart:async';

import 'package:easylivechat/easylivechat.dart';
import 'package:flutter/material.dart';

import 'l10n.dart';
import 'picked_file.dart';
import 'theme.dart';
import 'views/composer_bar.dart';
import 'views/feedback_prompt_view.dart';
import 'views/closed_notice_view.dart';
import 'views/post_chat_form_view.dart';
import 'views/pre_chat_form_view.dart';
import 'views/thread_view.dart';

/// Full chat surface — a phase router bound to `EasyLiveChat.instance.phase`.
///
/// Maps each [ChatPhase] to the matching view:
///  • `idle` / `loading` / `resuming` → centered spinner (and triggers
///    `open()` from `idle` so the bubble can present this directly);
///  • `offline` → [ClosedNoticeView];
///  • `prechat` → [PreChatFormView];
///  • `chat` → a [Column] of [ThreadView] + [ComposerBar];
///  • `feedback` → [PostChatFormView] when the tenant configured a survey,
///    otherwise [FeedbackPromptView].
///
/// The subtree is wrapped in a [Directionality] driven by `theme.direction` so
/// `ar`/`ku` tenants flip bubbles + composer. A [WidgetsBindingObserver] relays
/// foreground/background transitions to `EasyLiveChat.instance.setAppLifecycle`
/// to gate heartbeat + presence.
class EasyLiveChatScreen extends StatefulWidget {
  /// Host theme override; non-null fields win over the server config.
  final EasyLiveChatTheme? themeOverride;

  /// Force the layout direction (e.g. from the host app's current locale),
  /// independent of the server workspace direction. When null, the
  /// server/config direction is used.
  final TextDirection? directionOverride;

  /// Host hook that fully owns attachment picking (e.g. the app's own
  /// camera/gallery bottom sheet). When set, the composer's attach button calls
  /// this instead of the built-in image/file pickers.
  final ElcAttachmentPicker? onPickAttachments;

  /// Host overrides for the SDK chrome strings, keyed by string key (e.g.
  /// `{'send': '…', 'typeAMessage': '…'}`). Applied to every locale; keys not
  /// provided fall back to the built-in translations. Lets a host fully own the
  /// chat wording/translation.
  final Map<String, String>? strings;

  /// Force the chrome locale (e.g. the host app's current locale code like
  /// `kmr`/`ar`), overriding the server workspace locale — the server returns
  /// its own default (often `en`) regardless of the visitor's app language.
  final String? locale;

  /// Ask before the visitor leaves the chat.
  ///
  /// When true, backing out — the host's app-bar back button, the Android back
  /// button, or the iOS swipe — first shows a confirmation. A stray gesture
  /// mid-conversation otherwise drops the visitor straight out of the thread.
  ///
  /// This confirms LEAVING THE SCREEN, not ending the conversation: the chat
  /// stays open and reopening resumes it with its history.
  ///
  /// Off by default so hosts that already own their own exit flow are
  /// unaffected.
  final bool confirmExit;

  const EasyLiveChatScreen({
    super.key,
    this.themeOverride,
    this.directionOverride,
    this.onPickAttachments,
    this.strings,
    this.locale,
    this.confirmExit = false,
  });

  @override
  State<EasyLiveChatScreen> createState() => _EasyLiveChatScreenState();
}

class _EasyLiveChatScreenState extends State<EasyLiveChatScreen>
    with WidgetsBindingObserver {
  /// Latches the (non-idempotent) open() so a phase rebuild can't re-fire it.
  bool _openRequested = false;

  /// A blocking failure while loading config / starting the session, shown as
  /// a full-screen error + retry. Later (send/socket) errors are handled inline.
  EasyLiveChatError? _error;
  StreamSubscription<EasyLiveChatError>? _errSub;

  @override
  void initState() {
    super.initState();
    // Register host locale + string overrides (own translation) before views build.
    if (widget.locale != null) ElcStrings.setLocale(widget.locale);
    if (widget.strings != null) ElcStrings.overrideAll(widget.strings!);
    WidgetsBinding.instance.addObserver(this);
    if (EasyLiveChat.instance.isBooted) {
      // Surface a full-screen error only while we're still blocked loading the
      // config (no config yet). Once config is in, send/socket errors are owned
      // by the composer/thread, not this screen.
      _errSub = EasyLiveChat.instance.onError.listen((e) {
        if (!mounted) return;
        if (EasyLiveChat.instance.widgetConfig.value == null) {
          setState(() => _error = e);
        }
      });
    }
    // If the host pushed the screen without going through the launcher, kick
    // the session machine after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOpen());
  }

  @override
  void dispose() {
    _errSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!EasyLiveChat.instance.isBooted) return;
    switch (state) {
      case AppLifecycleState.resumed:
        EasyLiveChat.instance.setAppLifecycle(EasyLiveChatLifecycle.resumed);
        // The workspace may have closed — or reopened — while the app sat in
        // the background. Re-ask rather than trusting stale state; from the
        // notice screen this also lets the chat come back by itself.
        // Only the notice screen is worth re-driving through open(); clearing
        // the guard unconditionally could double-open on top of a request
        // that is still in flight.
        if (EasyLiveChat.instance.phase.value == ChatPhase.offline) {
          _openRequested = false;
        }
        _maybeOpen();
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        EasyLiveChat.instance.setAppLifecycle(EasyLiveChatLifecycle.paused);
      case AppLifecycleState.inactive:
        // Transient (call banner, app switcher, control center). Don't churn
        // heartbeat/presence — it's common on iOS.
        break;
    }
  }

  void _maybeOpen() {
    if (_openRequested) return;
    if (!EasyLiveChat.instance.isBooted) return;
    final p = EasyLiveChat.instance.phase.value;
    // Open on a fresh mount when idle, OR when a previous session ended at the
    // feedback/CSAT screen — so reopening the chat after rating starts a fresh
    // conversation (the old one is closed) instead of re-showing the already-
    // submitted rate screen.
    //
    // `offline` re-opens too: it is a snapshot of an availability answer that
    // has since expired, and open() re-fetches the config and lands on
    // whichever screen is right now — the notice again, or the live chat.
    if (p == ChatPhase.idle ||
        p == ChatPhase.feedback ||
        p == ChatPhase.offline) {
      _startOpen();
      return;
    }
    // A live session: open() would be a no-op, but this is still a fresh *view*
    // of the chat, and availability is decided by the server and can have moved
    // since the last open (hours boundary, agents going offline).
    unawaited(EasyLiveChat.instance.refreshAvailability());
  }

  void _startOpen() {
    _openRequested = true;
    // open() is fire-and-forget for the happy path (the phase listenable drives
    // the UI), but a loadConfig failure throws OUT of open() rather than onto
    // onError — catch it so we show an error+retry instead of an endless spinner.
    EasyLiveChat.instance.open().catchError((Object e) {
      if (!mounted) return;
      setState(() => _error = e is EasyLiveChatError
          ? e
          : EasyLiveChatError(EasyLiveChatErrorCode.unknown,
              message: e.toString()));
    });
  }

  void _retry() {
    setState(() {
      _error = null;
      _openRequested = false;
    });
    _startOpen();
  }

  @override
  Widget build(BuildContext context) {
    if (!EasyLiveChat.instance.isBooted) {
      return const _BootRequiredScaffold();
    }
    // Clamp text scaling so a large accessibility font can't clip the fixed-
    // height controls (e.g. the "Start chat" / "Submit" buttons).
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: ValueListenableBuilder<WidgetConfigModel?>(
        valueListenable: EasyLiveChat.instance.widgetConfig,
        builder: (context, config, _) {
          var theme = config != null
              ? EasyLiveChatTheme.fromConfig(config,
                  override: widget.themeOverride)
              : (widget.themeOverride ?? _fallbackTheme);
          if (widget.directionOverride != null) {
            theme = theme.copyWith(direction: widget.directionOverride);
          }
          return Directionality(
            textDirection: theme.direction,
            child: _ExitGuard(
              enabled: widget.confirmExit,
              theme: theme,
              strings: ElcStrings.of(widget.locale ?? config?.locale),
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
            ),
          );
        },
      ),
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
        if (_error != null) return _buildError(config, theme);
        // Re-trigger open() if we landed in idle (e.g. host pushed us directly).
        // Schedule post-frame — never start work from inside build().
        if (phase == ChatPhase.idle && !_openRequested) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOpen());
        }
        return _spinner(theme);

      case ChatPhase.offline:
        if (config == null) {
          return _error != null ? _buildError(config, theme) : _spinner(theme);
        }
        return ClosedNoticeView(config: config, theme: theme);

      case ChatPhase.prechat:
        if (config == null) {
          return _error != null ? _buildError(config, theme) : _spinner(theme);
        }
        return PreChatFormView(config: config, theme: theme);

      case ChatPhase.chat:
        return Column(
          children: [
            // Closed, but the composer stays live: the message becomes a
            // PENDING conversation the team picks up when they are back.
            // Also when only the composer is locked: an input that refuses to
            // type with nothing explaining why reads as a broken app.
            if (EasyLiveChat.instance.isBooted &&
                (EasyLiveChat.instance.workspaceClosed ||
                    EasyLiveChat.instance.composerLocked))
              ClosedNoticeBanner(config: config, theme: theme),
            Expanded(child: ThreadView(theme: theme)),
            ComposerBar(
              theme: theme,
              onPickAttachments: widget.onPickAttachments,
            ),
          ],
        );

      case ChatPhase.feedback:
        // A tenant that built a survey in the dashboard gets exactly that;
        // everyone else keeps the built-in CSAT. Same rule as the web widget,
        // so a visitor's questions don't depend on which client they opened.
        final postChat = config?.postChatForm;
        if (config != null && (postChat?.hasFields ?? false)) {
          return PostChatFormView(config: config, theme: theme);
        }
        return FeedbackPromptView(theme: theme);
    }
  }

  Widget _spinner(EasyLiveChatTheme theme) => _Centered(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(theme.primary),
        ),
      );

  Widget _buildError(WidgetConfigModel? config, EasyLiveChatTheme theme) {
    final s = ElcStrings.of(config?.locale);
    return _ErrorRetry(
      theme: theme,
      message: s.couldNotConnect,
      retryLabel: s.retry,
      onRetry: _retry,
    );
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

/// Confirms before the visitor leaves the chat.
///
/// A `PopScope` rather than a wrapper around some close button, because the
/// host owns the chrome: the rider app supplies its own app-bar back arrow,
/// and there is still the Android back button and the iOS edge swipe. Guarding
/// the ROUTE catches all three, so a host needs no changes beyond the flag.
class _ExitGuard extends StatelessWidget {
  final bool enabled;
  final EasyLiveChatTheme theme;
  final ElcStrings strings;
  final Widget child;

  const _ExitGuard({
    required this.enabled,
    required this.theme,
    required this.strings,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _ask(context);
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: child,
    );
  }

  Future<bool> _ask(BuildContext context) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: theme.direction,
        child: AlertDialog(
          backgroundColor: theme.surface,
          title: Text(
            strings.exitChatTitle,
            style: TextStyle(color: theme.text, fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                strings.exitChatCancel,
                style: TextStyle(color: theme.text.withValues(alpha: 0.7)),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                strings.exitChatConfirm,
                style: TextStyle(
                  color: theme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    // Dismissing the dialog by tapping outside means "no", not "leave".
    return answer ?? false;
  }
}

/// Full-screen error + retry, shown when config/session loading fails (instead
/// of an endless spinner).
class _ErrorRetry extends StatelessWidget {
  final EasyLiveChatTheme theme;
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  const _ErrorRetry({
    required this.theme,
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 40, color: theme.text.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: theme.text.withValues(alpha: 0.8), fontSize: 15),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(backgroundColor: theme.primary),
              child: Text(retryLabel),
            ),
          ],
        ),
      ),
    );
  }
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
