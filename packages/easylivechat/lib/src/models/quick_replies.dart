/// Quick replies: tappable answers under a message from the team.
///
/// They come from the workspace's greeting (Widget settings) and from the AI
/// assistant's "shall I pass you to the team?" (a one-tap Yes / No). A tap sends
/// the text as the visitor's own message — through `EasyLiveChat.sendMessage`,
/// like anything typed.
///
/// A port of `apps/widget/src/lib/quick-replies.ts`, so the web widget, the
/// prebuilt UI and a host's own UI all offer them under the same message.
library;

import 'package:meta/meta.dart';

import 'chat_message.dart';
import 'enums.dart';

/// The quick replies on offer right now, and the message they belong under.
@immutable
class QuickReplyOffer {
  /// The [ChatMessage.id] to draw them under.
  final String messageId;

  /// Never empty, never blank, in the order the server sent them. Send one
  /// exactly as it is.
  final List<String> replies;

  const QuickReplyOffer({required this.messageId, required this.replies});

  @override
  bool operator ==(Object other) {
    if (other is! QuickReplyOffer ||
        other.messageId != messageId ||
        other.replies.length != replies.length) {
      return false;
    }
    for (var i = 0; i < replies.length; i++) {
      if (other.replies[i] != replies[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(messageId, Object.hashAll(replies));

  @override
  String toString() => 'QuickReplyOffer($messageId, $replies)';
}

/// The message whose quick replies are on offer right now, or null.
///
/// [messages] is oldest first, as `EasyLiveChat.instance.messages` holds them.
///
/// Only the newest message can offer them. Once anything else is said — the
/// visitor answered (with a tap or by typing), or someone from the team wrote
/// again — the question they answered has moved on, and buttons left above the
/// newer message would send an answer to something no longer being asked. For
/// the handover offer that is worse than stale: a late "Yes" would read as a
/// brand-new message. System notices (a transfer line) don't count as moving on.
QuickReplyOffer? quickRepliesOnOffer(List<ChatMessage> messages) {
  for (var i = messages.length - 1; i >= 0; i--) {
    final m = messages[i];
    if (m.senderType == SenderType.system) continue;
    if (m.senderType == SenderType.customer) return null;
    final replies = m.quickReplies;
    return replies.isEmpty
        ? null
        : QuickReplyOffer(messageId: m.id, replies: replies);
  }
  return null;
}
