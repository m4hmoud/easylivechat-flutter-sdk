import 'dart:async';

import 'package:easylivechat/easylivechat.dart';
import 'package:flutter/material.dart';

import 'chime.dart';
import 'end_chat_button.dart';
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

  /// Per-locale chrome overrides: `{'ckb': {'send': 'بنێرە'}, 'ar': {…}}`.
  ///
  /// Prefer this over [strings] when your own copy is multilingual — [strings]
  /// applies to every locale, so it shows a Kurdish and an Arabic visitor the
  /// same words. Wins over [strings] key by key; anything you leave out falls
  /// back to the SDK's own translation.
  ///
  /// A locale the SDK doesn't ship works too, which is how you add a language
  /// without waiting on an SDK release.
  final Map<String, Map<String, String>>? stringsByLocale;

  /// Force the chrome locale (e.g. the host app's current locale code like
  /// `kmr`/`ar`), overriding the server workspace locale — the server returns
  /// its own default (often `en`) regardless of the visitor's app language.
  final String? locale;

  /// Deprecated — backing out no longer ends the conversation, so there is
  /// nothing to confirm. Leaving mid-chat keeps the conversation open, and
  /// reopening the screen resumes it right where it was (silentResume).
  /// Ending is a deliberate act now: give the visitor an explicit affordance
  /// via [EasyLiveChatEndChatButton] (or its `confirmAndEnd` helper for
  /// callback-slot app bars), which confirms and shows the post-chat survey
  /// in place.
  @Deprecated('Back no longer ends the chat; use EasyLiveChatEndChatButton.')
  final bool confirmExit;

  /// Show the SDK's own app bar: a back button that leaves the chat running,
  /// and an X that ends it (after [EasyLiveChatEndChatButton]'s confirmation).
  ///
  /// Opt-in and false by default because most hosts push this screen inside a
  /// route that already has an app bar, and turning it on unconditionally
  /// would give them two stacked bars. Turn it on when the SDK owns the whole
  /// screen.
  ///
  /// Leaving and ending are deliberately different actions: backing out keeps
  /// the conversation open so the visitor can return to it, while the X is the
  /// explicit "I'm done" that closes it and shows the post-chat survey.
  final bool showAppBar;

  /// Title for [showAppBar]. Defaults to the workspace's own chat title.
  final String? appBarTitle;

  const EasyLiveChatScreen({
    super.key,
    this.themeOverride,
    this.directionOverride,
    this.onPickAttachments,
    this.strings,
    this.stringsByLocale,
    this.locale,
    this.confirmExit = false,
    this.showAppBar = false,
    this.appBarTitle,
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

  /// Reports "the visitor is reading this" for as long as the screen is up.
  StreamSubscription<ChatMessage>? _seenSub;

  @override
  void initState() {
    super.initState();
    // Register host locale + string overrides (own translation) before views build.
    if (widget.locale != null) ElcStrings.setLocale(widget.locale);
    if (widget.strings != null) ElcStrings.overrideAll(widget.strings!);
    if (widget.stringsByLocale != null) {
      ElcStrings.overrideByLocale(widget.stringsByLocale!);
    }
    WidgetsBinding.instance.addObserver(this);
    // Chime here too, for hosts that push the screen directly without ever
    // mounting the launcher bubble. Ref-counted, so having both up is fine.
    ElcChime.instance.attach();
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
    // The thread being on screen IS the read receipt. Reported on every
    // arrival rather than once on mount because the socket may not be up yet
    // at this point, and because a visitor sitting on the thread should keep
    // the agent's ticks current as each reply lands.
    _seenSub = EasyLiveChat.instance.onMessage.listen((message) {
      if (!mounted || message.isFromCustomer) return;
      EasyLiveChat.instance.markRead();
    });
    // If the host pushed the screen without going through the launcher, kick
    // the session machine after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeOpen();
      // Catches everything that arrived before this screen was pushed.
      EasyLiveChat.instance.markRead();
    });
  }

  @override
  void dispose() {
    _errSub?.cancel();
    _seenSub?.cancel();
    ElcChime.instance.detach();
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
        // Back on the thread after a spell in the background — anything that
        // landed meanwhile is being read right now.
        EasyLiveChat.instance.markRead();
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
            child: Material(
              color: theme.background,
              child: SafeArea(
                child: Column(
                  children: [
                    if (widget.showAppBar)
                      _ChatAppBar(
                        theme: theme,
                        title: widget.appBarTitle ?? config?.welcomeTitle ?? '',
                        locale: widget.locale,
                      ),
                    Expanded(
                      child: ValueListenableBuilder<ChatPhase>(
                        valueListenable: EasyLiveChat.instance.phase,
                        builder: (context, phase, _) =>
                            _buildPhase(context, phase, config, theme),
                      ),
                    ),
                  ],
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

/// The SDK's own app bar: back on the leading edge, end-chat on the trailing.
///
/// Two separate affordances on purpose. Backing out leaves the conversation
/// open — the visitor can come back to it and the agent still sees it live —
/// whereas the X is the explicit end, which confirms first and then shows the
/// post-chat survey. Collapsing them into one control loses that distinction,
/// and a visitor who merely wanted to look at something else ends up ending
/// their chat.
///
/// Directional icons throughout: `arrow_back` mirrors itself for RTL, and the
/// leading/trailing slots follow the resolved text direction, so ar/ku/ur get
/// the back button on the right without a second layout.
class _ChatAppBar extends StatelessWidget {
  final EasyLiveChatTheme theme;
  final String title;
  final String? locale;

  const _ChatAppBar({
    required this.theme,
    required this.title,
    this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = theme.text;
    return Container(
      height: 52,
      padding: const EdgeInsetsDirectional.only(start: 4, end: 4),
      decoration: BoxDecoration(
        color: theme.background,
        border: Border(
          bottom: BorderSide(color: theme.text.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            color: onSurface,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            // Leaving is not ending: the conversation stays open behind us.
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Only while there is something to end — during the survey or the
          // offline notice this would close nothing.
          ValueListenableBuilder<ChatPhase>(
            valueListenable: EasyLiveChat.instance.phase,
            builder: (context, phase, _) {
              if (phase != ChatPhase.chat) {
                return const SizedBox(width: 48);
              }
              return EasyLiveChatEndChatButton(
                color: onSurface,
                locale: locale,
                theme: theme,
              );
            },
          ),
        ],
      ),
    );
  }
}
