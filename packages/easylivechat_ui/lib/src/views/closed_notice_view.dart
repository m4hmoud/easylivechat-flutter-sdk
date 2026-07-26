import 'package:easylivechat/easylivechat.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../theme.dart';

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
        ? config.offlineMessage.trim()
        : strings.closedNotice;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            // The theme exposes only primary/background/surface/text; muted is
            // derived, matching how the other views tint.
            color: theme.text.withValues(alpha: 0.7),
            fontSize: 15,
            height: 1.5,
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
        ? cfg.offlineMessage.trim()
        : strings.closedNotice;

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
