# Changelog

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
