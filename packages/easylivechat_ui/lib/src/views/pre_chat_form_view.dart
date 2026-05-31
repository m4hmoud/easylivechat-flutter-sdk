import 'dart:async';

import 'package:easylivechat/easylivechat.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../theme.dart';

/// Dynamic pre-chat form (the native analog of the web `PreChat.tsx`).
///
/// Renders `config.preChatForm.fields` in order, choosing an input per
/// [PreChatFieldType] (text / email / phone / number / textarea / select).
/// Enforces `required` + per-type validation locally via [PreChatField.validate]
/// (the server stays the authority), then submits a `Map<fieldId, value>` via
/// `EasyLiveChat.instance.startSession(fields: …)`.
///
/// Tenant-authored copy — [WidgetConfigModel.welcomeTitle] /
/// [WidgetConfigModel.welcomeSubtitle] and every field `label`/`placeholder` —
/// is rendered **verbatim** (never localized). Only SDK chrome (button,
/// validation messages) is localized.
///
/// Server `400 { fieldId }` errors arrive on `EasyLiveChat.instance.onError`;
/// the matching field is highlighted inline.
class PreChatFormView extends StatefulWidget {
  final WidgetConfigModel config;
  final EasyLiveChatTheme theme;

  const PreChatFormView({
    super.key,
    required this.config,
    required this.theme,
  });

  @override
  State<PreChatFormView> createState() => _PreChatFormViewState();
}

