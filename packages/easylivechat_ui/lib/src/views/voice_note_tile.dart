import 'dart:async';
import 'dart:io' show Directory, File, FileSystemException, HttpClient;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';

/// A voice message you can listen to, with its length and a seek bar.
///
/// ## Why the file is downloaded before it is played
///
/// The obvious implementation — hand `UrlSource` to `audioplayers` and let it
/// stream — does not work against this API. `routes/uploads.ts` serves every
/// upload as a single `200` with the whole body and **no `Accept-Ranges`**, so
/// it cannot answer a byte-range request. iOS plays remote media through
/// `AVPlayer`, which reads an MP4/M4A `moov` atom by issuing range requests;
/// with no range support the asset never loads and `play()` throws. That is
/// what turned a voice note back into a download chip the moment it was
/// tapped: the tile caught the failure and showed its fallback.
///
/// Fetching the file first sidesteps that (a plain GET needs no ranges), and
/// is what a voice note wants anyway:
///
///  - **A real duration, before anything is played.** It cannot be known
///    without the file, and a voice note that will not tell you whether it is
///    four seconds or four minutes is missing the one thing you need to decide
///    whether to listen now.
///  - **Seeking that works.** Dragging through a local file is instant; over a
///    server that cannot serve ranges it is impossible.
///
/// A recording is small — AAC at this bitrate is a few KB per second — and it
/// is cached under the system temp directory, so scrolling back through a
/// thread re-reads it from disk instead of the network.
///
/// Only one note plays at a time, and the tile is keyed by url upstream, so a
/// message arriving mid-listen neither restarts nor re-downloads it.
class ElcVoiceNoteTile extends StatefulWidget {
  /// Already resolved to an absolute URL by the caller.
  final String url;

  /// The bubble's text colour. Everything here is drawn from it at varying
  /// alpha, so one tile works on both the accent bubble the visitor's own
  /// messages get and the neutral one the agent's arrive in.
  final Color foreground;

  /// The surface to paint, when this tile is the whole message and the
  /// bubble behind it has been dropped. Null while it sits INSIDE a bubble
  /// (a note with a caption), where it stays a translucent inlay instead.
  final Color? background;

  final ElcStrings strings;

  /// Shown when the audio cannot be fetched or decoded at all — a dead
  /// control helps nobody, and the file stays reachable through the chip.
  final Widget fallback;

