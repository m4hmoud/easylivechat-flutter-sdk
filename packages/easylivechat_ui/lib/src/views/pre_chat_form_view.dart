import 'dart:async';

import 'package:easylivechat/easylivechat.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n.dart';
import '../theme.dart';

/// Dynamic pre-chat form (the native analog of the web `PreChat.tsx`).
///
/// Renders `config.preChatForm.fields` in order, choosing an input per
/// [PreChatFieldType] (text / email / phone / number / textarea / select /
/// consent). Enforces `required` + per-type validation locally via
/// [PreChatField.validate] and [PreChatField.validateConsent] (the server stays
/// the authority), then submits a `Map<fieldId, value>` and the ticked consent
/// ids via `EasyLiveChat.instance.startSession(fields: …, consents: …)`.
///
/// A consent field is a checkbox beside the tenant's sentence, with a
/// "Privacy policy" link under it when the field has a `policyUrl`; the link
/// opens in the visitor's browser, never inside the host app.
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

  /// Consent checkboxes by field id. Absent means unticked, so a consent field
  /// that arrives with a refreshed config starts unticked too.
  final Map<String, bool> _consents = {};

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
      } else if (!f.isConsent) {
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
      if (fieldId != null && _fields.any((f) => f.id == fieldId)) {
        _serverFieldErrors[fieldId] = err.code;
      } else if (fieldId != null && fieldId.isNotEmpty) {
        // A field this form does not show — the tenant changed the form while
        // the visitor was filling it in. Nothing inline can be highlighted, so
        // say so at the form level and fetch the form as it is now.
        _formError = _s.somethingWentWrong;
        unawaited(EasyLiveChat.instance.refreshAvailability());
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
    final consents = <String>[];
    for (final f in _fields) {
      if (f.isConsent) {
        // Consent is not a value: it travels as the list of ticked ids.
        if (_consents[f.id] ?? false) consents.add(f.id);
        continue;
      }
      final v = (f.type == PreChatFieldType.select)
          ? (_selectValues[f.id] ?? '')
          : (_controllers[f.id]?.text ?? '');
      final trimmed = v.trim();
      if (trimmed.isNotEmpty) fields[f.id] = trimmed;
    }

    setState(() => _submitting = true);
    try {
      await EasyLiveChat.instance
          .startSession(fields: fields, consents: consents);
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
                  // Tenant copy can address the visitor by name. The server
                  // can't fill this in: `GET /config` is answered before
                  // anyone has identified.
                  substituteVisitorVariables(
                    widget.config.welcomeTitle,
                    name: EasyLiveChat.instance.visitorName,
                    defaultName: widget.config.defaultCustomerName,
                  ),
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
                      color: t.text.withValues(alpha: 0.7),
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
    if (f.isConsent) return _buildConsent(f);
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
                          style:
                              TextStyle(color: t.text.withValues(alpha: 0.5)),
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
            hintStyle: TextStyle(color: t.text.withValues(alpha: 0.4)),
            filled: true,
            fillColor: t.surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            enabledBorder: _border(t.text.withValues(alpha: 0.15)),
            focusedBorder: _border(t.primary, width: 1.5),
            errorBorder: _border(_FormErrorColor.color),
            focusedErrorBorder: _border(_FormErrorColor.color, width: 1.5),
            errorStyle: const TextStyle(color: _FormErrorColor.color),
          ),
        ),
      ],
    );
  }

  /// A checkbox, the tenant's sentence beside it (verbatim, wrapping — it can
  /// run to 500 characters) and, under the sentence, the privacy-policy link.
  ///
  /// Tapping the sentence ticks the box, as a label does. The link is its own
  /// target and its own node for a screen reader, so opening the policy never
  /// ticks anything — reading what you agree to is not agreeing to it.
  Widget _buildConsent(PreChatField f) {
    final t = _theme;
    final policyUrl = f.policyUrl;
    final sentence = f.label + (f.required ? ' *' : '');
    return FormField<bool>(
      key: ValueKey('elc-consent-${f.id}'),
      initialValue: _consents[f.id] ?? false,
      validator: (_) {
        final serverCode = _serverFieldErrors[f.id];
        if (serverCode != null) return _s.forErrorCode(serverCode);
        final code = f.validateConsent(_consents[f.id] ?? false);
        return code == null ? null : _s.forErrorCode(code);
      },
      builder: (state) {
        final checked = _consents[f.id] ?? false;
        void toggle(bool value) {
          setState(() {
            _consents[f.id] = value;
            _serverFieldErrors.remove(f.id);
          });
          state.didChange(value);
          // Clear the error the moment the box is ticked, rather than leave
          // "please tick this box" under a ticked box until the next submit.
          if (state.hasError) state.validate();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  label: f.label,
                  child: Checkbox(
                    value: checked,
                    activeColor: t.primary,
                    side: BorderSide(
                      color: state.hasError
                          ? _FormErrorColor.color
                          : t.text.withValues(alpha: 0.45),
                      width: 1.5,
                    ),
                    onChanged: _submitting ? null : (v) => toggle(v ?? false),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ExcludeSemantics(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _submitting ? null : () => toggle(!checked),
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(
                                top: 13, end: 4),
                            child: Text(
                              sentence,
                              textAlign: TextAlign.start,
                              style: TextStyle(
                                color: t.text,
                                fontSize: 14,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (policyUrl != null)
                        _PolicyLink(
                          label: _s.privacyPolicy,
                          color: t.primary,
                          onTap: () => _openPolicy(policyUrl),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (state.hasError) _errorText(state.errorText!),
          ],
        );
      },
    );
  }

  /// Out to the visitor's browser. The URL was checked when the config was
  /// parsed — only `http:`/`https:` ever reaches here — and a platform that
  /// cannot open it is a no-op, not a crash in the middle of a form.
  Future<void> _openPolicy(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // No browser, or the platform refused — nothing useful to show.
    }
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
          disabledBackgroundColor: t.primary.withValues(alpha: 0.5),
          elevation: 0,
          // Let the text center in the full 50px height (default button padding
          // squeezes it and clips descenders).
          padding: EdgeInsets.zero,
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
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }

  Widget _errorText(String msg) => Padding(
        padding: const EdgeInsetsDirectional.only(top: 6, start: 4),
        child: Text(
          msg,
          style: const TextStyle(color: _FormErrorColor.color, fontSize: 12),
        ),
      );

  BoxDecoration _fieldDecoration(bool hasError) => BoxDecoration(
        color: _theme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasError
              ? _FormErrorColor.color
              : _theme.text.withValues(alpha: 0.15),
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

/// The "Privacy policy" link under a consent sentence.
class _PolicyLink extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _PolicyLink({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(top: 6, bottom: 6, end: 8),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
              decorationColor: color,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared destructive color for validation/errors (no `error` slot on the
/// theme contract, so the views define one consistently).
abstract final class _FormErrorColor {
  static const Color color = Color(0xFFDC2626);
}