class _PreChatFormViewState extends State<PreChatFormView> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _selectValues = {};

  /// Server-supplied per-field error codes (keyed by fieldId), shown inline.
  final Map<String, String> _serverFieldErrors = {};

  StreamSubscription<EasyLiveChatError>? _errorSub;
  bool _submitting = false;
  String? _formError; // non-field error (e.g. network)

  EasyLiveChatTheme get _theme => widget.theme;
  ElcStrings get _s => ElcStrings.of(widget.config.locale);

  List<PreChatField> get _fields => widget.config.preChatForm.fields;

  @override
  void initState() {
    super.initState();
    for (final f in _fields) {
      if (f.type == PreChatFieldType.select) {
        _selectValues[f.id] = '';
      } else {
        _controllers[f.id] = TextEditingController();
      }
    }
    _errorSub = EasyLiveChat.instance.onError.listen(_onError);
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onError(EasyLiveChatError err) {
    if (!mounted) return;
    setState(() {
      _submitting = false;
      final fieldId = err.fieldId;
      if (fieldId != null && fieldId.isNotEmpty) {
        _serverFieldErrors[fieldId] = err.code;
      } else {
        _formError = err.message ?? _s.somethingWentWrong;
      }
    });
    // Re-run the form validators so the inline server error renders.
    _formKey.currentState?.validate();
  }

  String? _localValidate(PreChatField f, String? value) {
    // A server error for this field takes precedence until the user edits it.
    final serverCode = _serverFieldErrors[f.id];
    if (serverCode != null) return _s.forErrorCode(serverCode);
    final code = f.validate(value);
    if (code == null) return null;
    return _s.forErrorCode(code);
  }

  Future<void> _submit() async {
    setState(() {
      _formError = null;
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final fields = <String, String>{};
    for (final f in _fields) {
      final v = (f.type == PreChatFieldType.select)
          ? (_selectValues[f.id] ?? '')
          : (_controllers[f.id]?.text ?? '');
      final trimmed = v.trim();
      if (trimmed.isNotEmpty) fields[f.id] = trimmed;
    }

    setState(() => _submitting = true);
    try {
      await EasyLiveChat.instance.startSession(fields: fields);
      // On success the controller advances `phase`; the shell swaps this view.
    } on EasyLiveChatError catch (e) {
      _onError(e);
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _formError = _s.somethingWentWrong;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _theme;
    return Directionality(
      textDirection: t.direction,
      child: Container(
        color: t.background,
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              children: [
                Text(
                  widget.config.welcomeTitle,
                  style: TextStyle(
                    color: t.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (widget.config.welcomeSubtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    widget.config.welcomeSubtitle,
                    style: TextStyle(
                      color: t.text.withOpacity(0.7),
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                for (final f in _fields) ...[
                  _buildField(f),
                  const SizedBox(height: 16),
                ],
                if (_formError != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _formError!,
                    style: const TextStyle(
                      color: _FormErrorColor.color,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 8),
                _buildSubmit(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(PreChatField f) {
    final t = _theme;
    final label = Text(
      f.label + (f.required ? ' *' : ''),
      style: TextStyle(
        color: t.text,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );

    if (f.type == PreChatFieldType.select) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label,
          const SizedBox(height: 8),
          FormField<String>(
            initialValue: _selectValues[f.id],
            validator: (v) => _localValidate(f, v),
            builder: (state) {
              final value = (_selectValues[f.id] ?? '');
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    decoration: _fieldDecoration(state.hasError),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: value.isEmpty ? null : value,
                        hint: Text(
                          f.placeholder?.isNotEmpty == true
                              ? f.placeholder!
                              : _s.selectAnOption,
                          style: TextStyle(color: t.text.withOpacity(0.5)),
                        ),
                        dropdownColor: t.surface,
                        style: TextStyle(color: t.text, fontSize: 15),
                        items: [
                          for (final opt in f.options)
                            DropdownMenuItem(value: opt, child: Text(opt)),
                        ],
                        onChanged: (v) {
                          setState(() {
                            _selectValues[f.id] = v ?? '';
                            _serverFieldErrors.remove(f.id);
                          });
                          state.didChange(v);
                        },
                      ),
                    ),
                  ),
                  if (state.hasError) _errorText(state.errorText!),
                ],
              );
            },
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label,
        const SizedBox(height: 8),
        TextFormField(
          controller: _controllers[f.id],
          keyboardType: _keyboardType(f.type),
          maxLines: f.type == PreChatFieldType.textarea ? 4 : 1,
          minLines: f.type == PreChatFieldType.textarea ? 3 : 1,
          style: TextStyle(color: t.text, fontSize: 15),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          onChanged: (_) {
            if (_serverFieldErrors.remove(f.id) != null) setState(() {});
          },
          validator: (v) => _localValidate(f, v),
          decoration: InputDecoration(
            isDense: true,
            hintText: f.placeholder,
            hintStyle: TextStyle(color: t.text.withOpacity(0.4)),
            filled: true,
            fillColor: t.surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            enabledBorder: _border(t.text.withOpacity(0.15)),
            focusedBorder: _border(t.primary, width: 1.5),
            errorBorder: _border(_FormErrorColor.color),
            focusedErrorBorder: _border(_FormErrorColor.color, width: 1.5),
            errorStyle: const TextStyle(color: _FormErrorColor.color),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmit() {
    final t = _theme;
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: _submitting ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: t.primary,
          foregroundColor: _onColor(t.primary),
          disabledBackgroundColor: t.primary.withOpacity(0.5),
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _submitting
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(_onColor(t.primary)),
                ),
              )
            : Text(
                _s.startChat,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }

  Widget _errorText(String msg) => Padding(
        padding: const EdgeInsets.only(top: 6, left: 4),
        child: Text(
          msg,
          style: const TextStyle(
              color: _FormErrorColor.color, fontSize: 12),
        ),
      );

  BoxDecoration _fieldDecoration(bool hasError) => BoxDecoration(
        color: _theme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasError
              ? _FormErrorColor.color
              : _theme.text.withOpacity(0.15),
        ),
      );

  static OutlineInputBorder _border(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: color, width: width),
      );

  static TextInputType _keyboardType(PreChatFieldType t) {
    switch (t) {
      case PreChatFieldType.email:
        return TextInputType.emailAddress;
      case PreChatFieldType.phone:
        return TextInputType.phone;
      case PreChatFieldType.number:
        return const TextInputType.numberWithOptions(decimal: true);
      case PreChatFieldType.textarea:
        return TextInputType.multiline;
      default:
        return TextInputType.text;
    }
  }

  static Color _onColor(Color bg) =>
      bg.computeLuminance() > 0.5 ? const Color(0xFF0F172A) : Colors.white;
}

/// Shared destructive color for validation/errors (no `error` slot on the
/// theme contract, so the views define one consistently).
abstract final class _FormErrorColor {
  static const Color color = Color(0xFFDC2626);
}
