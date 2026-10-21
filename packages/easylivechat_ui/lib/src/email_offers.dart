import 'dart:async';

import 'package:easylivechat/easylivechat.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n.dart';
import 'theme.dart';
import 'views/closed_notice_view.dart' show elcAvailabilityListenable;
import 'views/email_card_view.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  The rules — the web widget's, from apps/widget/src/app/embed/Embed.tsx
//  (section 7b, "Emails to the visitor"), kept apart from the widgets so they
//  can be read and tested on their own.
// ─────────────────────────────────────────────────────────────────────────────

/// "Email me this chat" is on offer from the menu: the workspace allows it,
/// the chat is on screen, and there is something in it besides system lines.
bool elcCanEmailTranscript({
  required bool transcriptEmailEnabled,
  required ChatPhase phase,
  required String? conversationId,
  required Iterable<ChatMessage> messages,
}) =>
    transcriptEmailEnabled &&
    phase == ChatPhase.chat &&
    conversationId != null &&
    messages.any((m) => m.senderType != SenderType.system);

/// Ask "Get the reply by email" now: once the visitor has written, while
/// nobody can answer (closed, queued, nobody accepting), only to someone we
/// hold no address for, and once per conversation.
bool elcShouldOfferReplyEmail({
  required bool replyEmailEnabled,
  required ChatPhase phase,
  required bool composerLocked,
  required String? conversationId,
  required bool hintKnown,
  required String? emailHint,
  required Iterable<ChatMessage> messages,
  required bool workspaceClosed,
  required bool queued,
  required bool agentsAccepting,
  required String? alreadyAskedFor,
  required String? dismissedFor,
}) {
  if (conversationId == null) return false;
  if (phase != ChatPhase.chat || !replyEmailEnabled || composerLocked) {
    return false;
  }
  // Unknown is not "none": wait until the server has said.
  if (!hintKnown || emailHint != null) return false;
  if (!messages.any((m) => m.isFromCustomer)) return false;
  if (!(workspaceClosed || queued || !agentsAccepting)) return false;
  return alreadyAskedFor != conversationId && dismissedFor != conversationId;
}

/// What to say for a refused email, in the visitor's language — the web's
/// mapping (Embed.tsx `sendTranscript` / `saveNotifyEmail`).
String elcEmailErrorText(Object error, ElcStrings s) {
  if (error is EasyLiveChatError) {
    switch (error.code) {
      case 'TRANSCRIPT_RATE_LIMITED':
      case EasyLiveChatErrorCode.rateLimited:
        return s.emailRateLimited;
      case 'EMAIL_UNSUBSCRIBED':
        return s.emailUnsubscribed;
      case 'INVALID_EMAIL':
      case 'NO_CONTACT_EMAIL':
        return s.invalidEmail;
    }
    if (error.httpStatus == 429) return s.emailRateLimited;
  }
  return s.emailFailed;
}

// ─────────────────────────────────────────────────────────────────────────────
//  The state, shared by the chat screen, its app bar and a host's own menu
// ─────────────────────────────────────────────────────────────────────────────

/// The two email offers' state for the visitor on screen: the address on file
/// (masked), and which card is open. One per app, like `EasyLiveChat.instance`,
/// so a host's own app-bar button and the chat screen act on the same card.
class ElcEmailOffers extends ChangeNotifier {
  ElcEmailOffers._();
  static final ElcEmailOffers instance = ElcEmailOffers._();

  /// Where "Get the reply by email" remembers the conversation it was
  /// answered or dismissed for, so it is not asked again after a relaunch
  /// (the web keeps the same in its browser's storage).
  static const String dismissedKey = 'easylivechat:replyEmailAsked';

  String? _visitorId;
  String? _hintConversation;
  bool _hintKnown = false;
  String? _hint;
  int _hintRequest = 0;
  bool _transcriptOpen = false;
  bool _notifyOpen = false;
  String? _notifyAskedFor;
  String? _dismissedFor;
  bool _restored = false;
  Future<void>? _restoring;

  /// The server has said what is on file (even "nothing").
  bool get hintKnown => _hintKnown;

  /// The address on the visitor's contact, masked, or null.
  String? get emailHint => _hint;

  /// "Email me this chat" is open — shown once the address on file is known.
  bool get transcriptOpen => _transcriptOpen && _hintKnown;

  /// "Get the reply by email" is showing — never over the transcript card.
  bool get notifyOpen => _notifyOpen && !_transcriptOpen;

