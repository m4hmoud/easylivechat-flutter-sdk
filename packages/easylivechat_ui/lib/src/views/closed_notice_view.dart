import 'package:easylivechat/easylivechat.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../theme.dart';

/// The words shown while the workspace is shut — on the banner above the
/// thread and on the closed screen alike. The web widget's `closedBannerText`
/// (apps/widget/src/app/embed/Embed.tsx), rule for rule:
///
///  1. The business's own notice ([tenantNotice], `offlineInfoText`) ALWAYS
///     wins — their words, whatever the mode, whether or not the assistant
///     covers.
///  2. Without one, a composer locked by `NOTICE_ONLY` is told when the team
///     is back ("We're back at 06:00.") — the time IS the notice — or that
///     they will be back soon.
///  3. Busy rather than shut (`NO_AGENTS`): "everyone's busy", or, while the
///     assistant answers, that it can help in the meantime.
///  4. Shut: "we're offline" — the assistant's version while it covers, the
///     closure's name on a named holiday otherwise — followed by the
///     reopening time, which stays even while the assistant covers: it is when
///     a PERSON is back.
///
/// Deliberately not `offlineMessage`. That column is the leave-a-message
/// prompt and carries a schema default nobody typed, so reading it here put
/// English in front of every visitor and invited a message from workspaces
/// that take none.
///
/// The reopening time is [nextOpenLocal] — the BUSINESS's clock, formatted by
/// the server, since Dart carries no timezone database — and falls back to
/// [nextOpenAt] on the device's clock only for an older server that sends no
/// `nextOpenLocal`.
@visibleForTesting
String closedNoticeText(
  ElcStrings strings, {
  String? tenantNotice,
  bool composerLocked = false,
  String reason = 'OPEN',
  bool assistantCovers = false,
  DateTime? nextOpenAt,
  String? nextOpenLocal,
  String? closureLabel,
}) {
  final own = tenantNotice?.trim() ?? '';
  if (own.isNotEmpty) return own;

  String? reopensAt;
  if (nextOpenAt != null) {
    final local = nextOpenLocal?.trim() ?? '';
    reopensAt = local.isNotEmpty
        ? local
        : '${nextOpenAt.hour.toString().padLeft(2, '0')}:'
            '${nextOpenAt.minute.toString().padLeft(2, '0')}';
  }
  final backAt =
      reopensAt == null ? null : strings.backAt.replaceAll('{time}', reopensAt);

  if (composerLocked) return backAt ?? strings.closedReadOnly;

  // With the assistant covering, "leave a message and we'll reply when we're
  // back" is untrue — a reply arrives in seconds.
  if (reason == 'NO_AGENTS') {
    return assistantCovers
        ? strings.noAgentsAssistantNotice
        : strings.noAgentsNotice;
  }
  // A named closure ("Closed for Eid al-Adha") tells the visitor far more than
  // a generic "we're offline", so it is used when the server sent one.
  final label = closureLabel?.trim() ?? '';
  final closed = assistantCovers
      ? strings.closedAssistantNotice
      : (reason == 'HOLIDAY' && label.isNotEmpty)
          ? strings.closedForLabel.replaceAll('{label}', label)
          : strings.closedNotice;
  return backAt == null ? closed : '$closed $backAt';
}

/// Everything the notice is worded from, as it stands now.
String _currentNotice(WidgetConfigModel? config, ElcStrings strings) {
  final elc = EasyLiveChat.instance;
  final own = config?.offlineInfoText;
  if (!elc.isBooted) {
    return closedNoticeText(strings, tenantNotice: own);
  }
  return closedNoticeText(
    strings,
    // `%name%` and friends, as in the rest of the tenant's copy.
    tenantNotice: own == null
        ? null
        : substituteVisitorVariables(own,
            name: elc.visitorName, defaultName: config?.defaultCustomerName),
    composerLocked: elc.composerLocked,
    reason: elc.availabilityReason.value,
    assistantCovers: elc.assistantCovers.value,
    nextOpenAt: elc.nextOpenAt.value,
    nextOpenLocal: elc.nextOpenLocal.value,
    closureLabel: elc.closureLabel.value,
  );
}

