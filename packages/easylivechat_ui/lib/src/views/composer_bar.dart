import 'dart:async';
import 'dart:io' show Directory, File;

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:easylivechat/easylivechat.dart';
import 'dart:typed_data' show Endian, Uint8List;

import 'package:flutter/foundation.dart' show ValueListenable, visibleForTesting;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bidi.dart';
import '../l10n.dart';
import '../picked_file.dart';
import '../theme.dart';
import 'image_viewer.dart';
import 'voice_levels.dart';

/// The message composer (native analog of the web `Composer.tsx`).
///
/// A text field + send button (tinted [EasyLiveChatTheme.primary]) + an attach
/// button. Attachments are picked (image via `image_picker`, any file via
/// `file_picker`), read to bytes, uploaded with
/// `EasyLiveChat.instance.uploadBytes`, and the returned server-relative URLs
/// are linked to the message via `sendMessage(text, attachmentUrls: [...])` —
/// the send itself is optimistic (the controller pushes a `tmp-` bubble).
///
/// Typing presence follows the FIELD, not the keystrokes: `setTyping(true)`
/// repeats every 2s for as long as the box has text, and `setTyping(false)`
/// fires the moment it empties, on send, or on teardown.
class ComposerBar extends StatefulWidget {
  final EasyLiveChatTheme theme;

  /// Host hook that fully owns attachment picking (e.g. the app's own
  /// camera/gallery bottom sheet). When set, the attach button calls this and
  /// uploads whatever it returns, instead of the built-in image/file pickers.
  final ElcAttachmentPicker? onPickAttachments;

  const ComposerBar({super.key, required this.theme, this.onPickAttachments});

  @override
  State<ComposerBar> createState() => _ComposerBarState();
}

