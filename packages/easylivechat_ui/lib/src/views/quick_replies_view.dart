import 'package:flutter/material.dart';

import '../bidi.dart';
import '../theme.dart';

/// Tappable answers under the newest message — the workspace's greeting
/// replies, or the assistant's Yes / No to a handover offer. The native analog
/// of `.quick-replies` in the web widget.
///
/// Outlined in the workspace accent and filled with it on press, so they read
/// as answers the visitor can give rather than as more of the message. They
/// wrap from the team's side of the thread, which is the leading edge in both
/// directions.
///
/// Which message offers them is not decided here — see `quickRepliesOnOffer`
/// in the core package.
class ElcQuickReplies extends StatelessWidget {
  final List<String> replies;
  final EasyLiveChatTheme theme;

  /// What a screen reader calls the group (`ElcStrings.suggestedReplies`).
  final String semanticLabel;

  /// Called with the reply exactly as the server sent it. Null disables every
  /// button — while a reply is already on its way, or while the composer is
  /// locked — so a double tap cannot send twice.
  final ValueChanged<String>? onSelected;

  const ElcQuickReplies({
    super.key,
    required this.replies,
    required this.theme,
    required this.semanticLabel,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(top: 8),
        // They rise into place once, as on the web — and not at all for a
        // visitor who has asked for less motion.
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: still ? Duration.zero : const Duration(milliseconds: 260),
          curve: const Cubic(0.16, 1, 0.3, 1),
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, 4 * (1 - t)),
              child: child,
            ),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final reply in replies)
                _QuickReplyButton(
                  reply: reply,
                  theme: theme,
                  onPressed: onSelected == null ? null : () => onSelected!(reply),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickReplyButton extends StatelessWidget {
  final String reply;
  final EasyLiveChatTheme theme;
  final VoidCallback? onPressed;

  const _QuickReplyButton({
    required this.reply,
    required this.theme,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final accent = theme.primary;
    final onAccent = accent.computeLuminance() > 0.5
        ? const Color(0xFF0F172A)
        : Colors.white;
    return OutlinedButton(
      onPressed: onPressed,
      style: ButtonStyle(
        // 40 tall rather than the pill's natural ~34: still reads as a pill,
        // and a thumb finds it.
        minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
        padding: const WidgetStatePropertyAll(
          EdgeInsetsDirectional.fromSTEB(14, 8, 14, 8),
        ),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        animationDuration: const Duration(milliseconds: 120),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.25),
        ),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.disabled)
                ? accent.withValues(alpha: 0.5)
                : accent,
            width: 1.5,
          ),
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.pressed) &&
                  !states.contains(WidgetState.disabled)
              ? accent
              : theme.background,
        ),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return accent.withValues(alpha: 0.5);
          }
          return states.contains(WidgetState.pressed) ? onAccent : accent;
        }),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          // Pressed fills with the accent itself; an overlay on top of that
          // would only muddy it.
          if (states.contains(WidgetState.pressed)) return Colors.transparent;
          if (states.contains(WidgetState.focused)) {
            return accent.withValues(alpha: 0.12);
          }
          if (states.contains(WidgetState.hovered)) {
            return accent.withValues(alpha: 0.10);
          }
          return null;
        }),
      ),
      child: Text(
        reply,
        textAlign: TextAlign.start,
        textDirection: textDirectionOf(reply),
      ),
    );
  }
}
