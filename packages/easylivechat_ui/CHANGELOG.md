# Changelog

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
