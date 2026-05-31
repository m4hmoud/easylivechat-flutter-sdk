import 'enums.dart';

/// A rehosted attachment (rich shape the server fills in once the media
/// re-host worker runs; arrives via `message:updated`). Prefer this over the
/// flat [ChatMessage.attachmentUrls] when present.
class RehostedAttachment {
  final String url;
  final String? mime;
  final String? filename;
  final int? size;
  final AttachmentKind kind;

  const RehostedAttachment({
    required this.url,
    this.mime,
    this.filename,
    this.size,
    required this.kind,
  });

  factory RehostedAttachment.fromJson(Map<String, dynamic> j) {
    final mime = j['mime'] as String? ?? j['mimeType'] as String?;
    return RehostedAttachment(
      url: (j['url'] ?? '').toString(),
      mime: mime,
      filename: j['filename'] as String? ?? j['name'] as String?,
      size: (j['size'] as num?)?.toInt(),
      kind: j['kind'] != null
          ? AttachmentKind.fromWire(j['kind'])
          : _kindFromMime(mime),
    );
  }

  static AttachmentKind _kindFromMime(String? mime) {
    final m = (mime ?? '').toLowerCase();
    if (m.startsWith('image/')) return AttachmentKind.image;
    if (m.startsWith('video/')) return AttachmentKind.video;
    if (m.startsWith('audio/')) return AttachmentKind.audio;
    return AttachmentKind.file;
  }

  /// True for non-HTTP placeholders like `wa:media:{id}` that cannot be
  /// rendered as a real URL yet — show an inert "media unavailable" chip.
  bool get isResolvable =>
      url.startsWith('http://') ||
      url.startsWith('https://') ||
      url.startsWith('/');
}

/// One message in a conversation.
///
/// [ChatMessage.fromAny] is intentionally lenient: it parses **both** the
/// trimmed REST shape (`GET /messages`, `/session`) and the **raw Prisma row**
/// delivered over the `/widgets` socket (`message:new` / `message:updated`),
/// tolerating extra/unknown fields and future enum values.
class ChatMessage {
  final String id;
  final String conversationId;
  final String? tenantId;
  final String? senderAgentId;
  final String? senderName;

  /// Body text. Note: attachment-only messages come back as the empty string
  /// `''` (not null) — relevant for optimistic reconcile-by-body matching.
  final String? body;

  final SenderType senderType;
  final MessageContentType contentType;

  /// Flat URL list — always present (legacy + current). May contain
  /// server-relative paths (`/uploads/...`) or placeholders (`wa:media:{id}`).
  final List<String> attachmentUrls;

  /// Rich attachments — preferred when non-empty (post re-host).
  final List<RehostedAttachment> attachments;

  final MessageDeliveryStatus deliveryStatus;
  final DateTime createdAt;

  /// True only for a locally-created optimistic message (id starts `tmp-`),
  /// before the server `message:send` ack / echo reconciles it.
  final bool isOptimistic;

  /// True when the optimistic send failed (ack `ok:false`) — UI shows retry.
  final bool failed;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    this.tenantId,
    this.senderAgentId,
    this.senderName,
    this.body,
    required this.senderType,
    required this.contentType,
    this.attachmentUrls = const [],
    this.attachments = const [],
    this.deliveryStatus = MessageDeliveryStatus.sent,
    required this.createdAt,
    this.isOptimistic = false,
    this.failed = false,
  });

  bool get isFromCustomer => senderType == SenderType.customer;
  bool get isFromAgent => senderType == SenderType.agent;
  bool get hasAttachments => attachments.isNotEmpty || attachmentUrls.isNotEmpty;

  factory ChatMessage.fromAny(Map<String, dynamic> j) {
    final rawAttachments = j['attachments'];
    final attachments = <RehostedAttachment>[];
    if (rawAttachments is List) {
      for (final a in rawAttachments) {
        if (a is Map) {
          attachments.add(RehostedAttachment.fromJson(a.cast<String, dynamic>()));
        }
      }
    }
    final rawUrls = j['attachmentUrls'];
    final urls = <String>[
      if (rawUrls is List) ...rawUrls.map((e) => e.toString()),
    ];
    return ChatMessage(
      id: (j['id'] ?? '').toString(),
      conversationId: (j['conversationId'] ?? j['conversation_id'] ?? '').toString(),
      tenantId: j['tenantId']?.toString(),
      senderAgentId: j['senderAgentId']?.toString() ?? j['agentId']?.toString(),
      senderName: j['senderName'] as String? ?? j['agentName'] as String?,
      body: j['body'] as String?,
      senderType: SenderType.fromWire(j['senderType']),
      contentType: MessageContentType.fromWire(j['contentType']),
      attachmentUrls: urls,
      attachments: attachments,
      deliveryStatus: MessageDeliveryStatus.fromWire(j['deliveryStatus'] ?? j['status']),
      createdAt: _parseDate(j['createdAt'] ?? j['created_at']),
      isOptimistic: false,
    );
  }

  /// Build a local optimistic message (shown immediately on send).
  factory ChatMessage.optimistic({
    required String tempId,
    required String conversationId,
    required String body,
    List<String> attachmentUrls = const [],
    required DateTime createdAt,
  }) {
    return ChatMessage(
      id: tempId,
      conversationId: conversationId,
      body: body,
      senderType: SenderType.customer,
      contentType: attachmentUrls.isNotEmpty && body.trim().isEmpty
          ? MessageContentType.file
          : MessageContentType.text,
      attachmentUrls: attachmentUrls,
      deliveryStatus: MessageDeliveryStatus.pending,
      createdAt: createdAt,
      isOptimistic: true,
    );
  }

  ChatMessage copyWith({
    String? id,
    MessageDeliveryStatus? deliveryStatus,
    bool? isOptimistic,
    bool? failed,
    List<RehostedAttachment>? attachments,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      conversationId: conversationId,
      tenantId: tenantId,
      senderAgentId: senderAgentId,
      senderName: senderName,
      body: body,
      senderType: senderType,
      contentType: contentType,
      attachmentUrls: attachmentUrls,
      attachments: attachments ?? this.attachments,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      createdAt: createdAt,
      isOptimistic: isOptimistic ?? this.isOptimistic,
      failed: failed ?? this.failed,
    );
  }

  static DateTime _parseDate(Object? v) {
    if (v is String) return DateTime.tryParse(v)?.toLocal() ?? DateTime.now();
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v).toLocal();
    return DateTime.now();
  }
}
