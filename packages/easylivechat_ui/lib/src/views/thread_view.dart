import 'package:cached_network_image/cached_network_image.dart';
import 'package:easylivechat/easylivechat.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../theme.dart';

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
  bool _hasMoreOlder = true;

  EasyLiveChatTheme get _theme => widget.theme;
  ElcStrings get _s =>
      ElcStrings.of(EasyLiveChat.instance.widgetConfig.value?.locale);

  bool get _showAgentNames =>
      EasyLiveChat.instance.widgetConfig.value?.showAgentNames ?? true;

  @override
  void initState() {
    super.initState();
    _lastCount = EasyLiveChat.instance.messages.value.length;
    EasyLiveChat.instance.messages.addListener(_onMessages);
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
  }

  @override
  void dispose() {
    EasyLiveChat.instance.messages.removeListener(_onMessages);
    _scroll.dispose();
    super.dispose();
  }

  void _onMessages() {
    final count = EasyLiveChat.instance.messages.value.length;
    // Auto-scroll only when a *new* (appended) message arrives, not when
    // older history is prepended.
    final appended = count > _lastCount && !_loadingOlder;
    _lastCount = count;
    if (appended) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _animateToBottom());
    }
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

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasMoreOlder) return;
    setState(() => _loadingOlder = true);
    try {
      final page = await EasyLiveChat.instance.loadOlderMessages();
      if (mounted && page.nextCursor == null) _hasMoreOlder = false;
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
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: itemCount,
                  itemBuilder: (context, index) {
                    if (index == 0) return _buildLoadOlder();
                    final msgIndex = index - 1;
                    if (msgIndex < messages.length) {
                      return MessageBubble(
                        message: messages[msgIndex],
                        theme: t,
                        showAgentName: _showAgentNames,
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
                      _theme.text.withOpacity(0.4)),
                ),
              )
            : TextButton(
                onPressed: _loadOlder,
                child: Text(
                  _s.loadOlder,
                  style: TextStyle(
                    color: _theme.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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
  final ElcStrings strings;

  const MessageBubble({
    super.key,
    required this.message,
    required this.theme,
    required this.showAgentName,
    required this.strings,
  });

  bool get _isCustomer => message.isFromCustomer;

  @override
  Widget build(BuildContext context) {
    final bubbleColor = _isCustomer ? theme.primary : theme.surface;
    final textColor = _isCustomer ? _onColor(theme.primary) : theme.text;
    final align = _isCustomer ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    final body = (message.body ?? '').trim();
    final tiles = _attachmentTiles(textColor);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (!_isCustomer && showAgentName && _agentName != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(
                _agentName!,
                style: TextStyle(
                  color: theme.text.withOpacity(0.6),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(_isCustomer ? 16 : 4),
                  bottomRight: Radius.circular(_isCustomer ? 4 : 16),
                ),
                border: _isCustomer
                    ? null
                    : Border.all(color: theme.text.withOpacity(0.08)),
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
                    Text(
                      body,
                      style: TextStyle(
                          color: textColor, fontSize: 15, height: 1.35),
                    ),
                  // Attachment-only message with no resolvable media still
                  // needs *something* visible so it never renders empty.
                  if (body.isEmpty && tiles.isEmpty)
                    Text(
                      strings.attachment,
                      style: TextStyle(
                          color: textColor.withOpacity(0.7),
                          fontSize: 14,
                          fontStyle: FontStyle.italic),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),
          _meta(textColorMuted: theme.text.withOpacity(0.45)),
        ],
      ),
    );
  }

  String? get _agentName {
    final n = message.senderName?.trim();
    return (n != null && n.isNotEmpty) ? n : null;
  }

  Widget _meta({required Color textColorMuted}) {
    final time = _formatTime(message.createdAt);
    final parts = <Widget>[
      Text(time,
          style: TextStyle(color: textColorMuted, fontSize: 10)),
    ];
    if (_isCustomer) {
      if (message.failed) {
        parts
          ..add(const SizedBox(width: 6))
          ..add(Text(strings.sendFailedRetry,
              style: const TextStyle(
                  color: _ThreadErrorColor.color, fontSize: 10)));
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
              color: fg.withOpacity(0.08),
              alignment: Alignment.center,
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(fg.withOpacity(0.4)),
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
          color: fg.withOpacity(0.08),
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
            Icon(Icons.download_rounded, size: 16, color: fg.withOpacity(0.7)),
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
          color: fg.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: fg.withOpacity(0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined,
                size: 18, color: fg.withOpacity(0.6)),
            const SizedBox(width: 8),
            Text(
              strings.mediaUnavailable,
              style: TextStyle(
                  color: fg.withOpacity(0.6), fontSize: 13),
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
  static String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// Animated three-dot "agent is typing" row, left-aligned like an agent bubble.
class _TypingRow extends StatefulWidget {
  final EasyLiveChatTheme theme;
  final String label;
  const _TypingRow({required this.theme, required this.label});

  @override
  State<_TypingRow> createState() => _TypingRowState();
}

class _TypingRowState extends State<_TypingRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
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
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomRight: Radius.circular(16),
              bottomLeft: Radius.circular(4),
            ),
            border: Border.all(color: t.text.withOpacity(0.08)),
          ),
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final phase = (_c.value + i * 0.33) % 1.0;
                  final opacity = 0.3 + 0.7 * (1 - (phase - 0.5).abs() * 2).clamp(0.0, 1.0);
                  return Padding(
                    padding: EdgeInsets.only(right: i < 2 ? 4 : 0),
                    child: Opacity(
                      opacity: opacity,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: t.text.withOpacity(0.5),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ),
      ),
      ),
    );
  }
}

/// Destructive color for failed-send markers (kept local to the thread view).
abstract final class _ThreadErrorColor {
  static const Color color = Color(0xFFDC2626);
}
