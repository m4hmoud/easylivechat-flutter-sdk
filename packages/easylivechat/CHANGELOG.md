# Changelog

## 0.1.42

- A resumed chat opens on the visit it is in. A returning customer lands back
  in the thread they already have, which can span months and half a dozen
  separate problems, so opening it handed them all of it at once and buried
  what they came back for. The session request now asks for
  `historyScope: 'session'`; the first page starts at the session boundary the
  transcript is already bracketed by, and earlier visits stay behind the
  cursor. Paging deliberately crosses that boundary — only the first page is
  scoped.
- New `EasyLiveChat.hasOlderHistory`: whether the server says history sits
  behind the loaded page. A brand-new conversation reports false. Hosts that
  draw their own "load earlier" affordance should read this instead of assuming
  there is always more, since a scoped first page can no longer be told apart
  from a complete one by looking at what arrived.
- Older servers ignore `historyScope` and return the whole thread as before, so
  this is safe against a backend that has not been updated.

## 0.1.41

- The post-chat survey is offered once per VISIT, not once per conversation.
  `_ratedConversations` is keyed by conversation id, and a returning customer
  now lands back in the thread they already have — so rating a chat once
  suppressed the survey for every later visit: the visitor ended a second chat
  and it simply closed, having never been asked. Cleared when the server
  announces a new session in that thread.

## 0.1.40

- `ChatMessage.postChat` reads a post-chat survey the visitor submitted out of
  `metadata.postChat`, so a thread can draw the submission at the point it was
  filled in. The getter has been in the source since the survey work, but no
  release carried it — which left `easylivechat_ui` 0.1.44 calling into a core
  that did not have it.

## 0.1.39

- Read receipts: `markRead()` now also reports to the server, so an agent's
  delivery ticks turn green once the visitor is looking at the thread. Every
  other channel learns this from a provider webhook; an SDK conversation had no
  receipt path at all, leaving agent messages on a permanent single check with
  no way to tell read from ignored.

## 0.1.38

- Repository moved to a dedicated public home:
  [m4hmoud/easylivechat-flutter-sdk](https://github.com/m4hmoud/easylivechat-flutter-sdk).
  No code changes.

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
