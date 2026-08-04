# easylivechat_ui

Prebuilt, themeable Flutter UI for
[EasyLiveChat](https://livechattools.com) — embed real-time customer support
in a few lines. Launcher bubble, full chat screen (pre-chat form, message
thread, composer, attachments, CSAT, offline form), all driven by your
workspace's server-side widget configuration.

Built on the headless
[`easylivechat`](https://pub.dev/packages/easylivechat) core — use that
directly if you want your own UI.

## Quick start

```dart
import 'package:easylivechat_ui/easylivechat_ui.dart';

await EasyLiveChat.instance.boot(
  const EasyLiveChatConfig(
    apiBase: 'https://api.livechattools.com',
    tenantSlug: 'your-workspace',
  ),
  storage: SecurePrefsStorage(), // durable default from this package
);

// Floating bubble over your app:
Stack(children: [MyApp(), const EasyLiveChatLauncher()]);

// …or push the full screen yourself:
Navigator.of(context).push(
  MaterialPageRoute(builder: (_) => const EasyLiveChatScreen()),
);
```

## Behavior worth knowing

- **Leaving ≠ ending.** Backing out of the screen keeps the conversation
  open; reopening resumes it with history. Ending is explicit: drop
  `EasyLiveChatEndChatButton` into your app bar (it appears only while a
  conversation is live, confirms in the chrome locale, then shows the
  tenant's post-chat survey in place). App bars with icon+callback slots can
  call `EasyLiveChatEndChatButton.confirmAndEnd(context)` instead — it
  no-ops when nothing is live.
- **Theming** — colors come from the server widget config; override with
  `themeOverride:` to match your app. RTL layouts follow the locale (or
  `directionOverride:`).
- **13 chrome locales** — en, ar, ckb (Sorani), kmr (Badini), de, es, fr,
  hi, it, pt, tr, ur, zh. Force one with `locale:`, or override any string
  per locale via `ElcStrings.overrideByLocale` (also the way to add a
  language without waiting on a release).
- **Localized system notices** — transfer lines render in the visitor's
  language from the server's structured key, not the workspace default.
- **Attachments** — image/file pickers included; supply your own via
  `onPickAttachments:`.
- **Tenant copy stays verbatim** — greeting, welcome text, offline notice
  and survey questions are authored per-language in your dashboard and are
  never machine-localized by the SDK.

## Server

Talks to an EasyLiveChat workspace — the `apps/api` service in the
[same repository](https://github.com/nullsam/easylivechat).
