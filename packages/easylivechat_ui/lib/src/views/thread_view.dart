import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easylivechat/easylivechat.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../theme.dart';
import 'linkified_text.dart';

/// The message thread (native analog of the web `Thread.tsx`).
///
/// Binds `EasyLiveChat.instance.messages` + `agentTyping`. Customer messages
/// align to the trailing edge (right in LTR), agent/system/bot to the leading
/// edge. Agent names are shown only when `config.showAgentNames` is true
/// (the server already nulls `senderName` when disabled — double-guarded here).
///
/// Attachments: prefer the rich [RehostedAttachment] list when present
/// (kind==image → inline via `cached_network_image`; otherwise a download
/// chip). Otherwise fall back to flat [ChatMessage.attachmentUrls] (image-like
/// extensions render inline, the rest as chips). Non-resolvable placeholders
/// (`wa:media:{id}`) render an inert "media unavailable" chip — never a broken
/// image. Unknown `contentType` degrades to a plain text bubble; nothing here
/// may crash on a future enum value.
///
/// Auto-scrolls to the newest message on append; a "load earlier" trigger at
/// the top calls `loadOlderMessages()`.
class ThreadView extends StatefulWidget {
  final EasyLiveChatTheme theme;

  const ThreadView({super.key, required this.theme});

  @override
  State<ThreadView> createState() => _ThreadViewState();
}

