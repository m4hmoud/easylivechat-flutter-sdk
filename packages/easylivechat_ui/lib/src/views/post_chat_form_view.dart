import 'package:easylivechat/easylivechat.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../theme.dart';

/// The tenant's post-chat survey (the native analog of the web `PostChatForm`).
///
/// Renders `config.postChatForm.fields` in order — the questions the tenant
/// built in the dashboard, not a fixed CSAT — choosing an input per
/// [PostChatFieldType], and submits `Map<fieldId, value>` via
/// `EasyLiveChat.instance.submitPostChat`.
///
/// Wire format matches the web widget exactly, because both write to the same
/// column and the dashboard reads one shape: a checkbox is sent as `'true'`
/// only when ticked and omitted otherwise, a rating as `'1'`–`'5'`, everything
/// else trimmed. A required checkbox means "must be ticked", not "must be
/// answered".
///
/// Tenant-authored copy (every field `label` / `placeholder`) is rendered
/// **verbatim** — never localized. Only SDK chrome is.
class PostChatFormView extends StatefulWidget {
  final WidgetConfigModel config;
  final EasyLiveChatTheme theme;

  /// Dismisses the survey — the visitor may decline to answer.
  final VoidCallback? onDone;

  const PostChatFormView({
    super.key,
    required this.config,
    required this.theme,
    this.onDone,
  });

  @override
  State<PostChatFormView> createState() => _PostChatFormViewState();
}