class _ComposerBarState extends State<ComposerBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();

  /// Voice messages. The recorder is created lazily so a workspace that never
  /// turns them on pays nothing for it, and disposed on the way out — a
  /// recorder left holding the microphone keeps the OS indicator lit.
  AudioRecorder? _recorder;
  bool _recording = false;
  int _recordSeconds = 0;
  Timer? _recordTicker;
  String? _recordPath;

  /// Paused mid-take. The microphone is off but the audio is kept, and
  /// `resume()` appends to the SAME file — so continuing really continues,
  /// rather than starting a second recording that would have to be merged.
  bool _paused = false;

  /// Set once the take has been CLOSED so it can be listened to.
  ///
  /// `record` writes an m4a progressively and only finalises the container on
  /// `stop()`, so a paused recording is not yet a playable file: previewing
  /// has to end the take. Once it is set the microphone button goes, because
  /// there is no longer anything to append to. Recording, pausing, deleting
  /// and sending are unaffected — only "listen, then carry on talking" is out
  /// of reach, and it needs an uncompressed format to be possible at all.
  String? _reviewPath;

  AudioPlayer? _preview;
  bool _previewPlaying = false;
  Duration _previewPos = Duration.zero;
  Duration? _previewTotal;
  final List<StreamSubscription<dynamic>> _previewSubs = [];

  /// Input levels, one per sample interval, drawn as the waveform. Real
  /// amplitudes off the microphone — unlike the ones the THREAD draws for a
  /// received note, which cannot be measured without decoding it.
  ///
  /// A notifier rather than plain state: at sixteen samples a second,
  /// `setState` on the composer rebuilt the text field, the buttons and the
  /// pending-attachment strip sixteen times a second to move some bars.
  final ValueNotifier<List<double>> _levels =
      ValueNotifier<List<double>>(const <double>[]);
  StreamSubscription<Amplitude>? _ampSub;

  /// Kept for the whole take, so the review can draw all of it. Five minutes
  /// at this rate is ~4800 doubles, which is nothing.
  static const Duration _levelInterval = Duration(milliseconds: 60);

  /// Which way the visitor writes, remembered for when the box is EMPTY.
  ///
  /// With text in it the text decides (see [textDirectionOf]). With nothing in
  /// it there is nothing to read, and the keyboard's language — the thing that
  /// would actually answer this — is not exposed to a Flutter app by either
  /// platform. So the last thing this visitor wrote stands in for it: type one
  /// Kurdish message and the box stays right-to-left for the next one, and for
  /// the next visit, rather than snapping back to the workspace's direction
  /// every time it clears.
  TextDirection? _rememberedDirection;

  /// Where that memory lives. Not in `EasyLiveChatStorage`: this is a UI
  /// preference on this device, not part of the visitor's identity, and it
  /// must not be swept by `reset()` when somebody signs out — the next person
  /// on a shared phone probably writes the same language.
  static const _directionKey = 'easylivechat:composer_direction';

  /// Repeats `true` while the field has text; cancelled when it empties.
  Timer? _typingKeepAlive;
  bool _typingActive = false;

  /// Uploaded attachments awaiting send, each with the bytes it was uploaded
  /// from so the strip can draw the picture rather than name it.
  final List<_PendingAttachment> _pending = [];
  bool _uploading = false;
  String? _attachError;

  EasyLiveChatTheme get _theme => widget.theme;
  ElcStrings get _s =>
      ElcStrings.of(EasyLiveChat.instance.widgetConfig.value?.locale);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _restoreDirection();
  }

  Future<void> _restoreDirection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_directionKey);
      if (saved == null || !mounted) return;
      setState(() {
        _rememberedDirection =
            saved == 'rtl' ? TextDirection.rtl : TextDirection.ltr;
      });
    } catch (_) {
      // A preference we cannot read just means we fall back a step further.
    }
  }

  /// Remember what the visitor is writing in, so the empty box keeps facing
  /// that way. Only called with a direction the TEXT actually established.
  void _rememberDirection(TextDirection d) {
    if (_rememberedDirection == d) return;
    setState(() => _rememberedDirection = d);
    SharedPreferences.getInstance()
        .then((p) => p.setString(_directionKey, d == TextDirection.rtl ? 'rtl' : 'ltr'))
        .catchError((_) => false);
  }

  @override
  void dispose() {
    _typingKeepAlive?.cancel();
    if (_typingActive) {
      // Best-effort: let the agent side know we stopped typing on teardown.
      EasyLiveChat.instance.setTyping(false);
    }
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focus.dispose();
    _recordTicker?.cancel();
    _ampSub?.cancel();
    _disposePreview();
    _levels.dispose();
    _recorder?.dispose();
    super.dispose();
  }

  // ── typing presence ──

  void _onTextChanged() {
    final written = textDirectionOf(_controller.text);
    if (written != null) _rememberDirection(written);
    final hasText = _controller.text.trim().isNotEmpty;
    if (!hasText) {
      _stopTyping();
      return;
    }
    if (!_typingActive) {
      _typingActive = true;
      EasyLiveChat.instance.setTyping(true);
    }
    // Keep announcing for as long as the field HAS TEXT — not merely while
    // keys are moving. The agent side clears its indicator a few seconds
    // after the last event it heard, so pausing mid-sentence would read as
    // "stopped typing" even though the visitor is still composing.
    _typingKeepAlive ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) => EasyLiveChat.instance.setTyping(true),
    );
  }

  void _stopTyping() {
    _typingKeepAlive?.cancel();
    _typingKeepAlive = null;
    if (_typingActive) {
      _typingActive = false;
      EasyLiveChat.instance.setTyping(false);
    }
  }

  // ── send ──

  /// True while the workspace is shut AND the tenant chose to take no message.
  ///
  /// Read through [_lockListenable] rather than once at build time: a visitor
  /// already sitting on the chat screen when closing time arrives has to see
  /// the composer lock, and a plain getter never rebuilds.
  bool get _locked =>
      EasyLiveChat.instance.isBooted && EasyLiveChat.instance.composerLocked;

  /// Rebuild trigger for [_locked] — the server pushes visitorMode on every
  /// availability change.
  ValueListenable<String>? get _lockListenable =>
      EasyLiveChat.instance.isBooted ? EasyLiveChat.instance.visitorMode : null;

  void _send() {
    final text = _controller.text.trim();
    final urls = _pending.map((p) => p.file.url).toList(growable: false);
    if (text.isEmpty && urls.isEmpty) return;

    _stopTyping();
    // Fire-and-forget optimistic send; the controller surfaces ack/echo via
    // `messages` (a failure shows as a failed bubble). Swallow the serverId
    // future so a no-socket/rejected send isn't an unhandled async error.
    EasyLiveChat.instance
        .sendMessage(text, attachmentUrls: urls)
        .serverMessageId
        .catchError((_) => '');

    _controller.clear();
    setState(() {
      _pending.clear();
      _attachError = null;
    });
  }

  // ── attachments ──

  /// Attach tapped: defer to the host picker when provided, else the built-in
  /// image/file menu.
  Future<void> _onAttach() async {
    if (_uploading) return;
    final picker = widget.onPickAttachments;
    if (picker == null) {
      _showAttachMenu();
      return;
    }
    try {
      final files = await picker(context);
      for (final f in files) {
        await _upload(
          bytes: f.bytes,
          filename: f.filename,
          contentType: f.contentType,
        );
      }
    } catch (_) {
      _showAttachError();
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? picked =
          await _imagePicker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      await _upload(
        bytes: bytes,
        filename: picked.name,
        contentType: picked.mimeType,
      );
    } catch (_) {
      _showAttachError();
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(withData: true);
      if (result == null || result.files.isEmpty) return;
      final f = result.files.first;
      final bytes = f.bytes;
      if (bytes == null) {
        _showAttachError();
        return;
      }
      await _upload(bytes: bytes, filename: f.name);
    } catch (_) {
      _showAttachError();
    }
  }

  /// `m:ss` — voice messages are short, so no hours component.
  static String formatRecordDuration(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  /// Hard stop, so a forgotten open microphone cannot upload something huge.
  static const int maxRecordSeconds = 5 * 60;

  Future<void> _startRecording() async {
    if (_recording || _uploading) return;
    final recorder = _recorder ??= AudioRecorder();
    try {
      if (!await recorder.hasPermission()) {
        setState(() => _attachError = _s.micDenied);
        return;
      }
      // systemTemp rather than a path_provider dependency: on iOS and Android
      // it already resolves inside the app's own sandbox.
      final dir = Directory.systemTemp;
      final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final path = '${dir.path}/voice-$stamp.wav';
      // PCM in a WAV, NOT the AAC this used to record.
      //
      // AAC lives in an MP4 container whose index is only written when the
      // recording stops, so a take could not be listened to without ending
      // it — press play and the microphone button was gone for good. WAV is
      // raw samples appended in order, so a playable copy can be cut from a
      // take that is merely PAUSED, and talking can carry on afterwards.
      //
      // The upload is bigger for it: 16kHz mono is 32KB a second, against
      // about 6 for AAC. It is well inside the 25MB cap even at the
      // five-minute ceiling, and `services/audio-normalize.ts` re-encodes an
      // uploaded wav to Ogg/Opus, so what is STORED and what goes out to
      // WhatsApp is smaller than the AAC was. Only the upload pays.
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          numChannels: 1,
          sampleRate: 16000,
        ),
        path: path,
      );
      _recordPath = path;
      setState(() {
        _recording = true;
        _paused = false;
        _reviewPath = null;
        _recordSeconds = 0;
        _levels.value = const <double>[];
        _attachError = null;
      });
      _listenToLevels(recorder);
      _recordTicker?.cancel();
      _startTicker();
    } catch (_) {
      setState(() => _attachError = _s.micFailed);
      await _teardownRecorder(deleteFile: true);
    }
  }

  /// Stopping sends: a voice message is finished when you stop talking, and a
  /// visitor is unlikely to hunt for a second button to make it leave.
  Future<void> _stopRecordingAndSend() async {
    if (!_recording) return;
    // Already closed for a preview: send exactly what was listened to.
    final path = await _finalizeTake();
    if (mounted) setState(() => _recording = false);
    final file = File(path ?? '');
    if (!await file.exists()) {
      await _teardownRecorder(deleteFile: true);
      return;
    }
    final bytes = await file.readAsBytes();
    final name = file.uri.pathSegments.last;
    await _teardownRecorder(deleteFile: true);
    if (bytes.isEmpty) return;

    // Sent, not parked in the pending strip: a voice message is finished when
    // you stop talking, and a visitor is unlikely to hunt for a second button
    // to make it leave.
    if (mounted) setState(() => _uploading = true);
    try {
      final uploaded = await EasyLiveChat.instance.uploadBytes(
        bytes: bytes,
        filename: name,
        contentType: 'audio/wav',
      );
      _stopTyping();
      EasyLiveChat.instance
          .sendMessage('', attachmentUrls: [uploaded.url])
          .serverMessageId
          .catchError((_) => '');
    } on EasyLiveChatError catch (e) {
      _showAttachError(message: _s.forErrorCode(e.code));
    } catch (_) {
      _showAttachError();
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      } else {
        _uploading = false;
      }
    }
  }

  void _startTicker() {
    _recordTicker?.cancel();
    _recordTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_recording || _paused) return;
      setState(() => _recordSeconds++);
      if (_recordSeconds >= maxRecordSeconds) unawaited(_pauseRecording());
    });
  }

  /// Real microphone levels, at the rate the bar can actually redraw.
  void _listenToLevels(AudioRecorder recorder) {
    _ampSub?.cancel();
    _ampSub = recorder.onAmplitudeChanged(_levelInterval).listen((amp) {
      if (!mounted || _paused) return;
      // `current` is dBFS: 0 is clipping and anything under about -45 is a
      // quiet room. Map that range onto the bar rather than the full -160,
      // or ordinary speech draws as a flat line along the bottom.
      final db = amp.current.isFinite ? amp.current : -45.0;
      final raw = ((db + 45) / 45).clamp(0.0, 1.0);
      final previous = _levels.value;
      // Ease toward the new level instead of snapping to it. Raw amplitude
      // jitters hard between consecutive samples and drew a comb; this is
      // the same wave with the flicker taken out.
      final smoothed = previous.isEmpty
          ? raw
          : (previous.last * 0.45 + raw * 0.55).clamp(0.0, 1.0);
      _levels.value = <double>[...previous, smoothed.toDouble()];
    }, onError: (_) {});
  }

  /// Stop listening, keep the audio. `resume()` appends to the same file.
  Future<void> _pauseRecording() async {
    if (!_recording || _paused) return;
    try {
      await _recorder?.pause();
    } catch (_) {
      // A recorder that would not pause is one we can still stop to send.
    }
    _ampSub?.cancel();
    _ampSub = null;
    if (mounted) setState(() => _paused = true);
  }

  Future<void> _resumeRecording() async {
    final recorder = _recorder;
    if (recorder == null || !_paused || _reviewPath != null) return;
    try {
      await recorder.resume();
    } catch (_) {
      if (mounted) setState(() => _attachError = _s.micFailed);
      return;
    }
    // The take is about to grow, so the copy that was made of it is stale.
    _disposePreview();
    if (mounted) setState(() => _paused = false);
    _listenToLevels(recorder);
    _startTicker();
  }

  /// Close the take so it can be played. See [_reviewPath].
  Future<String?> _finalizeTake() async {
    if (_reviewPath != null) return _reviewPath;
    _recordTicker?.cancel();
    _recordTicker = null;
    _ampSub?.cancel();
    _ampSub = null;
    String? path;
    try {
      path = await _recorder?.stop();
    } catch (_) {
      path = null;
    }
    path ??= _recordPath;
    if (path == null || !await File(path).exists()) return null;
    if (mounted) {
      setState(() {
        _paused = true;
        _reviewPath = path;
      });
    } else {
      _reviewPath = path;
    }
    return path;
  }

  /// A playable copy of the take so far, without disturbing the recorder.
  ///
  /// A WAV that is still being written carries a header whose two length
  /// fields describe how much had been written when it was opened — which is
  /// nothing. Players read those, conclude the file is empty and refuse it.
  /// The bytes after the header are the real samples, so this copies what is
  /// on disk and rewrites the two lengths to match what is actually there.
  ///
  /// Only ever called while PAUSED, so nothing is appending underneath.
  Future<String?> _previewCopy() async {
    final source = _recordPath;
    if (source == null) return null;
    try {
      final bytes = await File(source).readAsBytes();
      final fixed = withRealWavLengths(bytes);
      if (fixed == null) return null;
      final out = File('$source.preview.wav');
      await out.writeAsBytes(fixed, flush: true);
      return out.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _togglePreview() async {
    if (_previewPlaying) {
      try {
        await _preview?.pause();
      } catch (_) {
        // Nothing to pause is the state we wanted.
      }
      return;
    }
    // A COPY of what has been recorded so far, with a header that describes
    // it. The recorder is left exactly as it was — paused, holding the take —
    // so carrying on talking afterwards is still there to do.
    final path = await _previewCopy();
    if (path == null) return;
    var player = _preview;
    if (player == null) {
      player = _preview = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
      // `record` leaves the session in playAndRecord, which routes playback
      // to the earpiece — the same reset the thread's tile makes.
      unawaited(player.setAudioContext(AudioContext(iOS: AudioContextIOS()))
          .catchError((_) {}));
      _previewSubs.add(player.onPositionChanged.listen((d) {
        if (mounted) setState(() => _previewPos = d);
      }));
      _previewSubs.add(player.onDurationChanged.listen((d) {
        if (mounted && d > Duration.zero) setState(() => _previewTotal = d);
      }));
      _previewSubs.add(player.onPlayerStateChanged.listen((st) {
        if (mounted) setState(() => _previewPlaying = st == PlayerState.playing);
      }));
      _previewSubs.add(player.onPlayerComplete.listen((_) async {
        try {
          await player!.seek(Duration.zero);
        } catch (_) {
          // Disposed mid-completion.
        }
        if (mounted) {
          setState(() {
            _previewPos = Duration.zero;
            _previewPlaying = false;
          });
        }
      }));
      try {
        await player.setSourceDeviceFile(path);
        _previewTotal = await player.getDuration();
      } catch (_) {
        if (mounted) setState(() => _attachError = _s.micFailed);
        return;
      }
    }
    try {
      await player.resume();
    } catch (_) {
      if (mounted) setState(() => _attachError = _s.micFailed);
    }
  }

  Future<void> _seekPreview(double fraction) async {
    final total = _previewTotal;
    final player = _preview;
    if (player == null || total == null || total.inMilliseconds == 0) return;
    final target = Duration(
        milliseconds: (total.inMilliseconds * fraction.clamp(0.0, 1.0)).round());
    if (mounted) setState(() => _previewPos = target);
    try {
      await player.seek(target);
    } catch (_) {
      // A seek the platform refused leaves the playhead where it was.
    }
  }

  Future<void> _cancelRecording() async {
    _recordTicker?.cancel();
    _recordTicker = null;
    try {
      await _recorder?.stop();
    } catch (_) {}
    if (mounted) setState(() => _recording = false);
    await _teardownRecorder(deleteFile: true);
  }

  /// Throw the take away. The microphone stops, the file goes, and the
  /// composer comes back — the same thing the trash does in every messenger.
  Future<void> _discardRecording() async {
    await _cancelRecording();
  }

  void _disposePreview() {
    final source = _recordPath;
    if (source != null) {
      // Best effort: the OS reclaims temp anyway.
      unawaited(File('$source.preview.wav').delete().catchError((_) => File(source)));
    }
    for (final sub in _previewSubs) {
      sub.cancel();
    }
    _previewSubs.clear();
    _preview?.dispose();
    _preview = null;
    _previewPlaying = false;
    _previewPos = Duration.zero;
    _previewTotal = null;
  }

  Future<void> _teardownRecorder({required bool deleteFile}) async {
    _ampSub?.cancel();
    _ampSub = null;
    _disposePreview();
    if (mounted) {
      setState(() {
        _paused = false;
        _reviewPath = null;
        _levels.value = const <double>[];
      });
    } else {
      _paused = false;
      _reviewPath = null;
      _levels.value = const <double>[];
    }
    final path = _recordPath;
    _recordPath = null;
    if (mounted) setState(() => _recordSeconds = 0);
    if (deleteFile && path != null) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  Future<void> _upload({
    required List<int> bytes,
    required String filename,
    String? contentType,
  }) async {
    setState(() {
      _uploading = true;
      _attachError = null;
    });
    try {
      final uploaded = await EasyLiveChat.instance.uploadBytes(
        bytes: bytes,
        filename: filename,
        contentType: contentType,
      );
      if (!mounted) return;
      setState(() => _pending.add(
            // Keep the bytes we already read: the thumbnail is then instant and
            // offline, instead of pulling the visitor's own photo back down
            // from the server to show it to them.
            _PendingAttachment(
              file: uploaded,
              bytes: bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
              pickedContentType: contentType,
            ),
          ));
    } on EasyLiveChatError catch (e) {
      _showAttachError(message: _s.forErrorCode(e.code));
    } catch (_) {
      _showAttachError();
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      } else {
        _uploading = false;
      }
    }
  }

  void _showAttachError({String? message}) {
    if (!mounted) return;
    setState(() {
      _uploading = false;
      _attachError = message ?? _s.somethingWentWrong;
    });
  }

  void _showAttachMenu() {
    if (_uploading) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _theme.background,
      builder: (sheetCtx) => Directionality(
        textDirection: _theme.direction,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.image_outlined, color: _theme.text),
                title:
                    Text(_s.attachImage, style: TextStyle(color: _theme.text)),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _pickImage();
                },
              ),
              ListTile(
                leading: Icon(Icons.attach_file_outlined, color: _theme.text),
                title:
                    Text(_s.attachFile, style: TextStyle(color: _theme.text)),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _pickFile();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _removePending(int index) {
    setState(() => _pending.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final listenable = _lockListenable;
    if (listenable == null) return _build(context);
    // Rebuild whenever the server pushes a new visitorMode, so closing time
    // locks a composer the visitor is already looking at.
    return ValueListenableBuilder<String>(
      valueListenable: listenable,
      builder: (context, _, __) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final t = _theme;
    return Directionality(
      textDirection: t.direction,
      child: Container(
        decoration: BoxDecoration(
          color: t.background,
          border: Border(
            top: BorderSide(color: t.text.withValues(alpha: 0.08)),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_attachError != null) _errorBanner(_attachError!),
              if (_pending.isNotEmpty) _pendingStrip(),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Hidden rather than dimmed while locked: a greyed
                    // paperclip still reads as "attach something", and there
                    // is nothing to attach to a composer that cannot send.
                    if (!_locked && !_recording) ...[
                      _attachButton(),
                      const SizedBox(width: 4),
                    ],
                    if (!_locked && !_recording && _voiceNotesEnabled) ...[
                      _micButton(),
                      const SizedBox(width: 4),
                    ],
                    // Recording puts the trash where the paperclip was: the
                    // two destructive-ish controls never share a position, and
                    // the take is the only thing on screen to act on.
                    if (_recording) ...[
                      _trashButton(),
                      const SizedBox(width: 4),
                    ],
                    // While the microphone is live there is nothing to type,
                    // so the bar stands in for the field and the only two
                    // things to press are discard and send.
                    Expanded(
                      child: _recording ? _recordingBar() : _textField(),
                    ),
                    // Same reasoning as the paperclip: a live accent-colored
                    // send button beside a disabled field promised something
                    // the composer would then refuse. While locked the row is
                    // just the field and its explanatory hint.
                    // Paused with something to hear: the microphone comes
                    // back to carry on talking, exactly where it was before
                    // the take started.
                    if (_recording && _paused) ...[
                      const SizedBox(width: 4),
                      _continueRecordingButton(),
                    ],
                    if (!_locked) ...[
                      const SizedBox(width: 8),
                      _recording ? _sendRecordingButton() : _sendButton(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Workspace-wide switch, off unless somebody turned it on.
  bool get _voiceNotesEnabled =>
      EasyLiveChat.instance.widgetConfig.value?.voiceNotesEnabled ?? false;

  Widget _micButton() {
    final t = _theme;
    return IconButton(
      onPressed: _uploading ? null : _startRecording,
      tooltip: _s.recordVoice,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      icon: Icon(Icons.mic_none_outlined,
          color: t.text.withValues(alpha: _uploading ? 0.4 : 0.75)),
    );
  }

  /// The take, while it is being made and once it is made.
  ///
  /// Recording: a live waveform off the microphone, running time, and a pause.
  /// Paused: the same waveform with a playhead, a play button, and the elapsed
  /// time as it plays back.
  Widget _recordingBar() {
    final t = _theme;
    final reviewing = _paused;
    final total = _previewTotal;
    final fraction = (reviewing && total != null && total.inMilliseconds > 0)
        ? (_previewPos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
        : (reviewing ? 0.0 : 1.0);
    final elapsed = reviewing && _previewPos > Duration.zero
        ? formatRecordDuration(_previewPos.inSeconds)
        : formatRecordDuration(_recordSeconds);

    return Row(
      children: [
        if (reviewing)
          IconButton(
            onPressed: _togglePreview,
            tooltip: _previewPlaying ? _s.pauseVoice : _s.playVoice,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            icon: Icon(
              _previewPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 22,
              color: t.text,
            ),
          )
        else
          // The recording dot, which is the one thing on the bar that says
          // the microphone is actually open.
          Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(
                color: Color(0xFFE11D48), shape: BoxShape.circle),
          ),
        const SizedBox(width: 8),
        Expanded(
          child: VoiceLevels(
            levels: _levels,
            // Nothing is played back while the microphone is live, so every
            // bar is "already recorded" and none of it is dimmed.
            fraction: fraction,
            color: t.text,
            interval: _levelInterval,
            onSeek: reviewing ? _seekPreview : null,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          elapsed,
          style: TextStyle(
              color: t.text.withValues(alpha: 0.7),
              fontSize: 13,
              fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        if (!reviewing)
          IconButton(
            onPressed: _pauseRecording,
            tooltip: _s.pauseVoice,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            icon: Icon(Icons.pause_rounded, size: 22, color: t.text),
          ),
      ],
    );
  }

  Widget _trashButton() {
    final t = _theme;
    return IconButton(
      onPressed: _discardRecording,
      tooltip: _s.discardVoice,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      icon: Icon(Icons.delete_outline,
          size: 22, color: t.text.withValues(alpha: 0.75)),
    );
  }

  /// Carry on talking. Genuinely appends — `record` pauses and resumes the
  /// same file, so this is one recording and not two stitched together.
  Widget _continueRecordingButton() {
    return IconButton(
      onPressed: _resumeRecording,
      tooltip: _s.recordVoice,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      icon: const Icon(Icons.mic_none_outlined,
          size: 22, color: Color(0xFFE11D48)),
    );
  }

  Widget _sendRecordingButton() {
    final t = _theme;
    final onPrimary = t.primary.computeLuminance() > 0.5
        ? const Color(0xFF0F172A)
        : Colors.white;
    return IconButton(
      onPressed: _stopRecordingAndSend,
      tooltip: _s.sendVoice,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      icon: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(color: t.primary, shape: BoxShape.circle),
        // `onPrimary`, not a hardcoded white: a workspace on a pale accent had
        // a white glyph on a near-white disc, which is the same bug one layer
        // down. The send button has always computed this.
        child: Icon(Icons.send_rounded, size: 18, color: onPrimary),
      ),
    );
  }

  Widget _attachButton() {
    final t = _theme;
    return IconButton(
      onPressed: _uploading ? null : _onAttach,
      tooltip: _s.attach,
      // Match the send button's box so the row centers cleanly.
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      icon: _uploading
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                    t.text.withValues(alpha: 0.5)),
              ),
            )
          : Icon(Icons.add_circle_outline,
              color: t.text.withValues(alpha: 0.7)),
    );
  }

  Widget _textField() {
    // Rebuilt per keystroke so the field can turn around under the text as it
    // is typed — see [textDirectionOf]. A ValueListenableBuilder rather than
    // setState: only this box depends on the draft, and rebuilding the whole
    // composer (attach button, send button, pending strip) on every character
    // is work nobody asked for.
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _controller,
      builder: (context, value, _) => _textFieldFor(value.text),
    );
  }

  Widget _textFieldFor(String draft) {
    final t = _theme;
    // The workspace's direction is the starting point, not the answer. A
    // visitor typing Arabic into an English workspace was writing into a
    // left-to-right box: caret on the wrong end, text against the wrong edge.
    // Neither iOS nor Android exposes the keyboard's language, so the first
    // strong character decides — as it does in every other messenger, and as
    // `dir="auto"` does on the web.
    // Text first; then what this visitor last wrote; then the phone's own
    // language; then the workspace's. Each step is a worse guess than the one
    // before it, and the first two are usually all it takes.
    final direction = textDirectionOf(draft) ??
        _rememberedDirection ??
        deviceTextDirection() ??
        t.direction;
    // Fixed-height (44, matching the round buttons) TRANSPARENT box so the text
    // centres on the same line as the attach/send buttons — no fill, no border.
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        textDirection: direction,
        // Resolved against the line above, so it follows the text rather than
        // the workspace.
        textAlign: TextAlign.start,
        minLines: 1,
        maxLines: 5,
        // NOTICE_ONLY tenants take nothing while closed. Disabled rather than
        // hidden: an input that vanishes reads as breakage, whereas a greyed
        // one carrying the notice as its hint explains itself.
        //
        // The hint is `closedReadOnly`, not `closedNotice`. The latter says
        // "leave your message", which is written for the banner where they
        // still can — as a hint on a disabled field, beside a send button, it
        // asked for something the composer would then refuse.
        enabled: !_locked,
        textInputAction: TextInputAction.send,
        // Keep the keyboard up across a send, the way every messenger does.
        //
        // Flutter's default finalize-editing UNFOCUSES the field for
        // `TextInputAction.send`, so tapping the keyboard's send key collapsed
        // the keyboard on every message. That also made the thread lurch: the
        // viewport grew as the keyboard left while the auto-scroll was already
        // animating to the old extent, so the list scrolled, resized, and
        // settled again — a visible shake on each send.
        //
        // Supplying `onEditingComplete` REPLACES that default wholesale (see
        // EditableText._finalizeEditing), which is the documented way to keep
        // focus. `clearComposing()` is the rest of what the default did and
        // still has to happen — without it an in-progress IME composition
        // survives the send. The send itself stays on `onSubmitted`, which
        // fires unconditionally afterwards; doing it here as well would send
        // the message twice.
        onEditingComplete: () => _controller.clearComposing(),
        onSubmitted: (_) => _send(),
        style: TextStyle(color: t.text, fontSize: 15),
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText: _locked ? _s.closedReadOnly : _s.typeAMessage,
          hintStyle: TextStyle(color: t.text.withValues(alpha: 0.4)),
        ),
      ),
    );
  }

  Widget _sendButton() {
    final t = _theme;
    final onPrimary = t.primary.computeLuminance() > 0.5
        ? const Color(0xFF0F172A)
        : Colors.white;
    return Material(
      color: t.primary,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _send,
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Icon(Icons.send_rounded, size: 22, color: onPrimary),
        ),
      ),
    );
  }

  /// The row of attachments waiting to be sent.
  ///
  /// Pictures show as pictures. This used to be a paperclip chip carrying
  /// `IMG_20260814_113255.jpg`, which told the visitor nothing about which of
  /// four screenshots they had just picked — the one thing they need to check
  /// before hitting send. Non-images keep the chip, because a filename IS what
  /// identifies a PDF.
  Widget _pendingStrip() {
    return SizedBox(
      // 12 + 56 (tile) + 4, with the top padding leaving room for the remove
      // badge that overhangs the corner.
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        itemCount: _pending.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final p = _pending[i];
          final thumb = p.thumbnail;
          return thumb == null ? _pendingChip(p, i) : _pendingThumb(p, thumb, i);
        },
      ),
    );
  }

  Widget _pendingThumb(_PendingAttachment p, ImageProvider thumb, int index) {
    const size = 56.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        // The remove badge sits on the corner, half outside the tile.
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GestureDetector(
              // Same affordance as a sent image: tap to see it full-size,
              // which is the only way to be sure it is the right screenshot.
              onTap: () => ElcImageViewer.show(
                context,
                image: p.fullImage!,
                theme: _theme,
                strings: _s,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image(
                  // Decoded at tile size — a 12MP camera photo decoded to fill
                  // a 56px box would cost ~50MB of image cache per attachment.
                  image: ResizeImage(thumb, width: (size * 3).round()),
                  fit: BoxFit.cover,
                  width: size,
                  height: size,
                  errorBuilder: (_, __, ___) => _thumbFallback(),
                ),
              ),
            ),
          ),
          PositionedDirectional(top: -12, end: -12, child: _removeBadge(index)),
        ],
      ),
    );
  }

  Widget _thumbFallback() {
    final t = _theme;
    return Container(
      color: t.surface,
      alignment: Alignment.center,
      child: Icon(Icons.broken_image_outlined,
          size: 20, color: t.text.withValues(alpha: 0.5)),
    );
  }

  /// A 20px badge in a 32px touch target, so the corner × is hittable without
  /// covering the picture it sits on.
  Widget _removeBadge(int index) {
    final t = _theme;
    return Semantics(
      button: true,
      label: _s.removeAttachment,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _removePending(index),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Center(
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.72),
                shape: BoxShape.circle,
                // Ring in the composer's own background so the badge separates
                // from a dark photo underneath it.
                border: Border.all(color: t.background, width: 1.5),
              ),
              child: const Icon(Icons.close, size: 12, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pendingChip(_PendingAttachment p, int index) {
    final t = _theme;
    return Center(
      child: Container(
        padding: const EdgeInsetsDirectional.only(start: 10, end: 4),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.text.withValues(alpha: 0.12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file_outlined,
                size: 16, color: t.text.withValues(alpha: 0.7)),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                p.file.filename ?? _s.attachment,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.text, fontSize: 13),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: _s.removeAttachment,
              onPressed: () => _removePending(index),
              icon: Icon(Icons.close, color: t.text.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorBanner(String msg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFFDC2626).withValues(alpha: 0.1),
      child: Text(
        msg,
        style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12),
      ),
    );
  }
}

/// One uploaded-but-not-yet-sent attachment, plus what it takes to preview it.
class _PendingAttachment {
  final UploadedFile file;

  /// The bytes the file was uploaded from, kept until send so the strip can
  /// draw a thumbnail without a round trip. Dropped with the whole record when
  /// the message goes out or the visitor removes it.
  final Uint8List? bytes;

  /// Content type as reported by the picker. The server's echoed `mimeType` is
  /// preferred over it, but `file_picker` hands back neither for some sources,
  /// which is why the extension check below still exists.
  final String? pickedContentType;

  const _PendingAttachment({
    required this.file,
    this.bytes,
    this.pickedContentType,
  });

  bool get isImage {
    final mime = (file.mimeType ?? pickedContentType ?? '').toLowerCase();
    if (mime.isNotEmpty) return mime.startsWith('image/');
    return _looksLikeImage(file.filename ?? file.url);
  }

  /// Thumbnail source: local bytes when we have them, else the uploaded copy.
  /// Null for anything that is not a picture — the caller draws a chip.
  ImageProvider? get thumbnail {
    if (!isImage) return null;
    final b = bytes;
    if (b != null && b.isNotEmpty) return MemoryImage(b);
    return CachedNetworkImageProvider(
      EasyLiveChat.instance.resolveUrl(file.url),
    );
  }

  /// Full-resolution provider for the tap-to-enlarge viewer. Same source as
  /// [thumbnail]; separate getter because the thumbnail is decoded downsized.
  ImageProvider? get fullImage => thumbnail;

  static bool _looksLikeImage(String name) {
    final path = name.toLowerCase().split('?').first;
    return path.endsWith('.png') ||
        path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.gif') ||
        path.endsWith('.webp') ||
        path.endsWith('.bmp') ||
        path.endsWith('.heic');
  }
}

/// Rewrite a WAV's RIFF and `data` lengths from the bytes actually present.
///
/// Returns null for anything that is not a RIFF/WAVE file, rather than
/// guessing at offsets in a container this did not write.
@visibleForTesting
Uint8List? withRealWavLengths(Uint8List bytes) {
  if (bytes.length < 44) return null;
  bool tagAt(int offset, String tag) {
    for (var i = 0; i < tag.length; i++) {
      if (bytes[offset + i] != tag.codeUnitAt(i)) return false;
    }
    return true;
  }

  if (!tagAt(0, 'RIFF') || !tagAt(8, 'WAVE')) return null;

  // Walk the chunks to find `data`; `fmt ` is not always the only one
  // before it, and its size is not always 16.
  var cursor = 12;
  var dataAt = -1;
  while (cursor + 8 <= bytes.length) {
    final size = bytes.buffer.asByteData().getUint32(cursor + 4, Endian.little);
    if (tagAt(cursor, 'data')) {
      dataAt = cursor;
      break;
    }
    // Chunks are word-aligned, and a stale size must never walk backwards.
    final step = 8 + size + (size.isOdd ? 1 : 0);
    if (step <= 8) return null;
    cursor += step;
  }
  if (dataAt < 0 || dataAt + 8 > bytes.length) return null;

  final out = Uint8List.fromList(bytes);
  final view = out.buffer.asByteData();
  view.setUint32(4, out.length - 8, Endian.little);
  view.setUint32(dataAt + 4, out.length - (dataAt + 8), Endian.little);
  return out;
}
