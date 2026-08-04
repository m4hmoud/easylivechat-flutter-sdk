import 'package:easylivechat/easylivechat.dart';
import 'package:flutter/material.dart';

import 'l10n.dart';

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

  const EasyLiveChatEndChatButton({super.key, this.locale, this.color});

  /// Confirm (in the chrome locale), then end the live conversation.
  ///
  /// Returns true when the chat was ended. No-ops — no dialog — when no
  /// conversation is in progress, so callback-slot hosts can wire this to an
  /// icon that is always visible.
  static Future<bool> confirmAndEnd(BuildContext context,
      {String? locale}) async {
    if (EasyLiveChat.instance.phase.value != ChatPhase.chat) return false;
    final strings = ElcStrings.of(
        locale ?? EasyLiveChat.instance.widgetConfig.value?.locale);
    final answer = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.exitChatTitle, style: const TextStyle(fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.exitChatCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              strings.exitChatConfirm,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
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
          onPressed: () => confirmAndEnd(context, locale: locale),
        );
      },
    );
  }
}
