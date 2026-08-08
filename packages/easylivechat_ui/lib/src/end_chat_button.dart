import 'package:easylivechat/easylivechat.dart';
import 'package:flutter/material.dart';

import 'l10n.dart';
import 'theme.dart';

/// The explicit "end chat" affordance.
///
/// Backing out of [EasyLiveChatScreen] does NOT end the conversation — the
/// visitor can leave mid-chat and be resumed right where they were the next
/// time the screen opens. Ending is therefore a deliberate act, and this is
/// its button: visible only while a conversation is live, it confirms in the
/// chrome locale, ends the chat, and the tenant's post-chat survey (if any)
/// appears in place on the screen.
///
/// Drop it into an app bar's actions. Hosts whose app bar takes a callback
/// rather than a widget (an `IconData` + `onPressed` slot) can call
/// [confirmAndEnd] directly instead — it no-ops when no conversation is live,
/// so an always-visible icon stays harmless.
class EasyLiveChatEndChatButton extends StatelessWidget {
  /// Chrome locale override — same contract as [EasyLiveChatScreen.locale].
  final String? locale;

  /// Icon color; defaults to the ambient [IconTheme].
  final Color? color;

  /// Colors for the confirmation dialog. Defaults to the workspace config —
  /// pass the same override the chat screen uses to keep them identical.
  final EasyLiveChatTheme? theme;

  const EasyLiveChatEndChatButton({
    super.key,
    this.locale,
    this.color,
    this.theme,
  });

  /// Confirm (in the chrome locale), then end the live conversation.
  ///
  /// Returns true when the chat was ended. No-ops — no dialog — when no
  /// conversation is in progress, so callback-slot hosts can wire this to an
  /// icon that is always visible.
  ///
  /// [theme] overrides the workspace colors, for a host whose app bar already
  /// themes the chat screen and wants the dialog to match.
  static Future<bool> confirmAndEnd(
    BuildContext context, {
    String? locale,
    EasyLiveChatTheme? theme,
  }) async {
    if (EasyLiveChat.instance.phase.value != ChatPhase.chat) return false;
    final config = EasyLiveChat.instance.widgetConfig.value;
    final strings = ElcStrings.of(locale ?? config?.locale);
    // The workspace's own colors and direction, so the dialog belongs to the
    // chat rather than inheriting whatever the host's Material theme happens
    // to be. Falls back to the override, then to sane defaults.
    final t = theme ??
        (config != null
            ? EasyLiveChatTheme.fromConfig(config)
            : const EasyLiveChatTheme(
                primary: Color(0xFF2563EB),
                background: Color(0xFFFFFFFF),
                surface: Color(0xFFF1F5F9),
                text: Color(0xFF0F172A),
              ));
    final onPrimary =
        t.primary.computeLuminance() > 0.5 ? const Color(0xFF0F172A) : Colors.white;

    final answer = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (dialogContext) => Directionality(
        textDirection: t.direction,
        child: Dialog(
          backgroundColor: t.surface,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 32),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  strings.exitChatTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: t.text,
                    fontSize: 17,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                // Ending is the deliberate choice, so it gets the solid
                // button; staying is one tap away and needs no emphasis.
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: t.primary,
                    foregroundColor: onPrimary,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(strings.exitChatConfirm),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: t.text.withValues(alpha: 0.7),
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(strings.exitChatCancel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // Dismissing the dialog by tapping outside means "no".
    if (answer != true) return false;
    await EasyLiveChat.instance.endChat();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ChatPhase>(
      valueListenable: EasyLiveChat.instance.phase,
      builder: (context, phase, _) {
        // Only a live conversation can be ended; hide otherwise (during the
        // survey, the pre-chat form, offline notice, …).
        if (phase != ChatPhase.chat) return const SizedBox.shrink();
        final strings = ElcStrings.of(
            locale ?? EasyLiveChat.instance.widgetConfig.value?.locale);
        return IconButton(
          icon: const Icon(Icons.speaker_notes_off_outlined),
          color: color,
          tooltip: strings.endChat,
          onPressed: () => confirmAndEnd(context, locale: locale, theme: theme),
        );
      },
    );
  }
}