  /// Forget everything, as for a new visitor. Tests, and a new person.
  @visibleForTesting
  void reset() {
    _visitorId = null;
    _hintConversation = null;
    _hintKnown = false;
    _hint = null;
    _hintRequest++;
    _transcriptOpen = false;
    _notifyOpen = false;
    _notifyAskedFor = null;
    _dismissedFor = null;
    _restored = false;
    _restoring = null;
    notifyListeners();
  }

  /// "Email me this chat" can be offered from a menu right now.
  bool get canEmailTranscript {
    final elc = EasyLiveChat.instance;
    if (!elc.isBooted) return false;
    return elcCanEmailTranscript(
      transcriptEmailEnabled: elc.transcriptEmailEnabled,
      phase: elc.phase.value,
      conversationId: elc.conversationId,
      messages: elc.messages.value,
    );
  }

  /// Open "Email me this chat". From the menu ([afterChat] false) only while
  /// [canEmailTranscript]; under the survey ([afterChat] true) for the chat
  /// that just ended. Resolves false when there was nothing to open.
  Future<bool> openTranscript({bool afterChat = false}) async {
    final elc = EasyLiveChat.instance;
    if (!elc.isBooted) return false;
    if (afterChat ? !elc.transcriptEmailEnabled : !canEmailTranscript) {
      return false;
    }
    _follow();
    if (!_hintKnown) await _loadHint();
    _transcriptOpen = true;
    notifyListeners();
    return true;
  }

  void closeTranscript() {
    if (!_transcriptOpen) return;
    _transcriptOpen = false;
    notifyListeners();
  }

  /// Answered or dismissed: not asked again for this conversation, here or
  /// after a relaunch. Whatever was saved is on file now; re-read it.
  void closeNotify() {
    _notifyOpen = false;
    final conv = EasyLiveChat.instance.isBooted
        ? EasyLiveChat.instance.conversationId
        : null;
    if (conv != null) {
      _dismissedFor = conv;
      unawaited(_persistDismissed(conv));
      unawaited(_loadHint());
    }
    notifyListeners();
  }

  /// "Email me this chat": [email] typed, or null for the address on file.
  Future<ElcEmailResult> sendTranscript(String? email, ElcStrings s) async {
    try {
      final sentTo = await EasyLiveChat.instance.emailTranscript(email: email);
      _hint = sentTo.isEmpty ? _hint : sentTo;
      _hintKnown = true;
      notifyListeners();
      return ElcEmailResult.sent(sentTo);
    } catch (e) {
      if (e is EasyLiveChatError && e.code == 'NO_CONTACT_EMAIL') {
        // Nothing on file after all: the card shows the field.
        _hint = null;
        _hintKnown = true;
        notifyListeners();
      }
      return ElcEmailResult.failed(elcEmailErrorText(e, s));
    }
  }

  /// "Get the reply by email": [email] goes on the visitor's contact.
  Future<ElcEmailResult> saveReplyEmail(String? email, ElcStrings s) async {
    if (email == null) return ElcEmailResult.failed(s.invalidEmail);
    try {
      final hint = await EasyLiveChat.instance.setVisitorEmail(email);
      return ElcEmailResult.sent(hint.isEmpty ? email : hint);
    } catch (e) {
      final text = elcEmailErrorText(e, s);
      // Only the transcript is rate-limited by its own code.
      return ElcEmailResult.failed(
          text == s.emailRateLimited ? s.emailFailed : text);
    }
  }

  /// Line the state up with the chat as it is now: a new visitor starts
  /// clean, a new conversation re-reads the address and closes old cards,
  /// and "Get the reply by email" opens when its moment has come.
  void refresh() {
    final elc = EasyLiveChat.instance;
    if (!elc.isBooted) return;
    _follow();
    unawaited(_restore());
    final conv = elc.conversationId;
    if (conv != null &&
        conv != _hintConversation &&
        (elc.transcriptEmailEnabled || elc.replyEmailEnabled)) {
      if (_hintConversation != null) {
        _transcriptOpen = false;
        _notifyOpen = false;
      }
      unawaited(_loadHint());
    }
    _maybeOfferNotify();
  }

  void _follow() {
    final vid = EasyLiveChat.instance.visitorId;
    if (vid == _visitorId) return;
    final first = _visitorId == null;
    _visitorId = vid;
    _hintConversation = null;
    _hintKnown = false;
    _hint = null;
    _hintRequest++;
    _transcriptOpen = false;
    _notifyOpen = false;
    _notifyAskedFor = null;
    if (!first) notifyListeners();
  }

