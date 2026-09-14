import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';

/// A voice message you can listen to, rather than a file you have to download.
///
/// The SDK has recorded and sent voice notes since `easylivechat_ui` 0.1.66,
/// but the thread rendered what came back as a generic attachment chip —
/// `_richTile` special-cased images and everything else fell through to the
/// download chip. A visitor's own recording came back as a uuid with a
/// download arrow next to it, and hearing it meant saving a file and leaving
/// the chat.
///
/// Playback is **lazy**: no player exists and nothing is fetched until the
/// visitor presses play. Reading a duration out of `audioplayers` means
/// loading the file, so a thread holding twenty voice notes would pull twenty
/// audio files over mobile data purely to print their lengths. Until a note
/// has been played once the tile says what it is instead of how long it runs.
///
/// Only one note plays at a time — starting one pauses whichever was running,
/// as every messaging app does.
class ElcVoiceNoteTile extends StatefulWidget {
  /// Already resolved to an absolute URL by the caller.
  final String url;

  /// The bubble's text colour. Everything here is drawn from it at varying
  /// alpha, so one tile works on both the accent bubble the visitor's own
  /// messages get and the neutral one the agent's arrive in.
  final Color foreground;

  final ElcStrings strings;

  /// Shown if the audio cannot be played at all — a device with no codec for
  /// it, a URL that 404s. The visitor keeps the download chip rather than
  /// being left with a dead control.
  final Widget fallback;

  const ElcVoiceNoteTile({
    super.key,
    required this.url,
    required this.foreground,
    required this.strings,
    required this.fallback,
  });

  @override
  State<ElcVoiceNoteTile> createState() => _ElcVoiceNoteTileState();
}

class _ElcVoiceNoteTileState extends State<ElcVoiceNoteTile> {
  /// The note currently holding the floor. Static because the rule is "one at
  /// a time" across the whole thread, not within one bubble.
  static _ElcVoiceNoteTileState? _current;

  AudioPlayer? _player;
  final List<StreamSubscription<dynamic>> _subs = [];

  Duration _position = Duration.zero;
  Duration? _total;
  bool _playing = false;
  bool _loading = false;
  bool _failed = false;

  @override
  void dispose() {
    if (identical(_current, this)) _current = null;
    for (final sub in _subs) {
      sub.cancel();
    }
    _player?.dispose();
    super.dispose();
  }

  AudioPlayer _createPlayer() {
    final player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
    _subs.add(player.onDurationChanged.listen((d) {
      if (!mounted) return;
      setState(() {
        _total = d;
        _loading = false;
      });
    }));
    _subs.add(player.onPositionChanged.listen((d) {
      if (!mounted) return;
      setState(() => _position = d);
    }));
    _subs.add(player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() {
        _playing = state == PlayerState.playing;
        if (_playing) _loading = false;
      });
    }));
    // Rewind on finish, so pressing play again replays instead of sitting at
    // the end doing nothing.
    _subs.add(player.onPlayerComplete.listen((_) async {
      try {
        await player.seek(Duration.zero);
      } catch (_) {
        // A player disposed mid-completion: nothing left to rewind.
      }
      if (!mounted) return;
      setState(() {
        _position = Duration.zero;
        _playing = false;
      });
    }));
    return player;
  }

  Future<void> _pauseQuietly() async {
    try {
      await _player?.pause();
    } catch (_) {
      // Losing the floor is never worth an exception.
    }
  }

  Future<void> _toggle() async {
    if (_failed) return;
    final player = _player;
    if (_playing && player != null) {
      await _pauseQuietly();
      return;
    }
    final other = _current;
    if (other != null && !identical(other, this)) {
      await other._pauseQuietly();
    }
    _current = this;
    try {
      if (player == null) {
        final created = _player = _createPlayer();
        if (mounted) setState(() => _loading = true);
        await created.play(UrlSource(widget.url));
      } else {
        await player.resume();
      }
    } catch (_) {
      if (!mounted) return;
      // One failure is enough: fall back to the chip so the visitor can still
      // save the file.
      setState(() {
        _failed = true;
        _loading = false;
        _playing = false;
      });
    }
  }

  Future<void> _seekToFraction(double fraction) async {
    final total = _total;
    final player = _player;
    if (player == null || total == null || total.inMilliseconds == 0) return;
    final target = Duration(
      milliseconds: (total.inMilliseconds * fraction.clamp(0.0, 1.0)).round(),
    );
    try {
      await player.seek(target);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() => _position = target);
  }

  /// `m:ss`. The elapsed time once it is running, its length before that, and
  /// the word for what it is until the file has been loaded and either is
  /// known.
  String get _label {
    final total = _total;
    if (total == null) return widget.strings.voiceMessage;
    if (_position == Duration.zero) return _formatted(total);
    return _formatted(_position);
  }

  static String _formatted(Duration d) {
    final seconds = d.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.fallback;
    final fg = widget.foreground;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: fg.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _playButton(fg),
            const SizedBox(width: 10),
            SizedBox(
              width: 132,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _progressBar(fg),
                  const SizedBox(height: 4),
                  Text(
                    _label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg.withValues(alpha: 0.75),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playButton(Color fg) {
    final strings = widget.strings;
    return Semantics(
      button: true,
      label: _playing ? strings.pauseVoice : strings.playVoice,
      child: GestureDetector(
        onTap: _toggle,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: fg.withValues(alpha: 0.15),
          ),
          alignment: Alignment.center,
          child: _loading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      fg.withValues(alpha: 0.7),
                    ),
                  ),
                )
              // Both glyphs are symmetrical, so neither needs mirroring in
              // RTL — unlike a "skip" or "next" arrow would.
              : Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 20,
                  color: fg,
                ),
        ),
      ),
    );
  }

  Widget _progressBar(Color fg) {
    final total = _total;
    final value = (total == null || total.inMilliseconds == 0)
        ? 0.0
        : (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        // LinearProgressIndicator fills from the trailing edge under RTL on
        // its own, so only the hit test has to be mirrored back.
        final rtl = Directionality.of(context) == TextDirection.rtl;
        void seek(Offset local) {
          final width = constraints.maxWidth;
          if (width <= 0) return;
          final fraction = local.dx / width;
          _seekToFraction(rtl ? 1 - fraction : fraction);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => seek(d.localPosition),
          onHorizontalDragUpdate: (d) => seek(d.localPosition),
          child: SizedBox(
            // Taller than the bar it draws: 4px of progress is an impossible
            // drag target, 16 is a comfortable one.
            height: 16,
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 4,
                  backgroundColor: fg.withValues(alpha: 0.22),
                  valueColor: AlwaysStoppedAnimation<Color>(fg),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
