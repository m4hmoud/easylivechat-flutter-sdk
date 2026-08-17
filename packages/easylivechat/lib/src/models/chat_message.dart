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

  /// The replying agent's photo and job title.
  ///
  /// Both are gated server-side by the workspace's "Show agent avatars" /
  /// "Show agent names" switches — they arrive null when the tenant has turned
  /// them off, so the UI can render whatever it is given without re-checking.
  /// [senderAvatarUrl] may be server-relative (`/uploads/...`); resolve it with
  /// `EasyLiveChat.instance.resolveUrl` before loading.
  final String? senderAvatarUrl;
  final String? senderJobTitle;

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

  /// An agent has opened this message and seen it.
  ///
  /// Only ever true for the visitor's own messages — it is the read half of
  /// their sent/read ticks. The server sends it two ways and both are parsed:
  /// `read` on the trimmed REST rows, `readByAgentAt` on the raw row that comes
  /// down the socket.
  ///
  /// A per-message flag AND a conversation-level watermark
  /// (`SessionController.agentLastReadAt`) both exist because they answer
  /// different questions: this one is history — true for messages already read
  /// when the thread loaded — while the watermark is what advances live, for
  /// messages already on screen when the agent opens the conversation.
  /// [receiptFor] folds the two together; prefer it over reading either alone.
  final bool readByAgent;

  final DateTime createdAt;

  /// True only for a locally-created optimistic message (id starts `tmp-`),
  /// before the server `message:send` ack / echo reconciles it.
  final bool isOptimistic;

  /// True when the optimistic send failed (ack `ok:false`) — UI shows retry.
  final bool failed;

  /// Raw server metadata. SYSTEM notices carry `i18n: {key, params}` here so
  /// the UI can render them in the viewer's language; [body] stays as the
  /// workspace-language fallback. Kept as a loose map — unknown shapes must
  /// never break decoding.
  final Map<String, dynamic>? metadata;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    this.tenantId,
    this.senderAgentId,
    this.senderName,
    this.senderAvatarUrl,
    this.senderJobTitle,
    this.body,
    required this.senderType,
    required this.contentType,
    this.attachmentUrls = const [],
    this.attachments = const [],
    this.deliveryStatus = MessageDeliveryStatus.sent,
    this.readByAgent = false,
    required this.createdAt,
    this.isOptimistic = false,
    this.failed = false,
    this.metadata,
  });

  /// The i18n key of a SYSTEM notice (`conversation.transferred`), or null.
  String? get systemI18nKey {
    final i18n = metadata?['i18n'];
    return i18n is Map ? i18n['key']?.toString() : null;
  }

  /// A post-chat survey the customer submitted (`metadata.postChat`), or null.
  ///
  /// Carried on the message so it sits where they submitted it: a thread the
  /// visitor keeps coming back to holds one per visit, where the old
  /// conversation-level field held one ever and pinned it to the bottom.
  Map<String, dynamic>? get postChat {
    final raw = metadata?['postChat'];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  /// A named param of the SYSTEM notice's i18n payload, or ''.
  String systemI18nParam(String name) {
    final i18n = metadata?['i18n'];
    if (i18n is! Map) return '';
    final params = i18n['params'];
    return params is Map ? (params[name] ?? '').toString() : '';
  }

  bool get isFromCustomer => senderType == SenderType.customer;
  bool get isFromAgent => senderType == SenderType.agent;

  /// What to show next to this message: nothing, or one of the four states of
  /// the visitor's own send.
  ///
  /// Null for anything the visitor did not write — an agent's message has no
  /// receipt to show the visitor, and a system notice has no sender at all.
  ///
  /// [agentLastReadAt] is the conversation-level watermark from
  /// `SessionController.agentLastReadAt`; pass null if you are not tracking it
  /// and only [readByAgent] decides.
  ///
  /// The watermark is deliberately not applied to a message still carrying its
  /// local `tmp-` id. Its timestamp came from the device clock while the
  /// watermark comes from the server's, and comparing the two across even a few
  /// seconds of skew would show a message as read that no one has opened. Once
  /// the server row replaces it — moments later — both sides are server time
  /// and the comparison is sound.
  MessageReceipt? receiptFor(DateTime? agentLastReadAt) {
    if (!isFromCustomer) return null;
    if (failed || deliveryStatus == MessageDeliveryStatus.failed) {
      return MessageReceipt.failed;
    }
    if (isOptimistic || deliveryStatus == MessageDeliveryStatus.pending) {
      return MessageReceipt.pending;
    }
    if (readByAgent || deliveryStatus == MessageDeliveryStatus.read) {
      return MessageReceipt.read;
    }
    if (!isLocalTemp &&
        agentLastReadAt != null &&
        !createdAt.isAfter(agentLastReadAt)) {
      return MessageReceipt.read;
    }
    return MessageReceipt.sent;
  }

  /// True while this row still carries its local `tmp-` id — an optimistic send
  /// not yet reconciled to a server id (even if already ack'd via `_markSent`,
  /// which clears [isOptimistic] but keeps the temp id). Used to reconcile the
  /// server echo in place instead of appending a duplicate.
  bool get isLocalTemp => id.startsWith('tmp-');

  bool get hasAttachments =>
      attachments.isNotEmpty || attachmentUrls.isNotEmpty;

  factory ChatMessage.fromAny(Map<String, dynamic> j) {
    final rawAttachments = j['attachments'];
    final attachments = <RehostedAttachment>[];
    if (rawAttachments is List) {
      for (final a in rawAttachments) {
        if (a is Map) {
          attachments
              .add(RehostedAttachment.fromJson(a.cast<String, dynamic>()));
        }
      }
    }
    final rawUrls = j['attachmentUrls'];
    final urls = <String>[
      if (rawUrls is List) ...rawUrls.map((e) => e.toString()),
    ];
    return ChatMessage(
      id: (j['id'] ?? '').toString(),
      conversationId:
          (j['conversationId'] ?? j['conversation_id'] ?? '').toString(),
      tenantId: j['tenantId']?.toString(),
      senderAgentId: j['senderAgentId']?.toString() ?? j['agentId']?.toString(),
      senderName: j['senderName'] as String? ?? j['agentName'] as String?,
      senderAvatarUrl:
          j['senderAvatarUrl'] as String? ?? j['agentAvatarUrl'] as String?,
      senderJobTitle: j['senderJobTitle'] as String?,
      body: j['body'] as String?,
      senderType: SenderType.fromWire(j['senderType']),
      contentType: MessageContentType.fromWire(j['contentType']),
      attachmentUrls: urls,
      attachments: attachments,
      deliveryStatus:
          MessageDeliveryStatus.fromWire(j['deliveryStatus'] ?? j['status']),
      // `read` on the trimmed REST rows; `readByAgentAt` on the raw Prisma row
      // from the socket, where a timestamp means read and null means not.
      readByAgent: j['read'] == true || j['readByAgentAt'] != null,
      createdAt: _parseDate(j['createdAt'] ?? j['created_at']),
      isOptimistic: false,
      metadata: j['metadata'] is Map
          ? (j['metadata'] as Map).cast<String, dynamic>()
          : null,
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

  /// True when this row says nothing about who sent it.
  bool get _hasNoIdentity =>
      senderName == null && senderAvatarUrl == null && senderJobTitle == null;

  /// Keep the face that a bare row would erase.
  ///
  /// `senderName` / `senderAvatarUrl` / `senderJobTitle` are not columns — the
  /// server resolves them per viewer and adds them on the way out. Only some
  /// paths do: `message:updated` (a delivery receipt, a media re-host) fans out
  /// the raw row, and since clients replace by id, applying it blanked the
  /// agent's name and photo on a bubble that already had them. The visitor's
  /// own read receipt fires that update seconds after every reply lands, so the
  /// face appeared and then vanished, and only came back on restart when
  /// history was read again.
  ///
  /// Fixed server-side; this keeps an app already in the field from being
  /// blanked by a server that hasn't been updated yet. Identity never changes
  /// for a given message, so inheriting it is always sound — and a row that
  /// does carry its own always keeps it.
  ChatMessage withIdentityFrom(ChatMessage previous) {
    if (!_hasNoIdentity || previous._hasNoIdentity) return this;
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      tenantId: tenantId,
      senderAgentId: senderAgentId ?? previous.senderAgentId,
      senderName: previous.senderName,
      senderAvatarUrl: previous.senderAvatarUrl,
      senderJobTitle: previous.senderJobTitle,
      body: body,
      senderType: senderType,
      contentType: contentType,
      attachmentUrls: attachmentUrls,
      attachments: attachments,
      deliveryStatus: deliveryStatus,
      readByAgent: readByAgent,
      createdAt: createdAt,
      isOptimistic: isOptimistic,
      failed: failed,
      metadata: metadata,
    );
  }

  ChatMessage copyWith({
    String? id,
    MessageDeliveryStatus? deliveryStatus,
    bool? readByAgent,
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
      senderAvatarUrl: senderAvatarUrl,
      senderJobTitle: senderJobTitle,
      body: body,
      senderType: senderType,
      contentType: contentType,
      attachmentUrls: attachmentUrls,
      attachments: attachments ?? this.attachments,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      readByAgent: readByAgent ?? this.readByAgent,
      createdAt: createdAt,
      isOptimistic: isOptimistic ?? this.isOptimistic,
      failed: failed ?? this.failed,
      metadata: metadata,
    );
  }

  static DateTime _parseDate(Object? v) {
    if (v is String) {
      final parsed = DateTime.tryParse(v);
      if (parsed != null) return parsed.toLocal();
    }
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v).toLocal();
    // Deterministic fallback for malformed/missing timestamps: the epoch (sorts
    // to the top and stays put on re-parse). NEVER DateTime.now() — that is
    // non-deterministic and would re-order the row on every message:updated.
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}
