# Changelog

## 0.1.37

First pub.dev release. Previously consumed as a git dependency
(`flutter-sdk-v0.1.x` tags in the repository); version numbers continue that
series.

- Session boot / open / silent-resume with durable visitorId + JWT storage.
- Optimistic message sends with delivery status and server reconcile;
  attachment upload with progress; history paging.
- Realtime via Socket.IO: messages, typing, presence, close, transfer notices.
- SYSTEM notices carry structured `metadata.i18n` (key + params) so UIs can
  render them in the viewer's language; `ChatMessage.systemI18nKey` /
  `systemI18nParam` expose it (`copyWith` preserves it).
- `identify()` is authoritative for name/email/phone; client custom
  attributes via `EasyLiveChatConfig.attributes`; channel/inbox routing key.
- Pre-chat and post-chat (CSAT + questions) form models; `endChat()` reports
  whether a post-chat step follows.
