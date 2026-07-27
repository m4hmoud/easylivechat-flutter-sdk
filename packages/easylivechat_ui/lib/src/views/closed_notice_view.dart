import 'package:easylivechat/easylivechat.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../theme.dart';

/// Being shut and being understaffed are different states and read differently
/// to a visitor: "back at 09:00" is actionable, "everyone's busy" is not. The
/// server tells us which via `reason`.
String _defaultNotice(ElcStrings strings) {
  final elc = EasyLiveChat.instance;
  if (!elc.isBooted) return strings.closedNotice;

  if (elc.availabilityReason.value == 'NO_AGENTS') return strings.noAgentsNotice;

  // A named closure ("Closed for Eid al-Adha") tells the visitor far more than
  // a generic "we're offline", so prefer it when the server sent one.
  final label = elc.closureLabel.value;
  final head = (elc.availabilityReason.value == 'HOLIDAY' &&
          label != null &&
          label.isNotEmpty)
      ? strings.closedForLabel.replaceAll('{label}', label)
      : strings.closedNotice;

  // The BUSINESS's clock, formatted server-side. Rendering the instant here
  // would use the device's zone — "back at 09:00" would read 07:00 to a
  // visitor one country over, for a business that opens at nine.
  final local = elc.nextOpenLocal.value;
  if (local != null && local.isNotEmpty) {
    return '$head ${strings.backAt.replaceAll('{time}', local)}';
  }

  // Older server: fall back to the instant in device-local time rather than
  // dropping the reopening time entirely.
  final next = elc.nextOpenAt.value;
  if (next == null) return head;
  final hh = next.hour.toString().padLeft(2, '0');
  final mm = next.minute.toString().padLeft(2, '0');
  return '$head ${strings.backAt.replaceAll('{time}', '$hh:$mm')}';
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
      color: theme.primary.withValues(alpha: 0.55),
    );
    final url = logoUrl?.trim() ?? '';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.primary.withValues(alpha: 0.08),
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
/// Prefers the tenant's own wording (`config.offlineMessage`) and falls back to
/// the localized default.
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
    final message = config.offlineMessage.trim().isNotEmpty
        ? substituteVisitorVariables(config.offlineMessage.trim(),
            name: EasyLiveChat.instance.visitorName,
            defaultName: config.defaultCustomerName)
        : _defaultNotice(strings);

    return Center(
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
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                // The theme exposes only primary/background/surface/text; muted
                // is derived, matching how the other views tint.
                color: theme.text.withValues(alpha: 0.7),
                fontSize: 15,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slim banner pinned above the thread while the workspace is closed.
///
/// The visitor keeps a working composer — their message becomes a PENDING
/// conversation that is auto-assigned when the team comes back — so this sets
/// the expectation about reply time rather than blocking anything.
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
    final cfg = config;
    final strings = ElcStrings.of(cfg?.locale ?? 'en');
    final message = (cfg != null && cfg.offlineMessage.trim().isNotEmpty)
        ? substituteVisitorVariables(cfg.offlineMessage.trim(),
            name: EasyLiveChat.instance.visitorName,
            defaultName: cfg.defaultCustomerName)
        : _defaultNotice(strings);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.surface,
        border: Border(
          bottom: BorderSide(color: theme.text.withValues(alpha: 0.12)),
        ),
      ),
      child: Text(
        message,
        // Logical alignment so RTL locales (ar / ku / ur) mirror correctly.
        textAlign: TextAlign.start,
        style: TextStyle(
          color: theme.text.withValues(alpha: 0.7),
          fontSize: 13,
          height: 1.45,
        ),
      ),
    );
  }
}
