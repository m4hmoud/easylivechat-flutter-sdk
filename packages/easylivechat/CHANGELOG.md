# Changelog

## 0.1.56

- **Reply buttons.** `ChatMessage.botButtons` reads the buttons under a
  message from the team — a bot flow's, or ones an agent added
  (`metadata.bot`: `BotButtons.text` and `BotButton`s with ids) — and
  `EasyLiveChat.answerButton(message, buttonId:, label:)` answers one: the
  label goes as the visitor's own message with `reply: {messageId, buttonId}`
  beside it, so the server records the choice (the agents read "Chose: …").
  `buttonsOpen(messages, id)` says whether the question is still open (the
  newest thing anyone but the system said, and unanswered);
  `chosenButtonId(messages, id)` and `ChatMessage.botReply` say which button
  was chosen. Draw `BotButtons.text`, not `body`: the body repeats the words
  with a numbered menu for clients that predate buttons.
- **Richer cards.** A `MessageCardButton` can be a reply
  (`MessageCardButton.reply`, `isReply`, `replyId`; its `url` is empty and its
  `uri` null) — answer it with `answerButton`, using the label
  `ChatMessage.botButtons` gives that id. `ChatMessage.cards` reads one card
  or a carousel of up to ten (`metadata.cards`, `MessageCard.tryParseCarousel`);
  a carousel has no `card`, so a client that only reads `card` shows the body,
  which carries every card's words and links.

- **Identity verification.** `identify()` takes `userId` (your app's own id for
  the signed-in user) and `userHash` — `hex(HMAC_SHA256(identitySecret,
  userId))`, computed by YOUR backend; the secret never belongs in the app.
  Both travel as top-level `userId` / `userHash` on every `POST /session`, the
  silent resume as well as the start (and the token re-mint), and are omitted
  for anonymous visitors. With the workspace's verification off they are
  ignored; optional verifies a correct hash and never refuses; ENFORCED refuses
  a `userId` with a missing or wrong hash.
- **The refusal is typed.** A 403 `{ error: 'IDENTITY_NOT_VERIFIED', reason }`
  is an `EasyLiveChatError` with `isIdentityNotVerified`, the new
  `EasyLiveChatErrorCode.identityNotVerified`, and the server's `reason` kept on
  the new `EasyLiveChatError.reason` (`IdentityNotVerifiedReason.noSecret` /
  `noHash` / `badHash`; the dartdoc says what to fix for each). `open()` throws
  it for an identified visitor and it is emitted on `onError`. It is not an
  auth error, so no token re-mint loops on it.
- **A different person never resumes the last one's chat.** The SDK now
  remembers which `userId` this device's visitor was identified as
  (`StorageKeys.identifiedUserId`, cleared by `reset()`) and lines it up
  before every new session, the web widget's rule: anonymous → signed in keeps
  the visitor and their conversation, with the identity attached (re-minted at
  once when a chat is live); a different `userId`, or opening the chat with
  none after one was set, forgets the stored visitor, token, conversation and
  profile and starts a fresh visitorId — re-opening the chat as the new person
  if one was on screen, and unregistering the previous person's push token.
  Declare the identity on every launch before the chat opens.
- **`clearIdentity()`** — the signed-in user signed out, without tearing the
  SDK down (forgets the visitor when it carried a `userId`; `reset()` remains
  the full logout).
- `identify()` before `boot()` now works as its docs always said: it is held
  and applied by `boot()` (it used to throw a `StateError`).
- `open()` is single-flight: a call while one runs joins it, so two overlapping
  opens cannot start two sessions.
- **Help articles.** `searchHelp(q, {category, limit})`, `helpArticles()`
  (the top list), `getHelpArticle(id)` and `rateHelpArticle(id, helpful)` on
  `EasyLiveChat.instance`, over the public `GET /help/articles`, `GET
  /help/articles/:id`, `POST …/view` and `POST …/feedback` endpoints. No
  session or token needed. Typed, null-tolerant models: `HelpArticleList`
  (`enabled`, `articles`, `categories`), `HelpArticleSummary`, `HelpArticle`
  (markdown `body`, `locale`, `url`). Articles are asked for in
  `config.contentLocale`. `getHelpArticle` records the reading
  (fire-and-forget; a failed count is swallowed), and views and answers share
  one per-launch reading session id, which the server uses to dedupe views and
  count chats the articles saved.
- `WidgetConfigModel.helpArticlesEnabled` (false when an older server omits
  it) — gate any help UI on it.
- New error codes `RATE_LIMITED` (also the default for a bare 429) and
  `INVALID_PAYLOAD`.
