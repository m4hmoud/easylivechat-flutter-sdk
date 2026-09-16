import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easylivechat/easylivechat.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../theme.dart';
import 'bubble_shape.dart';
import 'image_viewer.dart';
import 'linkified_text.dart';
import 'message_card_view.dart';
import 'quick_replies_view.dart';
import 'voice_note_tile.dart';

/// The message thread (native analog of the web `Thread.tsx`).
///
/// Binds `EasyLiveChat.instance.messages` + `agentTyping`. Customer messages
/// align to the trailing edge (right in LTR), agent/system/bot to the leading
/// edge. Agent names are shown only when `config.showAgentNames` is true
/// (the server already nulls `senderName` when disabled — double-guarded here).
///
/// Attachments: prefer the rich [RehostedAttachment] list when present
/// (kind==image → inline via `cached_network_image`; kind==audio → a playable
/// [ElcVoiceNoteTile]; otherwise a download chip). Otherwise fall back to flat
/// [ChatMessage.attachmentUrls] (image-like extensions render inline,
/// audio-like ones play, the rest are chips). Non-resolvable placeholders
/// (`wa:media:{id}`) render an inert "media unavailable" chip — never a broken
/// image. Unknown `contentType` degrades to a plain text bubble; nothing here
/// may crash on a future enum value.
///
/// Auto-scrolls to the newest message on append; a "load earlier" trigger at
/// the top calls `loadOlderMessages()`.
///
/// A card (`ChatMessage.card`) draws as a card instead of a bubble, and the
/// quick replies on offer (`quickRepliesOnOffer`) draw under the message that
/// offers them — only when [onQuickReply] is given, as on the web.
class ThreadView extends StatefulWidget {
  final EasyLiveChatTheme theme;

  /// Sends a tapped quick reply as the visitor's own message, completing once
  /// the server has it or has refused it. Every button is disabled until then,
  /// so a double tap sends once. Null draws no quick replies at all.
  ///
  /// The chat screen passes [sendReplyAsMessage].
  final Future<void> Function(String reply)? onQuickReply;

  const ThreadView({super.key, required this.theme, this.onQuickReply});

  /// A quick reply goes out exactly as typed text does — the same
  /// `EasyLiveChat.sendMessage` the composer calls, so it shows at once as the
  /// visitor's message, ticks the same way, and a failure leaves the same
  /// tap-to-retry bubble behind. The reply is sent exactly as the server
  /// offered it.
  ///
  /// Never throws: a failed send is already on screen as that bubble.
  static Future<void> sendReplyAsMessage(String reply) => EasyLiveChat.instance
      .sendMessage(reply)
      .serverMessageId
      .then<void>((_) {}, onError: (Object _) {});

  @override
  State<ThreadView> createState() => _ThreadViewState();
}

class _ThreadViewState extends State<ThreadView> {
  final ScrollController _scroll = ScrollController();
  int _lastCount = 0;
  bool _loadingOlder = false;

  /// A tapped quick reply is on its way. Every button is disabled until the
  /// server has it — or has refused it.
  bool _sendingQuickReply = false;

  /// Read through to the controller rather than mirrored locally: the cursor
  /// is what actually knows whether earlier visits exist, and a copy of it here
  /// only creates two answers that can disagree.
  bool get _hasMoreOlder => EasyLiveChat.instance.hasOlderHistory;

  EasyLiveChatTheme get _theme => widget.theme;
  ElcStrings get _s =>
      ElcStrings.of(EasyLiveChat.instance.widgetConfig.value?.locale);

  bool get _showAgentNames =>
      EasyLiveChat.instance.widgetConfig.value?.showAgentNames ?? true;

  bool get _showAgentAvatars =>
      EasyLiveChat.instance.widgetConfig.value?.showAgentAvatars ?? true;

