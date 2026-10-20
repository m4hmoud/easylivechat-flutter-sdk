/// Reactions on messages, as the visitor sees them.
///
/// A port of the visitor's half of `packages/shared/src/reactions.ts` and the
/// web widget's `lib/reactions.ts`. One reaction per person per message, the
/// way WhatsApp, Messenger and iMessage work: picking another emoji replaces
/// yours, picking the same one again takes it back.
///
/// The server sends the visitor's view only — on the team's messages their own
/// reaction, on theirs the team's — and never an agent's id or name, so there
/// is nothing here to hide. It arrives three ways, all read the same:
/// `reactions` on history rows, on `message:updated`, and on the live
/// `message:reactions` event, which carries a message's whole list after a
/// change. A visitor reacts to the team's messages only
/// ([ChatMessage.canReact]), over `message:react` on the widget socket.
///
/// A reaction is not a message: it moves no unread count and plays no chime.
library;

import 'package:meta/meta.dart';

/// Who reacted.
enum ReactionBy {
  /// Someone on the team (never named to the visitor).
  agent,

  /// The visitor themselves.
  customer;

  static ReactionBy? _fromWire(Object? w) => switch (w) {
        'agent' => ReactionBy.agent,
        'customer' => ReactionBy.customer,
        _ => null,
      };
}

/// One reaction on a message: an emoji and whose it is.
@immutable
class MessageReaction {
  final String emoji;
  final ReactionBy by;

  const MessageReaction({required this.emoji, required this.by});

  /// The visitor's own reaction.
  bool get isMine => by == ReactionBy.customer;

  /// Well-formed entries only — the list comes off the wire. An entry without
  /// an emoji, or with a `by` this SDK does not know, is dropped, never
  /// guessed at.
  static List<MessageReaction> listFrom(Object? raw) {
    if (raw is! List) return const [];
    final out = <MessageReaction>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final emoji = item['emoji'];
      final by = ReactionBy._fromWire(item['by']);
      if (emoji is! String || emoji.isEmpty || by == null) continue;
      out.add(MessageReaction(emoji: emoji, by: by));
    }
    return List<MessageReaction>.unmodifiable(out);
  }

  Map<String, String> toJson() => {'emoji': emoji, 'by': by.name};

  @override
  bool operator ==(Object other) =>
      other is MessageReaction && other.emoji == emoji && other.by == by;

  @override
  int get hashCode => Object.hash(emoji, by);

  @override
  String toString() => 'MessageReaction($emoji by ${by.name})';
}

/// The quick row, in this order, on every client: the web widget, the
/// dashboard, the apps.
const List<String> quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

final RegExp _vs16 = RegExp('️');

/// The same emoji, with or without the emoji-presentation selector — `❤` and
/// `❤️` are one reaction. Null or empty is never the same as anything.
bool sameEmoji(String? a, String? b) {
  if (a == null || b == null || a.isEmpty || b.isEmpty) return false;
  return a.replaceAll(_vs16, '') == b.replaceAll(_vs16, '');
}

/// One chip under a bubble: an emoji, how many reacted with it, and whether
/// the visitor's own reaction is among them.
@immutable
class ReactionGroup {
  /// The emoji as first used (`❤` and `❤️` count as one).
  final String emoji;
  final int count;

  /// The visitor's own reaction is in it — pressing the chip takes it back.
  final bool mine;

  const ReactionGroup(
      {required this.emoji, required this.count, required this.mine});

  @override
  bool operator ==(Object other) =>
      other is ReactionGroup &&
      other.emoji == emoji &&
      other.count == count &&
      other.mine == mine;

  @override
  int get hashCode => Object.hash(emoji, count, mine);

  @override
  String toString() => 'ReactionGroup($emoji ×$count${mine ? ', mine' : ''})';
}

/// The chips under a bubble: one per emoji, in the order they were first used.
List<ReactionGroup> groupReactions(List<MessageReaction> reactions) {
  final emoji = <String>[];
  final counts = <int>[];
  final mine = <bool>[];
  for (final r in reactions) {
    var i = emoji.indexWhere((e) => sameEmoji(e, r.emoji));
    if (i == -1) {
      emoji.add(r.emoji);
      counts.add(0);
      mine.add(false);
      i = emoji.length - 1;
    }
    counts[i]++;
    if (r.isMine) mine[i] = true;
  }
  return List<ReactionGroup>.unmodifiable([
    for (var i = 0; i < emoji.length; i++)
      ReactionGroup(emoji: emoji[i], count: counts[i], mine: mine[i]),
  ]);
}
