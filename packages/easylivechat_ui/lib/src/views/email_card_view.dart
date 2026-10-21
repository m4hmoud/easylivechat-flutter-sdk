import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import '../theme.dart';

/// Which of the web widget's two email cards (apps/widget EmailCard.tsx).
enum ElcEmailCardMode {
  /// "Email me this chat" — from the ⋯ menu, or under the survey once the
  /// chat has ended.
  transcript,

  /// "Get the reply by email" — offered while nobody can answer.
  notify,
}

/// What a submit came back with: the address it went to (masked), or the
/// words to show for why not.
class ElcEmailResult {
  final String? hint;
  final String? message;
  const ElcEmailResult.sent(String this.hint) : message = null;
  const ElcEmailResult.failed(String this.message) : hint = null;
  bool get ok => hint != null;
}

/// The web widget's check (EmailCard.tsx `EMAIL_RE`) — the server decides.
final RegExp _emailShape = RegExp(
    r'^[^\s@<>()[\],;:"\\]+@[^\s@<>()[\],;:"\\]+\.[^\s@<>()[\],;:"\\.]{2,}$');

/// Whether [value] looks like an address worth sending, as the web judges it.
bool elcLooksLikeEmail(String value) => _emailShape.hasMatch(value.trim());

/// An inline card above the conversation — never a modal: the chat stays
/// where it was, and the card says what happened in its own place (no toast).
///
/// With an address on file the transcript card is a one-tap confirmation that
/// names it; "Use another address" (or no address at all) shows the field. The
/// notify card always asks. A sent transcript says so for a moment and goes; a
/// kept address stays said until dismissed.
class ElcEmailCard extends StatefulWidget {
  final ElcEmailCardMode mode;

  /// The address on file, masked (`d•••@example.com`), or null when there is
  /// none — then the field is shown.
  final String? emailHint;
  final EasyLiveChatTheme theme;
  final ElcStrings strings;

  /// [email] is what the visitor typed, or null to use the address on file.
  final Future<ElcEmailResult> Function(String? email) onSubmit;
  final VoidCallback onClose;

  const ElcEmailCard({
    super.key,
    required this.mode,
    required this.emailHint,
    required this.theme,
    required this.strings,
    required this.onSubmit,
    required this.onClose,
  });

  @override
  State<ElcEmailCard> createState() => _ElcEmailCardState();
}

class _ElcEmailCardState extends State<ElcEmailCard> {
  final TextEditingController _field = TextEditingController();
  final FocusNode _focus = FocusNode();
  late bool _typing =
      widget.emailHint == null || widget.mode == ElcEmailCardMode.notify;
  bool _busy = false;
  String? _error;
  String? _doneHint;
  Timer? _closeTimer;

  bool get _transcript => widget.mode == ElcEmailCardMode.transcript;

  /// The field shows while typing — and when the address on file went away
  /// under the card (`NO_CONTACT_EMAIL`), exactly as the web re-renders.
  bool get _showField => _typing || widget.emailHint == null;

  @override
  void initState() {
    super.initState();
    // Asked for by a tap ("Email me this chat"), so the keyboard is wanted.
    if (_transcript && _showField) _focusSoon();
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _focusSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    String? email;
    if (_showField) {
      final v = _field.text.trim();
      if (!elcLooksLikeEmail(v)) {
        setState(() => _error = widget.strings.invalidEmail);
        return;
      }
      email = v;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.onSubmit(email);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.ok) {
        _doneHint = result.hint;
      } else {
        _error = result.message;
      }
    });
    if (result.ok && _transcript) {
      // Said for a moment, then out of the way.
      _closeTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) widget.onClose();
      });
    }
  }

  /// The masked address isolated, so `d•••@example.com` keeps its shape
  /// inside an Arabic sentence (the web's U+2068 … U+2069).
  static String _isolated(String hint) => '\u2068$hint\u2069';

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final s = widget.strings;
    final dim = t.text.withValues(alpha: t.isDark ? 0.72 : 0.64);
    final card = BoxDecoration(
      color: t.background,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: t.text.withValues(alpha: 0.12)),
      boxShadow: t.isDark
          ? null
          : const [
              BoxShadow(
                  color: Color(0x0F000000),
                  blurRadius: 14,
                  offset: Offset(0, 4)),
            ],
    );
    final done = _doneHint;
    if (done != null) {
      final text = (_transcript ? s.emailSentTo : s.notifySaved)
          .replaceAll('{email}', _isolated(done));
      return Container(
        margin: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 0),
        padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 6, 6),
        decoration: card,
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(text,
                    style: TextStyle(fontSize: 13, height: 1.5, color: dim)),
              ),
            ),
            IconButton(
              onPressed: widget.onClose,
              tooltip: s.dismiss,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded, size: 16, color: dim),
            ),
          ],
        ),
      );
    }

    final buttonBase =
        Theme.of(context).textTheme.labelLarge ?? const TextStyle();
    return Container(
      margin: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(
              _transcript ? s.emailTranscript : s.notifyTitle,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: t.text),
            ),
          ),
          if (!_transcript) ...[
            const SizedBox(height: 6),
            Text(s.notifyBody,
                style: TextStyle(fontSize: 13, height: 1.5, color: dim)),
          ],
          const SizedBox(height: 8),
          if (!_showField)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                Text(
                  s.emailSendTo
                      .replaceAll('{email}', _isolated(widget.emailHint!)),
                  style: TextStyle(fontSize: 13, height: 1.5, color: dim),
                ),
                Semantics(
                  button: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: _busy
                        ? null
                        : () {
                            setState(() => _typing = true);
                            _focusSoon();
                          },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        s.emailOther,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: t.primaryInk,
                          decoration: TextDecoration.underline,
                          decorationColor: t.primaryInk,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          else
            TextField(
              controller: _field,
              focusNode: _focus,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.send,
              // An address reads left to right in every language.
              textDirection: TextDirection.ltr,
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'\s'))
              ],
              onSubmitted: (_) => _submit(),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              keyboardAppearance: t.brightness,
              cursorColor: t.primaryInk,
              style: TextStyle(color: t.text, fontSize: 15),
              decoration: InputDecoration(
                isDense: true,
                hintText: s.yourEmail,
                hintTextDirection: t.direction,
                hintStyle: TextStyle(color: t.text.withValues(alpha: 0.45)),
                filled: true,
                fillColor: t.surface,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                border: _border(t.text.withValues(alpha: 0.15)),
                enabledBorder: _border(t.text.withValues(alpha: 0.15)),
                disabledBorder: _border(t.text.withValues(alpha: 0.1)),
                focusedBorder: _border(t.primaryInk, width: 1.5),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Semantics(
              liveRegion: true,
              child: Text(_error!,
                  style: TextStyle(fontSize: 12.5, color: t.danger)),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _busy ? null : widget.onClose,
                style: OutlinedButton.styleFrom(
                  foregroundColor: dim,
                  side: BorderSide(color: t.text.withValues(alpha: 0.15)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  textStyle: buttonBase.copyWith(
                      fontSize: 13, fontWeight: FontWeight.w500),
                ),
                child: Text(_transcript ? s.cancel : s.notifyDismiss),
              ),
              FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: t.primary,
                  foregroundColor: t.onPrimary,
                  disabledBackgroundColor: t.primary.withValues(alpha: 0.5),
                  disabledForegroundColor: t.onPrimary.withValues(alpha: 0.8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  textStyle: buttonBase.copyWith(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                child: Text(_busy
                    ? s.sending
                    : _transcript
                        ? s.emailSend
                        : s.notifyButton),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static OutlineInputBorder _border(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: color, width: width),
      );
}
