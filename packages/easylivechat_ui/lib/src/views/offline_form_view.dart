import 'package:easylivechat/easylivechat.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../theme.dart';

/// Offline / out-of-hours form (native analog of the web offline path).
///
/// Renders the tenant's `config.offlineMessage` verbatim, then collects
/// name / email / message and submits via
/// `EasyLiveChat.instance.submitOfflineForm`. Offline submissions are NOT
/// resumable on the server (they create a Contact with a random externalId and
/// open no socket), so this view never attempts a realtime connection and ends
/// in a terminal "we'll get back to you" state on success.
class OfflineFormView extends StatefulWidget {
  final WidgetConfigModel config;
  final EasyLiveChatTheme theme;

  const OfflineFormView({
    super.key,
    required this.config,
    required this.theme,
  });

  @override
  State<OfflineFormView> createState() => _OfflineFormViewState();
}

class _OfflineFormViewState extends State<OfflineFormView> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _message = TextEditingController();

  bool _submitting = false;
  bool _done = false;
  String? _error;

  EasyLiveChatTheme get _theme => widget.theme;
  ElcStrings get _s => ElcStrings.of(widget.config.locale);

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await EasyLiveChat.instance.submitOfflineForm(
        name: _name.text.trim().isEmpty ? null : _name.text.trim(),
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        message: _message.text.trim(),
      );
      if (mounted) setState(() => _done = true);
    } on EasyLiveChatError catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = e.message ?? _s.somethingWentWrong;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = _s.somethingWentWrong;
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
          child: _done ? _thankYou() : _form(),
        ),
      ),
    );
  }

  Widget _thankYou() {
    final t = _theme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mark_email_read_outlined, size: 56, color: t.primary),
            const SizedBox(height: 16),
            Text(
              _s.offlineThanks,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: t.text, fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _form() {
    final t = _theme;
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: [
          // Tenant-authored copy — rendered verbatim, never localized.
          Text(
            widget.config.offlineMessage,
            style: TextStyle(color: t.text, fontSize: 16, height: 1.4),
          ),
          const SizedBox(height: 24),
          _field(
            controller: _name,
            label: _s.yourName,
            keyboardType: TextInputType.name,
          ),
          const SizedBox(height: 16),
          _field(
            controller: _email,
            label: _s.yourEmail,
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              final value = (v ?? '').trim();
              if (value.isEmpty) return null; // email optional
              final re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
              return re.hasMatch(value) ? null : _s.invalidEmail;
            },
          ),
          const SizedBox(height: 16),
          _field(
            controller: _message,
            label: _s.yourMessage,
            keyboardType: TextInputType.multiline,
            minLines: 3,
            maxLines: 6,
            validator: (v) =>
                (v ?? '').trim().isEmpty ? _s.fieldRequired : null,
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: t.primary,
                foregroundColor: _onColor(t.primary),
                disabledBackgroundColor: t.primary.withOpacity(0.5),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _submitting
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            _onColor(t.primary)),
                      ),
                    )
                  : Text(
                      _s.sendMessage,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    int minLines = 1,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    final t = _theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
              color: t.text, fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          minLines: minLines,
          maxLines: maxLines,
          validator: validator,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          style: TextStyle(color: t.text, fontSize: 15),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: t.surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: t.text.withOpacity(0.15)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: t.primary, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFDC2626)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
            ),
            errorStyle: const TextStyle(color: Color(0xFFDC2626)),
          ),
        ),
      ],
    );
  }

  static Color _onColor(Color bg) =>
      bg.computeLuminance() > 0.5 ? const Color(0xFF0F172A) : Colors.white;
}
