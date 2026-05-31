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

  static MessageDeliveryStatus fromWire(Object? w) => _parse(values, w, unknown);
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

/// Coarse kind of a rehosted attachment, for choosing a renderer.
enum AttachmentKind {
  image,
  video,
  audio,
  file;

  static AttachmentKind fromWire(Object? w) => _parse(values, w, file);
}
