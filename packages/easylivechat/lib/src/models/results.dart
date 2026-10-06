import 'chat_message.dart';

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

  const SessionResult({
    this.token,
    this.conversationId,
    this.nextCursor,
    required this.resumed,
    required this.hasActiveConversation,
    this.messages = const [],
    this.unsentIds = const [],
  });

  factory SessionResult.fromJson(Map<String, dynamic> j) => SessionResult(
        token: j['token'] as String?,
        conversationId: j['conversationId'] as String?,
        nextCursor: j['nextCursor'] as String?,
        resumed: j['resumed'] == true,
        hasActiveConversation: j['hasActiveConversation'] == true,
        messages: _msgs(j['messages']),
        unsentIds: _ids(j['unsentIds']),
      );
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
