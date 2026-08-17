# Changelog

## 0.1.48

- `EasyLiveChat.reset()` — forget who this visitor is. Call it from the host
  app's logout path.
  `shutdown()` only clears memory; the durable `visitorId` survives it, so the
  next boot resolved the same server-side contact and resumed the same
  conversation. That is right for a returning customer and wrong for a
  signed-out one: the server keeps a name it already holds when a client sends
  none — an anonymous resume knows only the id and must not wipe a real
  customer's name — so the next person to open the chat on that device was
  greeted by the previous person's name and carried on inside their transcript.
  On a shared device, a restaurant tablet or a POS terminal, that is somebody
  else's identity. There was previously no API that could say otherwise.
  Drops the visitorId, token, cached profile and conversation id, then tears
  down. The next boot mints a fresh visitorId, so the server sees a new contact
  with nothing to resume: history comes back empty and the "load earlier"
  affordance correctly stays hidden. The transcript is not deleted — this
  abandons the identity, not the history, and agents keep the old thread.
  Takes an optional `storage:` so it still works when the SDK was never booted
  this session, which is the common case for a logout that never opened the
  chat. `StorageKeys.identity` lists the durable keys it clears, so a new one
  cannot be added and silently left behind.

## 0.1.47

- The agent's name and photo survive a `message:updated`. `senderName` /
  `senderAvatarUrl` / `senderJobTitle` are resolved by the server per viewer
  rather than stored on the message, and only some paths add them: a delivery
  receipt or a media re-host re-broadcasts the raw row without them. Applying
  one blanked a bubble that already had a face — and the visitor's own read
  receipt fires exactly that update seconds after every reply lands, so the
  agent appeared and then disappeared, coming back only on restart when history
  was read again.
  `ChatMessage.withIdentityFrom` inherits the identity a held row already has
  when the incoming one carries none, applied on both `message:updated` and the
  dedup path of `message:new`. A row that carries its own identity always keeps
  it, so a workspace with the avatar/name switches off still renders faceless.
  Fixed server-side too; this keeps an app already in the field correct against
  a server that has not been updated yet.

## 0.1.46

- Sent/read receipts for the visitor's own messages. `ChatMessage.readByAgent`
  parses the read flag the server already sends on history (`read` on the REST
  rows, `readByAgentAt` on the raw socket row), the `messages:read` event is now
  handled, and `SessionController.agentLastReadAt` — also on the public client —
  tracks how far into the thread an agent has read.
  `ChatMessage.receiptFor(agentLastReadAt)` turns the two into one of
  `MessageReceipt.{pending,sent,read,failed}`, so a host building its own thread
  renders the same states as the bundled UI instead of re-deriving them.
  The reporting half of this (telling the server the visitor is looking) already
  worked; only the display half was missing, so an SDK visitor could never see
  whether anyone had read them.
  The watermark is seeded from history as well as from live events, so a visitor
  whose messages were read while the app was closed sees that on the first frame
  rather than after the next agent action. It never moves backwards: the events
  are per-agent, and a colleague opening the thread later reports the moment
  *they* read it. It is not applied to a message still carrying its local `tmp-`
  id, whose timestamp is the device's rather than the server's — comparing the
  two across clock skew would show a message as read that nobody had opened.

## 0.1.45

- "Close chat" works on a second visit. The post-chat survey is offered once per
  VISIT, but the bookkeeping that remembers a chat was rated is keyed by
  conversation id — and a returning customer lands back in the thread they
  already have. Rating once therefore suppressed the survey for the life of the
  conversation: `endChat()` reported there was nothing left to ask, so the host
  UI dismissed its confirmation dialog and nothing happened at all.
  The clearing this needs was described in a doc comment and never implemented;
  it now runs when a new session marker appears in the thread, and is covered by
  a test. Keyed on the marker's identity rather than its presence, so a resume
  or a reconnect re-delivering the same marker cannot re-ask someone who has
  just answered.

## 0.1.44

- Activated the lints. `lints` has been a dev-dependency all along with no
  `analysis_options.yaml` to include it, so `dart analyze` ran with no rules
  and stayed green while pub.dev — which analyses every package against
  lints_core regardless of what the package configures — deducted points for
  issues nothing local could see. Now on `lints/recommended`, a superset of the
  set pub.dev scores.
- Fixed what that surfaced: the socket import used an upper-case `IO` prefix,
  and a test imported a library it already had through the public entry point.
  No behaviour change.

## 0.1.43

Documentation and packaging only — no behaviour change.

- The README's quick start called `EasyLiveChat.instance.sendText(...)`, which
  is not a method on this package. The advertised copy-paste did not compile.
  It is `sendMessage`.
- README rewritten for someone arriving from pub.dev: install, the
  `boot → open → phase` shape, a table of every listenable and what to render
  from it, `SendResult` semantics, the `hasOlderHistory` rule for paging, forms,
  errors, and troubleshooting. It now states plainly that the default
  `InMemoryStorage` is NOT durable and shows the interface to implement.
- `description` shortened to fit pana's 180-character limit, which the previous
  284-character one exceeded — that alone forfeited the pubspec points.
- Added `topics` for pub.dev discovery, and formatted with `dart format`.

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
