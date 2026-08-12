# Changelog

## 0.1.47

- **Web is no longer a supported platform.** The package declares android,
  ios, linux, macos and windows. It is not that the UI cannot run on web — it
  does under the JS compiler — but it is not a platform we test or support, and
  `dart compile wasm` genuinely fails: cached_network_image pulls
  flutter_cache_manager, which reaches for dart:io, and neither has a
  WASM-ready release. The web product is the embeddable script-tag widget.
  **A Flutter app targeting web will now be told this dependency does not
  support that platform.**
- Added `example/`, which pub.dev requires and which this package never had.
  It shows both integrations: the launcher in a `Stack`, and the screen pushed
  as a route with the end-chat button.
- README rewritten as a guide rather than a summary: install, a complete
  runnable `main.dart`, the iOS `Info.plist` keys that attachments require
  (without them the picker silently fails), a phase table, recipes for
  identify / unread badge / theming / ending a chat / locales / custom picker,
  and troubleshooting for the failures people actually hit.
- `description` shortened to fit pana's 180-character limit; added `topics`;
  formatted with `dart format`.

## 0.1.46

- Requires `easylivechat` ^0.1.42. The thread reads
  `EasyLiveChat.hasOlderHistory`, which does not exist in earlier cores —
  the same compile failure 0.1.45 was cut to fix, one getter later.
- The thread no longer pulls a page of history the moment it appears. That was
  right when a conversation was a single visit; now that a returning customer
  resumes a thread spanning months, it dragged the previous visit straight back
  on screen, underneath the greeting for the visit just started. Older messages
  arrive when the visitor scrolls up, or asks for them.
- "Load earlier messages" is a real control again. It rendered nothing when
  idle, on the reasoning that loading was automatic; with the eager load gone
  that would have stranded history on a session too short to scroll. The list
  is also always draggable, so the pull gesture works even when the thread fits
  the screen.

## 0.1.45

- Requires `easylivechat` ^0.1.40. 0.1.44 drew the submitted post-chat survey
  in the thread through `ChatMessage.postChat`, but still allowed core 0.1.39,
  where that getter does not exist — so every host outside this repository
  failed to compile with "The getter 'postChat' isn't defined for the type
  'ChatMessage'". In-repo builds resolve the sibling core through
  `pubspec_overrides.yaml`, which is why the gap only showed up downstream.
- The post-chat survey a visitor filled in renders where they filled it in,
  instead of below newer messages. Shipped in 0.1.44 but never listed here.

## 0.1.44

- `EasyLiveChatScreen` can draw its own app bar: `showAppBar: true` gives a
  back button and an X. They are different actions on purpose — backing out
  leaves the conversation open so the visitor can return to it, while the X is
  the explicit end that confirms first and then shows the post-chat survey.
  Off by default, since most hosts push the screen into a route that already
  has an app bar and would otherwise get two. `appBarTitle` overrides the
  title, which defaults to the workspace's own.
- The end-chat confirmation now takes its typeface from the host app.
  `styleFrom(textStyle:)` REPLACES a button's text style, so the bare
  TextStyles it used dropped the app's fontFamily and fell back to Material's
  default — the two buttons could render in different faces from each other
  and from the rest of the app. Both are also the same weight now.

## 0.1.43

- An arriving agent reply now chimes, the way the web widget always has — the
  visitor is usually looking at something else in the host app, so a thread
  that updated silently was simply missed. Honours the workspace's
  `soundEnabled` / `soundUrl` widget config, falling back to a bundled default
  (the same audio file the web widget serves). Only AGENT messages ring, not
  the visitor's own sends, bot greetings, or transfer notices. Adds an
  `audioplayers` dependency.
- `EasyLiveChatEndChatButton` is a plain X instead of the speaker-notes-off
  glyph, which read as a mute control rather than "close this".
- The chat screen reports read receipts while it is on screen (on mount, on
  each arrival, and on app resume), so the agent's ticks turn green. Needs
  `easylivechat` 0.1.39.

## 0.1.42

- "Typing" now follows the FIELD, not the keystrokes: it keeps announcing for
  as long as the composer has text and stops the moment it empties (or on
  send). Previously it stopped after ~1.5s of no keystrokes, so pausing
  mid-sentence made the indicator disappear on the agent's screen while the
  visitor was still composing.

## 0.1.41

- The visitor's "typing" now keeps announcing itself while they type. It was
  sent once on the first keystroke, so an agent app — which clears its
  indicator ~4s after the last event — stopped showing it mid-sentence with no
  state change left to fire another event. Re-announced at most every 2s.

## 0.1.40

- End-chat confirmation redesigned: the workspace's own colors and text
  direction, 24px corners, a solid confirm button and a quiet cancel stacked
  full-width instead of two cramped text buttons in the host app's Material
  theme. `EasyLiveChatEndChatButton` and `confirmAndEnd` take an optional
  `theme` so a host that themes the chat screen can match the dialog to it.
- The send button now hides while the composer is locked, like the attach
  button already did — a live accent-colored send beside a disabled field
  promised something the composer would refuse.

## 0.1.39

- Typing indicator rebuilt: staggered messenger-style hop (each dot takes
  its turn to rise and brighten) instead of a flat synchronized fade — and
  the dot spacing no longer collapses under RTL, where the old physical
  padding stacked the dots on top of each other.
- Bubble tail corners are now logical (start/end), so the tail hugs the
  correct side in RTL layouts for both message bubbles and the typing row.

## 0.1.38

- Repository moved to a dedicated public home:
  [m4hmoud/easylivechat-flutter-sdk](https://github.com/m4hmoud/easylivechat-flutter-sdk).
  No code changes.

## 0.1.37

First pub.dev release. Previously consumed as a git dependency
(`flutter-sdk-v0.1.x` tags in the repository); version numbers continue that
series.

- Launcher bubble + full chat screen: pre-chat form, thread, composer,
  attachments (image/file), CSAT, offline form — all server-config driven.
- Backing out no longer ends the conversation; it resumes on reopen. New
  `EasyLiveChatEndChatButton` (and static `confirmAndEnd`) is the explicit,
  localized end-chat affordance; `EasyLiveChatScreen.confirmExit` is
  deprecated and inert.
- Transfer notices render as centered system lines, localized to the
  visitor's language via the server's structured i18n key.
- Post-chat survey is skippable; composer respects read-only/closed states
  with localized notices and working-hours copy.
- 13 chrome locales (en, ar, ckb, kmr, de, es, fr, hi, it, pt, tr, ur, zh)
  with per-key and per-locale host overrides; full RTL support.
