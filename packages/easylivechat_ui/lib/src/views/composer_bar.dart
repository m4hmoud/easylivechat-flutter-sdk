import 'dart:async';
import 'dart:io' show Directory, File;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easylivechat/easylivechat.dart';
import 'package:flutter/foundation.dart' show ValueListenable, Uint8List;
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
      final path = '${dir.path}/voice-$stamp.m4a';
      // AAC in m4a: the container every channel accepts, so a voice message
      // sent from here needs none of the server-side rewrapping a browser
      // recording does.
      await recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1),
        path: path,
      );
      _recordPath = path;
      setState(() {
        _recording = true;
        _recordSeconds = 0;
        _attachError = null;
      });
      _recordTicker?.cancel();
      _recordTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !_recording) return;
        setState(() => _recordSeconds++);
        if (_recordSeconds >= maxRecordSeconds) _stopRecordingAndSend();
      });
    } catch (_) {
      setState(() => _attachError = _s.micFailed);
      await _teardownRecorder(deleteFile: true);
    }
  }

  /// Stopping sends: a voice message is finished when you stop talking, and a
  /// visitor is unlikely to hunt for a second button to make it leave.
  Future<void> _stopRecordingAndSend() async {
    if (!_recording) return;
    _recordTicker?.cancel();
    _recordTicker = null;
    String? path;
    try {
      path = await _recorder?.stop();
    } catch (_) {
      path = null;
    }
    if (mounted) setState(() => _recording = false);
    final file = File(path ?? _recordPath ?? '');
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
        contentType: 'audio/mp4',
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

  Future<void> _cancelRecording() async {
    _recordTicker?.cancel();
    _recordTicker = null;
    try {
      await _recorder?.stop();
    } catch (_) {}
    if (mounted) setState(() => _recording = false);
    await _teardownRecorder(deleteFile: true);
  }

  Future<void> _teardownRecorder({required bool deleteFile}) async {
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
                    if (!_locked) ...[
                      const SizedBox(width: 8),
                      _recording ? _stopButton() : _sendButton(),
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

  Widget _recordingBar() {
    final t = _theme;
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: const BoxDecoration(
              color: Color(0xFFE11D48), shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Text(
          formatRecordDuration(_recordSeconds),
          style: TextStyle(
              color: t.text, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _s.recordingVoice,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: t.text.withValues(alpha: 0.6), fontSize: 13),
          ),
        ),
        IconButton(
          onPressed: _cancelRecording,
          tooltip: _s.discardVoice,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          icon: Icon(Icons.close, size: 18, color: t.text.withValues(alpha: 0.6)),
        ),
      ],
    );
  }

  Widget _stopButton() {
    final t = _theme;
    return IconButton(
      onPressed: _stopRecordingAndSend,
      tooltip: _s.sendVoice,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      icon: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(color: t.primary, shape: BoxShape.circle),
        child: const Icon(Icons.stop, size: 16, color: Colors.white),
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
