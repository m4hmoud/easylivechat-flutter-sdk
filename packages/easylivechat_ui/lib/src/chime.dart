import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:easylivechat/easylivechat.dart';

/// The sound an arriving agent reply makes.
///
/// The visitor is usually looking at something else in the host app when a
/// reply lands, so the thread updating silently means they simply miss it —
/// the web widget has always chimed here, and this brings the Flutter SDK in
/// line, down to the same audio file and the same half volume.
///
/// Only AGENT messages ring: not the visitor's own echoes, not bot greetings,
/// not the SYSTEM transfer notices — matching the web widget exactly. The
/// tenant's `soundEnabled` / `soundUrl` widget config is honoured, so turning
/// the sound off in the dashboard turns it off here too, and a workspace that
/// uploaded its own chime hears that one instead of the bundled default.
///
/// Mounting is ref-counted: the launcher bubble and the chat screen can both
/// be alive at once, and a single subscription means a reply that arrives with
/// both on screen chimes once rather than twice.
class ElcChime {
  ElcChime._();

  static final ElcChime instance = ElcChime._();

  /// Bundled fallback — the same file the web widget serves visitors. Package
  /// assets carry a `packages/<name>/` prefix once bundled into a host app,
  /// which is already the whole key, hence the empty [AudioCache] prefix
  /// below (the default `assets/` would look for `assets/packages/…`).
  static const _bundledAsset = 'packages/easylivechat_ui/assets/sounds/message.mp3';

  /// Matches the web widget's `audioRef.volume = 0.5`: audible without
  /// startling someone holding the phone to their ear.
  static const _volume = 0.5;

  AudioPlayer? _player;
  StreamSubscription<ChatMessage>? _sub;
  int _mounts = 0;

  /// Start listening. Call from `initState` of any widget that should chime.
  void attach() {
    _mounts++;
    _sub ??= EasyLiveChat.instance.onMessage.listen(_handleMessage);
  }

  /// Stop listening once the last mounted widget goes. Call from `dispose`.
  void detach() {
    if (_mounts > 0) _mounts--;
    if (_mounts > 0) return;
    _sub?.cancel();
    _sub = null;
    _player?.dispose();
    _player = null;
  }

  /// Whether this arrival should make a sound.
  ///
  /// Split out from the playback so the rule is testable without an audio
  /// device: a chime is for someone ELSE reaching the visitor, which is the
  /// agent and nothing else.
  static bool shouldChime(ChatMessage message, {required bool soundEnabled}) {
    if (!soundEnabled) return false;
    return message.isFromAgent;
  }

  void _handleMessage(ChatMessage message) {
    final config = EasyLiveChat.instance.widgetConfig.value;
    // Config not loaded yet: the tenant default is sound on, so ring rather
    // than swallow the first reply of a session.
    if (!shouldChime(message, soundEnabled: config?.soundEnabled ?? true)) {
      return;
    }
    unawaited(_play(config?.soundUrl));
  }

  Future<void> _play(String? soundUrl) async {
    // A chime is never worth an exception: no audio route, a codec the device
    // won't decode, a tenant sound URL that 404s — the reply still arrived and
    // the thread still shows it.
    try {
      final player = _player ??= AudioPlayer()
        // Our own cache rather than the shared `AudioCache.instance`: the
        // prefix has to be empty for a package asset, and rewriting the
        // global one would move every asset path in the HOST's app.
        ..audioCache = AudioCache(prefix: '')
        ..setReleaseMode(ReleaseMode.stop);
      // Restart rather than overlap when replies arrive back to back.
      await player.stop();
      await player.setVolume(_volume);
      final url = soundUrl?.trim();
      await player.play(
        url != null && url.isNotEmpty
            ? UrlSource(url)
            : AssetSource(_bundledAsset),
      );
    } catch (_) {
      // Deliberately swallowed.
    }
  }
}
