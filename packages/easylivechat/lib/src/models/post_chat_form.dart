import 'enums.dart';

/// A single post-chat survey field, as defined by the tenant in the dashboard.
///
/// Mirrors [PreChatField] — same submission contract (the key is [id], never
/// the label; labels are tenant-authored and rendered verbatim, not localized)
/// — with the two extra types a post-chat survey needs: `rating` for CSAT and
/// `checkbox` for a yes/no.
class PostChatField {
  final String id;
  final String label;
  final PostChatFieldType type;
  final bool required;
  final String? placeholder;

  /// Only meaningful for [PostChatFieldType.select].
  final List<String> options;

  const PostChatField({
    required this.id,
    required this.label,
    required this.type,
    this.required = false,
    this.placeholder,
    this.options = const [],
  });

  factory PostChatField.fromJson(Map<String, dynamic> j) => PostChatField(
        id: (j['id'] ?? '').toString(),
        label: (j['label'] ?? '').toString(),
        type: PostChatFieldType.fromWire(j['type']),
        required: j['required'] == true,
        placeholder: j['placeholder'] as String?,
        options: (j['options'] is List)
            ? (j['options'] as List).map((e) => e.toString()).toList()
            : const [],
      );

  /// Client-side validation mirroring the server. Returns an error code
  /// (`REQUIRED` | `INVALID_EMAIL` | `INVALID_NUMBER` | `INVALID_OPTION` |
  /// `INVALID_RATING`) or null when valid. The server stays the authority.
  String? validate(String? value) {
    final v = (value ?? '').trim();
    if (required && v.isEmpty) return 'REQUIRED';
    if (v.isEmpty) return null;
    switch (type) {
      case PostChatFieldType.email:
        final re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
        return re.hasMatch(v) ? null : 'INVALID_EMAIL';
      case PostChatFieldType.number:
        return num.tryParse(v) == null ? 'INVALID_NUMBER' : null;
      case PostChatFieldType.select:
        return options.contains(v) ? null : 'INVALID_OPTION';
      case PostChatFieldType.rating:
        final n = int.tryParse(v);
        return (n != null && n >= 1 && n <= 5) ? null : 'INVALID_RATING';
      default:
        return null;
    }
  }
}

/// The resolved post-chat survey, materialized by the server on
/// `GET /:slug/config` (widget defaults, with per-channel overrides applied).
///
/// `enabled: false`, or an empty [fields], means the host should fall back to
/// the built-in CSAT prompt rather than showing nothing — the same rule the web
/// widget follows, so a visitor's experience doesn't depend on which client
/// they happened to open.
class PostChatForm {
  final bool enabled;
  final List<PostChatField> fields;

  const PostChatForm({required this.enabled, this.fields = const []});

  /// True when the tenant has actually configured something to ask.
  bool get hasFields => enabled && fields.isNotEmpty;

  factory PostChatForm.fromJson(Map<String, dynamic> j) => PostChatForm(
        enabled: j['enabled'] == true,
        fields: (j['fields'] is List)
            ? (j['fields'] as List)
                .whereType<Map>()
                .map((m) => PostChatField.fromJson(m.cast<String, dynamic>()))
                .toList()
            : const [],
      );

  static const PostChatForm disabled = PostChatForm(enabled: false, fields: []);
}