  const ElcVoiceNoteTile({
    super.key,
    required this.url,
    required this.foreground,
    required this.strings,
    required this.fallback,
    this.background,
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
  bool _preparing = true;
  bool _failed = false;

  /// Why it failed. Printed always, and shown on screen in a DEBUG
  /// build — a voice note that silently becomes a download chip is
  /// indistinguishable from one the SDK never recognised, which cost two
  /// releases of guessing at exactly that difference.
  String? _error;

  /// Bar heights, 0..1, drawn behind the playhead.
  List<double> _waveform = const [];

  /// Set while a finger is on the seek bar: the thumb follows the drag rather
  /// than the playhead, which would otherwise fight it.
  double? _dragFraction;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  @override
  void dispose() {
    if (identical(_current, this)) _current = null;
    for (final sub in _subs) {
      sub.cancel();
    }
    _player?.dispose();
    super.dispose();
  }

  /// Fetch (or reuse) the file and read its real duration.
  ///
  /// Two ways in: the local copy first (see the class doc), then the remote
  /// url. Streaming cannot serve a duration or a seek against this API, but
  /// half a voice note beats a download chip, and which one succeeded is the
  /// single most useful thing to know when it goes wrong.
  Future<void> _prepare() async {
    Object? localError;
    // The local copy first (see the class doc), then the remote url.
    try {
      final path = await cacheVoiceNote(widget.url);
      final bars = waveformOf(await File(path).readAsBytes());
      if (mounted) setState(() => _waveform = bars);
      await _adopt(DeviceFileSource(path));
      return;
    } catch (e) {
      localError = e;
      debugPrint('[easylivechat] voice note: local copy failed for '
          '${widget.url} — $e');
    }

    // Streaming can serve neither a duration nor a seek against a server that
    // will not do byte ranges, but half a voice note beats a download chip.
    try {
      await _adopt(UrlSource(widget.url));
    } catch (e) {
      debugPrint('[easylivechat] voice note: streaming failed too for '
          '${widget.url} — $e');
      if (!mounted) return;
      setState(() {
        _failed = true;
        _preparing = false;
        _error = 'fetch: $localError\nstream: $e';
      });
    }
  }

  /// Load [source] and take it as the tile's player.
  ///
  /// Both attempts go through here so neither can fall through into the other.
  /// They used to be two inline copies, and the first was missing its
  /// `return`: a local copy that loaded perfectly was then thrown away by a
  /// streaming attempt that could never work, and the tile reported the
  /// STREAMING error — reading `fetch: null`, which is to say "the part that
  /// works, worked".
  Future<void> _adopt(Source source) async {
    final player = _createPlayer();
    await player.setSource(source);
    // Ask outright rather than waiting on onDurationChanged: the answer is
    // already known once the source is set, and a stream that never fires
    // would leave the tile saying "Voice message" for ever.
    final duration = await player.getDuration();
    if (!mounted) {
      player.dispose();
      return;
    }
    _player = player;
    setState(() {
      _total = duration;
      _preparing = false;
    });
  }

  AudioPlayer _createPlayer() {
    final player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
    // The same app records voice notes, and `record` leaves the iOS audio
    // session in `playAndRecord` — which routes playback to the EARPIECE, so
    // a note plays at a whisper against the side of your head unless the
    // session is put back. Stating `playback` here is that reset. The default
    // is already `playback`, but the default is not applied unless a context
    // is set, and the session is process-wide.
    unawaited(player
        .setAudioContext(AudioContext(iOS: AudioContextIOS()))
        .catchError((_) {}));
    _subs.add(player.onDurationChanged.listen((d) {
      // A second opinion: some codecs only report a length once decoding has
      // actually started.
      if (!mounted || d <= Duration.zero) return;
      setState(() => _total = d);
    }));
    _subs.add(player.onPositionChanged.listen((d) {
      if (!mounted || _dragFraction != null) return;
      setState(() => _position = d);
    }));
    _subs.add(player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state == PlayerState.playing);
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
    final player = _player;
    if (_failed || _preparing || player == null) return;
    if (_playing) {
      await _pauseQuietly();
      return;
    }
    final other = _current;
    if (other != null && !identical(other, this)) {
      await other._pauseQuietly();
    }
    _current = this;
    try {
      await player.resume();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
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
    setState(() => _position = target);
    try {
      await player.seek(target);
    } catch (_) {
      // A seek the platform refused leaves the playhead where it was.
    }
  }

  double get _fraction {
    final drag = _dragFraction;
    if (drag != null) return drag;
    final total = _total;
    if (total == null || total.inMilliseconds == 0) return 0;
    return (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }

  /// Its length until it is played, then the elapsed time — the way every
  /// messaging app reads. Only while the file is still arriving is there
  /// neither, and then it says what it is.
  String get _label {
    final total = _total;
    if (total == null) return widget.strings.voiceMessage;
    final atStart = _position == Duration.zero && _dragFraction == null;
    return _formatted(atStart ? total : _position);
  }

  static String _formatted(Duration d) {
    final seconds = d.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      final reason = _error;
      // Release builds keep the chip: the file is still reachable, and a
      // visitor must never be shown a stack trace.
      if (!kDebugMode || reason == null) return widget.fallback;
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFB91C1C).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFB91C1C)),
          ),
          child: Text(
            reason,
            textDirection: TextDirection.ltr,
            style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 10),
          ),
        ),
      );
    }
    final fg = widget.foreground;
    final standalone = widget.background;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          // Standing alone it IS the bubble, so it paints the bubble's colour
          // and takes the bubble's corners. Inlaid in one (a note with a
          // caption) it stays a translucent panel on the surface behind it.
          color: standalone ?? fg.withValues(alpha: 0.08),
          borderRadius: standalone == null
              ? BorderRadius.circular(10)
              : const BorderRadius.all(Radius.circular(16)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _playButton(fg),
            const SizedBox(width: 10),
            SizedBox(
              width: 140,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _seekBar(fg),
                  const SizedBox(height: 2),
                  Text(
                    _label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg.withValues(alpha: 0.75),
                      fontSize: 12,
                      fontFeatures: const [FontFeature.tabularFigures()],
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
          child: _preparing
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
              // Both glyphs are symmetrical, so neither is mirrored in RTL —
              // unlike a "skip" or "next" arrow would be.
              : Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 20,
                  color: fg,
                ),
        ),
      ),
    );
  }

  Widget _seekBar(Color fg) {
    final bars = _waveform.isEmpty ? _flatWaveform : _waveform;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final rtl = Directionality.of(context) == TextDirection.rtl;
        final fraction = _fraction;

        double fractionFor(double dx) {
          if (width <= 0) return 0;
          // localPosition is physical; the bars run the other way in RTL.
          return ((rtl ? width - dx : dx) / width).clamp(0.0, 1.0);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _seekToFraction(fractionFor(d.localPosition.dx)),
          onHorizontalDragStart: (d) =>
              setState(() => _dragFraction = fractionFor(d.localPosition.dx)),
          onHorizontalDragUpdate: (d) =>
              setState(() => _dragFraction = fractionFor(d.localPosition.dx)),
          onHorizontalDragEnd: (_) {
            final target = _dragFraction;
            setState(() => _dragFraction = null);
            if (target != null) unawaited(_seekToFraction(target));
          },
          child: SizedBox(
            // Taller than the bars: a 22px band is a comfortable drag target
            // where the 3px columns themselves are not.
            height: 26,
            // A Row mirrors itself under RTL, so playback fills from the
            // leading edge in both directions with no arithmetic.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (var i = 0; i < bars.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 0.8),
                      child: Container(
                        height: 4 + bars[i] * 18,
                        decoration: BoxDecoration(
                          // Played bars are solid; the rest recede.
                          color: (i + 0.5) / bars.length <= fraction
                              ? fg
                              : fg.withValues(alpha: 0.32),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Fetch [url] into the temp directory, or reuse what is already there.
///
/// Visible for testing: the concurrent case is the one that broke, and it
/// cannot be reached through the widget without a real network.
///
/// `Directory.systemTemp` rather than a `path_provider` dependency, matching
/// the recorder in `composer_bar.dart`: on iOS and Android it is already a
/// per-app sandboxed location the OS may reclaim, which is exactly right for
/// a cache.
@visibleForTesting
Future<String> cacheVoiceNote(String url) {
  // One download per url, however many tiles ask for it.
  //
  // A message re-keys from its optimistic `tmp-` id to the server's, which
  // re-mounts the tile while the first download is still running, so two
  // fetches of the same note overlap routinely — it is the normal case for
  // the visitor's OWN recording, not an edge case. Sharing the future means
  // the second caller waits on the first instead of racing it, and the note
  // crosses the network once.
  final existing = _inFlight[url];
  if (existing != null) return existing;
  final fetch = _fetchVoiceNote(url);
  _inFlight[url] = fetch;
  return fetch.whenComplete(() => _inFlight.remove(url));
}

final Map<String, Future<String>> _inFlight = {};

Future<String> _fetchVoiceNote(String url) async {
  final dir = Directory('${Directory.systemTemp.path}/easylivechat-voice');
  if (!await dir.exists()) await dir.create(recursive: true);
  final file = File('${dir.path}/${_cacheName(url)}');
  if (await file.exists() && await file.length() > 0) return file.path;

  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw StateError('voice note fetch failed: HTTP ${response.statusCode}');
    }
    final bytes = await consolidateHttpClientResponseBytes(response);
    if (bytes.isEmpty) {
      throw StateError('voice note fetch returned an empty body');
    }
    // The scratch name is unique to THIS attempt. Two tiles can be preparing
    // the same url at once — a message re-keys from its optimistic `tmp-` id
    // to the server's, which re-mounts the tile while the first download is
    // still running — and a single shared `.part` meant whichever finished
    // first renamed the file out from under the other, which then failed with
    // ENOENT. That is the "Cannot rename file … No such file or directory"
    // this used to die on, every time, on the visitor's own recording.
    final scratch =
        File('${file.path}.${DateTime.now().microsecondsSinceEpoch}.part');
    await scratch.writeAsBytes(bytes, flush: true);
    try {
      await scratch.rename(file.path);
    } on FileSystemException {
      // Lost the race: the other attempt already put the file there, which is
      // the same bytes and just as good.
      try {
        await scratch.delete();
      } catch (_) {
        // A scratch file the OS will reclaim anyway.
      }
      if (await file.exists()) return file.path;
      rethrow;
    }
    return file.path;
  } finally {
    client.close();
  }
}

/// The uploaded name is already a uuid, so it needs no hashing — only
/// stripping of anything that is not safe in a path.
String _cacheName(String url) {
  final path = Uri.parse(url).path;
  final last = path.split('/').where((s) => s.isNotEmpty).lastOrNull ?? 'voice';
  final safe = last.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return safe.isEmpty ? 'voice' : safe;
}

/// A flat bar row, for the moment before the file has been read.
final List<double> _flatWaveform = List<double>.filled(32, 0.22);

/// Bar heights for a voice note, derived from the file's own bytes.
///
/// **Decorative, not an amplitude envelope.** A true waveform means decoding
/// the AAC to PCM, which needs a platform decoder this package deliberately
/// does not carry — so these bars are a stable fingerprint of the compressed
/// payload, not a measurement of loudness. Two different notes look different
/// and one note always looks the same; a quiet passage is not drawn short.
///
/// Frame sizes in a variable-bitrate stream do loosely track how much signal
/// there is, so this is not pure noise — but it is not a reading either, and
/// nothing in the UI claims it is.
@visibleForTesting
List<double> waveformOf(List<int> bytes, {int bars = 32}) {
  if (bytes.isEmpty) return List<double>.filled(bars, 0.22);
  // Skip the container header, which is identical across recordings and would
  // otherwise give every note the same opening bars.
  const skip = 1024;
  final start = bytes.length > skip * 2 ? skip : 0;
  final span = bytes.length - start;
  final out = <double>[];
  for (var i = 0; i < bars; i++) {
    final from = start + (span * i) ~/ bars;
    final to = start + (span * (i + 1)) ~/ bars;
    var sum = 0;
    var count = 0;
    // Sample rather than read every byte: a minute of audio is a megabyte,
    // and 64 samples a bucket is plenty to vary a 20px column.
    final step = ((to - from) ~/ 64).clamp(1, 1 << 20);
    for (var j = from; j < to; j += step) {
      sum += (bytes[j] - 128).abs();
      count++;
    }
    out.add(count == 0 ? 0.22 : (sum / count / 128).clamp(0.08, 1.0));
  }
  // Normalise so every note uses the full height, rather than all of them
  // hovering around the middle.
  final peak = out.reduce((a, b) => a > b ? a : b);
  if (peak <= 0) return List<double>.filled(bars, 0.22);
  return [for (final v in out) (v / peak).clamp(0.12, 1.0)];
}
