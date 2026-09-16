# Changelog

## 0.1.70

- **Cards draw as cards.** An agent's card — image, title, text and link
  buttons — used to arrive as its plain-text version, every button spelled
  out as `Label: https://…`. It is now drawn in the team's bubble: the same
  surface, corners, tail and outline as the message beside it, with the image
  across the top at 16:9, the title, the text, and each button as a full-width
  row in the workspace accent. A button opens its link in the visitor's
  browser, and only an `http:`/`https:` link ever reaches the platform. The
  text version and the image attachment the card carries for other clients
  are not drawn a second time. A card that doesn't validate reads as its text,
  as it did before.
- **Quick replies.** The answers a workspace offers under its greeting, and
  the AI assistant's Yes / No when it offers to pass the visitor to the team,
  are one-tap buttons under that message: pills outlined in the accent that
  fill with it on press, wrapping from the team's side in either direction,
  announced as "Suggested replies" in all 13 languages. A tap sends the reply
  as the visitor's own message, through the same send the composer uses — so
  it ticks, and fails to a retry, like anything typed. The buttons go the
  moment the visitor answers or the team writes again, and are disabled while
  a reply is on its way and while the workspace takes no messages, so a double
  tap sends once.
- The line with an agent's name above their bubble was inset from the physical
  left, so in Arabic, Kurdish and Urdu it sat 4px off the wrong edge. It uses
  a logical inset now.
- Requires `easylivechat` 0.1.53.

## 0.1.69

- **A voice note now actually plays, and shows its length and a seek bar.**
  0.1.68 gave it a play button, but pressing it turned the note straight back
  into a download chip. `routes/uploads.ts` serves every upload as a single
  `200` with the whole body and **no `Accept-Ranges`** — it cannot answer a
  byte-range request — and iOS plays remote media through `AVPlayer`, which
  reads an MP4/M4A `moov` atom by issuing exactly those requests. The asset
  never loaded, `play()` threw, and the tile fell back to its chip.
- The file is now fetched before it is played, which a voice note wants in any
  case. A plain GET needs no ranges, so it works against the server as it
  stands; the **real duration is shown before anything is played** rather than
  the words "voice message"; and **dragging the seek bar works**, which over a
  server that cannot serve ranges it could not. Recordings are small, and are
  cached under the system temp directory, so scrolling back through a thread
  re-reads from disk instead of the network.
- **A voice note is now the whole card.** It already rounds its own corners, so
  the bubble around it was a second card holding a first one — on the visitor's
  own side the full accent colour, so their own recording arrived matted in a
  teal frame. It drops the bubble and paints that surface itself, exactly as an
  image-only message already did. A note WITH a caption keeps its bubble and
  stays an inlay, because the caption needs the surface.
- **A recording can be reviewed before it is sent.** The composer used to
  offer one move — stop, which sent immediately — so the only way to hear what
  you had said was to send it to someone. It now records against a live
  waveform of the microphone's own levels, pauses, plays back with a seek bar,
  carries on recording where it left off, and sends or bins the take: trash,
  play, waveform, mic, send, the way every messenger lays it out.
- The recording waveform no longer overflows the composer. It is deliberately
  wider than its window — it carries a spare bar to slide in from — and a
  `Row` cannot be told that, so it reported a flex overflow and painted yellow
  hazard stripes across the bar on a screen a visitor was looking at. The run
  is laid out at its own width inside an `OverflowBox` now, anchored to the
  trailing edge and clipped to the window. The widget moved to
  `views/voice_levels.dart` so it can be tested at a width, which is how this
  should have been caught.
- The recording waveform moves at frame rate rather than in steps. It samples
  at 60ms instead of 120, eases each level toward the last so raw amplitude
  jitter stops drawing a comb, keeps a FIXED bar pitch — bars used to shrink
  as the take grew, because they shared the width between them — and slides a
  fraction of a bar every frame off a `Ticker` instead of jumping a whole one
  each sample. Levels also moved to a `ValueNotifier`, so sixteen samples a
  second redraw the waveform and not the whole composer.
- Paused, the WHOLE take is fitted to the width — averaged down into as many
  bars as fit — instead of showing only the tail. Nothing moves but the
  playhead.
