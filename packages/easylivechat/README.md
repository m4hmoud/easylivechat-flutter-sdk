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
  easylivechat: ^0.1.42
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

  // Optional: skip the pre-chat form for a user you already know.
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

## Forms

Both forms are authored in the dashboard and arrive in
`widgetConfig.value` — render `preChatForm.fields` yourself, then:

```dart
await EasyLiveChat.instance.startSession(fields: {'order_id': '123'});
```

After the chat ends, `endChat()` returns `true` when a post-chat survey should
follow. Render `postChatForm` and submit:

```dart
await EasyLiveChat.instance.submitPostChat({'rating': '5'});
```

Field types, validation rules and localized labels are on the models, and
validation mirrors the server's so you can pre-validate for UX.

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

Token expiry, reconnects and re-mints are handled internally.

## System messages

Transfer and session notices arrive as messages with `senderType == 'SYSTEM'`
carrying a structured `metadata.i18n` key instead of baked-in English, so you
can render them in the visitor's language. Render the key if you have a
translation, and fall back to `body`.

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