  @override
  void initState() {
    super.initState();
    _lastCount = EasyLiveChat.instance.messages.value.length;
    EasyLiveChat.instance.messages.addListener(_onMessages);
    // The quick replies are disabled while the workspace takes no messages,
    // and that can change with the visitor already looking at them.
    EasyLiveChat.instance.visitorMode.addListener(_onVisitorMode);
    // Older history loads as the visitor scrolls up, and only then.
    //
    // It used to also pull one page the moment the thread appeared. That made
    // sense when a conversation was a single visit, but a returning customer
    // now lands back in a thread that can span months: the eager page dragged
    // the previous visit straight back on screen, under the greeting for the
    // visit they had just started. The server opens the thread on the current
    // session; reaching past it is the visitor's call.
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpToBottom();
    });
  }

  @override
  void dispose() {
    EasyLiveChat.instance.messages.removeListener(_onMessages);
    EasyLiveChat.instance.visitorMode.removeListener(_onVisitorMode);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onVisitorMode() {
    if (mounted) setState(() {});
  }

  void _onMessages() {
    final msgs = EasyLiveChat.instance.messages.value;
    final count = msgs.length;
    // Auto-scroll only when a *new* (appended) message arrives, not when older
    // history is prepended.
    final appended = count > _lastCount && !_loadingOlder;
    _lastCount = count;
    if (!appended) return;

    // The visitor's OWN message always follows itself down. This used to be
    // gated on `_isNearBottom()` alone, on the assumption — written into the
    // comment here — that "their own send is from the bottom, so it still
    // scrolls". It isn't: they can scroll up to re-read something, type a
    // reply to it, and send from there. The gate then failed and their message
    // landed off-screen, so the thread looked like it had swallowed it. The
    // keyboard opening moves `maxScrollExtent` too, which could push them out
    // of the 160px window without their having scrolled at all.
    //
    // An INBOUND message still respects the gate: an agent's reply must not
    // yank the visitor out of history they are in the middle of reading.
    final own = msgs.isNotEmpty && msgs.last.isFromCustomer;
    if (own || _isNearBottom()) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _animateToBottom());
    }
  }

  bool _isNearBottom() {
    if (!_scroll.hasClients) return true;
    final pos = _scroll.position;
    return pos.maxScrollExtent - pos.pixels <= 160;
  }

  void _jumpToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  void _animateToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// Pull the next page in as the visitor approaches the top of the thread.
  void _onScroll() {
    if (!_scroll.hasClients || _loadingOlder || !_hasMoreOlder) return;
    // Oldest first, so the top of the list is offset 0 — start fetching a
    // little before the visitor actually reaches it.
    const triggerPx = 240.0;
    if (_scroll.position.pixels <= triggerPx) unawaited(_loadOlder());
  }

  Future<void> _sendQuickReply(String messageId, String reply) async {
    final send = widget.onQuickReply;
    if (send == null || _sendingQuickReply) return;
    // Asked again at the moment of the tap, not read off the button: a second
    // tap can land in the same frame as the first, on a button the thread has
    // not yet rebuilt away. A send that fails at once — no connection — has
    // already cleared the in-flight flag by then, but it has also put the
    // visitor's message in the thread, and that is the answer.
    final offer = quickRepliesOnOffer(EasyLiveChat.instance.messages.value);
    if (offer == null ||
        offer.messageId != messageId ||
        !offer.replies.contains(reply)) {
      return;
    }
    setState(() => _sendingQuickReply = true);
    try {
      await send(reply);
    } catch (_) {
      // The send path owns failure: it leaves a failed bubble with retry.
    } finally {
      if (mounted) {
        setState(() => _sendingQuickReply = false);
      } else {
        _sendingQuickReply = false;
      }
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasMoreOlder) return;
    setState(() => _loadingOlder = true);
    // Capture the viewport so we can keep the user on the same content after
    // older history is prepended (which grows maxScrollExtent from the top).
    final beforeExtent =
        _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;
    final beforePixels = _scroll.hasClients ? _scroll.position.pixels : 0.0;
    try {
      final page = await EasyLiveChat.instance.loadOlderMessages();
      if (mounted && page.messages.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scroll.hasClients) return;
          final delta = _scroll.position.maxScrollExtent - beforeExtent;
          if (delta > 0) _scroll.jumpTo(beforePixels + delta);
        });
      }
    } on EasyLiveChatError {
      // Swallow — the load-older affordance simply stays available to retry.
    } finally {
      if (mounted) {
        setState(() => _loadingOlder = false);
      } else {
        _loadingOlder = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _theme;
    return Directionality(
      textDirection: t.direction,
      child: Container(
        color: t.background,
        child: ValueListenableBuilder<List<ChatMessage>>(
          valueListenable: EasyLiveChat.instance.messages,
          builder: (context, messages, _) {
            return ValueListenableBuilder<DateTime?>(
              // Rebuilds the thread when an agent reads it, which is what turns
              // the ticks over on messages already on screen.
              valueListenable: EasyLiveChat.instance.agentLastReadAt,
              builder: (context, lastReadAt, _) {
                return ValueListenableBuilder<bool>(
                  valueListenable: EasyLiveChat.instance.agentTyping,
                  builder: (context, typing, _) {
                    // Header row (load-older) + messages + optional typing row.
                    final itemCount = messages.length + 1 + (typing ? 1 : 0);
                    // Only ever under the newest message — decided once for
                    // the whole thread, not per row.
                    final offer = widget.onQuickReply == null
                        ? null
                        : quickRepliesOnOffer(messages);
                    return ListView.builder(
                      controller: _scroll,
                      // So the thread can be pulled even when it fits the
                      // screen — that drag is how a visitor reaches earlier
                      // visits.
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      itemCount: itemCount,
                      itemBuilder: (context, index) {
                        if (index == 0) return _buildLoadOlder();
                        final msgIndex = index - 1;
                        if (msgIndex < messages.length) {
                          final m = messages[msgIndex];
                          final replies =
                              offer != null && offer.messageId == m.id
                                  ? offer.replies
                                  : const <String>[];
                          return MessageBubble(
                            key: ValueKey(m.id),
                            message: m,
                            theme: t,
                            showAgentName: _showAgentNames,
                            showAgentAvatar: _showAgentAvatars,
                            strings: _s,
                            agentLastReadAt: lastReadAt,
                            quickReplies: replies,
                            // Disabled, not hidden, while one is on its way or
                            // the workspace takes no messages — the same rule
                            // as the composer beside them.
                            onQuickReply: _sendingQuickReply ||
                                    EasyLiveChat.instance.composerLocked
                                ? null
                                : (reply) =>
                                    unawaited(_sendQuickReply(m.id, reply)),
                          );
                        }
                        // Trailing typing indicator — named for the assistant
                        // when it is the one composing, so the wait is not
                        // mistaken for a person.
                        return _TypingRow(
                          theme: t,
                          label: EasyLiveChat.instance.assistantTyping.value
                              ? _s.assistantTyping
                              : _s.agentTyping,
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildLoadOlder() {
    if (!_hasMoreOlder && !_loadingOlder) {
      return const SizedBox(height: 4);
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _loadingOlder
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                      _theme.text.withValues(alpha: 0.4)),
                ),
              )
            // A real control, not just a spinner. Scrolling up still loads
            // automatically, but a thread that opens on a short session may
            // not be scrollable at all, and the earlier visits behind it have
            // to stay reachable.
            : GestureDetector(
                onTap: () => unawaited(_loadOlder()),
                child: Text(
                  _s.loadOlder,
                  style: TextStyle(
                    fontSize: 12,
                    color: _theme.text.withValues(alpha: 0.6),
                  ),
                ),
              ),
      ),
    );
  }
}

/// A single message row. Customer right, agent/system/bot left. Renders text,
/// inline images, file chips, and inert placeholders without ever crashing on
/// unknown content/attachment shapes.
class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final EasyLiveChatTheme theme;
  final bool showAgentName;
  final bool showAgentAvatar;
  final ElcStrings strings;

  /// How far an agent has read, for the visitor's own sent/read ticks.
  ///
  /// Optional so a host embedding this widget on its own keeps compiling and
  /// simply shows a single tick where it would otherwise show a double —
  /// `EasyLiveChat.instance.agentLastReadAt` is the value to pass.
  final DateTime? agentLastReadAt;

  /// Quick replies to draw under this message — empty unless it is the one
  /// `quickRepliesOnOffer` picked for the thread.
  final List<String> quickReplies;

  /// Sends a tapped quick reply. Null draws [quickReplies] disabled.
  final ValueChanged<String>? onQuickReply;

  const MessageBubble({
    super.key,
    required this.message,
    required this.theme,
    required this.showAgentName,
    this.showAgentAvatar = true,
    required this.strings,
    this.agentLastReadAt,
    this.quickReplies = const [],
    this.onQuickReply,
  });

  bool get _isCustomer => message.isFromCustomer;

  @override
  Widget build(BuildContext context) {
    // System lines ("Conversation transferred to X") are notices, not chat:
    // centered, small, muted, no bubble/avatar/name/meta — matching the
    // dashboard, web widget and native apps. The body arrives from the server
    // already localized to the workspace language.
    // The survey the visitor filled in, drawn where they filled it in. A
    // thread that swallowed it would look like the submission failed, and
    // pinning it below everything (as the old conversation-level field did)
    // put an older visit's rating under newer messages.
    final submitted = message.postChat;
    if (submitted != null) {
      return _PostChatCard(
        submission: submitted,
        submittedAt: message.createdAt,
        theme: theme,
        strings: strings,
      );
    }
    if (message.senderType == SenderType.system) {
      // A returning visitor lands back in the conversation they already have
      // rather than starting a fresh one, so a thread can span months and
      // several unrelated problems. These bracket each visit — a labelled rule
      // rather than the usual pill, so a session boundary reads as a break in
      // the transcript and not as another notice. The date comes off the row
      // itself, in the visitor's own locale.
      final sessionKey = message.systemI18nKey;
      if (sessionKey == 'conversation.session.ended' ||
          sessionKey == 'conversation.session.ended.customer' ||
          sessionKey == 'conversation.session.started') {
        final started = sessionKey == 'conversation.session.started';
        // Leaving is a moment in a working day, so it reads at a clock time;
        // an agent resolving something is a day-level event in a thread that
        // may span months.
        final left = sessionKey == 'conversation.session.ended.customer';
        final label = left
            ? strings.systemSessionLeft
                .replaceAll('{time}', _sessionTime(context, message.createdAt))
            : (started
                    ? strings.systemSessionStarted
                    : strings.systemSessionEnded)
                .replaceAll('{date}', _sessionDate(context, message.createdAt));
        final rule = theme.text.withValues(alpha: 0.12);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(child: Container(height: 1, color: rule)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: started
                        ? theme.primary
                        : theme.text.withValues(alpha: 0.55),
                  ),
                ),
              ),
              Expanded(child: Container(height: 1, color: rule)),
            ],
          ),
        );
      }
      // Prefer the structured key so the line renders in the VIEWER's
      // language; the body is the workspace-language fallback for notices
      // sent before the key existed (or with keys this SDK doesn't know).
      final notice = message.systemI18nKey == 'conversation.transferred'
          ? strings.systemTransferredTo
              .replaceAll('{name}', message.systemI18nParam('name'))
          : (message.body ?? '').trim();
      if (notice.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 280),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: theme.text.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              notice,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.text.withValues(alpha: 0.55),
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ),
        ),
      );
    }

    final bubbleColor = _bubbleColor;
    final textColor = _isCustomer ? _onColor(theme.primary) : theme.text;
    final align =
        _isCustomer ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    final card = message.card;
    final body = (message.body ?? '').trim();
    final tiles = _attachmentTiles(context, textColor);
    // An avatar sits beside every inbound bubble when the workspace has the
    // switch on. System notices never reach here — they return above — so what
    // is left is the team talking, and the team gets a face.
    //
    // This used to also require knowing WHO sent it, which meant the
    // auto-greeting of a chat opened while everyone was offline had no face at
    // all: the server stamps the greeting with the assignee, and there wasn't
    // one yet. The first bubble of the conversation was blank while every later
    // one had a photo. `_AgentAvatar` already degrades to an initial, and to a
    // neutral circle when there is no name either, which is what the web widget
    // has always drawn in the same situation.
    final withAvatar = !_isCustomer && showAgentAvatar;
    // Leave room for the face so a narrow phone doesn't overflow the row.
    final maxBubble =
        MediaQuery.of(context).size.width * (withAvatar ? 0.68 : 0.78);

    final column = Column(
      crossAxisAlignment: align,
      children: [
        // Assistant messages always carry their name and an AI badge, even
        // when the workspace hides agent names: hiding a colleague's name is
        // the tenant's choice to make, hiding that nobody is there is not.
        if (message.isFromAssistant)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, bottom: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_agentName != null)
                  Flexible(
                    child: Text(
                      _agentName!,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.text.withValues(alpha: 0.6),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (_agentName != null) const SizedBox(width: 6),
                AiBadge(label: strings.aiBadge, theme: theme),
              ],
            ),
          )
        else if (!_isCustomer && showAgentName && _agentName != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, bottom: 2),
            child: Text(
              _agentLine!,
              style: TextStyle(
                color: theme.text.withValues(alpha: 0.6),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        // A card draws as a card, and only as a card: its body is the
        // plain-text version for clients that can't draw one, and its
        // attachment is the card's own image — drawing either as well would
        // say it all twice.
        // A CARD message whose card doesn't validate falls through to the
        // bubble and reads as that text, like every other client.
        if (card != null)
          ElcMessageCardView(card: card, theme: theme, maxWidth: maxBubble)
        else
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxBubble,
            ),
            child: Container(
              // A message that is only self-drawn media gets no bubble. The
              // bubble exists to put a surface behind text; wrapped around a
              // photo or a voice note it becomes a second card around a first
              // one — on the visitor's own side the full accent colour, so
              // their own images arrived matted in orange and their own
              // recording in a teal frame.
              padding: _isBareMedia
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _isBareMedia ? Colors.transparent : bubbleColor,
                borderRadius: ElcBubbleShape.radius(fromCustomer: _isCustomer),
                border: _isCustomer || _isBareMedia
                    ? null
                    : ElcBubbleShape.teamBorder(theme),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (tiles.isNotEmpty) ...[
                    ...tiles,
                    if (body.isNotEmpty) const SizedBox(height: 8),
                  ],
                  if (body.isNotEmpty)
                    LinkifiedText(
                      text: body,
                      style:
                          TextStyle(color: textColor, fontSize: 15, height: 1.35),
                      // On the accent-colored customer bubble the accent is the
                      // background, so a link there keeps the bubble's own
                      // foreground and relies on the underline; agent bubbles
                      // sit on `surface`, where the accent reads correctly.
                      linkColor: _isCustomer ? textColor : theme.primary,
                    ),
                  // Attachment-only message with no resolvable media still
                  // needs *something* visible so it never renders empty.
                  if (body.isEmpty && tiles.isEmpty)
                    Text(
                      strings.attachment,
                      style: TextStyle(
                          color: textColor.withValues(alpha: 0.7),
                          fontSize: 14,
                          fontStyle: FontStyle.italic),
                    ),
                ],
              ),
            ),
          ),
        if (quickReplies.isNotEmpty)
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxBubble),
            child: ElcQuickReplies(
              replies: quickReplies,
              theme: theme,
              semanticLabel: strings.suggestedReplies,
              onSelected: onQuickReply,
            ),
          ),
        const SizedBox(height: 2),
        _meta(textColorMuted: theme.text.withValues(alpha: 0.45)),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: withAvatar
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AgentAvatar(
                  url: message.senderAvatarUrl,
                  name: _agentName,
                  theme: theme,
                ),
                const SizedBox(width: 8),
                Flexible(child: column),
              ],
            )
          : column,
    );
  }

  String? get _agentName {
    final n = message.senderName?.trim();
    return (n != null && n.isNotEmpty) ? n : null;
  }

  /// Name, plus the job title when the agent has one — matches the web widget,
  /// which renders "Ava · Support Lead" above the bubble.
  String? get _agentLine {
    final n = _agentName;
    if (n == null) return null;
    final title = message.senderJobTitle?.trim();
    return (title != null && title.isNotEmpty) ? '$n · $title' : n;
  }

  Widget _meta({required Color textColorMuted}) {
    final time = _formatTime(message.createdAt);
    final parts = <Widget>[
      Text(time, style: TextStyle(color: textColorMuted, fontSize: 10)),
    ];
    final receipt = message.receiptFor(agentLastReadAt);
    if (receipt == MessageReceipt.failed) {
      // The one state that is not a tick. It is the only one the visitor can
      // act on, so it stays a worded, tappable affordance rather than an icon
      // they would have to guess at.
      parts
        ..add(const SizedBox(width: 6))
        ..add(GestureDetector(
          onTap: () {
            // Re-send and swallow the (already UI-reflected) failure future
            // so a second failure isn't an unhandled async error.
            EasyLiveChat.instance
                .resend(message)
                ?.serverMessageId
                .catchError((_) => '');
          },
          child: Text(strings.sendFailedRetry,
              style: const TextStyle(
                color: _ThreadErrorColor.color,
                fontSize: 10,
                decoration: TextDecoration.underline,
                decorationColor: _ThreadErrorColor.color,
              )),
        ));
    } else if (receipt != null) {
      parts
        ..add(const SizedBox(width: 4))
        ..add(_ReceiptTicks(
          receipt: receipt,
          mutedColor: textColorMuted,
          readColor: theme.primary,
          strings: strings,
        ));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: parts),
    );
  }

  // ── attachment rendering ──

  /// Build attachment tiles, preferring the rich rehosted list when present.
  /// True when this message is nothing but media that draws its own surface.
  ///
  /// A picture, or a voice note: both already round their own corners, so the
  /// bubble around them is a second card holding a first one. On the visitor's
  /// own side that is the full accent colour, and their own recording arrived
  /// matted in a teal frame.
  ///
  /// Deliberately strict. A caption needs the bubble behind it, and so does a
  /// file chip or an unavailable-media placeholder — those read as controls and
  /// would float loose without a surface. Only when every tile draws its own
  /// and there is no text does the bubble stop earning its place.
  /// The visitor's own messages sit on the accent, everyone else's on the
  /// neutral surface. A getter because a voice note standing outside the
  /// bubble has to paint the same colour the bubble would have.
  Color get _bubbleColor => _isCustomer ? theme.primary : theme.surface;

  bool get _isBareMedia {
    if ((message.body ?? '').trim().isNotEmpty) return false;
    if (message.attachments.isNotEmpty) {
      return message.attachments.every((a) =>
          a.isResolvable &&
          (a.kind == AttachmentKind.image ||
              a.kind == AttachmentKind.audio ||
              _looksLikeAudio(a.url)));
    }
    if (message.attachmentUrls.isNotEmpty) {
      return message.attachmentUrls.every((u) =>
          _isResolvableUrl(u) && (_looksLikeImage(u) || _looksLikeAudio(u)));
    }
    return false;
  }

  List<Widget> _attachmentTiles(BuildContext context, Color fg) {
    final tiles = <Widget>[];
    if (message.attachments.isNotEmpty) {
      for (final a in message.attachments) {
        tiles.add(_richTile(context, a, fg));
      }
      return tiles;
    }
    for (final raw in message.attachmentUrls) {
      tiles.add(_urlTile(context, raw, fg));
    }
    return tiles;
  }

  Widget _richTile(BuildContext context, RehostedAttachment a, Color fg) {
    if (!a.isResolvable) {
      return _unavailableChip(fg);
    }
    final url = EasyLiveChat.instance.resolveUrl(a.url);
    if (a.kind == AttachmentKind.image) {
      return _inlineImage(context, url, fg);
    }
    final label = a.filename ?? _basename(a.url);
    // The server's `kind` is authoritative — it comes from the mime type, so
    // it catches an extension this end has never heard of.
    if (a.kind == AttachmentKind.audio || _looksLikeAudio(a.url)) {
      return _voiceTile(url, label, fg);
    }
    return _fileChip(label, fg);
  }

  Widget _urlTile(BuildContext context, String raw, Color fg) {
    if (!_isResolvableUrl(raw)) {
      // wa:media:{id} and similar placeholders.
      return _unavailableChip(fg);
    }
    final url = EasyLiveChat.instance.resolveUrl(raw);
    if (_looksLikeImage(raw)) {
      return _inlineImage(context, url, fg);
    }
    if (_looksLikeAudio(raw)) {
      return _voiceTile(url, _basename(raw), fg);
    }
    return _fileChip(_basename(raw), fg);
  }

  /// Keyed by URL so playback survives the thread rebuilding around it —
  /// a message arriving mid-listen must not restart what is playing.
  Widget _voiceTile(String url, String label, Color fg) {
    return ElcVoiceNoteTile(
      key: ValueKey('voice:$url'),
      url: url,
      foreground: fg,
      // Standing on its own it has to paint the surface the bubble used to,
      // or white-on-white is all there is to see.
      background: _isBareMedia ? _bubbleColor : null,
      strings: strings,
      fallback: _fileChip(label, fg),
    );
  }

  Widget _inlineImage(BuildContext context, String url, Color fg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      // The tile is a thumbnail — cropped to `cover` and capped at 240×220 —
      // so tapping it opens the picture full-screen, where it can be pinched,
      // panned and double-tapped. Without this a screenshot of the very error
      // the visitor is writing in about was unreadable in the thread and there
      // was nothing to do about it.
      child: GestureDetector(
        onTap: () => ElcImageViewer.show(
          context,
          image: CachedNetworkImageProvider(url),
          theme: theme,
          strings: strings,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220, maxWidth: 240),
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              placeholder: (context, _) => Container(
                width: 200,
                height: 140,
                color: fg.withValues(alpha: 0.08),
                alignment: Alignment.center,
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        fg.withValues(alpha: 0.4)),
                  ),
                ),
              ),
              // A broken/blocked image must never throw — degrade to a chip.
              errorWidget: (context, _, __) => _fileChip(strings.image, fg),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fileChip(String label, Color fg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: fg.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file_outlined, size: 18, color: fg),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg, fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.download_rounded,
                size: 16, color: fg.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }

  Widget _unavailableChip(Color fg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: fg.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: fg.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined,
                size: 18, color: fg.withValues(alpha: 0.6)),
            const SizedBox(width: 8),
            Text(
              strings.mediaUnavailable,
              style: TextStyle(color: fg.withValues(alpha: 0.6), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // ── helpers ──

  static bool _isResolvableUrl(String u) =>
      u.startsWith('http://') || u.startsWith('https://') || u.startsWith('/');

  static bool _looksLikeImage(String u) {
    final lower = u.toLowerCase();
    final path = lower.split('?').first;
    return path.endsWith('.png') ||
        path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.gif') ||
        path.endsWith('.webp') ||
        path.endsWith('.bmp');
  }

  /// `.webm` is deliberately absent: the outbound media classifier
  /// (`adapters/media-out.ts`) reads it as video, and the API rewraps a
  /// browser-recorded audio `.webm` to `.ogg` on upload, so one arriving here
  /// really is a video. A `.webm` that is audio-only still plays — it reaches
  /// [_richTile] carrying `kind: audio` from its mime type.
  static bool _looksLikeAudio(String u) {
    final path = u.toLowerCase().split('?').first;
    return path.endsWith('.m4a') ||
        path.endsWith('.mp3') ||
        path.endsWith('.ogg') ||
        path.endsWith('.oga') ||
        path.endsWith('.opus') ||
        path.endsWith('.aac') ||
        path.endsWith('.amr') ||
        path.endsWith('.wav');
  }

  static String _basename(String u) {
    final path = u.split('?').first;
    final segs = path.split('/');
    final last = segs.isNotEmpty ? segs.last : path;
    return last.isEmpty ? path : last;
  }

  Color _onColor(Color bg) =>
      bg.computeLuminance() > 0.5 ? const Color(0xFF0F172A) : Colors.white;

  /// Context-free `HH:mm` (24h) timestamp. Locale-aware day/12h formatting is
  /// avoided here to keep the bubble free of a `BuildContext` dependency.
  /// Localized clock time, for the line a visitor's own exit leaves behind.
  ///
  /// Same reasoning as [_sessionDate]: the host app's MaterialLocalizations
  /// Always 24-hour and zero-padded, matching the bubble timestamps, rather
  /// than whatever the host's delegates would return.
  static String _sessionTime(BuildContext context, DateTime dt) {
    final local = dt.toLocal();
    // Formatted here for the same reason as the date: a host delegate that
    // mis-implements this returns literal pattern characters, and the SDK
    // cannot tell that from a real time. 24h, since that is what the bubble
    // timestamps already use.
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return _isolate('$h:$m');
  }

  /// Short date for a session divider — formatted here, not by the host.
  ///
  /// This used to call `MaterialLocalizations.formatShortDate`, on the
  /// reasoning that the host's delegates already know the app's locale. But the
  /// SDK ships chrome in 13 languages, and two of them — ckb and kmr — have no
  /// Flutter Material localizations at all, so a host that supports them must
  /// supply its own delegate. When one of those returns a bad pattern the date
  /// arrives as literal format characters (`٠٨/٢٢٤/YY`), and the SDK had no way
  /// to tell that from a real date.
  ///
  /// A widget in someone else's app cannot be at the mercy of that, so the date
  /// is built from the parts: day/month/year, Western digits, isolated. Plain,
  /// unambiguous, and identical in every locale.
  static String _sessionDate(BuildContext context, DateTime dt) {
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    return _isolate('$d/$m/${local.year}');
  }

  /// Wrap a number-and-separator run so it keeps its own reading order inside a
  /// right-to-left sentence.
  ///
  /// `12/08/2026` is digits joined by neutral characters, and neutrals take the
  /// direction of the paragraph around them. Dropped bare into Kurdish or
  /// Arabic copy, the groups are laid out right-to-left and the date reads back
  /// to front — `2026/08/12` rendered as `12/08/2026` reversed, which is how a
  /// correct date arrives on screen looking like `٢٢/٠٨/٢٢٤`. Arabic hid this
  /// only because its short format uses a month NAME, whose strong letters pin
  /// the order.
  ///
  /// FSI/PDI (rather than LRE/PDF): the run decides its own direction from its
  /// first strong character and cannot leak that decision to the sentence.
  static String _isolate(String run) => '\u2068$run\u2069';

  static String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// Animated three-dot "agent is typing" row, left-aligned like an agent bubble.
/// The replying agent's face, beside their bubble.
///
/// Falls back to the initial of their name on a tinted circle when there is no
/// photo — the same fallback the web widget uses, so an agent without an
/// avatar still reads as a person rather than leaving a hole in the layout.
class _AgentAvatar extends StatelessWidget {
  final String? url;
  final String? name;
  final EasyLiveChatTheme theme;

  const _AgentAvatar(
      {required this.url, required this.name, required this.theme});

  static const double _size = 28;

  @override
  Widget build(BuildContext context) {
    final raw = url?.trim();
    final initial = (name?.trim().isNotEmpty ?? false)
        ? name!.trim()[0].toUpperCase()
        : 'A';

    final fallback = Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.primary.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: theme.primary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    if (raw == null || raw.isEmpty) return fallback;

    // Avatars come back server-relative (`/uploads/...`); resolveUrl makes them
    // absolute against the configured API host.
    final resolved = EasyLiveChat.instance.resolveUrl(raw);
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: resolved,
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        // A broken or slow avatar must never break the thread — degrade to the
        // initial rather than showing an error glyph mid-conversation.
        placeholder: (_, __) => fallback,
        errorWidget: (_, __, ___) => fallback,
      ),
    );
  }
}

