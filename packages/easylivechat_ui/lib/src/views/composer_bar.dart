import 'dart:async';

import 'package:easylivechat/easylivechat.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n.dart';
import '../picked_file.dart';
import '../theme.dart';

/// The message composer (native analog of the web `Composer.tsx`).
///
/// A text field + send button (tinted [EasyLiveChatTheme.primary]) + an attach
/// button. Attachments are picked (image via `image_picker`, any file via
/// `file_picker`), read to bytes, uploaded with
/// `EasyLiveChat.instance.uploadBytes`, and the returned server-relative URLs
/// are linked to the message via `sendMessage(text, attachmentUrls: [...])` —
/// the send itself is optimistic (the controller pushes a `tmp-` bubble).
///
/// Typing presence is debounced: `setTyping(true)` fires on input, and
/// `setTyping(false)` after ~1.5s idle or immediately on send.
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

  Timer? _typingDebounce;
  bool _typingActive = false;

  /// Pending uploaded attachment URLs awaiting send.
  final List<UploadedFile> _pending = [];
  bool _uploading = false;
  String? _attachError;

  EasyLiveChatTheme get _theme => widget.theme;
  ElcStrings get _s =>
      ElcStrings.of(EasyLiveChat.instance.widgetConfig.value?.locale);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    if (_typingActive) {
      // Best-effort: let the agent side know we stopped typing on teardown.
      EasyLiveChat.instance.setTyping(false);
    }
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ── typing presence ──

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText) {
      if (!_typingActive) {
        _typingActive = true;
        EasyLiveChat.instance.setTyping(true);
      }
      _typingDebounce?.cancel();
      _typingDebounce = Timer(const Duration(milliseconds: 1500), _stopTyping);
    } else if (_typingActive) {
      _stopTyping();
    }
  }

  void _stopTyping() {
    _typingDebounce?.cancel();
    if (_typingActive) {
      _typingActive = false;
      EasyLiveChat.instance.setTyping(false);
    }
  }

  // ── send ──

  /// True while the workspace is shut AND the tenant chose to take no message.
  bool get _locked => EasyLiveChat.instance.isBooted &&
      EasyLiveChat.instance.composerLocked;

  void _send() {
    final text = _controller.text.trim();
    final urls = _pending.map((f) => f.url).toList(growable: false);
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
      setState(() => _pending.add(uploaded));
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
                    _attachButton(),
                    const SizedBox(width: 4),
                    Expanded(child: _textField()),
                    const SizedBox(width: 8),
                    _sendButton(),
                  ],
                ),
              ),
            ],
          ),
        ),
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
    final t = _theme;
    // Fixed-height (44, matching the round buttons) TRANSPARENT box so the text
    // centres on the same line as the attach/send buttons — no fill, no border.
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        minLines: 1,
        maxLines: 5,
        // NOTICE_ONLY tenants take nothing while closed. Disabled rather than
        // hidden: an input that vanishes reads as breakage, whereas a greyed
        // one carrying the notice as its hint explains itself.
        enabled: !_locked,
        textInputAction: TextInputAction.send,
        onSubmitted: (_) => _send(),
        style: TextStyle(color: t.text, fontSize: 15),
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText: _locked ? _s.closedNotice : _s.typeAMessage,
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

  Widget _pendingStrip() {
    final t = _theme;
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        itemCount: _pending.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final f = _pending[i];
          return Container(
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
                    f.filename ?? _s.attachment,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.text, fontSize: 13),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _removePending(i),
                  icon: Icon(Icons.close, color: t.text.withValues(alpha: 0.6)),
                ),
              ],
            ),
          );
        },
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
