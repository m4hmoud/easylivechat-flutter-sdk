import 'package:easylivechat/easylivechat.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../theme.dart';

/// CSAT prompt shown after the agent closes the conversation (native analog of
/// the web feedback step).
///
/// Collects a 1–5 star rating + an optional comment and submits via
/// `EasyLiveChat.instance.submitFeedback`. On success — or when the server says
/// the conversation was `ALREADY_RATED` (HTTP 409) — it flips to a localized
/// thank-you state; a one-shot rating is enforced server-side, so an
/// already-rated response is treated as "done", not an error.
class FeedbackPromptView extends StatefulWidget {
  final EasyLiveChatTheme theme;

  const FeedbackPromptView({super.key, required this.theme});

  @override
  State<FeedbackPromptView> createState() => _FeedbackPromptViewState();
}

class _FeedbackPromptViewState extends State<FeedbackPromptView> {
  final TextEditingController _comment = TextEditingController();
  int _rating = 0;
  bool _submitting = false;
  bool _done = false;
  String? _error;

  EasyLiveChatTheme get _theme => widget.theme;
  ElcStrings get _s =>
      ElcStrings.of(EasyLiveChat.instance.widgetConfig.value?.locale);

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating < 1 || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final comment = _comment.text.trim();
    try {
      await EasyLiveChat.instance.submitFeedback(
        rating: _rating,
        comment: comment.isEmpty ? null : comment,
      );
      if (mounted) setState(() => _done = true);
    } on EasyLiveChatError catch (e) {
      // Already rated => treat as success (one-shot CSAT).
      if (e.code == EasyLiveChatErrorCode.alreadyRated) {
        if (mounted) setState(() => _done = true);
        return;
      }
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = _s.somethingWentWrong;
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
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: _done ? _thankYou() : _form(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _thankYou() {
    final t = _theme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle_rounded, size: 56, color: t.primary),
        const SizedBox(height: 16),
        Text(
          _s.thanksForFeedback,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: t.text, fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _form() {
    final t = _theme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _s.rateYourChat,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: t.text, fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          _s.rateHint,
          textAlign: TextAlign.center,
          style: TextStyle(color: t.text.withValues(alpha: 0.7), fontSize: 14),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (i) {
            final star = i + 1;
            final filled = star <= _rating;
            return IconButton(
              onPressed: _submitting
                  ? null
                  : () => setState(() {
                        _rating = star;
                        _error = null;
                      }),
              iconSize: 40,
              icon: Icon(
                filled ? Icons.star_rounded : Icons.star_border_rounded,
                color: filled ? t.primary : t.text.withValues(alpha: 0.3),
              ),
            );
          }),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _comment,
          enabled: !_submitting,
          minLines: 2,
          maxLines: 4,
          style: TextStyle(color: t.text, fontSize: 15),
          decoration: InputDecoration(
            hintText: _s.addAComment,
            hintStyle: TextStyle(color: t.text.withValues(alpha: 0.4)),
            filled: true,
            fillColor: t.surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: t.text.withValues(alpha: 0.15)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: t.text.withValues(alpha: 0.15)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: t.primary, width: 1.5),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: (_rating >= 1 && !_submitting) ? _submit : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: t.primary,
              foregroundColor: _onColor(t.primary),
              disabledBackgroundColor: t.primary.withValues(alpha: 0.4),
              elevation: 0,
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
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
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
        ),
      ],
    );
  }

  static Color _onColor(Color bg) =>
      bg.computeLuminance() > 0.5 ? const Color(0xFF0F172A) : Colors.white;
}
