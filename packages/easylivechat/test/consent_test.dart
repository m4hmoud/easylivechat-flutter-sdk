/// Pre-chat consent checkboxes.
///
/// A consent field is a checkbox, not a value: its `label` is the sentence the
/// visitor agrees to, and what goes to the server is the list of ticked ids
/// beside the `consent` capability. The server only sends consent fields to a
/// client that asks (`?caps=consent`) and only demands them from one that
/// declares it (`capabilities: ['consent']`), so the invariants here are about
/// WHEN this SDK asks and declares — never over a form it did not draw — as
/// much as about what it sends.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:easylivechat/easylivechat.dart';
import 'package:easylivechat/src/rest_client.dart';
import 'package:easylivechat/src/session_controller.dart';
import 'package:test/test.dart';

void main() {
  group('parsing', () {
    test('reads a consent field and its policy link', () {
      final f = PreChatField.fromJson({
        'id': 'privacy',
        'label': 'I agree to the processing of my data.',
        'type': 'consent',
        'required': true,
        'policyUrl': 'https://example.com/privacy',
      });
      expect(f.type, PreChatFieldType.consent);
      expect(f.isConsent, isTrue);
      expect(f.required, isTrue);
      expect(f.policyUrl, 'https://example.com/privacy');
    });

    test('drops a policy link that is not http(s)', () {
      for (final bad in [
        'javascript:alert(1)',
        'ftp://example.com/p',
        'https://localhost/p', // no dot in the host
        'https://exa mple.com',
        'https://user@example.com/p',
        '',
        42,
      ]) {
        final f = PreChatField.fromJson(
            {'id': 'c', 'label': 'x', 'type': 'consent', 'policyUrl': bad});
        expect(f.policyUrl, isNull, reason: '$bad');
      }
    });

    test('keeps a link only on a consent field', () {
      final f = PreChatField.fromJson({
        'id': 'name',
        'label': 'Name',
        'type': 'text',
        'policyUrl': 'https://example.com/privacy',
      });
      expect(f.policyUrl, isNull);
    });

    test('a consent field has no placeholder', () {
      final f = PreChatField.fromJson(
          {'id': 'c', 'label': 'x', 'type': 'consent', 'placeholder': 'p'});
      expect(f.placeholder, isNull);
    });

    test('an unknown type still reads as text', () {
      final f =
          PreChatField.fromJson({'id': 'x', 'label': 'X', 'type': 'signature'});
      expect(f.type, PreChatFieldType.text);
    });

    test('a long sentence arrives whole', () {
      final sentence = 'I agree. ' * 55; // ~500 characters
      final f = PreChatField.fromJson(
          {'id': 'c', 'label': sentence, 'type': 'consent'});
      expect(f.label, sentence);
    });
  });

  group('cleanPolicyUrl matches the server', () {
    test('accepts what the server stores', () {
      for (final ok in [
        'https://example.com',
        'http://example.com/privacy',
        'HTTPS://Example.COM/a?b=c#d',
        '  https://example.com/privacy  ',
        'https://sub.example.co.uk/p/q',
      ]) {
        expect(cleanPolicyUrl(ok), ok.trim(), reason: ok);
      }
    });

    test('refuses an over-long link', () {
      expect(cleanPolicyUrl('https://example.com/${'a' * 500}'), isNull);
    });
  });

  group('validation', () {
    const consent = PreChatField(
        id: 'privacy',
        label: 'I agree',
        type: PreChatFieldType.consent,
        required: true);
    const optional = PreChatField(
        id: 'news', label: 'Send me news', type: PreChatFieldType.consent);
    const name = PreChatField(
        id: 'name', label: 'Name', type: PreChatFieldType.text, required: true);

    test('consent is never a value', () {
      expect(consent.validate(null), isNull);
      expect(consent.validate(''), isNull);
    });

    test('a required consent must be ticked', () {
      expect(consent.validateConsent(false),
          EasyLiveChatErrorCode.consentRequired);
      expect(consent.validateConsent(true), isNull);
      expect(optional.validateConsent(false), isNull);
      expect(name.validateConsent(false), isNull);
    });

    test('missingConsent names the first required one left unticked', () {
      const form = PreChatForm(enabled: true, fields: [
        name,
        optional,
        consent,
        PreChatField(
            id: 'terms',
            label: 'Terms',
            type: PreChatFieldType.consent,
            required: true),
      ]);
      expect(form.missingConsent(const [])?.id, 'privacy');
      expect(form.missingConsent(const ['privacy'])?.id, 'terms');
      expect(form.missingConsent(const ['privacy', 'terms']), isNull);
      expect(form.consentFields.map((f) => f.id), ['news', 'privacy', 'terms']);
    });

    test('a disabled form asks for nothing', () {
      const form = PreChatForm(enabled: false, fields: [consent]);
      expect(form.missingConsent(const []), isNull);
    });
  });

  group('wire', () {
    late _FakeServer server;
    late RestClient rest;

    setUp(() {
      server = _FakeServer();
      rest = RestClient(_config, dio: server.dio);
    });

    test('config asks for consent fields only when told to', () async {
      await rest.getConfig();
      expect(server.last.uri.queryParameters.containsKey('caps'), isFalse);
      await rest.getConfig(consent: true);
      expect(server.last.uri.queryParameters['caps'], 'consent');
    });

    test('a session sends the ticked ids with the capability', () async {
      await rest.postSession(
          visitorId: 'v1', consents: const ['privacy', 'privacy', 'news']);
      final body = server.lastBody;
      expect(body['capabilities'], ['consent']);
      expect(body['consents'], ['privacy', 'news']);
    });

    test('an empty list still declares the capability', () async {
      await rest.postSession(visitorId: 'v1', consents: const []);
      expect(server.lastBody['capabilities'], ['consent']);
      expect(server.lastBody['consents'], isEmpty);
    });

    test('no consents, no capability — the request an older SDK made',
        () async {
      await rest.postSession(visitorId: 'v1', fields: const {'name': 'Ada'});
      expect(server.lastBody.containsKey('capabilities'), isFalse);
      expect(server.lastBody.containsKey('consents'), isFalse);
    });

    test('the offline form carries consents the same way', () async {
      await rest.postOfflineForm(message: 'hi', consents: const ['privacy']);
      expect(server.lastBody['capabilities'], ['consent']);
      expect(server.lastBody['consents'], ['privacy']);
      await rest.postOfflineForm(message: 'hi');
      expect(server.lastBody.containsKey('capabilities'), isFalse);
    });

    test('CONSENT_REQUIRED decodes like any field error', () async {
      server.sessionStatus = 400;
      server.sessionBody = {'error': 'CONSENT_REQUIRED', 'fieldId': 'privacy'};
      await expectLater(
        rest.postSession(visitorId: 'v1', consents: const []),
        throwsA(isA<EasyLiveChatError>()
            .having(
                (e) => e.code, 'code', EasyLiveChatErrorCode.consentRequired)
            .having((e) => e.fieldId, 'fieldId', 'privacy')
            .having((e) => e.httpStatus, 'httpStatus', 400)),
      );
    });
  });

  group('controller', () {
    late _FakeServer server;
    late SessionController c;

    Future<SessionController> boot({
      bool supportsConsent = true,
      Map<String, dynamic>? form,
    }) async {
      server = _FakeServer(preChatForm: form ?? _consentForm);
      final controller =
          SessionController(config: _config, storage: InMemoryStorage())
            ..supportsConsent = supportsConsent;
      controller.rest = RestClient(_config, dio: server.dio);
      await controller.boot();
      return controller;
    }

    tearDown(() => c.dispose());

    test('asks for consent fields when it can draw them', () async {
      c = await boot();
      await c.loadConfig();
      expect(server.configRequests.last.queryParameters['caps'], 'consent');
      expect(
          c.widgetConfig.value!.preChatForm.consentFields.single.id, 'privacy');
    });

    test('does not ask when it cannot', () async {
      c = await boot(supportsConsent: false);
      await c.loadConfig();
      expect(server.configRequests.last.queryParameters.containsKey('caps'),
          isFalse);
    });

    test('refreshAvailability asks the same way', () async {
      c = await boot();
      await c.refreshAvailability();
      expect(server.configRequests.last.queryParameters['caps'], 'consent');
    });

    test('a new chat declares the capability and the ticked ids', () async {
      c = await boot();
      await c.loadConfig();
      await c.startSession(
          fields: const {'name': 'Ada'}, consents: const ['privacy']);
      final body = server.sessionBodies.last;
      expect(body['capabilities'], ['consent']);
      expect(body['consents'], ['privacy']);
      // Consent is not a value.
      expect((body['fields'] as Map).containsKey('privacy'), isFalse);
    });

    test('a required consent left unticked fails before the round trip',
        () async {
      c = await boot();
      await c.loadConfig();
      await expectLater(
        c.startSession(fields: const {'name': 'Ada'}),
        throwsA(isA<EasyLiveChatError>()
            .having((e) => e.code, 'code', 'CONSENT_REQUIRED')
            .having((e) => e.fieldId, 'fieldId', 'privacy')),
      );
      expect(server.sessionBodies, isEmpty);
    });

    test('the value fields are checked first, as the server does', () async {
      c = await boot();
      await c.loadConfig();
      await expectLater(
        c.startSession(fields: const {}),
        throwsA(isA<EasyLiveChatError>()
            .having((e) => e.code, 'code', 'REQUIRED')
            .having((e) => e.fieldId, 'fieldId', 'name')),
      );
    });

    test('never declares over a form fetched without consent', () async {
      c = await boot(supportsConsent: false);
      await c.loadConfig();
      await c.startSession(
          fields: const {'name': 'Ada'}, consents: const ['privacy']);
      final body = server.sessionBodies.last;
      expect(body.containsKey('capabilities'), isFalse);
      expect(body.containsKey('consents'), isFalse);
    });

    test('a host-identified visitor saw no form and is asked nothing',
        () async {
      c = await boot();
      c.identify(name: 'Ada', email: 'ada@example.com');
      await c.open();
      final create =
          server.sessionBodies.lastWhere((b) => b['resumeOnly'] != true);
      expect(create.containsKey('capabilities'), isFalse);
      expect(c.phase.value, ChatPhase.chat);
    });

    test('an anonymous start has no form to tick', () async {
      c = await boot(form: {'enabled': false, 'fields': []});
      await c.open();
      final create =
          server.sessionBodies.lastWhere((b) => b['resumeOnly'] != true);
      expect(create.containsKey('capabilities'), isFalse);
    });

    test('an older server sends no consent field; nothing is demanded',
        () async {
      // It ignores `caps` and its form has no consent field. The capability
      // is still declared — with nothing ticked, which nothing requires.
      c = await boot(form: {
        'enabled': true,
        'fields': [
          {'id': 'name', 'label': 'Name', 'type': 'text', 'required': true},
        ],
      });
      await c.loadConfig();
      await c.startSession(fields: const {'name': 'Ada'});
      expect(server.sessionBodies.last['consents'], isEmpty);
      expect(c.phase.value, ChatPhase.chat);
    });

    test('the offline form checks and sends consents', () async {
      c = await boot();
      await c.loadConfig();
      await expectLater(
        c.submitOfflineForm(message: 'hi', consents: const []),
        throwsA(isA<EasyLiveChatError>()
            .having((e) => e.code, 'code', 'CONSENT_REQUIRED')),
      );
      await c.submitOfflineForm(message: 'hi', consents: const ['privacy']);
      expect(server.offlineBodies.last['consents'], ['privacy']);
      await c.submitOfflineForm(message: 'hi');
      expect(server.offlineBodies.last.containsKey('capabilities'), isFalse);
    });
  });

  group('facade', () {
    tearDown(() {
      EasyLiveChat.instance.shutdown();
      EasyLiveChat.instance.supportsConsent = false;
    });

    test('supportsConsent can be set before boot and survives it', () async {
      expect(EasyLiveChat.instance.supportsConsent, isFalse);
      EasyLiveChat.instance.supportsConsent = true;
      await EasyLiveChat.instance.boot(_config);
      expect(EasyLiveChat.instance.supportsConsent, isTrue);
    });
  });
}

