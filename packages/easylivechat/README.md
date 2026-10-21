# easylivechat

Headless Dart client for [EasyLiveChat](https://livechattools.com) real-time
customer support. Sessions, messages, attachments, typing, presence and
server-driven forms — exposed as plain `ValueListenable`s, with **no widgets**,
so you can build the chat UI your design system asks for.

**Want the UI built for you?** Use
[`easylivechat_ui`](https://pub.dev/packages/easylivechat_ui) instead — a
launcher bubble and full chat screen in a few lines. It re-exports this
package, so you would not depend on both.

```yaml
dependencies:
  easylivechat: ^0.1.57
```

or

```sh
flutter pub add easylivechat
```

## Quick start

```dart
import 'package:easylivechat/easylivechat.dart';

Future<void> main() async {
  await EasyLiveChat.instance.boot(
    const EasyLiveChatConfig(
      apiBase: 'https://api.livechattools.com',
      tenantSlug: 'your-workspace',
    ),
    // See "Storage" below — the default is in-memory and NOT durable.
    storage: InMemoryStorage(),
  );

  // Optional: skip the pre-chat form for a user you already know. Add
  // userId + userHash to verify who they are (see "Identity verification").
  EasyLiveChat.instance.identify(name: 'Jane', email: 'jane@example.com');

  // Start a new conversation, or resume the open one with its history.
  await EasyLiveChat.instance.open();

  EasyLiveChat.instance.messages.addListener(() {
    for (final m in EasyLiveChat.instance.messages.value) {
      print('${m.senderType}: ${m.body}');
    }
  });

  EasyLiveChat.instance.sendMessage('Hi there');
}
```

`tenantSlug` is your workspace slug — the one in your dashboard URL
(`your-workspace.livechattools.com`). A runnable version, including binding
every listenable, is in [`example/main.dart`](example/main.dart).

## How it fits together

`EasyLiveChat.instance` is a singleton facade over a state machine. You drive
it with a handful of methods and render from its listenables — it never calls
into your UI.

```
boot()  →  open()  →  [prechat] → chat → feedback
                          ↑                  │
                          └── endChat() ─────┘
```

| Listenable | Type | Use it for |
|---|---|---|
| `phase` | `ChatPhase` | Which screen to show |
| `messages` | `List<ChatMessage>` | The thread |
| `agentTyping` | `bool` | Typing indicator |
| `unreadCount` | `int` | Badge |
| `connection` | `ConnectionState` | "Reconnecting…" |
| `widgetConfig` | `WidgetConfigModel?` | Colours, copy, forms from the dashboard |
| `isOpen` / `visitorMode` | `bool` / `String` | Whether the workspace is taking chats |

`ChatPhase` is `idle`, `loading`, `resuming`, `prechat`, `chat`, `feedback`,
`offline`. `ConnectionState` is `disconnected`, `connecting`, `connected`,
`reconnecting`.

## Sending

```dart
final result = EasyLiveChat.instance.sendMessage('Hello');
```

Returns immediately with a `SendResult`. Its `optimistic` message is already in
`messages` so you can render it at once; `serverMessageId` completes when the
server confirms. A send that fails is marked failed rather than vanishing —
`resend(message)` retries it.

Attachments are a two-step: upload, then send the returned URLs.

```dart
EasyLiveChat.instance.sendMessage('', attachmentUrls: [url]);
```

## History

`open()` gives you the current visit. A returning customer's earlier visits sit
behind a cursor rather than landing on screen — so ask, don't assume:

```dart
if (EasyLiveChat.instance.hasOlderHistory) {
  final page = await EasyLiveChat.instance.loadOlderMessages();
}
```

`hasOlderHistory` is the only reliable signal: a scoped first page cannot be
told from a complete one by looking at what arrived.

## Message events

`messages` is the thread as it stands; two streams tell you what happened to it,
for anything you derive from messages yourself (a notification, a preview, a
copy in your own store):

```dart
EasyLiveChat.instance.onMessage.listen((m) { /* a new message arrived */ });

EasyLiveChat.instance.onMessageDeleted.listen((d) {
  // d.id, d.conversationId — an agent unsent this message.
  notifications.cancelFor(messageId: d.id);
});
```

An agent may edit or unsend a reply for a few minutes after sending it. An
edit replaces the message in `messages` by id, in place, with the new `body`
and `editedAt` set (`isEdited`) — show "edited" beside the time. An unsent
message leaves `messages` with no placeholder, and `onMessageDeleted` fires
once per id: for the live event, and for every id a history response lists as
unsent the first time the session hears of it — so a message unsent while the
app was closed still comes down, and the stream can name one this device only
ever saw as a push notification.

## Forms

Both forms are authored in the dashboard and arrive in
`widgetConfig.value` — render `preChatForm.fields` yourself, then:

```dart
await EasyLiveChat.instance.startSession(fields: {'order_id': '123'});
```

A workspace can add **consent checkboxes** to the form
(`PreChatFieldType.consent`): `label` is the sentence the visitor agrees to
(tenant copy, up to 500 characters — render it verbatim and let it wrap) and
`policyUrl` an optional `http(s)` privacy-policy link to open outside the app.
The server only sends them to a client that says it can draw them, so a form of
your own opts in, and passes the ticked ids — consent is never a `fields` value:

```dart
EasyLiveChat.instance.supportsConsent = true; // before open()
await EasyLiveChat.instance.startSession(
  fields: {'name': 'Ada'},
  consents: ['privacy'], // the consent field ids the visitor ticked
);
```

A required one left unticked fails with `CONSENT_REQUIRED` and its `fieldId`,
like any other field error (`PreChatForm.missingConsent` checks it up front).
The prebuilt `easylivechat_ui` form does all of this itself.

After the chat ends, `endChat()` returns `true` when a post-chat survey should
follow. Render `postChatForm` and submit:

```dart
await EasyLiveChat.instance.submitPostChat({'rating': '5'});
```

Field types, validation rules and localized labels are on the models, and
validation mirrors the server's so you can pre-validate for UX.

## Identity verification

Anyone can type any name into a chat. When your workspace releases account data
to a visitor — the AI assistant looking up their orders, say — it has to know
the signed-in user is who your app says. So your **backend** signs its own user
id with the workspace's identity secret (dashboard → Settings → AI assistant →
"Know who is signed in"), and the app passes both:

```dart
// userHash = hex(HMAC_SHA256(identitySecret, userId)) — made on YOUR server.
// Never compute it in the app: the secret must not ship in a binary.
EasyLiveChat.instance.identify(
  userId: user.id,
  userHash: user.chatHash,
  name: user.name,
  email: user.email,
);
await EasyLiveChat.instance.open();
```

They are sent as `userId` / `userHash` on every session call — the silent
resume, the start and the token re-mint — and omitted for anonymous visitors.
What happens depends on the workspace's setting: off ignores them; optional
marks the contact verified when the hash checks out and simply does not trust it
otherwise; **enforced** refuses a `userId` with a missing or wrong hash:

```dart
try {
  await EasyLiveChat.instance.open();
} on EasyLiveChatError catch (e) {
  if (e.isIdentityNotVerified) {
    // e.reason: IdentityNotVerifiedReason.noSecret | noHash | badHash
  }
}
```

Anonymous visitors are never refused, in any mode — support stays open to
people who are not signed in.

**Declare the identity on every launch, before the chat opens.** The SDK
remembers which `userId` this device's visitor belongs to, and lines the two up
the way the web widget does:

- anonymous → signed in keeps the visitor: the conversation they already started
  continues, now with the identity attached;
- a **different** `userId`, or opening the chat with **none** after one was set,
  forgets the stored visitor — a fresh visitorId and nothing to resume — so the
  next person on a shared device never sees the last one's conversation.

On sign-out call `EasyLiveChat.instance.clearIdentity()` (keeps the SDK booted)
or `await EasyLiveChat.instance.reset(storage: …)` — the full logout, which
drops the visitorId, token, profile and identified user id in every case and
tears the SDK down. `identify()` may be called before `boot()`; it is applied
when boot runs.

## Help articles

Your workspace's published help articles, readable without a chat session —
an answer found there is a chat nobody had to start. Show them only when the
workspace turned them on:

```dart
final chat = EasyLiveChat.instance;
if (chat.widgetConfig.value?.helpArticlesEnabled ?? false) {
  final top = await chat.helpArticles();          // the workspace's own order
  final hits = await chat.searchHelp('refund');   // ranked; < 2 chars = top list
  final article = await chat.getHelpArticle(hits.articles.first.id);
  // article.body is markdown — render it as text, never as HTML.
  await chat.rateHelpArticle(article.id, true);   // "Was this helpful?"
}
```

`HelpArticleList` carries `enabled`, `articles` (`HelpArticleSummary`: `id`,
`title`, `excerpt`, `category`, `updatedAt`) and `categories`; `HelpArticle`
adds the markdown `body`, its `locale` and its public `url`. Articles come in
`config.contentLocale` when the workspace wrote any in it. `getHelpArticle`
records the reading for the workspace's help analytics on its own (a failed
count never fails the call). [`easylivechat_ui`](https://pub.dev/packages/easylivechat_ui)
ships a help screen and a safe renderer for the body.

## Storage

`boot()` takes an `EasyLiveChatStorage`. It holds the visitor id and session
token, which is what lets a returning visitor keep their identity and history.

The default `InMemoryStorage` is **not durable** — fine for tests, wrong for
production, where every launch would create a stranger. Either use
`SecurePrefsStorage` from
[`easylivechat_ui`](https://pub.dev/packages/easylivechat_ui), or implement the
interface over your own store:

```dart
class MyStorage implements EasyLiveChatStorage {
  @override
  Future<String?> read(String key) async => /* ... */;
  @override
  Future<void> write(String key, String value) async => /* ... */;
  @override
  Future<void> delete(String key) async => /* ... */;
}
```

Tokens are credentials — put them somewhere encrypted, not plain preferences.

## Errors

Failures surface on a stream rather than throwing out of the calls above, so a
dropped network never crashes a build method:

```dart
EasyLiveChat.instance.onError.listen((e) => debugPrint('$e'));
```

Token expiry, reconnects and re-mints are handled internally. Every error is an
`EasyLiveChatError` with a `code` (`EasyLiveChatErrorCode`); a refused identity
claim is `isIdentityNotVerified`, with the server's `reason`.

## System messages

Transfer and session notices arrive as messages with `senderType == 'SYSTEM'`
carrying a structured `metadata.i18n` key instead of baked-in English, so you
can render them in the visitor's language. Render the key if you have a
translation, and fall back to `body`.

## Cards and quick replies

An agent can send a card — an image, a title, a short text and link buttons —
and a greeting or the AI assistant can offer one-tap answers. Both arrive on
ordinary messages, and both have a plain-text fallback, so a UI that ignores
them still shows something sensible.

```dart
final card = message.card; // null unless it's a valid card
if (card != null) {
  // Draw the card INSTEAD of message.body and message.attachmentUrls.
  // card.imageUrl may be /uploads/…: EasyLiveChat.instance.resolveUrl(it).
  for (final button in card.buttons) {
    // button.uri is http(s) only, ready for url_launcher.
  }
}

final offer = quickRepliesOnOffer(EasyLiveChat.instance.messages.value);
if (offer != null) {
  // Draw offer.replies under the message whose id is offer.messageId.
  // A tap: EasyLiveChat.instance.sendMessage(reply);
}
```

`quickRepliesOnOffer` is the web widget's rule: only the newest message offers
them, and only until the visitor or the team says something else.

## Reactions

Messages carry reactions, as the visitor may see them: on the team's messages
their own, on theirs the team's — never an agent's name. One per person per
message, as on WhatsApp: another emoji replaces yours, the same one again takes
it back.

```dart
for (final g in groupReactions(message.reactions)) {
  // One chip per emoji: g.emoji, g.count, g.mine (the visitor's own).
}

if (message.canReact) {           // the team's messages, once the server has them
  // The row every client shows first: quickReactions (👍 ❤️ 😂 😮 😢 🙏).
  await EasyLiveChat.instance.toggleReaction(message, '👍');
  // or set / take back explicitly: react(message, '❤️') / react(message, null)
}
```

`react` goes over the same `message:react` socket event the web widget uses.
The thread shows the change at once and puts it back if the server says no
(more than twenty in ten seconds, a message that takes none); the future says
which. Reactions from the team, or from the visitor's other devices, arrive live
on `message:reactions` and replace the message's list in `messages` — a
`message:updated` that leaves the field out keeps it. A reaction is not a
message: no `onMessage`, no unread count.

## Link previews

A link in a message gets a preview card — title, site, a line of description and
a picture — made once by the server and stored on the message, so no visitor's
device ever fetches the linked page:

```dart
final preview = message.linkPreview; // null when there is none, or it is malformed
if (preview != null && config.linkPreviews && message.cards.isEmpty) {
  // preview.siteName, preview.title, preview.description (may be null)
  // preview.imageUrl: /uploads/… (resolveUrl it) or https — may still fail to load
  // preview.uri: http(s) only, ready for url_launcher
}
```

It is read through the same checks the web uses (lengths capped, the link
`http:`/`https:` only, the picture our own upload or `https:`), and usually lands
a moment after the message, as a `message:updated`. `config.linkPreviews` is the
workspace's switch.

## Light and dark

`config.colorScheme` is the workspace's choice: `WidgetColorScheme.light`,
`dark`, or `auto` — follow the device. Existing workspaces were kept on light; new
ones start on auto. An older server sends nothing, which reads as light.

```dart
final dark = config.colorScheme.resolveDark(
    deviceDark: MediaQuery.platformBrightnessOf(context) == Brightness.dark);
```

The dark look is derived from the one light look the workspace set — the web
widget's rule, which `easylivechat_ui` follows: the brand stays where the
visitor sees it as a fill, the light surfaces become a dark ground and card.
`config.launcherLabel` (a few words beside the launcher's icon, or null) and
`config.launcherSize` (`small` 48, `medium` 56, `large` 64) are the launcher's
options.

## Closed and busy

While the workspace is shut, say so above the thread. The web widget's rule, in
order:

1. `config.offlineInfoText` — the business's own notice — when it wrote one.
   It always wins, whatever the mode and whether or not the assistant covers.
   (Not `offlineMessage`: that is the leave-a-message prompt, with a default
   nobody typed.)
2. `composerLocked` (`NOTICE_ONLY`): when the team is back (`nextOpenLocal`),
   or that it will be soon.
3. `availabilityReason == 'NO_AGENTS'`: everyone's busy — or, while
   `assistantCovers`, that the assistant can help in the meantime.
4. Otherwise closed — the assistant's version while it covers — followed by the
   reopening time, which stays: it is when a person is back.

All of these update live from `workspace:availability`.

## Waiting in the queue

```dart
ValueListenableBuilder<QueueStatus?>(
  valueListenable: EasyLiveChat.instance.queue,
  builder: (context, q, _) => q == null
      ? const SizedBox.shrink()
      : Text('${q.text}  #${q.position} · ~${q.minutes} min'),
);
```

Non-null while the visitor waits for a person: the place, the expected minutes
and the workspace's own words, with the visitor's name and place filled in. Show
it above the conversation, not instead of it. It turns null the moment somebody
is there — the chat assigned, a team message, someone typing.

## Emails to the visitor

The web widget's "Email me this chat" and "Get the reply by email", for your own
UI. Both need a session, and addresses come back masked — the device may not be
the visitor's.

```dart
if (EasyLiveChat.instance.transcriptEmailEnabled) {
  final sentTo = await EasyLiveChat.instance.emailTranscript(); // a•••@example.com
}

final state = await EasyLiveChat.instance.visitorEmail(); // emailHint, unsubscribed
if (EasyLiveChat.instance.replyEmailEnabled && state.emailHint == null) {
  await EasyLiveChat.instance.setVisitorEmail('ava@example.com');
}
```

`emailTranscript()` sends to the address on the contact; pass `email:` when the
visitor typed one. Refusals are `EasyLiveChatError`s with the server's code:
`NO_CONTACT_EMAIL` (ask for an address), `INVALID_EMAIL`, `EMAIL_UNSUBSCRIBED`,
`TRANSCRIPT_RATE_LIMITED`.

## "Reply in the chat" links

When the team answers a visitor who has gone, the workspace can email them, and
the email's "Reply in the chat" button links back into the conversation: to the
page they were on with `#elc_chat=<token>` in the fragment, or to our own chat
page with `#resume=<token>`. If that link opens your app — a universal link /
app link on your site's domain, or your own scheme you rewrite it into — hand it
to `resumeFromLink` from your deep-link handler, then show the chat:

```dart
// e.g. with package:app_links — any deep-link source works the same way.
AppLinks().uriLinkStream.listen((uri) async {
  // identify(...) / clearIdentity() first, as before open().
  if (await EasyLiveChat.instance.resumeFromLink(uri.toString())) {
    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => const EasyLiveChatScreen()),
    );
  }
  // false: not one of ours, expired, or refused — route it as usual.
});
```

It takes the whole link or just the token. The token is traded with the server
for the visitor that reaches that conversation (the web widget's own route),
this device becomes that visitor — so the chat opens on any device the email is
read on — and the conversation is resumed: `true` means it is in `messages`
with `phase` on `chat`. `false`, never a throw, for a link that is not ours,
one the server refuses (another workspace's, expired, a chat that is gone), no
network, or a chat that could not be resumed. It needs `boot()`.

Declare who is signed in first, exactly as before `open()`. While a user is
signed in with a `userId`, a link to any visitor other than this device's own
is refused (`false`): the SDK cannot tell whether that chat is theirs, and
moving them into it would attach their verified identity to someone else's
conversation. Signed-in users hear about replies from your own notifications
(below); anonymous visitors follow the link as they would on the web.

## Notifications

EasyLiveChat does not notify your app's users itself, and needs no Firebase key
from you: a key that can message every user of your app is not one to hand to a
third party. Your own server sends the notification, on the `message.created`
webhook (dashboard → Settings → Webhooks):

1. Identify signed-in users with a **verified** id: `identify(userId:, userHash:)`
   with the HMAC your server computes (see Identity verification). Only a
   verified id is ever handed back — `contact.userId` is `null` otherwise.
2. Subscribe an endpoint to `message.created`. Every delivery carries the
   `message`, the `conversation` and its `contact`.
3. For a reply from the team or the assistant — `message.senderType` is
   `AGENT`, or `BOT` (`message.automatic` says which automatic sender) — with
   `contact.userId` set, send your own push to that user's devices.
   `contact.userId` is the `userId` you passed to `identify()`, so it is
   already your own user id.
4. Ignore the rest: the visitor's own messages (`CUSTOMER`), system lines, and
   anonymous visitors (no `contact.userId` — they have the reply email).

```js
// Your server — verify X-Easylivechat-Signature-V2 first (see the webhook docs).
app.post('/hooks/easylivechat', (req, res) => {
  const { event, data } = req.body;
  const reply = ['AGENT', 'BOT'].includes(data?.message?.senderType);
  if (event === 'message.created' && reply && data.contact?.userId) {
    notifyUser(data.contact.userId, {
      title: 'New reply from support',
      body: data.message.body ?? '',
      data: { conversationId: data.conversationId },
    });
  }
  res.sendStatus(200);
});
```

Your app already knows whether the chat is on screen, so suppress the
notification there, and open `EasyLiveChatScreen` when one is tapped.

`setPushToken()` from 0.1.54–0.1.57 is deprecated and does nothing — no
request, nothing held for later. Delete the call.

## Localization

This package holds no user-facing strings — it is protocol and state only.
`locale` tells the server which language to send *your tenant's* copy in;
`contentLocale` picks the language for auto-greetings. Chrome strings live in
`easylivechat_ui`.

## Troubleshooting

**"boot() must be called before use".** Something touched
`EasyLiveChat.instance` before `boot()` completed. Await it during startup.

**The visitor is new on every launch.** You are on `InMemoryStorage` — see
Storage above.

**Nothing arrives after a reconnect.** The client re-joins and backfills on
reconnect; if you also cache messages yourself, reconcile on message `id` and
`clientId` rather than appending.

**Config seems stale after a language switch.** `boot()` is safe to call again
with a new config — it adopts the change rather than ignoring it.

## Server

Talks to an EasyLiveChat workspace. Create one at
[livechattools.com](https://livechattools.com).