/// Fires whenever anything the closed notice reads changes — the server's
/// verdict arrives live over `workspace:availability`, and the assistant can
/// start or stop covering with the visitor looking at the notice.
Listenable elcAvailabilityListenable() {
  final elc = EasyLiveChat.instance;
  if (!elc.isBooted) return const _Never();
  return Listenable.merge([
    elc.isOpen,
    elc.agentsAccepting,
    elc.visitorMode,
    elc.availabilityReason,
    elc.assistantCovers,
    elc.nextOpenAt,
    elc.nextOpenLocal,
    elc.closureLabel,
  ]);
}

class _Never implements Listenable {
  const _Never();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

/// The business's own logo, or a neutral placeholder when it has none or the
/// image fails to load — an empty gap where a logo should be looks broken.
class _BusinessMark extends StatelessWidget {
  final String? logoUrl;
  final EasyLiveChatTheme theme;

  const _BusinessMark({required this.logoUrl, required this.theme});

  @override
  Widget build(BuildContext context) {
    const size = 76.0;
    final fallback = Icon(
      Icons.chat_bubble_outline_rounded,
      size: 32,
      color: theme.primaryInk.withValues(alpha: 0.55),
    );
    final url = logoUrl?.trim() ?? '';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.primary.withValues(alpha: theme.isDark ? 0.16 : 0.08),
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: url.isEmpty
          ? Center(child: fallback)
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(child: fallback),
            ),
    );
  }
}

/// Shown when the workspace is closed and no conversation can be started.
///
/// This replaced a ticket/offline form. The form was a dead end: whatever the
/// visitor typed was filed as a separate record instead of becoming a
/// conversation, so it never appeared in the thread and the visitor had no way
/// to follow it up.
///
/// In the normal (messaging-mode) path the visitor is not sent here at all —
/// they get the ordinary chat with [ClosedNoticeBanner] above it and can write
/// straight away. This view is the narrow fallback for tenants configured to
/// refuse new chats when nobody is accepting.
///
/// Worded exactly as the banner is ([closedNoticeText]): the business's own
/// notice when it wrote one, otherwise ours — the assistant's version while
/// it covers — with the reopening time.
class ClosedNoticeView extends StatelessWidget {
  final WidgetConfigModel config;
  final EasyLiveChatTheme theme;

  const ClosedNoticeView({
    super.key,
    required this.config,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final strings = ElcStrings.of(config.locale);
    return ListenableBuilder(
      listenable: elcAvailabilityListenable(),
      builder: (context, _) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BusinessMark(logoUrl: config.logoUrl, theme: theme),
              const SizedBox(height: 20),
              // Stated first and in full contrast: whatever the tenant's body
              // copy says, the visitor learns the state from this line alone.
              Text(
                strings.unavailableTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.text,
                  fontSize: 17,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _currentNotice(config, strings),
                textAlign: TextAlign.center,
                style: TextStyle(
                  // The theme exposes only primary/background/surface/text;
                  // muted is derived, matching how the other views tint.
                  color: theme.text.withValues(alpha: 0.7),
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Slim banner pinned above the thread while the workspace is closed.
///
/// The visitor keeps a working composer — their message becomes a PENDING
/// conversation that is auto-assigned when the team comes back — so this sets
/// the expectation about reply time rather than blocking anything. Worded by
/// [closedNoticeText], and kept current as the availability moves.
class ClosedNoticeBanner extends StatelessWidget {
  final WidgetConfigModel? config;
  final EasyLiveChatTheme theme;

  const ClosedNoticeBanner({
    super.key,
    required this.config,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final strings = ElcStrings.of(config?.locale ?? 'en');
    return ListenableBuilder(
      listenable: elcAvailabilityListenable(),
      builder: (context, _) => Semantics(
        liveRegion: true,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: theme.surface,
            border: Border(
              bottom: BorderSide(color: theme.text.withValues(alpha: 0.12)),
            ),
          ),
          child: Text(
            _currentNotice(config, strings),
            // Logical alignment so RTL locales (ar / ku / ur) mirror correctly.
            textAlign: TextAlign.start,
            style: TextStyle(
              color: theme.text.withValues(alpha: 0.7),
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ),
      ),
    );
  }
}
