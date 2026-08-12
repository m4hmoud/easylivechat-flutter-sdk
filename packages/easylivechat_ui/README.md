# easylivechat_ui

Drop real-time customer support into a Flutter app. Add a floating bubble, or
push a full chat screen — the pre-chat form, message thread, attachments,
typing indicators, CSAT survey and offline form are all built, themed from your
[EasyLiveChat](https://livechattools.com) dashboard, and translated into 13
languages.

Built on the headless [`easylivechat`](https://pub.dev/packages/easylivechat)
core and re-exports it, so this is the only dependency you need.

```yaml
dependencies:
  easylivechat_ui: ^0.1.46
```

or

```sh
flutter pub add easylivechat_ui
```

## Quick start

Two things: boot once at startup, then show a widget. This is a complete app —
paste it into `main.dart`, put your own workspace slug in, and it runs.

```dart
import 'package:flutter/material.dart';
import 'package:easylivechat_ui/easylivechat_ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await EasyLiveChat.instance.boot(
    const EasyLiveChatConfig(
      apiBase: 'https://api.livechattools.com',
      tenantSlug: 'your-workspace',
    ),
    // Durable storage for the visitor id + session token. Without this the
    // visitor is a stranger on every launch and their history is lost.
    storage: SecurePrefsStorage(),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('My app')),
        // The launcher positions itself; give it a Stack to sit in.
        body: const Stack(
          children: [
            Center(child: Text('Your app')),
            EasyLiveChatLauncher(),
          ],
        ),
      ),
    );
  }
}
```

`tenantSlug` is your workspace slug — the one in your dashboard URL
(`your-workspace.livechattools.com`).

That is the whole integration. Everything below is optional.

### …or your own entry point

If you would rather open the chat from a menu item or a support button, skip
the launcher and push the screen:

```dart
Navigator.of(context).push(
  MaterialPageRoute(builder: (_) => const EasyLiveChatScreen()),
);
```

`EasyLiveChatScreen` is a normal widget — put it in a tab, a dialog, wherever
you like. Both integrations are in [`example/main.dart`](example/main.dart).

## Platform setup

Attachments use the camera and photo library, so iOS needs the two usage
strings. Add them to `ios/Runner/Info.plist`:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Attach images to your support conversation.</string>
<key>NSCameraUsageDescription</key>
<string>Take a photo to send to support.</string>
```

Android needs nothing for the default setup. If you supply your own picker via
`onPickAttachments`, neither is required.

Supported platforms: **Android, iOS, macOS, Windows, Linux**. Web is not
supported — the web product is the embeddable script-tag widget, which you
already have in your dashboard.

## What the visitor sees

The UI follows `EasyLiveChat.instance.phase`, and you do not have to manage
any of it:

| Phase      | Screen                                                       |
|------------|--------------------------------------------------------------|
| `idle`     | Nothing open                                                 |
| `loading`  | Fetching your workspace config                               |
| `prechat`  | The pre-chat form you configured (skipped if you `identify`)  |
| `chat`     | The conversation                                             |
| `feedback` | Post-chat survey / CSAT                                      |
| `offline`  | Your out-of-hours notice                                     |

Out-of-hours behaviour is a dashboard setting, not a client one — take a
message, show a notice, or accept chats anyway.

## Recipes

### Identify a signed-in user

Call before opening. The pre-chat form is skipped and the agent sees who they
are talking to.

```dart
EasyLiveChat.instance.identify(
  name: user.name,
  email: user.email,
  phone: user.phone,
  fields: {'plan': 'pro', 'userId': user.id}, // shown to the agent
);
```

### Show an unread badge

```dart
ValueListenableBuilder<int>(
  valueListenable: EasyLiveChat.instance.unreadCount,
  builder: (_, count, __) => Badge(
    isLabelVisible: count > 0,
    label: Text('$count'),
    child: const Icon(Icons.support_agent),
  ),
);
```

### Match your app's theme

Colours come from your dashboard so non-developers can rebrand without a
release. Override when you need to match the host app:

```dart
final scheme = Theme.of(context).colorScheme;

EasyLiveChatLauncher(
  themeOverride: EasyLiveChatTheme(
    primary: scheme.primary,
    background: scheme.surface,
    surface: scheme.surfaceContainerHighest,
    text: scheme.onSurface,
  ),
)
```

Layout direction is deliberately *not* taken from the override — it follows the
resolved locale, so a colours-only override cannot accidentally force an RTL
workspace back to LTR.

### End the conversation

Backing out of the screen does **not** end the chat — reopening resumes it with
its history, which is what visitors expect. Ending is explicit:

```dart
AppBar(actions: const [EasyLiveChatEndChatButton()])
```

It appears only while a conversation is live, confirms first, then shows the
post-chat survey in place. If your app bar takes an icon and a callback
instead, call `EasyLiveChatEndChatButton.confirmAndEnd(context)` — it no-ops
when there is nothing to end.

### Language

Chrome (buttons, labels, errors) ships in en, ar, ckb (Sorani), kmr (Badini),
de, es, fr, hi, it, pt, tr, ur, zh, and follows the device locale. Force one,
or add your own:

```dart
const EasyLiveChatLauncher(locale: 'ar');   // force one

// Add a language, or reword an existing one, without waiting on a release.
ElcStrings.overrideByLocale({
  'sv': {'send': 'Skicka'},
});
```

Your own copy — greeting, welcome text, survey questions — is authored per
language in the dashboard and is never machine-translated by the SDK. RTL
follows the locale automatically.

### Your own attachment picker

```dart
EasyLiveChatScreen(
  onPickAttachments: () async => [
    ElcPickedFile(filename: 'screenshot.png', bytes: bytes),
  ],
)
```

## API

Every widget takes `themeOverride`, `directionOverride`, `onPickAttachments`,
`strings` and `locale`.

| Widget | Purpose |
|---|---|
| `EasyLiveChatLauncher` | Floating bubble with unread badge. `alignment:` to move it, `useBottomSheet: true` to open as a sheet |
| `EasyLiveChatScreen` | The full chat screen, for your own navigation |
| `EasyLiveChatEndChatButton` | Explicit end-chat action for an app bar |
| `SecurePrefsStorage` | Durable storage default (secure storage + shared prefs) |

The core's API — `identify`, `open`, `messages`, `unreadCount`, `phase`,
`sendMessage` — is re-exported here and documented in
[`easylivechat`](https://pub.dev/packages/easylivechat).

## Troubleshooting

**The visitor is a stranger on every launch.** You booted without
`storage: SecurePrefsStorage()`, so the default in-memory store is used and the
visitor id does not survive a restart.

**The launcher is invisible.** It needs a `Stack` (or another widget that
allows overlap) as its parent. In a `Column` it has nowhere to position itself.

**"boot() must be called before use".** A widget was built before `boot()`
finished. Await it in `main()` before `runApp`, as above.

**Nothing happens when opening.** Check `apiBase` and `tenantSlug` against your
dashboard, and listen to `EasyLiveChat.instance.onError` — configuration
problems surface there rather than throwing.

**Attachments do nothing on iOS.** The two `Info.plist` usage strings are
missing; iOS silently denies the picker without them.

## Want a different UI?

Use [`easylivechat`](https://pub.dev/packages/easylivechat) directly. It is the
same protocol and state machine with no widgets — bind the `ValueListenable`s
to your own design system.

## Server

Talks to an EasyLiveChat workspace. Create one at
[livechattools.com](https://livechattools.com).