  Future<void> _loadHint() async {
    final elc = EasyLiveChat.instance;
    final request = ++_hintRequest;
    _hintConversation = elc.conversationId ?? _hintConversation;
    String? hint;
    try {
      hint = (await elc.visitorEmail()).emailHint;
    } catch (_) {
      // As on the web: unreadable reads as "nothing on file".
      hint = null;
    }
    if (request != _hintRequest) return;
    _hint = hint;
    _hintKnown = true;
    notifyListeners();
    _maybeOfferNotify();
  }

  void _maybeOfferNotify() {
    final elc = EasyLiveChat.instance;
    if (!elc.isBooted || !_restored || _notifyOpen) return;
    final conv = elc.conversationId;
    if (!elcShouldOfferReplyEmail(
      replyEmailEnabled: elc.replyEmailEnabled,
      phase: elc.phase.value,
      composerLocked: elc.composerLocked,
      conversationId: conv,
      hintKnown: _hintKnown,
      emailHint: _hint,
      messages: elc.messages.value,
      workspaceClosed: elc.workspaceClosed,
      queued: elc.queue.value != null,
      agentsAccepting: elc.agentsAccepting.value,
      alreadyAskedFor: _notifyAskedFor,
      dismissedFor: _dismissedFor,
    )) {
      return;
    }
    _notifyAskedFor = conv;
    _notifyOpen = true;
    notifyListeners();
  }

  Future<void> _restore() {
    if (_restored) return Future.value();
    return _restoring ??= () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        _dismissedFor ??= prefs.getString(dismissedKey);
      } catch (_) {
        // No storage: it may be asked again next launch.
      }
      _restored = true;
      _maybeOfferNotify();
    }();
  }

  Future<void> _persistDismissed(String conversationId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(dismissedKey, conversationId);
    } catch (_) {}
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Where the cards go
// ─────────────────────────────────────────────────────────────────────────────

/// The email cards above the conversation (under the queue notice), as the
/// web widget places them: "Email me this chat" when opened from the menu,
/// otherwise "Get the reply by email" when its moment comes.
class ElcEmailOffersSlot extends StatefulWidget {
  final EasyLiveChatTheme theme;
  final ElcStrings strings;

  const ElcEmailOffersSlot(
      {super.key, required this.theme, required this.strings});

  @override
  State<ElcEmailOffersSlot> createState() => _ElcEmailOffersSlotState();
}

class _ElcEmailOffersSlotState extends State<ElcEmailOffersSlot> {
  Listenable? _watched;

