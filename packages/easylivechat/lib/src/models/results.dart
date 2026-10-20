import 'chat_message.dart';
import 'reactions.dart';

/// Result of `POST /:slug/session`. On a `resumeOnly` call with no active
/// conversation, [token] is null and [hasActiveConversation] is false.
class SessionResult {
  final String? token;
  final String? conversationId;
  final String? nextCursor;
  final bool resumed;
  final bool hasActiveConversation;
  final List<ChatMessage> messages;

  /// Messages an agent unsent in this conversation lately — see
  /// [MessagePage.unsentIds].
  final List<String> unsentIds;

  /// Where the visitor stands while they wait for a person (`queued`), or
  /// null when nobody is waiting — see [QueueStatus].
  final QueueStatus? queue;

  const SessionResult({
    this.token,
    this.conversationId,
    this.nextCursor,
    required this.resumed,
    required this.hasActiveConversation,
    this.messages = const [],
    this.unsentIds = const [],
    this.queue,
  });

  factory SessionResult.fromJson(Map<String, dynamic> j) => SessionResult(
        token: j['token'] as String?,
        conversationId: j['conversationId'] as String?,
        nextCursor: j['nextCursor'] as String?,
        resumed: j['resumed'] == true,
        hasActiveConversation: j['hasActiveConversation'] == true,
        messages: _msgs(j['messages']),
        unsentIds: _ids(j['unsentIds']),
        queue: j['queued'] == true
            ? QueueStatus._read(j['queuePosition'], j['queueMinutes'],
                j['queueInfoText'])
            : null,
      );
}

/// The visitor is waiting for a person — the web widget's queue notice.
///
/// Waiting is a notice above the conversation, not a screen of its own: the
/// visitor reads what has been said and writes their question while they
/// wait. The server says so on the session (`queued`) and moves it on with
/// `queue:update`; anything that means "somebody is here now" ends it — the
/// chat being assigned, a team message arriving, someone starting to type.
/// The assistant covering does not queue anyone: it answers.
class QueueStatus {
  /// Place in the queue, 1 for next; 0 when the server could not say.
  final int position;

  /// The expected wait in minutes; meaningful only with a [position].
  final int minutes;

  /// The workspace's queue notice in the visitor's language, with their name
  /// and place already filled in by the server. May be empty.
  final String text;

  const QueueStatus({this.position = 0, this.minutes = 0, this.text = ''});

  static QueueStatus _read(Object? position, Object? minutes, Object? text) =>
      QueueStatus(
        position: position is num && position > 0 ? position.toInt() : 0,
        minutes: minutes is num && minutes > 0 ? minutes.round() : 0,
        text: text is String ? text.trim() : '',
      );

  /// `queue:update` — null when it says the chat was assigned (the wait is
  /// over).
  static QueueStatus? fromUpdate(Map<String, dynamic> j) => j['assigned'] == true
      ? null
      : _read(j['position'], j['minutes'], j['text']);

  @override
  bool operator ==(Object other) =>
      other is QueueStatus &&
      other.position == position &&
      other.minutes == minutes &&
      other.text == text;

  @override
  int get hashCode => Object.hash(position, minutes, text);

  @override
  String toString() => 'QueueStatus(#$position, ~$minutes min, "$text")';
}

/// A page of history from `GET /:slug/messages` (oldest→newest). [nextCursor]
/// is the id of the *oldest* message in the page; pass it as `?cursor=` to load
/// the previous (older) page; null when there is no more history.
class MessagePage {
  final List<ChatMessage> messages;
  final String? nextCursor;

  /// Messages an agent unsent in this conversation lately (the server keeps a
  /// week of them). A client holding any of them takes them down — that is how
  /// a visitor who was away when one went stops seeing it. Empty from a server
  /// that predates the field.
  final List<String> unsentIds;

  const MessagePage({
    required this.messages,
    this.nextCursor,
    this.unsentIds = const [],
  });