- Continuing a paused take really continues it — `record` pauses and resumes
  the same file, so it is one recording and not two stitched together.
- **Listening to a take no longer ends it.** Play it, hear it, carry on
  talking, as many times as you like. This is why the recording format changed
  from AAC to WAV: AAC lives in an MP4 container whose index is only written
  when the recording stops, so hearing a take meant ending it and the
  microphone button disappeared for good. WAV is raw samples appended in
  order, so a playable copy can be cut from a take that is merely paused. The
  copy's two length fields are rewritten from the bytes actually on disk — a
  half-written WAV says it holds nothing, and players believe it.
- The upload is bigger for that: 16kHz mono is ~32KB a second against about 6
  for AAC. It stays well inside the 25MB cap even at the five-minute ceiling,
  and the server re-encodes an uploaded wav to Ogg/Opus, so what is stored and
  what goes out to WhatsApp is *smaller* than the AAC was. Only the upload
  pays.
- **The button that sends a recording is drawn as a send arrow**, not a stop
  square. It never stopped anything — it puts the note straight in the thread —
  so the square was asking people to commit while showing them a pause. Its
  tooltip has said "send voice message" the whole time; only the glyph
  disagreed. It also takes its colour from the accent the way the composer's
  send button does, instead of a hardcoded white that vanished on a pale one.
- **A waveform seek bar**, in place of the single line. Playback fills the bars
  from the leading edge, and dragging anywhere in the band seeks. The bars are
  **decorative**: a true amplitude envelope means decoding the AAC to PCM,
  which needs a platform decoder this package deliberately does not carry, so
  they are a stable fingerprint of the file rather than a reading of its
  loudness. One note always looks the same and two notes look different, but a
  quiet passage is not drawn short.
- **The download itself was racing, and that was the whole failure.** Every
  fetch wrote through one shared `<name>.part`, held open for the length of the
  download. A message re-keys from its optimistic `tmp-` id to the server's,
  which re-mounts the tile while the first download is still running — so two
  fetches of the same note overlap as a matter of course on the visitor's OWN
  recording. Whichever finished first renamed the file out from under the
  other, and the loser died with `PathNotFoundException: Cannot rename file …
  No such file or directory`. A note is now fetched once however many tiles ask
  for it, written through a scratch name unique to that attempt, and a lost
  rename resolves to the file the winner left.
- If the local copy cannot be made, it falls back to streaming the url before
  giving up — half a voice note beats a download chip, even though streaming
  can serve neither a duration nor a seek against this server.
- A failure now says what it was: the reason is printed with an
  `[easylivechat]` prefix, and in a **debug build** it is drawn in place of the
  tile. A voice note that silently turns into a download chip is
  indistinguishable from one the SDK never recognised as audio, and telling
  those two apart by guesswork cost two releases.
- The iOS audio session is put back to `playback` before a note starts. The
  same app records voice notes, and `record` leaves the session in
  `playAndRecord` — which routes playback to the **earpiece**, so a note plays
  at a whisper against the side of your head.

## 0.1.68


- **Voice messages play in the thread.** The SDK has recorded and sent them
  since 0.1.66, but what came back rendered through the generic attachment
  path — `_richTile` special-cased images and every other kind fell through to
  the download chip. A visitor's own recording came back as a uuid with a
  download arrow beside it, and hearing it meant saving a file and leaving the
  chat. A voice note now gets a play button, a progress bar you can scrub, and
  its running time. Only one plays at a time, audio the device cannot decode
  still falls back to the chip so the file is never unreachable, and the tile
  is keyed by url so a message arriving mid-listen does not restart it.
- Nothing is fetched until play is pressed. Reading a duration out of
  `audioplayers` means loading the file, so a thread holding twenty notes would
  otherwise pull twenty audio files over mobile data purely to print their
  lengths. Until a note has been played once the tile says what it is instead
  of how long it runs.
- **`kmr` is Badini, not Kurmanji.** The six voice and microphone strings added
  in 0.1.66 were written in Latin-script Kurmanji, while the other fifty-six in
  that locale are Arabic-script Badini — which is what `kmr` means everywhere
  else in the product (`Kurdish (Badini)` in every picker), and what the SDK's
  own RTL list already assumed, so they were Latin text laid out right-to-left.
  They now read as Badini, as do the three new playback strings.
