import 'enums.dart';

/// A single pre-chat form field, as defined by the tenant in WidgetConfig.
/// The submission key is [id] (NOT label). Labels are tenant-authored and are
/// NOT localized — render verbatim.
class PreChatField {
  final String id;
  final String label;
  final PreChatFieldType type;
  final bool required;
  final String? placeholder;

  /// Only meaningful for [PreChatFieldType.select].
  final List<String> options;

  const PreChatField({
    required this.id,
    required this.label,
    required this.type,
    this.required = false,
    this.placeholder,
    this.options = const [],
  });

  factory PreChatField.fromJson(Map<String, dynamic> j) => PreChatField(
        id: (j['id'] ?? '').toString(),
        label: (j['label'] ?? '').toString(),
        type: PreChatFieldType.fromWire(j['type']),
        required: j['required'] == true,
        placeholder: j['placeholder'] as String?,
        options: (j['options'] is List)
            ? (j['options'] as List).map((e) => e.toString()).toList()
            : const [],
      );

  /// Client-side validation mirroring the server (`validatePreChatSubmission`).
  /// Returns an error code (`REQUIRED` | `INVALID_EMAIL` | `INVALID_NUMBER` |
  /// `INVALID_OPTION`) or null when valid. The server remains the authority.
  String? validate(String? value) {
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
}