  factory MessagePage.fromJson(Map<String, dynamic> j) => MessagePage(
        messages: _msgs(j['messages']),
        nextCursor: j['nextCursor'] as String?,
        unsentIds: _ids(j['unsentIds']),
      );
}

/// One uploaded file as returned (in an array) by `POST /api/uploads`.
/// Note the field is `mimeType` (not `mime`); [url] is server-relative.
class UploadedFile {
  final String url;
  final String? filename;
  final String? mimeType;
  final int? size;

  const UploadedFile({
    required this.url,
    this.filename,
    this.mimeType,
    this.size,
  });

  factory UploadedFile.fromJson(Map<String, dynamic> j) => UploadedFile(
        url: (j['url'] ?? '').toString(),
        filename: j['filename'] as String?,
        mimeType: j['mimeType'] as String?,
        size: (j['size'] as num?)?.toInt(),
      );
}

/// Result of `POST /:slug/conversations/:id/feedback` (CSAT).
class FeedbackResult {
  final bool ok;
  final int rating;
  final String? comment;
  final DateTime? ratedAt;

  const FeedbackResult({
    required this.ok,
    required this.rating,
    this.comment,
    this.ratedAt,
  });

  factory FeedbackResult.fromJson(Map<String, dynamic> j) => FeedbackResult(
        ok: j['ok'] != false,
        rating: (j['rating'] as num?)?.toInt() ?? 0,
        comment: j['comment'] as String?,
        // Localize for display consistency with ChatMessage timestamps.
        ratedAt: j['ratedAt'] is String
            ? DateTime.tryParse(j['ratedAt'] as String)?.toLocal()
            : null,
      );
}

/// A message an agent unsent — see `EasyLiveChat.onMessageDeleted`.
///
/// Arrives live (`message:deleted`) or, for one that went while this client
/// was not listening, from the `unsentIds` a history response carries.
class DeletedMessage {
  /// The unsent message's id.
  final String id;

  /// The conversation it was in.
  final String conversationId;

  const DeletedMessage({required this.id, required this.conversationId});

  @override
  bool operator ==(Object other) =>
      other is DeletedMessage &&
      other.id == id &&
      other.conversationId == conversationId;

  @override
  int get hashCode => Object.hash(id, conversationId);

  @override
  String toString() => 'DeletedMessage($id in $conversationId)';
}

/// A proactive outreach pushed by an agent (`widget:proactive-message`).
class ProactiveMessage {
  final String conversationId;
  final String message;

  const ProactiveMessage({required this.conversationId, required this.message});

  factory ProactiveMessage.fromJson(Map<String, dynamic> j) => ProactiveMessage(
        conversationId: (j['conversationId'] ?? '').toString(),
        message: (j['message'] ?? '').toString(),
      );
}

/// The visitor's locally-cached identity/profile, persisted across launches.
///
/// [phone] is here for the same reason [name] and [email] are: `identify()`
/// used to keep it in memory only, so it survived neither an app restart nor
/// the resume path — a host that named a signed-in customer got the name
/// through and the phone nowhere. A key absent from an older cache simply
/// decodes to null.
class StoredProfile {
  final String? name;
  final String? email;
  final String? phone;
  final Map<String, String>? preChat;

  const StoredProfile({this.name, this.email, this.phone, this.preChat});

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (preChat != null) 'preChat': preChat,
      };

  factory StoredProfile.fromJson(Map<String, dynamic> j) => StoredProfile(
        name: j['name'] as String?,
        email: j['email'] as String?,
        phone: j['phone'] as String?,
        preChat: (j['preChat'] is Map)
            ? (j['preChat'] as Map)
                .map((k, v) => MapEntry(k.toString(), v.toString()))
            : null,
      );
}

/// What `GET /:slug/visitor-email` says about emailing the visitor: the
/// address on their contact — masked, because the device may not be theirs —
/// and whether the workspace offers each email.
class VisitorEmailState {
  /// `a•••@example.com`, or null when the contact has no address.
  final String? emailHint;