- **Consent checkboxes in the pre-chat form.** A workspace can ask the visitor
  to agree to something — its privacy notice, usually — before a chat starts.
  It arrives as a pre-chat field of the new type `PreChatFieldType.consent`:
  `label` is the sentence the visitor agrees to (the tenant's own words, up to
  500 characters — render it verbatim and let it wrap) and the new
  `PreChatField.policyUrl` an optional privacy-policy link. The link is checked
  with the server's own rule (`cleanPolicyUrl`, public): only an `http:` /
  `https:` URL survives parsing, so a `javascript:` link never reaches a
  launcher. A type this SDK does not know still reads as `text`.
- **Opt-in: `EasyLiveChat.instance.supportsConsent`** (default false, may be set
  before `boot`). The server leaves consent fields out of the config for a
  client that does not ask (`GET /config?caps=consent`), so a host's own
  pre-chat form keeps working on this release exactly as before, and never
  draws a text box labelled "I agree to…". The prebuilt `easylivechat_ui`
  turns it on itself; a host with its own form turns it on once it renders
  consent fields.
- **`startSession(…, consents:)` and `submitOfflineForm(…, consents:)`**, the
  ids of the consent fields the visitor ticked — consent is never a `fields`
  value. With consent on and a pre-chat form shown, a new chat sends them with
  `capabilities: ['consent']`; a required one left unticked fails with the new
  `EasyLiveChatErrorCode.consentRequired` (`CONSENT_REQUIRED`) and its
  `fieldId` — checked locally first, and decoded from the server's 400 like
  any other field error. Nothing about consent is declared over a form fetched
  without consent fields, for a host-identified visitor (who never saw the
  form), or for an anonymous start, so the server cannot demand a box nobody
  drew. An older server ignores both the query parameter and the body fields.
- `PreChatField.isConsent`, `PreChatField.validateConsent(bool)`,
  `PreChatForm.consentFields` and `PreChatForm.missingConsent(ids)` mirror the
  server's `validateConsents` for a host's own form. `PreChatField.validate`
  returns null for a consent field — it has no value to check.

## 0.1.55

- **An agent's edited or unsent reply follows on the visitor's screen.** An
  agent may change or take back a reply for a few minutes after sending it.
  An edit arrives as `message:updated` and replaces the message by id, in
  place, with the new `body`; `ChatMessage.editedAt` (with `isEdited`) carries
  when it was changed, parsed from the socket and from history alike, and is
  null when absent or malformed rather than the epoch.
- An unsend arrives as the new `message:deleted` (`{ id, conversationId }`) and
  the message leaves `messages` with no placeholder, Telegram-style. It comes
  off `unreadCount` if it was counted there, and nothing that lands late — the
  read-receipt `message:updated` the server fans out seconds after a reply, a
  `message:new`, a reconnect backfill page — brings it back.
- **Unsent while away.** A message unsent while the visitor was not listening
  (socket down, app suspended or closed) comes down too: the session open or
  restore, every page of history and the reconnect backfill now carry
  `unsentIds` (`SessionResult.unsentIds`, `MessagePage.unsentIds`; empty from an
  older server), and any of those messages is removed and remembered.
- **`EasyLiveChat.instance.onMessageDeleted`**, a `Stream<DeletedMessage>` (`id`,
  `conversationId`) beside `onMessage`: fires once per id, for the live event
  and for each id a history response lists the first time the session hears of
  it. Use it to withdraw a notification or anything else you derived from the
  message; `messages` already drops it.

## 0.1.54

- **Background push for visitors.** `EasyLiveChat.instance.setPushToken(token,
  platform: 'ANDROID' | 'IOS')` registers the device that should be told when an
  agent replies while your app is closed. The SDK brings no push dependency of
  its own — you hand it the Firebase token your app already receives, so your
  project keeps one Firebase setup and one permission prompt.
- Call it as soon as you have a token, even before the visitor opens a chat: a
  registration can only be authenticated with a session token, so it is held and
  sent the moment there is one. Calling it again with a new token moves the
  registration (the old one is dropped first); `null` stops the notifications.
- The notification is always sent — nothing is suppressed server-side, because a
  connected socket is not a person looking at the screen. Skip it in your own
  notification handler when the chat is already on screen; your app is the only
  thing that knows.
- The payload carries `type: visitor.message`, `conversationId`, `messageId` and
  `tenantId` in `data`, so a tap can open the right conversation. Its title is
  the name the visitor already sees on the reply, and media without words
  announces itself ("Sent a photo") in the device's language.

## 0.1.53