class _TypingRow extends StatefulWidget {
  final EasyLiveChatTheme theme;
  final String label;
  const _TypingRow({required this.theme, required this.label});

  @override
  State<_TypingRow> createState() => _TypingRowState();
}

class _TypingRowState extends State<_TypingRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    return Semantics(
      label: widget.label,
      liveRegion: true,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: t.surface,
              // The team's shape, so the dots sit in the bubble the reply is
              // about to arrive in.
              borderRadius: ElcBubbleShape.radius(fromCustomer: false),
              border: ElcBubbleShape.teamBorder(t),
            ),
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                // Fixed gaps between the dots (a SizedBox is direction-proof;
                // the old physical `right:` padding collapsed under RTL and
                // stacked the dots on top of each other).
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: 5),
                      _dot(t, i),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// One dot of the staggered wave: each takes its turn to hop and brighten,
  /// resting between turns — the familiar messenger cadence rather than a
  /// flat synchronized fade.
  Widget _dot(EasyLiveChatTheme t, int i) {
    final phase = (_c.value - i * 0.15) % 1.0;
    final active = phase < 0.45 ? math.sin(phase / 0.45 * math.pi) : 0.0;
    return Transform.translate(
      // Hop stays inside the bubble's 12px vertical padding.
      offset: Offset(0, -3.5 * active),
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: t.text.withValues(alpha: 0.35 + 0.45 * active),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// Destructive color for failed-send markers (kept local to the thread view).
abstract final class _ThreadErrorColor {
  static const Color color = Color(0xFFDC2626);
}

/// The visitor's own send status, in the idiom every messaging app uses:
/// a clock while it is in flight, one tick once the server has it, two in the
/// workspace's accent once an agent has read it.
///
/// Matches the web widget so a customer who uses both surfaces reads the same
/// marks. `Icons.done`/`done_all` are shape-symmetric, so unlike a chevron they
/// need no mirroring in Arabic, Sorani, Badini or Urdu — the surrounding Row
/// already flips their position for those layouts.
class _ReceiptTicks extends StatelessWidget {
  final MessageReceipt receipt;
  final Color mutedColor;
  final Color readColor;
  final ElcStrings strings;

  const _ReceiptTicks({
    required this.receipt,
    required this.mutedColor,
    required this.readColor,
    required this.strings,
  });

  @override
  Widget build(BuildContext context) {
    final isRead = receipt == MessageReceipt.read;
    final (IconData icon, String label) = switch (receipt) {
      MessageReceipt.pending => (Icons.schedule_rounded, strings.sending),
      MessageReceipt.read => (Icons.done_all_rounded, strings.messageRead),
      // `failed` never reaches here — the meta row renders its retry link
      // instead — but an exhaustive switch beats a default that would silently
      // start ticking failed sends if that ever changed.
      MessageReceipt.failed => (Icons.done_rounded, strings.messageSent),
      MessageReceipt.sent => (Icons.done_rounded, strings.messageSent),
    };
    return Semantics(
      label: label,
      // The time next to it is already read out; the tick is one more fact
      // about the same message, not a control.
      excludeSemantics: true,
      child: Icon(
        icon,
        size: 13,
        color: isRead ? readColor : mutedColor,
      ),
    );
  }
}

/// The post-chat survey as it appears in the thread.
///
/// Deliberately not a chat bubble: it is a form the visitor submitted, so it
/// reads as a small centred card — matching the dashboard and the native apps.
class _PostChatCard extends StatelessWidget {
  final Map<String, dynamic> submission;
  final DateTime submittedAt;
  final EasyLiveChatTheme theme;
  final ElcStrings strings;

  const _PostChatCard({
    required this.submission,
    required this.submittedAt,
    required this.theme,
    required this.strings,
  });

  @override
  Widget build(BuildContext context) {
    final rating = submission['rating'];
    final comment = (submission['comment'] ?? '').toString();
    final rawAnswers = submission['answers'];
    // Everything except the rating and the comment, which are drawn in their
    // own right above — a form whose comment field IS the comment would
    // otherwise print it twice.
    final extras = (rawAnswers is List ? rawAnswers : const [])
        .whereType<Map>()
        .where((a) =>
            a['type'] != 'rating' &&
            (a['value'] ?? '').toString().trim().isNotEmpty &&
            (a['value'] ?? '').toString() != comment)
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.text.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                strings.postChatTitle.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: theme.text.withValues(alpha: 0.55),
                ),
              ),
              if (rating is int) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(5, (i) {
                    final earned = i < rating;
                    return Icon(
                      earned ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 16,
                      color: earned
                          ? const Color(0xFFF59E0B)
                          : theme.text.withValues(alpha: 0.3),
                    );
                  }),
                ),
              ],
              if (comment.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  comment,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: theme.text),
                ),
              ],
              for (final answer in extras) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (answer['label'] ?? '').toString(),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: theme.text.withValues(alpha: 0.55),
                        ),
                      ),
                      Text(
                        (answer['value'] ?? '').toString(),
                        style: TextStyle(fontSize: 12.5, color: theme.text),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}


/// The small "AI" pill beside an assistant message's sender name.
@visibleForTesting
class AiBadge extends StatelessWidget {
  final String label;
  final EasyLiveChatTheme theme;

  const AiBadge({super.key, required this.label, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: theme.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: theme.primary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
}
