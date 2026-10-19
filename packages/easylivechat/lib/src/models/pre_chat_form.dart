import '../errors.dart';
import 'enums.dart';

/// A single pre-chat form field, as defined by the tenant in WidgetConfig.
/// The submission key is [id] (NOT label). Labels are tenant-authored and are
/// NOT localized — render verbatim.
class PreChatField {
  final String id;

  /// What the visitor reads beside the input. For a [PreChatFieldType.consent]
  /// field this is the whole sentence they agree to — up to 500 characters,
  /// so let it wrap.
  final String label;
  final PreChatFieldType type;
  final bool required;
  final String? placeholder;

  /// Only meaningful for [PreChatFieldType.select].
  final List<String> options;

  /// Only meaningful for [PreChatFieldType.consent]: the privacy policy the
  /// sentence refers to, to be linked beside the checkbox and opened outside
  /// the app. Always an `http:`/`https:` URL — anything else is dropped when
  /// the field is parsed (see [cleanPolicyUrl]).
  final String? policyUrl;

  const PreChatField({
    required this.id,
    required this.label,
    required this.type,
    this.required = false,
    this.placeholder,
    this.options = const [],
    this.policyUrl,
  });

  factory PreChatField.fromJson(Map<String, dynamic> j) {
    final type = PreChatFieldType.fromWire(j['type']);
    return PreChatField(
      id: (j['id'] ?? '').toString(),
      label: (j['label'] ?? '').toString(),
      type: type,
      required: j['required'] == true,
      placeholder: type == PreChatFieldType.consent
          ? null
          : (j['placeholder'] is String ? j['placeholder'] as String : null),
      options: (j['options'] is List)
          ? (j['options'] as List).map((e) => e.toString()).toList()
          : const [],
      policyUrl: type == PreChatFieldType.consent
          ? cleanPolicyUrl(j['policyUrl'])
          : null,
    );
  }

  /// A checkbox the visitor ticks, not a value they type.
  bool get isConsent => type == PreChatFieldType.consent;

  /// Client-side validation mirroring the server (`validatePreChatSubmission`).
  /// Returns an error code (`REQUIRED` | `INVALID_EMAIL` | `INVALID_NUMBER` |
  /// `INVALID_OPTION`) or null when valid. The server remains the authority.
  ///
  /// Always null for a consent field: consent is not a value. Check it with
  /// [validateConsent].
  String? validate(String? value) {
    if (isConsent) return null;
    final v = (value ?? '').trim();
    if (required && v.isEmpty) return 'REQUIRED';
    if (v.isEmpty) return null;
    switch (type) {
      case PreChatFieldType.email:
        final re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
        return re.hasMatch(v) ? null : 'INVALID_EMAIL';
      case PreChatFieldType.number:
        return num.tryParse(v) == null ? 'INVALID_NUMBER' : null;
      case PreChatFieldType.select:
        return options.contains(v) ? null : 'INVALID_OPTION';
      default:
        return null;
    }
  }

  /// A consent field's check: `CONSENT_REQUIRED` when it is required and
  /// [accepted] is false, else null. Null for any other kind of field.
  String? validateConsent(bool accepted) {
    if (!isConsent) return null;
    return required && !accepted ? EasyLiveChatErrorCode.consentRequired : null;
  }
}

/// The resolved pre-chat form. `enabled:false` => skip straight to anonymous
/// chat. The server always materializes this on `GET /:slug/config`.
class PreChatForm {
  final bool enabled;
  final List<PreChatField> fields;

  const PreChatForm({required this.enabled, this.fields = const []});

  factory PreChatForm.fromJson(Map<String, dynamic> j) => PreChatForm(
        enabled: j['enabled'] == true,
        fields: (j['fields'] is List)
            ? (j['fields'] as List)
                .whereType<Map>()
                .map((m) => PreChatField.fromJson(m.cast<String, dynamic>()))
                .toList()
            : const [],
      );

  static const PreChatForm disabled = PreChatForm(enabled: false, fields: []);

  /// The consent checkboxes, in form order. Empty from a server that has none
  /// or that was not asked for them.
  List<PreChatField> get consentFields =>
      fields.where((f) => f.isConsent).toList(growable: false);

  /// The first required consent field whose id is not in [accepted], or null
  /// when every required one is ticked — the server's `validateConsents`, so
  /// a `CONSENT_REQUIRED` can be shown before the round trip. A disabled form
  /// asks for nothing.
  PreChatField? missingConsent(Iterable<String> accepted) {
    if (!enabled) return null;
    final ticked = accepted.toSet();
    for (final f in fields) {
      if (f.validateConsent(ticked.contains(f.id)) != null) return f;
    }
    return null;
  }
}

/// [raw] as an `http:`/`https:` URL, or null.
///
/// The server's `cleanPolicyUrl` (`packages/shared/src/pre-chat-form.ts`),
/// ported so the SDK never opens a link the server would not have stored —
/// a `javascript:` link beside a checkbox is an attack, not a policy. It
/// reads the URL with the same pattern rather than `Uri.parse`, which accepts
/// things a browser refuses.
String? cleanPolicyUrl(Object? raw) {
  if (raw is! String) return null;
  final v = raw.trim();
  if (v.isEmpty || v.length > _policyUrlMax) return null;
  return _policyUrlPattern.hasMatch(v) ? v : null;
}

const int _policyUrlMax = 500;
final RegExp _policyUrlPattern = RegExp(
  r'^https?://[^\s/?#@]+\.[^\s/?#@]+(?:[/?#][^\s]*)?$',
  caseSensitive: false,
);
