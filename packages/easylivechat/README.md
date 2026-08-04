# easylivechat

Headless Dart/Flutter client for [EasyLiveChat](https://livechattools.com) —
the real-time omni-channel support inbox. This package speaks the anonymous
widget protocol (HTTP + Socket.IO): sessions, messages, attachments, typing,
presence, pre/post-chat forms. **No UI** — pure protocol and state, built on
`ValueListenable` so any widget layer can drive it.

Want prebuilt widgets instead? Use
[`easylivechat_ui`](https://pub.dev/packages/easylivechat_ui), which is built
on this package and adds the launcher bubble, chat screen, theming and 13
chrome locales.

## Quick start

```dart
import 'package:easylivechat/easylivechat.dart';

await EasyLiveChat.instance.boot(
  const EasyLiveChatConfig(
    apiBase: 'https://api.livechattools.com',
    tenantSlug: 'your-workspace',
  ),
  storage: MyDurableStorage(), // persist visitorId + JWT across launches
);

// Optional: attach the signed-in user so agents see who they're talking to.
EasyLiveChat.instance.identify(name: 'Jane', email: 'jane@example.com');

await EasyLiveChat.instance.open();          // start / resume the session
EasyLiveChat.instance.sendText('Hi there');  // optimistic send + reconcile
```

## What you get

- **Session lifecycle** — `boot` / `open` / `silentResume`: an open
  conversation is resumed with history across app launches; `endChat()`
  reports whether a post-chat survey follows.
- **Messages** — optimistic sends with delivery status, server reconcile,
  attachments (multipart upload with progress), history paging.
- **Realtime** — Socket.IO under the hood: `message:new`, typing both ways,
  agent presence, conversation close, transfer notices (SYSTEM messages carry
  a structured `metadata.i18n` key so your UI can localize them).
- **State as `ValueListenable`** — `phase`, `messages`, `widgetConfig`,
  `agentTyping`… subscribe from any framework layer.
- **Forms** — server-driven pre-chat and post-chat (CSAT + questions) models.
- **Storage abstraction** — bring your own persistence (`EasyLiveChatStorage`);
  the UI package ships secure defaults.

## Server

This client talks to an EasyLiveChat workspace. The backend is the
`apps/api` service in the [same repository](https://github.com/nullsam/easylivechat).
