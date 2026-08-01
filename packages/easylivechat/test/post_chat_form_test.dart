/// The post-chat survey the tenant builds in the dashboard.
///
/// The SDK and the web widget write to the same column and the dashboard reads
/// one shape, so the rules below are not the SDK's own: they mirror
/// `validatePostChatSubmission` in the widget app. A checkbox is `'true'` only
/// when ticked and absent otherwise, a rating is `'1'`–`'5'`, and every key is
/// the field **id** rather than its label.
library;

import 'package:easylivechat/easylivechat.dart';
import 'package:test/test.dart';

/// The default form the server materializes when a tenant hasn't customised
/// one, plus the question types a real survey adds.
Map<String, dynamic> formJson() => {
      'enabled': true,
      'fields': [
        {
          'id': 'resolved',
          'label': 'Was your issue resolved?',
          'type': 'select',
          'required': true,
          'options': ['Yes', 'No'],
        },
        {'id': 'rating', 'label': 'Rate this chat', 'type': 'rating', 'required': true},
        {'id': 'subscribe', 'label': 'Email me a transcript', 'type': 'checkbox', 'required': false},
        {
          'id': 'comment',
          'label': 'Anything else?',
          'type': 'textarea',
          'required': false,
          'placeholder': 'Optional',
        },
      ],
    };

void main() {
  group('PostChatForm.fromJson', () {
    test('reads the tenant\'s questions in order', () {
      final form = PostChatForm.fromJson(formJson());

      expect(form.enabled, isTrue);
      expect(form.hasFields, isTrue);
      expect(form.fields.map((f) => f.id).toList(),
          ['resolved', 'rating', 'subscribe', 'comment']);
      expect(form.fields.first.type, PostChatFieldType.select);
      expect(form.fields.first.options, ['Yes', 'No']);
      expect(form.fields[1].type, PostChatFieldType.rating);
      expect(form.fields[2].type, PostChatFieldType.checkbox);
      expect(form.fields[3].placeholder, 'Optional');
    });

    test('an unknown field type degrades to text rather than dropping the question', () {
      final form = PostChatForm.fromJson({
        'enabled': true,
        'fields': [
          {'id': 'q', 'label': 'From a newer dashboard', 'type': 'signature'},
        ],
      });
      // Better to render a text box than to silently ask nothing.
      expect(form.fields.single.type, PostChatFieldType.text);
    });

    test('hasFields is what decides between the survey and the built-in CSAT', () {
      expect(PostChatForm.fromJson({'enabled': false, 'fields': []}).hasFields, isFalse);
      // Enabled but empty is the trap: it must NOT show a survey with no
      // questions, it must fall back.
      expect(PostChatForm.fromJson({'enabled': true, 'fields': []}).hasFields, isFalse);
      expect(PostChatForm.disabled.hasFields, isFalse);
    });

    test('a config with no postChatForm at all falls back, not crashes', () {
      final cfg = WidgetConfigModel.fromJson({
        'id': 'w1',
        'tenantId': 't1',
        'primaryColor': '#000000',
        'backgroundColor': '#FFFFFF',
        'textColor': '#111111',
        'welcomeTitle': 'Hi',
        'welcomeSubtitle': 'How can we help?',
        'offlineMessage': '',
        'position': 'bottom-right',
        'locale': 'en',
      });
      expect(cfg.postChatForm.hasFields, isFalse);
    });
  });

  group('PostChatField.validate — mirrors the server', () {
    final form = PostChatForm.fromJson(formJson());
    PostChatField byId(String id) => form.fields.firstWhere((f) => f.id == id);

    test('required fields must be answered', () {
      expect(byId('resolved').validate(''), 'REQUIRED');
      expect(byId('rating').validate(''), 'REQUIRED');
      // Optional ones are happy empty.
      expect(byId('comment').validate(''), isNull);
      expect(byId('subscribe').validate(''), isNull);
    });

    test('a rating is an integer 1-5', () {
      expect(byId('rating').validate('1'), isNull);
      expect(byId('rating').validate('5'), isNull);
      expect(byId('rating').validate('0'), 'INVALID_RATING');
      expect(byId('rating').validate('6'), 'INVALID_RATING');
      expect(byId('rating').validate('3.5'), 'INVALID_RATING');
      expect(byId('rating').validate('good'), 'INVALID_RATING');
    });

    test('a select only accepts one of its own options', () {
      expect(byId('resolved').validate('Yes'), isNull);
      expect(byId('resolved').validate('Maybe'), 'INVALID_OPTION');
    });

    test('email and number are checked the same way the server checks them', () {
      const email = PostChatField(
        id: 'e', label: 'Email', type: PostChatFieldType.email, required: false);
      expect(email.validate('someone@example.com'), isNull);
      expect(email.validate('someone@'), 'INVALID_EMAIL');

      const number = PostChatField(
        id: 'n', label: 'How many?', type: PostChatFieldType.number, required: false);
      expect(number.validate('42'), isNull);
      expect(number.validate('-3.5'), isNull);
      expect(number.validate('lots'), 'INVALID_NUMBER');
    });
  });
}