- `l10n/sdk_strings.json` had fallen ten keys behind the compiled table, so
  running `l10n/apply.py` — the documented way to edit these strings — would
  have silently deleted every voice and AI string from all thirteen locales.
  The JSON is the source of truth again.

## 0.1.67

- The "AI" badge and the assistant's name appear only on the AI assistant's
  replies. The automatic greeting was badged "AI" too (for example
  "Zirak · AI" above a workspace's own greeting, with no assistant switched on).
  Greetings now render like any other message from the business.
- Requires `easylivechat` 0.1.52.

## 0.1.66

- **Voice messages.** When the workspace turns them on (dashboard → Widget), the
  composer shows a microphone beside the paperclip; recording replaces the text
  field with a running timer, and stopping sends. Records AAC in m4a. Off by
  default, and invisible while the workspace has them off.
- **Host app changes this release needs** — voice messages come from the new
  `record` dependency:
  - **Android:** `record` adds `RECORD_AUDIO` to your merged manifest, whether or
    not your workspace uses voice messages, and your Play Data safety answers
    follow it. If you will never use them, remove it in
    `android/app/src/main/AndroidManifest.xml`:
    `<uses-permission android:name="android.permission.RECORD_AUDIO" tools:node="remove" />`
    (with `xmlns:tools="http://schemas.android.com/tools"` on `<manifest>`).
  - **iOS:** add `NSMicrophoneUsageDescription` to `Info.plist`. Without it iOS
    terminates the app the moment a visitor starts recording.
  - **macOS:** the same `NSMicrophoneUsageDescription`, plus the
    `com.apple.security.device.audio-input` entitlement for sandboxed apps.
- Assistant replies say they are automated: the assistant's name and an "AI"
  badge above every `BOT` message, shown even when the workspace hides agent
  names — hiding a colleague's name is the tenant's choice, hiding that nobody
  is there is not. They were drawn exactly like a colleague's, and with names
  off like nobody's. Matches the web widget.
- While the assistant covers a closed or busy workspace, the notice says it can
  help in the meantime instead of "leave a message and we'll reply when we're
  back", and the tenant's leave-a-message copy gives way to it. The reopening
  time stays: it is when a person is back.
- "Assistant is typing…" while the assistant composes a reply.
- New strings in all thirteen locales: `aiBadge`, `assistantTyping`,
  `closedAssistantNotice`, `noAgentsAssistantNotice` — overridable like the rest.
- Requires `easylivechat` 0.1.51.
- `file_picker` ^10.3.3 (was ^8.1.0). 8.x compiles against Android API 34 and
  `flutter_plugin_android_lifecycle` 2.0.35 requires 36, so a fresh Android
  build of a host app failed in `:file_picker:checkDebugAarMetadata`.
- `record` ^6.2.1 (was ^5.1.0). record 5.x accepts `record_linux` 0.7.x, which
  does not implement `record_platform_interface` 1.6.0, published 2026-05-22 —
  so since then a fresh resolution of this package failed to compile on every
  platform, not only Linux. Apps with an older lockfile were unaffected until
  they ran `pub upgrade`.

## 0.1.65

- An EMPTY composer keeps facing the way the visitor writes. 0.1.64 turned the
  box around from the text in it, which left the moment before the first
  character — and every moment after a send cleared it — back on the
  workspace's direction. The keyboard's language would settle it and no
  Flutter API exposes it (reading `UITextInputMode` / `InputMethodManager`
  needs native code, which would make this a plugin), so the box now remembers
  what was last written in it, persisted per device, and falls back to the
  phone's own language before the workspace's. Type one Kurdish message and it
  stays right-to-left — next message, next visit.

## 0.1.64

- The composer faces the way you are typing. It took the workspace's
  direction, so a visitor writing Arabic, Sorani or Urdu into a left-to-right
  workspace typed into a box pointing the wrong way: caret on the wrong end,
  text against the wrong edge, punctuation on the wrong side. Neither iOS nor
  Android tells an app what language the keyboard is in, so the first strongly
  directional character decides — the rule `dir="auto"` uses on the web. An
  empty box, or one holding only digits or emoji, keeps the workspace's
  direction.
- Message bubbles do the same with their own text, so a thread where the
  visitor writes Arabic and the agent answers in English reads correctly on
  both sides instead of forcing one direction on the whole conversation.

## 0.1.63

- Requires `easylivechat` 0.1.50, which asks the server for the host inbox's
  configuration rather than the workspace default. Nothing in this package
  changed; the constraint is what stops a host resolving fresh from getting a
  core that still ignores its channel.

## 0.1.62

- Requires `easylivechat` 0.1.49, which sends an identified visitor's phone
  number on the resume path and persists it. Nothing in this package changed;
  raising the constraint is what stops a host resolving fresh from getting the
  old core and wondering why the agent still sees no phone.

## 0.1.61

- Images in the thread open full-screen. Attachments only ever rendered as
  240×220 `cover` tiles, which is a thumbnail — a screenshot of the error the
  visitor is writing in about was unreadable, and no gesture enlarged it.
  Tapping one now opens a viewer with pinch-zoom, pan and double-tap-to-zoom
  (toward the point tapped, not the middle). A tap on the backdrop leaves, but
  not while zoomed in — there a tap is how a pan ends — and the × closes at any
  scale.
- The composer shows the picture you picked, not its filename. A pending image
  attachment was a paperclip chip reading `IMG_20260814_113255.jpg`, which
  says nothing about which of four screenshots was attached — the one thing
  worth checking before hitting send. It is now a 56px thumbnail, drawn from
  the bytes already read for the upload (so it appears instantly and costs no
  second download), tappable to preview full-size, with the remove × on its
  corner. Non-images keep the chip: a filename IS what identifies a PDF.
- New chrome strings `close` and `removeAttachment` in all 12 locales.

## 0.1.60

- The post-chat form's Submit button takes the host app's typeface. Its label
  carried a bare `TextStyle`, and `ElevatedButton.styleFrom(textStyle:)`
  replaces a button's text style rather than merging into it — so the family
  the app had set was dropped and Submit could render in a different face from
  the form around it. The style is now derived from the ambient
  `textTheme.labelLarge`, keeping the family (and the package it ships in) and
  overriding only size and weight, the way the end-chat dialog already did.

## 0.1.59

- The keyboard stays up when you send. Flutter's default finalize-editing
  unfocuses the field for `TextInputAction.send`, so tapping the keyboard's
  send key collapsed the keyboard on every message — and made the thread shake:
  the viewport grew as the keyboard left while the auto-scroll was already
  animating to the old extent, so the list scrolled, resized and settled again.
  Supplying `onEditingComplete` replaces that default, which is the documented
  way to keep focus; the send stays on `onSubmitted` so nothing sends twice,
  and `clearComposing()` still runs so an in-progress IME composition does not
  survive the send.

## 0.1.58

- Requires `easylivechat` 0.1.48 for `EasyLiveChat.reset()`. Nothing in this
  package changed; raising the constraint is what guarantees a host resolving
  fresh gets the new API rather than a version without it.

## 0.1.57

- A message that is only pictures no longer sits in a bubble. The bubble exists
  to put a surface behind text, and wrapped around a photo it read as a thick
  coloured frame — on the visitor's own side that is the full accent colour, so
  their own images arrived matted in it. The tile already rounds its own
  corners, so the photo now renders bare, the way every other messenger draws
  one.
  Deliberately narrow: a caption still gets its bubble, and so do file chips and
  unavailable-media placeholders, which read as controls and would float loose
  without a surface behind them.

## 0.1.56

- The thread follows the visitor's own message down again. Auto-scroll was gated
  on already being near the bottom, on the assumption that a send always comes
  from there — it doesn't. Scroll up to re-read something, answer it from where
  you are, and the message landed off screen, so the thread looked like it had
  swallowed what you just sent. The keyboard opening moves the scroll extent
  too, which could push a visitor out of the window without their having
  scrolled at all.
  Their own message now always scrolls into view. An incoming one still respects
  the gate, so an agent's reply cannot yank someone out of history they are in
  the middle of reading.

## 0.1.55

- Requires `easylivechat` 0.1.47, which stops the replying agent's name and
  photo being wiped off a bubble by the delivery receipt the visitor's own
  client sends moments later. Nothing in this package changed: `MessageBubble`
  renders whatever identity the message carries, and it was the message losing
  it. Raising the constraint is what guarantees a host resolving fresh picks up
  the fix rather than staying on 0.1.46.

## 0.1.54

- The thread shows sent/read ticks on the visitor's own messages: a clock while
  the send is in flight, one tick once the server has it, two in the workspace
  accent once an agent has read it. Matches the web widget, so a customer who
  uses both surfaces reads the same marks. A failed send keeps its worded retry
  link — it is the only state the visitor can act on, so it stays a sentence
  rather than becoming an icon to interpret.
  Each state carries a screen-reader label (`messageSent`, `messageRead`, and
  the existing `sending`), translated into all 13 locales — the tick is the
  entire visual, so without them it announced nothing at all.
  `MessageBubble` takes an optional `agentLastReadAt` for hosts embedding it
  directly; omitted, it simply never shows the read state.

## 0.1.53

- Session-divider dates and times are formatted in this package instead of
  through the host's `MaterialLocalizations`. Two of the 13 chrome languages —
  ckb and kmr — have no Flutter Material localizations, so a host supporting
  them must supply its own delegate, and one with a bad pattern rendered a date
  as literal format characters (`٠٨/٢٢٤/YY`) with no way for the SDK to tell
  that from a real date. Now built from the parts: `dd/MM/yyyy` and `HH:mm`,
  Western digits, wrapped in a Unicode isolate so a numeric run keeps its own
  reading order inside right-to-left copy.
- The post-chat form's Submit button is full width, matching the fields above
  it, instead of shrinking to its label in the middle of the sheet.

## 0.1.52

- The date on a session divider reads correctly in right-to-left locales.
  `12/08/2026` is digits joined by neutral characters, and neutrals take the
  direction of the text around them — so in Kurdish (kmr, ckb) the groups were
  laid out right-to-left and a correct date arrived on screen looking like
  `٢٢/٠٨/٢٢٤`. Arabic hid the bug only because its short format uses a month
  name, whose strong letters pin the order. The date and the "you left the chat"
  time are now wrapped in a Unicode isolate, so each keeps its own reading order
  without leaking direction into the sentence around it.

## 0.1.51

- Kurmanji (kmr): corrected the wording of the failed-send retry line.

## 0.1.50

- Requires `easylivechat` ^0.1.45. The floor moves because behaviour this
  package presents now depends on it: "Close chat" only offers the post-chat
  survey on a second visit with core 0.1.45. `^0.1.42` still *allowed* 0.1.45,
  but it also allowed 0.1.42 — and a consumer holding an old lockfile would
  keep a UI whose end-chat button silently does nothing, which is the bug that
  release fixed.
- Corrected the Kurmanji (kmr) strings. Seven were still untranslated
  Latin-script placeholders — the close-chat button, the survey skip, the
  session notices and the post-chat title all showed romanised text to a
  Badini reader — and the rest are retranslations from a native speaker.

## 0.1.49

- Activated the lints. `flutter_lints` was a dev-dependency with no
  `analysis_options.yaml` including it, so local analysis had no rules at all
  while pub.dev scored against lints_core — which is how a missing pair of
  braces cost 10 points with every local check passing.
- Fixed the guard clause it flagged in the closed-notice view, and three
  `const` opportunities in the example. No behaviour change.

## 0.1.48

- The auto-greeting shows a face and a name again. An inbound bubble now always
  gets an avatar when the workspace has the switch on, instead of only when the
  message already carries a name or a photo. A chat opened before it is assigned
  has a greeting attributed to nobody, so the very first bubble of the thread
  was blank while every later one had a photo — and it stayed blank for the life
  of the conversation. The web widget has always drawn a circle here and fallen
  back to an initial; this matches it. System notices are unaffected: they
  render as centred lines and never reach the avatar path.
- Needs the matching server change to put a name on a greeting that was written
  while nobody was assigned — the client half only guarantees the circle.

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
