# EasyLiveChat — Flutter SDK

Native Flutter client for **EasyLiveChat**, the real-time omni-channel support
inbox. Embed live customer support (WhatsApp/Instagram/Messenger/Telegram +
your own app) into any Flutter app. The SDK speaks the existing anonymous
**widget protocol** — HTTP `/api/widget/*` + Socket.IO `/widgets` &
`/widget-presence`, with a per-visitor 24h widget JWT — so the foreground chat
experience works against today's backend with **zero server changes**.

> Design + protocol reference: [`docs/FLUTTER_SDK_SPEC.md`](../docs/FLUTTER_SDK_SPEC.md).

## Packages

| Package | What | Deps |
|---|---|---|
| [`easylivechat`](packages/easylivechat) | Headless protocol client + reactive state. No UI. | `socket_io_client`, `dio`, `uuid`, `jwt_decoder`, flutter foundation |
| [`easylivechat_ui`](packages/easylivechat_ui) | Prebuilt themeable widgets (launcher, chat screen, pre-chat form, thread, composer, CSAT, offline) on top of the core. | + `image_picker`, `file_picker`, `cached_network_image`, `flutter_secure_storage`, `shared_preferences` |

## Quick start (drop-in UI)

```dart
import 'package:easylivechat_ui/easylivechat_ui.dart';

await EasyLiveChat.instance.boot(
  const EasyLiveChatConfig(
    apiBase: 'https://api.livechattools.com',
    tenantSlug: 'acme',          // your workspace slug
  ),
  storage: SecurePrefsStorage(), // durable visitorId + JWT (from easylivechat_ui)
);

// In your widget tree — a floating bubble that opens the full chat:
Stack(children: [ MyApp(), const EasyLiveChatLauncher() ]);
```

That's it: pre-chat form (rendered from the server config), real-time thread,
typing indicators, image/file attachments, CSAT, working-hours offline form,
server-driven theming + RTL — all wired.

## Headless (build your own UI)

```dart
import 'package:easylivechat/easylivechat.dart';

final chat = EasyLiveChat.instance;
await chat.boot(const EasyLiveChatConfig(
  apiBase: 'https://api.livechattools.com', tenantSlug: 'acme'),
  storage: myDurableStorage); // implement EasyLiveChatStorage
await chat.open();            // config → resume → prechat/anon → connect

chat.messages.addListener(rebuild);   // ValueListenable<List<ChatMessage>>
chat.agentTyping.addListener(rebuild);
chat.connection.addListener(rebuild);

final res = chat.sendMessage('Hello!');     // optimistic; res.serverMessageId resolves on ack
await chat.submitFeedback(rating: 5);
```

Everything is exposed as `ValueListenable`s + `Stream`s — bind them to any state
management you like.

## What works today vs. needs server work

- ✅ **Foreground chat, pre-chat, attachments, CSAT, typing, RTL/theming** —
  zero server changes.
- ✅ **Tappable links in message bodies** — URLs, email addresses and phone
  numbers are auto-detected and open the browser / mail app / dialer. Message
  text is still rendered verbatim (never parsed as markup); see
  `lib/src/views/linkified_text.dart`. Uses `url_launcher` without
  `canLaunchUrl`, so **no host `Info.plist` / manifest entries are needed**.
  Scheme-less domains only link for the TLDs in `_bareLinkTlds` — `main.py` and
  `photo.png` stay plain text. Extend that set if a tenant needs more.
- ⛔ **Background push** ("agent replied while the app was closed") needs a
  server-side visitor push registry + fan-out (the backend currently pushes to
  agents only). The `EasyLiveChatPush` hook is stubbed until then.
- ⚠️ Rate-limiting on `message:send` / `/session`, a token-refresh route, and
  HEIC/MOV upload support are recommended follow-ups (see the spec §11).

## Status

`0.1.0` — Phase 1 (headless core) + Phase 2 (UI kit) implemented. `easylivechat_ui`
resolves and its `test/` suite passes under Flutter 3.41 (`flutter pub get &&
flutter test`); the rest is still a reviewed first cut with no CI compile. Note
`dart analyze --fatal-infos` (the `melos analyze` script) currently fails on
pre-existing `Color.withOpacity` deprecations in `thread_view.dart` on Flutter
3.41. Pin `socket_io_client` to a 3.x release (Engine.IO v4)
to match the server's `socket.io@4.8.x` and add an integration test against a
live `/widgets` namespace — a protocol mismatch fails the handshake silently.

## Layout

```
flutter-sdk/
  melos.yaml
  packages/
    easylivechat/        # headless core
      lib/easylivechat.dart
      lib/src/{config,errors,storage,rest_client,widget_socket,presence_socket,session_controller,easylivechat_client}.dart
      lib/src/models/{enums,chat_message,pre_chat_form,widget_config,results}.dart
      example/main.dart
    easylivechat_ui/     # prebuilt widgets
      lib/easylivechat_ui.dart
      lib/src/{theme,storage_impl,launcher,chat_screen,l10n}.dart
      lib/src/views/{pre_chat_form_view,thread_view,composer_bar,feedback_prompt_view,offline_form_view,linkified_text}.dart
      test/{linkified_text_test,linkified_text_widget_test}.dart
```