  /// The address asked not to be written to; the server will refuse to.
  final bool unsubscribed;

  /// "Email me this chat" is on offer.
  final bool transcriptEnabled;

  /// "Get the reply by email" is on offer.
  final bool replyEmailEnabled;

  const VisitorEmailState({
    this.emailHint,
    this.unsubscribed = false,
    this.transcriptEnabled = false,
    this.replyEmailEnabled = false,
  });

  factory VisitorEmailState.fromJson(Map<String, dynamic> j) {
    final hint = j['emailHint'];
    return VisitorEmailState(
      emailHint: hint is String && hint.trim().isNotEmpty ? hint : null,
      unsubscribed: j['unsubscribed'] == true,
      // Absent on an older server, which offers neither.
      transcriptEnabled: j['transcriptEnabled'] == true,
      replyEmailEnabled: j['replyEmailEnabled'] == true,
    );
  }
}

/// Socket ack for `message:send`.
class SendAck {
  final bool ok;
  final String? messageId;
  final String? error;
  const SendAck({required this.ok, this.messageId, this.error});

  factory SendAck.fromAck(Object? raw) {
    if (raw is Map) {
      final m = raw.cast<String, dynamic>();
      return SendAck(
        ok: m['ok'] != false,
        messageId: m['messageId'] as String?,
        error: m['error'] as String?,
      );
    }
    return const SendAck(ok: false, error: 'NO_ACK');
  }
}

/// `message:reactions` — one message's reactions after someone changed them,
/// as the visitor may see them (the whole list, not the change).
class ReactionsEvent {
  final String messageId;

  /// The conversation it is in; empty when the server left it out.
  final String conversationId;
  final List<MessageReaction> reactions;

  const ReactionsEvent({
    required this.messageId,
    this.conversationId = '',
    required this.reactions,
  });

  /// Null for a payload that names no message.
  static ReactionsEvent? tryParse(Map<String, dynamic> j) {
    final id = j['messageId'];
    if (id is! String || id.isEmpty) return null;
    return ReactionsEvent(
      messageId: id,
      conversationId: (j['conversationId'] ?? '').toString(),
      reactions: MessageReaction.listFrom(j['reactions']),
    );
  }
}

/// Socket ack for `message:react`: `{ ok: true, reactions }` — the message's
/// list as the visitor sees it once the server applied theirs — or
/// `{ ok: false, error }` (`NOT_REACTABLE`, `INVALID_EMOJI`,
/// `MESSAGE_NOT_FOUND`, `RATE_LIMITED` past twenty in ten seconds, `FAILED`).
class ReactionAck {
  final bool ok;
  final List<MessageReaction> reactions;
  final String? error;

  const ReactionAck(
      {required this.ok, this.reactions = const [], this.error});

  factory ReactionAck.fromAck(Object? raw) {
    if (raw is Map) {
      return ReactionAck(
        // Truthy only, as the web reads it: an ack that does not say ok
        // is not one.
        ok: raw['ok'] == true,
        reactions: MessageReaction.listFrom(raw['reactions']),
        error: raw['error']?.toString(),
      );
    }
    return const ReactionAck(ok: false, error: 'NO_ACK');
  }
}

/// Returned by [EasyLiveChat.sendMessage]: the optimistic message shown
/// immediately, plus a future resolving to the server message id on ack.
class SendResult {
  final ChatMessage optimistic;
  final Future<String> serverMessageId;
  const SendResult({required this.optimistic, required this.serverMessageId});
}

/// The ids in a response's `unsentIds`; anything that is not one is dropped,
/// and a missing field reads as none.
List<String> _ids(Object? raw) {
  if (raw is! List) return const [];
  return List<String>.unmodifiable(
      raw.whereType<String>().where((id) => id.isNotEmpty));
}

List<ChatMessage> _msgs(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((m) => ChatMessage.fromAny(m.cast<String, dynamic>()))
      .toList();
}