class _ThreadViewState extends State<ThreadView> {
  final ScrollController _scroll = ScrollController();
  int _lastCount = 0;
  bool _loadingOlder = false;
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
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onMessages() {
    final count = EasyLiveChat.instance.messages.value.length;
    // Auto-scroll only when a *new* (appended) message arrives, not when
    // older history is prepended — and only if the user is already near the
    // bottom, so an incoming reply doesn't yank them away from history they're
    // reading. (Their own send is from the bottom, so it still scrolls.)
    final appended = count > _lastCount && !_loadingOlder;
    _lastCount = count;
    if (appended && _isNearBottom()) {
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
            return ValueListenableBuilder<bool>(
              valueListenable: EasyLiveChat.instance.agentTyping,
              builder: (context, typing, _) {
                // Header row (load-older) + messages + optional typing row.
                final itemCount = messages.length + 1 + (typing ? 1 : 0);
                return ListView.builder(
                  controller: _scroll,
                  // So the thread can be pulled even when it fits the screen —
                  // that drag is how a visitor reaches earlier visits.
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: itemCount,
                  itemBuilder: (context, index) {
                    if (index == 0) return _buildLoadOlder();
                    final msgIndex = index - 1;
                    if (msgIndex < messages.length) {
                      final m = messages[msgIndex];
                      return MessageBubble(
                        key: ValueKey(m.id),
                        message: m,
                        theme: t,
                        showAgentName: _showAgentNames,
                        showAgentAvatar: _showAgentAvatars,
                        strings: _s,
                      );
                    }
                    // Trailing typing indicator.
                    return _TypingRow(theme: t, label: _s.agentTyping);
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

  const MessageBubble({
    super.key,
    required this.message,
    required this.theme,
    required this.showAgentName,
    this.showAgentAvatar = true,
    required this.strings,
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
            ? strings.systemSessionLeft.replaceAll(
                '{time}', _sessionTime(context, message.createdAt))
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
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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

    final bubbleColor = _isCustomer ? theme.primary : theme.surface;
    final textColor = _isCustomer ? _onColor(theme.primary) : theme.text;
    final align =
        _isCustomer ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    final body = (message.body ?? '').trim();
    final tiles = _attachmentTiles(textColor);
    // An avatar sits beside an inbound bubble when the workspace has the
    // switch on AND we know who sent it. The identity check is what keeps a
    // faceless system line from rendering an anonymous "A" circle — while
    // still letting the auto-greeting show a face, since the server now
    // attributes it to the agent the chat was routed to.
    final withAvatar = !_isCustomer && showAgentAvatar && _hasSenderIdentity;
    // Leave room for the face so a narrow phone doesn't overflow the row.
    final maxBubble =
        MediaQuery.of(context).size.width * (withAvatar ? 0.68 : 0.78);

    final column = Column(
        crossAxisAlignment: align,
        children: [
          if (!_isCustomer && showAgentName && _agentName != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(
                _agentLine!,
                style: TextStyle(
                  color: theme.text.withValues(alpha: 0.6),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxBubble,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bubbleColor,
                // Logical corners: the tail hugs the sender's own side in RTL
                // as well — bottomStart/bottomEnd flip with the layout,
                // physical left/right did not.
                borderRadius: BorderRadiusDirectional.only(
                  topStart: const Radius.circular(16),
                  topEnd: const Radius.circular(16),
                  bottomStart: Radius.circular(_isCustomer ? 16 : 4),
                  bottomEnd: Radius.circular(_isCustomer ? 4 : 16),
                ),
                border: _isCustomer
                    ? null
                    : Border.all(color: theme.text.withValues(alpha: 0.08)),
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
                      style: TextStyle(
                          color: textColor, fontSize: 15, height: 1.35),
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

  /// Do we know who this came from? Either field is enough — an agent with no
  /// photo still gets the initial circle, and a photo with the name switch off
  /// still gets the photo.
  bool get _hasSenderIdentity =>
      (message.senderAvatarUrl?.trim().isNotEmpty ?? false) ||
      _agentName != null;

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
    if (_isCustomer) {
      if (message.failed) {
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
      } else if (message.isOptimistic ||
          message.deliveryStatus == MessageDeliveryStatus.pending) {
        parts
          ..add(const SizedBox(width: 6))
          ..add(Text(strings.sending,
              style: TextStyle(color: textColorMuted, fontSize: 10)));
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: parts),
    );
  }

  // ── attachment rendering ──

  /// Build attachment tiles, preferring the rich rehosted list when present.
  List<Widget> _attachmentTiles(Color fg) {
    final tiles = <Widget>[];
    if (message.attachments.isNotEmpty) {
      for (final a in message.attachments) {
        tiles.add(_richTile(a, fg));
      }
      return tiles;
    }
    for (final raw in message.attachmentUrls) {
      tiles.add(_urlTile(raw, fg));
    }
    return tiles;
  }

  Widget _richTile(RehostedAttachment a, Color fg) {
    if (!a.isResolvable) {
      return _unavailableChip(fg);
    }
    final url = EasyLiveChat.instance.resolveUrl(a.url);
    if (a.kind == AttachmentKind.image) {
      return _inlineImage(url, fg);
    }
    return _fileChip(a.filename ?? _basename(a.url), fg);
  }

  Widget _urlTile(String raw, Color fg) {
    if (!_isResolvableUrl(raw)) {
      // wa:media:{id} and similar placeholders.
      return _unavailableChip(fg);
    }
    final url = EasyLiveChat.instance.resolveUrl(raw);
    if (_looksLikeImage(raw)) {
      return _inlineImage(url, fg);
    }
    return _fileChip(_basename(raw), fg);
  }

  Widget _inlineImage(String url, Color fg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
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
                  valueColor:
                      AlwaysStoppedAnimation<Color>(fg.withValues(alpha: 0.4)),
                ),
              ),
            ),
            // A broken/blocked image must never throw — degrade to a chip.
            errorWidget: (context, _, __) => _fileChip(strings.image, fg),
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
  /// decide the format (12- vs 24-hour included), and a host without them gets
  /// an unambiguous zero-padded 24-hour fallback rather than nothing.
  static String _sessionTime(BuildContext context, DateTime dt) {
    final local = dt.toLocal();
    final l10n = Localizations.of<MaterialLocalizations>(
      context,
      MaterialLocalizations,
    );
    if (l10n != null) {
      return l10n.formatTimeOfDay(TimeOfDay.fromDateTime(local));
    }
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Localized short date for a session divider.
  ///
  /// [MaterialLocalizations] comes from the host app's delegates, so the format
  /// follows the app's locale without this package taking an intl dependency.
  /// A host without Material localizations falls back to an unambiguous
  /// year-month-day rather than to nothing.
  static String _sessionDate(BuildContext context, DateTime dt) {
    final local = dt.toLocal();
    final l10n = Localizations.of<MaterialLocalizations>(
      context,
      MaterialLocalizations,
    );
    if (l10n != null) return l10n.formatShortDate(local);
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '${local.year}-$m-$d';
  }

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

  const _AgentAvatar({required this.url, required this.name, required this.theme});

  static const double _size = 28;

  @override
  Widget build(BuildContext context) {
    final raw = url?.trim();
    final initial =
        (name?.trim().isNotEmpty ?? false) ? name!.trim()[0].toUpperCase() : 'A';

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
              // Logical corners so the bubble tail hugs the leading edge in
              // RTL too, matching the message bubbles.
              borderRadius: const BorderRadiusDirectional.only(
                topStart: Radius.circular(16),
                topEnd: Radius.circular(16),
                bottomEnd: Radius.circular(16),
                bottomStart: Radius.circular(4),
              ),
              border: Border.all(color: t.text.withValues(alpha: 0.08)),
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
    final active =
        phase < 0.45 ? math.sin(phase / 0.45 * math.pi) : 0.0;
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