- **Cards.** `ChatMessage.card` is the card an agent sent — an image, a title,
  a short text and up to three link buttons — as a `MessageCard` with
  `MessageCardButton`s. A card reached an SDK host only as its plain-text
  `body` (`Label: https://…` for every button), while the web widget and the
  dashboard drew the card. It is null for anything that is not a `CARD`
  message or whose `metadata.card` does not validate; render the body then,
  as before.
- The card is validated here with the server's own rules
  (`packages/shared/src/message-card.ts`), not trusted from the row: a title
  is required, whitespace is collapsed, fields are capped (title 80, text 300,
  label 30, three buttons, links 1000), and a button whose link is not
  `http:`/`https:` — above all `javascript:` — is dropped. `MessageCard.tryParse`
  and `MessageCard.isSafeUrl` are public for hosts that read cards themselves.
- A link is judged the way a browser reads it, not the way Dart's
  `Uri.parse` does: `Uri.parse` accepts `https://exa mple.com`, a port of
  `99999` and `https://999.1.1.1`, all of which the web refuses, and refuses
  `https:host`, which the web opens. Checked against the TypeScript validator
  on 6,000 generated cards (identical) and 12,000 generated links (identical
  but for host names in a non-Latin script, where the browser's full IDNA
  tables are approximated in the accepting direction). Whitespace is trimmed
  by JavaScript's rules as well — Dart's `String.trim()` also strips U+0085,
  which the server keeps. `MessageCardButton.uri` is the link as a browser
  would visit it, ready for `url_launcher`.
- **Quick replies.** `ChatMessage.quickReplies` is the one-tap answers a
  message offers — the workspace greeting's, or the AI assistant's Yes / No
  to a handover — and `quickRepliesOnOffer(messages)` says which message's are
  on offer right now, as a `QuickReplyOffer`. Only the newest message offers
  them, and only until the visitor or the team says anything else; a system
  notice doesn't count. It is the web widget's rule, ported with its tests, so
  a host's own UI and the prebuilt one agree on when the buttons are there. A
  tap is an ordinary `sendMessage` with the reply's exact text.

## 0.1.52

- `ChatMessage.isFromAssistant` is true only for replies the AI assistant wrote,
  read from the server's `metadata.assistant`. It was true for every `BOT`
  message, and the workspace's automatic greeting is a `BOT` message too — so
  greetings were treated as the assistant's, in workspaces that never switched
  the assistant on.

## 0.1.51

- The AI assistant, as the SDK sees it. The server has answered SDK visitors
  with the workspace's assistant since it shipped, through the same `/widgets`
  namespace as the web widget, but the SDK read none of what the widget reads
  about it:
  - `ChatMessage.isFromAssistant` — true for `BOT` messages, so a host can say
    a reply is automated wherever it draws one.
  - `EasyLiveChat.assistantCovers` — whether the assistant answers a message
    sent right now, from `GET /config` and every `workspace:availability`
    push. While it does, "we're offline, leave a message" is untrue.
  - `EasyLiveChat.assistantTyping` — `agentTyping` is the assistant composing.
    It sends an explicit stop when its reply is ready, and a reply can take ten
    seconds, so it no longer falls to the 4-second clear meant for a person:
    the typing row used to vanish halfway through the wait and leave the
    visitor watching a silent thread. Its reply arriving also clears it.
- `WidgetConfig.voiceNotesEnabled` — whether the workspace lets visitors send
  voice messages. False when the server omits it, so an older server keeps a
  host quiet rather than guessing.

## 0.1.50

- `GET /config` now carries the host's `channel`, so an app receives ITS
  inbox's configuration. Sessions have always carried it — the conversation
  landed in the right inbox — but the config request did not, so every
  per-channel override the server resolves from that parameter (welcome
  screen, queue and offline text, and now the pre-chat form) was invisible to
  native hosts: the dashboard showed an inbox configured one way and the app
  showed the workspace default, with nothing to explain the difference.
- Pairs with the server's per-inbox pre-chat form: a workspace can now ask a
  stranger on its website who they are while its app, which already knows its
  signed-in users, shows no form at all.

## 0.1.49

- A phone number passed to `identify()` now reaches the agent on every path.
  It was sent when a session was CREATED and dropped when one was RESUMED, so
  a visitor who already had a live conversation at the moment the host
  identified them — opened the chat from a login screen, signed in, came back
  — arrived with a name and no phone number. The server adopts whatever a
  resume carries; it could only adopt what was sent.
- `identify()`'s phone is also persisted now. `StoredProfile` held name and
  email but not phone, so the number lived in memory alone and was gone after
  an app restart until the host called `identify()` again. Older caches
  without the key decode as before.

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