class _PostChatFormViewState extends State<PostChatFormView> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _selectValues = {};
  final Map<String, bool> _checkValues = {};
  final Map<String, int> _ratings = {};

  bool _submitting = false;
  bool _done = false;
  String? _formError;

  EasyLiveChatTheme get _theme => widget.theme;
  ElcStrings get _s => ElcStrings.of(widget.config.locale);
  List<PostChatField> get _fields => widget.config.postChatForm.fields;

  @override
  void initState() {
    super.initState();
    for (final f in _fields) {
      switch (f.type) {
        case PostChatFieldType.select:
          _selectValues[f.id] = '';
        case PostChatFieldType.checkbox:
          _checkValues[f.id] = false;
        case PostChatFieldType.rating:
          _ratings[f.id] = 0;
        default:
          _controllers[f.id] = TextEditingController();
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// The value a field currently holds, in the shape the server expects.
  String _valueOf(PostChatField f) {
    switch (f.type) {
      case PostChatFieldType.select:
        return _selectValues[f.id] ?? '';
      case PostChatFieldType.checkbox:
        return (_checkValues[f.id] ?? false) ? 'true' : '';
      case PostChatFieldType.rating:
        final r = _ratings[f.id] ?? 0;
        return r == 0 ? '' : '$r';
      default:
        return _controllers[f.id]?.text ?? '';
    }
  }

  String? _localValidate(PostChatField f) {
    final code = f.validate(_valueOf(f));
    return code == null ? null : _s.forErrorCode(code);
  }

  /// Leave the survey.
  ///
  /// The conversation is already over by the time this view exists, so there
  /// is nothing to confirm and nothing to lose — the visitor owes nobody an
  /// answer to get their own app back. Without this the only control on the
  /// screen was Submit, which made an optional survey behave like a required
  /// one.
  ///
  /// Pops our own route when we have one. A host that renders the chat inline
  /// rather than pushing it owns its own dismissal, and the SDK has no
  /// business forcing a state change on a screen it does not control — so
  /// `maybePop` is deliberately a no-op there rather than a guess.
  void _leave() => Navigator.maybePop(context);

  Future<void> _submit() async {
    setState(() => _formError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final fields = <String, String>{};
    for (final f in _fields) {
      final v = _valueOf(f).trim();
      // Empty stays out of the payload entirely — an unanswered optional
      // question is absent, not blank, which is how the dashboard reads it.
      if (v.isNotEmpty) fields[f.id] = v;
    }

    setState(() => _submitting = true);
    try {
      await EasyLiveChat.instance.submitPostChat(fields);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _done = true;
      });
    } on EasyLiveChatError catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _formError =
            e.fieldId != null ? _s.forErrorCode(e.code) : _s.somethingWentWrong;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _formError = _s.somethingWentWrong;
      });
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
          child: _done ? _buildThanks() : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildThanks() {
    final t = _theme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 44, color: t.primary),
            const SizedBox(height: 14),
            Text(
              _s.thanksForFeedback,
              textAlign: TextAlign.center,
              style: TextStyle(color: t.text, fontSize: 16, height: 1.4),
            ),
            const SizedBox(height: 20),
            // Somewhere to go once they're done. Previously the thanks screen
            // was terminal: the survey submitted and then simply sat there.
            TextButton(
              onPressed: _leave,
              child: Text(_s.closeChat, style: TextStyle(color: t.primary)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    final t = _theme;
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: [
          Text(
            _s.rateYourChat,
            style: TextStyle(
              color: t.text,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          for (final f in _fields) ...[
            _buildField(f),
            const SizedBox(height: 18),
          ],
          if (_formError != null) ...[
            Text(
              _formError!,
              style: const TextStyle(color: _ErrorColor.color, fontSize: 13),
            ),
            const SizedBox(height: 12),
          ],
          _buildSubmit(),
        ],
      ),
    );
  }

  Widget _buildField(PostChatField f) {
    switch (f.type) {
      case PostChatFieldType.rating:
        return _buildRating(f);
      case PostChatFieldType.checkbox:
        return _buildCheckbox(f);
      case PostChatFieldType.select:
        return _buildSelect(f);
      default:
        return _buildText(f);
    }
  }

  Widget _label(PostChatField f) => Text(
        f.label + (f.required ? ' *' : ''),
        style: TextStyle(
          color: _theme.text,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      );

  Widget _buildRating(PostChatField f) {
    final t = _theme;
    return FormField<int>(
      initialValue: _ratings[f.id],
      validator: (_) => _localValidate(f),
      builder: (state) {
        final current = _ratings[f.id] ?? 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(f),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var star = 1; star <= 5; star++)
                  IconButton(
                    onPressed: _submitting
                        ? null
                        : () {
                            setState(() => _ratings[f.id] = star);
                            state.didChange(star);
                          },
                    iconSize: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    constraints: const BoxConstraints(),
                    tooltip: '$star / 5',
                    icon: Icon(
                      star <= current
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: star <= current
                          ? t.primary
                          : t.text.withValues(alpha: 0.35),
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

  Widget _buildCheckbox(PostChatField f) {
    final t = _theme;
    return FormField<bool>(
      initialValue: _checkValues[f.id],
      validator: (_) => _localValidate(f),
      builder: (state) {
        final checked = _checkValues[f.id] ?? false;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: _submitting
                  ? null
                  : () {
                      setState(() => _checkValues[f.id] = !checked);
                      state.didChange(!checked);
                    },
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: checked,
                    activeColor: t.primary,
                    onChanged: _submitting
                        ? null
                        : (v) {
                            setState(() => _checkValues[f.id] = v ?? false);
                            state.didChange(v ?? false);
                          },
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _label(f),
                    ),
                  ),
                ],
              ),
            ),
            if (state.hasError) _errorText(state.errorText!),
          ],
        );
      },
    );
  }

  Widget _buildSelect(PostChatField f) {
    final t = _theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(f),
        const SizedBox(height: 8),
        FormField<String>(
          initialValue: _selectValues[f.id],
          validator: (_) => _localValidate(f),
          builder: (state) {
            final value = _selectValues[f.id] ?? '';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Radio rows, not a dropdown. A post-chat survey asks two or
                // three short questions with two or three short answers; a
                // dropdown hides every option behind a tap, opens a modal
                // sheet over the thread, and turns a one-tap answer into
                // three. Laying the options out flat means the visitor can
                // see and answer the whole survey without a single menu.
                for (final opt in f.options)
                  _RadioRow(
                    label: opt,
                    selected: value == opt,
                    enabled: !_submitting,
                    theme: t,
                    hasError: state.hasError,
                    onTap: () {
                      setState(() => _selectValues[f.id] = opt);
                      state.didChange(opt);
                    },
                  ),
                if (state.hasError) _errorText(state.errorText!),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildText(PostChatField f) {
    final t = _theme;
    final multiline = f.type == PostChatFieldType.textarea;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(f),
        const SizedBox(height: 8),
        TextFormField(
          controller: _controllers[f.id],
          enabled: !_submitting,
          keyboardType: _keyboardType(f.type),
          maxLines: multiline ? 4 : 1,
          minLines: multiline ? 3 : 1,
          style: TextStyle(color: t.text, fontSize: 15),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (_) => _localValidate(f),
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
            errorBorder: _border(_ErrorColor.color),
            focusedErrorBorder: _border(_ErrorColor.color, width: 1.5),
            errorStyle: const TextStyle(color: _ErrorColor.color),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmit() {
    final t = _theme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSubmitButton(),
        TextButton(
          onPressed: _submitting ? null : _leave,
          child: Text(
            _s.skipSurvey,
            style: TextStyle(color: t.text.withValues(alpha: 0.6)),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
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
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
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
                _s.submit,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  Widget _errorText(String msg) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          msg,
          style: const TextStyle(color: _ErrorColor.color, fontSize: 12),
        ),
      );

  OutlineInputBorder _border(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: color, width: width),
      );

  TextInputType _keyboardType(PostChatFieldType type) {
    switch (type) {
      case PostChatFieldType.email:
        return TextInputType.emailAddress;
      case PostChatFieldType.phone:
        return TextInputType.phone;
      case PostChatFieldType.number:
        return TextInputType.number;
      case PostChatFieldType.textarea:
        return TextInputType.multiline;
      default:
        return TextInputType.text;
    }
  }

  Color _onColor(Color bg) =>
      bg.computeLuminance() > 0.5 ? const Color(0xFF0F172A) : Colors.white;
}

/// Matches the pre-chat form's error red rather than the theme, which has no
/// error colour of its own.
abstract final class _ErrorColor {
  static const color = Color(0xFFDC2626);
}

/// One tappable answer in a select question.
///
/// The whole row is the target, not just the little circle — on a phone the
/// circle alone is well under the 44pt minimum, and nobody aims for it when
/// the label is right there.
class _RadioRow extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final bool hasError;
  final EasyLiveChatTheme theme;
  final VoidCallback onTap;

  const _RadioRow({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.hasError,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final border = hasError
        ? _ErrorColor.color
        : selected
            ? theme.primary
            : theme.text.withValues(alpha: 0.25);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? theme.primary.withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minHeight: 46),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: border, width: selected ? 1.6 : 1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                // Drawn rather than a Radio widget: Radio carries Material
                // theming that ignores the tenant's colours.
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? theme.primary
                          : theme.text.withValues(alpha: 0.35),
                      width: 2,
                    ),
                  ),
                  child: selected
                      ? Center(
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: theme.primary,
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: theme.text.withValues(alpha: enabled ? 1 : 0.5),
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