const _config = EasyLiveChatConfig(
  apiBase: 'https://api.example.test',
  tenantSlug: 'acme',
  enablePresenceSocket: false,
  enableHeartbeat: false,
);

const Map<String, dynamic> _consentForm = {
  'enabled': true,
  'fields': [
    {'id': 'name', 'label': 'Name', 'type': 'text', 'required': true},
    {
      'id': 'privacy',
      'label': 'I agree to the privacy notice.',
      'type': 'consent',
      'required': true,
      'policyUrl': 'https://example.com/privacy',
    },
  ],
};

/// Answers the widget endpoints from memory and records what was asked.
class _FakeServer implements HttpClientAdapter {
  _FakeServer({this.preChatForm = const {'enabled': false, 'fields': []}});

  final Map<String, dynamic> preChatForm;
  int sessionStatus = 200;
  Map<String, dynamic>? sessionBody;

  late final Dio dio = Dio(BaseOptions(validateStatus: (_) => true))
    ..httpClientAdapter = this;

  late RequestOptions last;
  final List<Uri> configRequests = [];
  final List<Map<String, dynamic>> sessionBodies = [];
  final List<Map<String, dynamic>> offlineBodies = [];

  Map<String, dynamic> get lastBody =>
      (last.data as Map).cast<String, dynamic>();

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    last = options;
    final path = options.uri.path;
    if (path.endsWith('/config')) {
      configRequests.add(options.uri);
      return _json(200, {
        'tenantId': 't1',
        'isOpen': true,
        'agentsAccepting': true,
        'visitorMode': 'CHAT',
        'reason': 'OPEN',
        'config': {'locale': 'en', 'preChatForm': preChatForm},
      });
    }
    if (path.endsWith('/session')) {
      final body = (options.data as Map).cast<String, dynamic>();
      if (body['resumeOnly'] == true) {
        return _json(200, {'resumed': false, 'hasActiveConversation': false});
      }
      sessionBodies.add(body);
      return _json(
          sessionStatus,
          sessionBody ??
              {
                'token': _jwt,
                'conversationId': 'c1',
                'resumed': false,
                'hasActiveConversation': true,
                'messages': const [],
              });
    }
    if (path.endsWith('/offline-form')) {
      offlineBodies.add((options.data as Map).cast<String, dynamic>());
      return _json(200, {'conversationId': 'c2'});
    }
    return _json(404, {'error': 'NOT_FOUND'});
  }

  ResponseBody _json(int status, Object body) => ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

/// Decodes (the SDK only reads `exp`); the signature is never checked.
final String _jwt = () {
  String b64(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  final exp =
      DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/
          1000;
  return '${b64({'alg': 'HS256'})}.${b64({'exp': exp})}.sig';
}();
