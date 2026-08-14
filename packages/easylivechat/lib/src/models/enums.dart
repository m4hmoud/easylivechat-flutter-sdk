/// Wire enums mirroring the server's Prisma enums.
///
/// Every enum carries an [unknown] member and a lenient `fromWire` parser:
/// the `/widgets` socket delivers the **raw Prisma row**, so a future server
/// enum value must never crash the client — it degrades to [unknown].
library;

/// Case-insensitive lookup of a wire string against an enum's `name`,
/// falling back to [fallback] (an `unknown` member).
T _parse<T extends Enum>(Iterable<T> values, Object? wire, T fallback) {
  if (wire == null) return fallback;
  final s = wire.toString().toLowerCase().trim();
  for (final v in values) {
    if (v.name.toLowerCase() == s) return v;
  }
  return fallback;
}

/// What a visitor is shown about the fate of their own message.
///
/// Not a wire enum — there is no server field with these four values. It is the
/// answer `ChatMessage.receiptFor` computes from the delivery status, the
/// optimistic flags and the conversation's read watermark, so that every host
/// renders the same four states from one rule instead of each re-deriving them.
///
/// There is no `delivered` here on purpose. The other channels get that from a
/// provider webhook (WhatsApp, Telegram); a message to an SDK visitor is stored
/// by our own server, so "stored" and "delivered" are the same instant and a
/// third tick state would be a distinction the visitor could never observe.
enum MessageReceipt {
  /// Written locally, not yet acknowledged by the server.
  pending,

  /// Stored server-side. No agent has opened it yet.
  sent,

  /// An agent has opened the conversation and seen it.
  read,

  /// The send failed and can be retried.
  failed,
}

/// Who sent a message. Server (Prisma `SenderType`): AGENT | CUSTOMER | SYSTEM | BOT.
enum SenderType {
  agent,
  customer,
  system,
  bot,
  unknown;

  static SenderType fromWire(Object? w) => _parse(values, w, unknown);
}

/// Message body kind. Server (Prisma `MessageContentType`).
enum MessageContentType {
  text,
  image,
  file,
  audio,
  video,
  sticker,
  location,
  template,
  event,
  card,
  unknown;

  static MessageContentType fromWire(Object? w) => _parse(values, w, unknown);
}

/// Delivery state of a message.
enum MessageDeliveryStatus {
  pending,
  sent,
  delivered,
  read,
  failed,
  unknown;

  static MessageDeliveryStatus fromWire(Object? w) =>
      _parse(values, w, unknown);
}

/// Conversation lifecycle. Server (Prisma `ConversationStatus`).
enum ConversationStatus {
  open,
  pending,
  closed,
  snoozed,
  archived,
  unknown;

  static ConversationStatus fromWire(Object? w) => _parse(values, w, unknown);
}

/// Originating channel of a conversation/message.
enum ChannelSource {
  widget,
  whatsapp,
  messenger,
  telegram,
  email,
  instagram,
  unknown;

  static ChannelSource fromWire(Object? w) => _parse(values, w, unknown);
}

/// Layout direction derived from `WidgetConfig.direction` (ar/ku => rtl).
enum LocaleDirection {
  ltr,
  rtl;

  static LocaleDirection fromWire(Object? w) =>
      w?.toString().toLowerCase().trim() == 'rtl' ? rtl : ltr;
}

/// Pre-chat form field input type (`packages/shared` PreChatField.type).
enum PreChatFieldType {
  text,
  email,
  phone,
  number,
  textarea,
  select;

  static PreChatFieldType fromWire(Object? w) => _parse(values, w, text);
}

/// Post-chat form field types. A superset of [PreChatFieldType]: the survey
/// shown after a conversation ends can also ask for a CSAT `rating` and a
/// yes/no `checkbox`.
enum PostChatFieldType {
  text,
  email,
  phone,
  number,
  textarea,
  select,
  checkbox,
  rating;

  static PostChatFieldType fromWire(Object? w) => _parse(values, w, text);
}

/// Coarse kind of a rehosted attachment, for choosing a renderer.
enum AttachmentKind {
  image,
  video,
  audio,
  file;

  static AttachmentKind fromWire(Object? w) => _parse(values, w, file);
}