  @override
  void initState() {
    super.initState();
    final elc = EasyLiveChat.instance;
    if (elc.isBooted) {
      _watched = Listenable.merge([
        elc.phase,
        elc.messages,
        elc.queue,
        elc.widgetConfig,
        elcAvailabilityListenable(),
      ])
        ..addListener(_changed);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
  }

  @override
  void dispose() {
    _watched?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) ElcEmailOffers.instance.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final offers = ElcEmailOffers.instance;
    return ListenableBuilder(
      listenable: offers,
      builder: (context, _) {
        if (offers.transcriptOpen) {
          return ElcEmailCard(
            key: const ValueKey('transcript'),
            mode: ElcEmailCardMode.transcript,
            emailHint: offers.emailHint,
            theme: widget.theme,
            strings: widget.strings,
            onSubmit: (email) => offers.sendTranscript(email, widget.strings),
            onClose: offers.closeTranscript,
          );
        }
        if (offers.notifyOpen) {
          return ElcEmailCard(
            key: const ValueKey('notify'),
            mode: ElcEmailCardMode.notify,
            emailHint: null,
            theme: widget.theme,
            strings: widget.strings,
            onSubmit: (email) => offers.saveReplyEmail(email, widget.strings),
            onClose: offers.closeNotify,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

/// Under the survey once the chat has ended: "Email me this chat" as a link,
/// opening the card in its place — a copy of the conversation to keep.
class ElcTranscriptAfterChat extends StatefulWidget {
  final EasyLiveChatTheme theme;
  final ElcStrings strings;

  const ElcTranscriptAfterChat(
      {super.key, required this.theme, required this.strings});

  @override
  State<ElcTranscriptAfterChat> createState() => _ElcTranscriptAfterChatState();
}

class _ElcTranscriptAfterChatState extends State<ElcTranscriptAfterChat> {
  /// The chat that ended, as it was when the survey came up. The core keeps
  /// reaching it for the transcript after the survey lets the session go.
  String? _ended;

  @override
  void initState() {
    super.initState();
    final elc = EasyLiveChat.instance;
    _ended = elc.isBooted ? elc.conversationId : null;
  }

  @override
  Widget build(BuildContext context) {
    final elc = EasyLiveChat.instance;
    if (_ended == null || !elc.isBooted || !elc.transcriptEmailEnabled) {
      return const SizedBox.shrink();
    }
    final offers = ElcEmailOffers.instance;
    final t = widget.theme;
    final s = widget.strings;
    return ListenableBuilder(
      listenable: offers,
      builder: (context, _) {
        if (offers.transcriptOpen) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: ElcEmailCard(
                  key: const ValueKey('transcript-after'),
                  mode: ElcEmailCardMode.transcript,
                  emailHint: offers.emailHint,
                  theme: t,
                  strings: s,
                  onSubmit: (email) => offers.sendTranscript(email, s),
                  onClose: offers.closeTranscript,
                ),
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Center(
            child: TextButton(
              onPressed: () => offers.openTranscript(afterChat: true),
              style: TextButton.styleFrom(foregroundColor: t.primaryInk),
              child: Text(
                s.emailTranscript,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  decoration: TextDecoration.underline,
                  decorationColor: t.primaryInk,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  The ⋯ menu
// ─────────────────────────────────────────────────────────────────────────────

/// The chat header's ⋯ menu — the web widget's (apps/widget Header.tsx):
/// "Email me this chat", opening the card above the conversation.
///
/// Drawn only while it has something in it — the workspace offers the
/// transcript and there is a chat with something in it — so it can sit in an
/// app bar permanently. [EasyLiveChatScreen]'s own app bar (`showAppBar`)
/// carries it; put it in yours beside [EasyLiveChatEndChatButton]:
///
/// ```dart
/// AppBar(actions: const [EasyLiveChatMenuButton(), EasyLiveChatEndChatButton()])
/// ```
///
/// Ending the chat stays its own button, as before.
class EasyLiveChatMenuButton extends StatelessWidget {
  /// Chrome locale override — same contract as [EasyLiveChatScreen.locale].
  final String? locale;

  /// Icon color; defaults to the ambient [IconTheme].
  final Color? color;

  /// Colors for the menu. Defaults to the workspace config — pass the same
  /// override the chat screen uses to keep them identical.
  final EasyLiveChatTheme? theme;

  const EasyLiveChatMenuButton(
      {super.key, this.locale, this.color, this.theme});

  /// Whether the menu has anything in it right now.
  static bool get hasItems => ElcEmailOffers.instance.canEmailTranscript;

  /// "Email me this chat", for an app bar that takes a callback rather than a
  /// widget: opens the card on the chat screen. Resolves false, doing nothing,
  /// when it is not on offer — so an always-visible item stays harmless.
  static Future<bool> emailTranscript() =>
      ElcEmailOffers.instance.openTranscript();

  @override
  Widget build(BuildContext context) {
    final elc = EasyLiveChat.instance;
    if (!elc.isBooted) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: Listenable.merge([elc.phase, elc.messages, elc.widgetConfig]),
      builder: (context, _) {
        if (!hasItems) return const SizedBox.shrink();
        final config = elc.widgetConfig.value;
        final s = ElcStrings.of(locale ?? config?.locale);
        final t = theme ??
            (config != null
                ? EasyLiveChatTheme.fromConfig(config,
                    platformBrightness:
                        MediaQuery.maybePlatformBrightnessOf(context) ??
                            Brightness.light)
                : null);
        return PopupMenuButton<String>(
          icon: Icon(Icons.more_horiz_rounded, color: color),
          tooltip: s.moreOptions,
          // The page's own ground, not a tier of its own.
          color: t?.background,
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: t == null
                ? BorderSide.none
                : BorderSide(color: t.text.withValues(alpha: 0.12)),
          ),
          onSelected: (_) => emailTranscript(),
          itemBuilder: (context) => [
            PopupMenuItem<String>(
              value: 'emailTranscript',
              child: Directionality(
                textDirection: t?.direction ?? Directionality.of(context),
                child: Text(
                  s.emailTranscript,
                  style: TextStyle(color: t?.text, fontSize: 15),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
