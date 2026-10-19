import 'package:dio/dio.dart';

import 'config.dart';
import 'errors.dart';
import 'models/help_article.dart';
import 'models/results.dart';
import 'models/widget_config.dart';

/// 1:1 wrapper over the widget HTTP endpoints (session, history, forms, push,
/// help articles) + `/api/uploads`.
///
/// Base: `<apiBase>/api/widget`. Tenant resolved by `:slug`. JWT-gated calls
/// (`GET /messages`, `POST /feedback`, `POST /uploads`) take a Bearer token
/// argument. All `{ error, fieldId, message }` bodies decode to
/// [EasyLiveChatError]; transport failures map to `NETWORK`.
class RestClient {
  final EasyLiveChatConfig config;
  final Dio _dio;

  RestClient(this.config, {Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: config.connectTimeout,
              receiveTimeout: config.connectTimeout,
              // We decode non-2xx ourselves into typed errors.
              validateStatus: (_) => true,
            ));

  String get _base => '${config.normalizedApiBase}/api/widget';
  String get _slug => config.tenantSlug;

  /// Future-proof protocol version header sent on every request. The server
  /// currently ignores it (harmless); it lets us negotiate wire changes later.
  static const String _protocolVersionHeader =
      'X-EasyLiveChat-Protocol-Version';
  static const String _protocolVersion = '1';

  /// Base headers attached to every request, optionally adding a Bearer token.
  Map<String, dynamic> _headers([String? token]) => {
        _protocolVersionHeader: _protocolVersion,
        if (token != null && token.isNotEmpty) 'authorization': 'Bearer $token',
      };

  /// The `capabilities` + `consents` pair, or nothing when [consents] is null.
  /// Always sent together: the ids mean nothing to the server without the
  /// declaration, and the declaration alone would make it demand consent the
  /// caller never said it collected. Duplicates are dropped.
  Map<String, dynamic> _consentBody(List<String>? consents) {
    if (consents == null) return const {};
    return {
      'capabilities': const [consentCapability],
      'consents': consents.toSet().toList(),
    };
  }

  /// True when [status] is a 2xx success code.
  bool _ok(int? status) => status != null && status >= 200 && status < 300;

  /// Coerce any decoded response body into a `Map<String, dynamic>`.
  Map<String, dynamic> _asMap(Object? data) {
    if (data is Map) return data.cast<String, dynamic>();
    return const <String, dynamic>{};
  }

  /// What a client declares when it can show a consent checkbox: `?caps=` on
  /// `GET /config`, `capabilities` on `POST /session` and `/offline-form`
  /// (`CONSENT_CAPABILITY` in `packages/shared/src/pre-chat-form.ts`).
  static const String consentCapability = 'consent';

  /// `GET /:slug/config?channel=&origin=` — public. Soft `allowedOrigins` gate
  /// only when an origin is supplied (native should usually omit it).
  ///
  /// [consent] adds `caps=consent`. Without it the server leaves consent
  /// fields out of the pre-chat form, because a client that cannot draw a
  /// checkbox would draw a text box labelled "I agree to…" instead. A server
  /// that predates consent ignores the parameter.
  Future<ConfigResponse> getConfig({bool consent = false}) async {
    try {
      final res = await _dio.get<dynamic>(
        '$_base/$_slug/config',
        queryParameters: {
          if (consent) 'caps': consentCapability,
          // The INBOX this host routes to. Sessions have always carried it, so
          // the conversation landed in the right inbox — but the config did
          // not, and the server resolves per-channel overrides from exactly
          // this parameter. So an app got the workspace defaults for the
          // welcome screen, the queue and offline text, and the pre-chat form,
          // while the dashboard showed an inbox configured differently and
          // nobody could see why it made no difference.
          if (config.channel != null && config.channel!.isNotEmpty)
            'channel': config.channel,
          if (config.originHeader != null && config.originHeader!.isNotEmpty)
            'origin': config.originHeader,
          if (config.contentLocale != null && config.contentLocale!.isNotEmpty)
            'locale': config.contentLocale,
        },
        options: Options(headers: _headers()),
      );
      if (!_ok(res.statusCode)) throwFor(res);
      return ConfigResponse.fromJson(_asMap(res.data));
    } on DioException catch (e) {
      throw _networkError(e);
    }
  }

  /// `POST /:slug/session` — public; MINTS the widget JWT.
  /// Body keys: visitorId (required), name?, email?, phone?, page?, locale?,
  /// resumeOnly?, fields? (keyed by PreChatField.id), userId?, userHash?. On
  /// pre-chat failure the server returns 400 `{ error, fieldId }` => throw
  /// [EasyLiveChatError]. A workspace that ENFORCES identity verification
  /// refuses a [userId] with a missing/wrong [userHash] with 403
  /// `{ error: 'IDENTITY_NOT_VERIFIED', reason }`.
  /// On `resumeOnly:true` with no active conversation the response has no
  /// `token` (and `hasActiveConversation:false`) — return it as-is.
  ///
  /// A non-null [consents] (the ids of the consent fields the visitor ticked,
  /// possibly none) also declares `capabilities: ['consent']`, which is what
  /// lets the server refuse a required one left unticked with 400
  /// `CONSENT_REQUIRED` + `fieldId`. Null sends neither, and the server asks
  /// nothing about consent — the request an SDK made before consent existed.
  Future<SessionResult> postSession({
    required String visitorId,
    String? name,
    String? email,
    String? phone,
    String? page,
    String? locale,
    bool resumeOnly = false,
    Map<String, String>? fields,
    String? userId,
    String? userHash,
    List<String>? consents,
  }) async {
    final claimedId = userId?.trim() ?? '';
    final claimedHash = userHash?.trim() ?? '';
    try {
      final res = await _dio.post<dynamic>(
        '$_base/$_slug/session',
        data: {
          'visitorId': visitorId,
          if (name != null) 'name': name,
          if (email != null) 'email': email,
          if (phone != null && phone.trim().isNotEmpty) 'phone': phone,
          if (page != null) 'page': page,
          // Prefer the explicit per-call locale, fall back to config.locale.
          if ((locale ?? config.locale) != null)
            'locale': locale ?? config.locale,
          // The locale CODE. `locale` above is free-form — hosts put a readable
          // language name there because it is what agents see — so the server
          // cannot match it against anything. This is what picks the visitor's
          // language for the auto-greeting.
          if (config.contentLocale != null && config.contentLocale!.isNotEmpty)
            'contentLocale': config.contentLocale,
          // Channel/inbox routing key — omitted when null (server => default).
          if (config.channel != null) 'channel': config.channel,
          // Client-provided custom attributes (device/app info). Stored as-is
          // by the server; not validated like pre-chat fields.
          if (config.attributes != null && config.attributes!.isNotEmpty)
            'attributes': config.attributes,
          if (resumeOnly) 'resumeOnly': true,
          // Open on the visit being started, not on every visit ever made.
          // A returning customer lands back in a conversation that can span
          // months, and handing them all of it at once buries what they came
          // back for. Earlier visits stay one scroll up, behind the cursor.
          'historyScope': 'session',
          if (fields != null && fields.isNotEmpty) 'fields': fields,
          // Host-declared identity (HMAC identity verification). The hash is
          // made by the host's BACKEND; a hash without an id proves nothing,
          // so it only travels with one. Omitted entirely for anonymous
          // visitors, whom the server never refuses.
          if (claimedId.isNotEmpty) 'userId': claimedId,
          if (claimedId.isNotEmpty && claimedHash.isNotEmpty)
            'userHash': claimedHash,
          ..._consentBody(consents),
        },
        options: Options(headers: _headers()),
      );
      if (!_ok(res.statusCode)) throwFor(res);
      return SessionResult.fromJson(_asMap(res.data));
    } on DioException catch (e) {
      throw _networkError(e);
    }
  }

  /// `GET /:slug/messages?cursor=&limit=` — Bearer [token]. Returns a page
  /// oldest→newest with `nextCursor` (oldest id; pass back to page older).
  /// Clamp [limit] to 1..100 CLIENT-SIDE — the server does not clamp it.
  Future<MessagePage> getMessages({
    required String token,
    String? cursor,
    int limit = 50,
  }) async {
    final clamped = limit < 1 ? 1 : (limit > 100 ? 100 : limit);
    try {
      final res = await _dio.get<dynamic>(
        '$_base/$_slug/messages',
        queryParameters: {
          if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
          'limit': clamped,
        },
        options: Options(headers: _headers(token)),
      );
      if (!_ok(res.statusCode)) throwFor(res);
      return MessagePage.fromJson(_asMap(res.data));
    } on DioException catch (e) {
      throw _networkError(e);
    }
  }

  /// `POST /:slug/offline-form` — public. Returns the created conversationId.
  /// NOTE: this creates an UNRESUMABLE conversation (random externalId, no
  /// token) — terminal "we'll get back to you" UX, never connect a socket.
  ///
  /// [consents] works as it does on [postSession].
  Future<String> postOfflineForm({
    String? name,
    String? email,
    required String message,
    List<String>? consents,
  }) async {
    try {
      final res = await _dio.post<dynamic>(
        '$_base/$_slug/offline-form',
        data: {
          if (name != null) 'name': name,
          if (email != null) 'email': email,
          'message': message,
          ..._consentBody(consents),
        },
        options: Options(headers: _headers()),
      );
      if (!_ok(res.statusCode)) throwFor(res);
      return (_asMap(res.data)['conversationId'] ?? '').toString();
    } on DioException catch (e) {
      throw _networkError(e);
    }
  }

  /// `POST /:slug/conversations/:id/feedback` — Bearer [token]; the token's
  /// conversationId must equal [conversationId]. One-shot (409 ALREADY_RATED).
  Future<FeedbackResult> postFeedback({
    required String token,
    required String conversationId,
    required int rating,
    String? comment,
  }) async {
    try {
      final res = await _dio.post<dynamic>(
        '$_base/$_slug/conversations/$conversationId/feedback',
        data: {
          'rating': rating,
          if (comment != null) 'comment': comment,
        },
        options: Options(headers: _headers(token)),
      );
      if (!_ok(res.statusCode)) throwFor(res);
      return FeedbackResult.fromJson(_asMap(res.data));
    } on DioException catch (e) {
      throw _networkError(e);
    }
  }

  /// `POST /:slug/conversations/:id/post-chat` — Bearer [token]; the token's
  /// conversationId must equal [conversationId]. One-shot, like feedback, but
  /// the server answers 409 `ALREADY_SUBMITTED` rather than `ALREADY_RATED`.
  ///
  /// [fields] is keyed by field **id**, never label — the same contract the
  /// pre-chat form submits under, and what the dashboard reads back.
  Future<void> postChat({
    required String token,
    required String conversationId,
    required Map<String, String> fields,
    String? locale,
  }) async {
    try {
      final res = await _dio.post<dynamic>(
        '$_base/$_slug/conversations/$conversationId/post-chat',
        data: {
          'fields': fields,
          if (locale != null && locale.isNotEmpty) 'locale': locale,
        },
        options: Options(headers: _headers(token)),
      );
      if (!_ok(res.statusCode)) throwFor(res);
    } on DioException catch (e) {
      throw _networkError(e);
    }
  }

  /// `POST /:slug/push/register` — the device to notify when an agent replies
  /// and this app is closed. Authed by the widget token: the server takes the
  /// tenant and the contact from it, never from this body.
  Future<void> registerPush({
    required String token,
    required String pushToken,
    required String platform,
    String? locale,
    String? appVersion,
  }) async {
    try {
      final res = await _dio.post<dynamic>(
        '$_base/$_slug/push/register',
        data: {
          'token': pushToken,
          'platform': platform,
          if (locale != null && locale.isNotEmpty) 'locale': locale,
          if (appVersion != null && appVersion.isNotEmpty) 'appVersion': appVersion,
        },
        options: Options(headers: _headers(token)),
      );
      if (!_ok(res.statusCode)) throwFor(res);
    } on DioException catch (e) {
      throw _networkError(e);
    }
  }

  /// `POST /:slug/push/unregister` — stop notifying this device.
  Future<void> unregisterPush({
    required String token,
    required String pushToken,
  }) async {
    try {
      final res = await _dio.post<dynamic>(
        '$_base/$_slug/push/unregister',
        data: {'token': pushToken},
        options: Options(headers: _headers(token)),
      );
      if (!_ok(res.statusCode)) throwFor(res);
    } on DioException catch (e) {
      throw _networkError(e);
    }
  }

  // ── help articles (public, no token) ──

  /// `GET /:slug/help/articles?q=&locale=&category=&limit=`.
  ///
  /// A [q] shorter than two characters lists the top articles in the
  /// workspace's order (server default 20, max 50); a longer one is a ranked
  /// search (default 5, max 20). A workspace with help switched off answers
  /// `enabled: false` and no articles — not an error.
  Future<HelpArticleList> getHelpArticles({
    String? q,
    String? category,
    int? limit,
  }) async {
    final query = q?.trim() ?? '';
    final cat = category?.trim() ?? '';
    try {
      final res = await _dio.get<dynamic>(
        '$_base/$_slug/help/articles',
        queryParameters: {
          if (query.isNotEmpty) 'q': query,
          if (cat.isNotEmpty) 'category': cat,
          if (limit != null && limit > 0) 'limit': limit,
          if (_contentLocale != null) 'locale': _contentLocale,
        },
        options: Options(headers: _headers()),
      );
      if (!_ok(res.statusCode)) throwFor(res);
      return HelpArticleList.fromJson(_asMap(res.data));
    } on DioException catch (e) {
      throw _networkError(e);
    }
  }

  /// `GET /:slug/help/articles/:id?locale=` — 404 `NOT_FOUND` when it is
  /// unpublished, gone, or the workspace switched help off.
  Future<HelpArticle> getHelpArticle(String id) async {
    try {
      final res = await _dio.get<dynamic>(
        '$_base/$_slug/help/articles/${Uri.encodeComponent(id)}',
        queryParameters: {
          if (_contentLocale != null) 'locale': _contentLocale,
        },
        options: Options(headers: _headers()),
      );
      if (!_ok(res.statusCode)) throwFor(res);
      final raw = _asMap(res.data)['article'];
      if (raw is! Map) {
        throw EasyLiveChatError(
          EasyLiveChatErrorCode.notFound,
          httpStatus: res.statusCode,
          message: 'help article response missing an `article` object',
        );
      }
      return HelpArticle.fromJson(raw.cast<String, dynamic>());
    } on DioException catch (e) {
      throw _networkError(e);
    }
  }

  /// `POST /:slug/help/articles/:id/view` — counts a reading. Returns whether
  /// it was counted (false for a repeat within the same [sessionId]).
  Future<bool> postHelpArticleView(
    String id, {
    required String visitorId,
    required String sessionId,
  }) async {
    try {
      final res = await _dio.post<dynamic>(
        '$_base/$_slug/help/articles/${Uri.encodeComponent(id)}/view',
        data: {'visitorId': visitorId, 'sessionId': sessionId},
        options: Options(headers: _headers()),
      );
      if (!_ok(res.statusCode)) throwFor(res);
      return _asMap(res.data)['counted'] == true;
    } on DioException catch (e) {
      throw _networkError(e);
    }
  }

  /// `POST /:slug/help/articles/:id/feedback` — "Was this helpful?". One
  /// answer per reading; answering again replaces it.
  Future<void> postHelpArticleFeedback(
    String id, {
    required String visitorId,
    required String sessionId,
    required bool helpful,
  }) async {
    try {
      final res = await _dio.post<dynamic>(
        '$_base/$_slug/help/articles/${Uri.encodeComponent(id)}/feedback',
        data: {
          'visitorId': visitorId,
          'sessionId': sessionId,
          'helpful': helpful,
        },
        options: Options(headers: _headers()),
      );
      if (!_ok(res.statusCode)) throwFor(res);
    } on DioException catch (e) {
      throw _networkError(e);
    }
  }

  /// The content-locale code help articles are asked for in, when the host set
  /// one. Unknown codes fall back to the workspace default server-side.
  String? get _contentLocale {
    final c = config.contentLocale?.trim();
    return (c == null || c.isEmpty) ? null : c;
  }

  /// `POST /visitor/heartbeat` — public; tenant from body.tenantSlug (NOTE: no
  /// `:slug` path segment). Always tolerant/2xx. Keep cadence modest — first
  /// arrival / re-arrival after idle notifies agents.
  Future<void> heartbeat({
    required String visitorId,
    String? currentUrl,
    String? currentTitle,
    String? referrerUrl,
    String? language,
  }) async {
    try {
      await _dio.post<dynamic>(
        '$_base/visitor/heartbeat',
        data: {
          'visitorId': visitorId,
          'tenantSlug': _slug,
          if (currentUrl != null) 'currentUrl': currentUrl,
          if (currentTitle != null) 'currentTitle': currentTitle,
          if (referrerUrl != null) 'referrerUrl': referrerUrl,
          // Fall back to the configured locale for the visitor's language.
          if ((language ?? config.locale) != null)
            'language': language ?? config.locale,
        },
        options: Options(headers: _headers()),
      );
      // The endpoint is deliberately tolerant and always returns 2xx; even a
      // non-2xx or `{ ok:false }` body is swallowed so the heartbeat never
      // affects UX. Only true transport failures surface (and are ignored by
      // the caller's fire-and-forget cadence).
    } on DioException {
      // Network failure on a presence ping is non-fatal — swallow it.
      return;
    }
  }

  /// `POST /api/uploads` — Bearer [token] (widget or agent; uses tenantId).
  /// Multipart field name MUST be `file`. Response is a JSON ARRAY — return
  /// element [0]. Whitelist/size are server-enforced (25 MB); map 413 =>
  /// FILE_TOO_LARGE, 415 => UNSUPPORTED_TYPE.
  Future<UploadedFile> uploadBytes({
    required String token,
    required List<int> bytes,
    required String filename,
    String? contentType,
    void Function(double progress)? onProgress,
  }) async {
    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: filename,
          contentType:
              contentType != null ? DioMediaType.parse(contentType) : null,
        ),
      });
      final res = await _dio.post<dynamic>(
        '${config.normalizedApiBase}/api/uploads',
        data: form,
        options: Options(
          headers: _headers(token),
          // Uploads run up to 25 MB; the default connect-sized timeout (20s)
          // aborts a large file on a slow cellular link. Give the request body
          // a generous window, independent of the connect/receive defaults.
          sendTimeout: const Duration(minutes: 2),
          receiveTimeout: const Duration(minutes: 2),
        ),
        onSendProgress: onProgress == null
            ? null
            : (sent, total) {
                if (total > 0) onProgress(sent / total);
              },
      );
      if (!_ok(res.statusCode)) throwFor(res);
      final data = res.data;
      if (data is List && data.isNotEmpty) {
        final first = data.first;
        if (first is Map) {
          return UploadedFile.fromJson(first.cast<String, dynamic>());
        }
      }
      // A 2xx with an unexpected (non-array / empty) body is a protocol
      // violation — treat it as an unknown server error rather than crashing.
      throw EasyLiveChatError(
        EasyLiveChatErrorCode.unknown,
        httpStatus: res.statusCode,
        message: 'upload response was not a non-empty JSON array',
      );
    } on DioException catch (e) {
      throw _networkError(e);
    }
  }

  /// Decode a non-2xx response body `{ error, fieldId, message }` into a typed
  /// error. Implementations should call this from every endpoint.
  Never throwFor(Response res) {
    final body = _asMap(res.data);
    final status = res.statusCode;
    final serverCode = (body['error'] as Object?)?.toString();
    final fieldId = (body['fieldId'] as Object?)?.toString();
    final message = (body['message'] as Object?)?.toString();
    final reason = (body['reason'] as Object?)?.toString();

    // Prefer the server-supplied `{ error }` code when present — it carries the
    // specific protocol codes (ORIGIN_NOT_ALLOWED, CONTENT_TYPE_MISMATCH,
    // REQUIRED, INVALID_RATING, ALREADY_RATED, …) that a status alone would
    // flatten. Fall back to a status-based default when the body omits `error`.
    final String code;
    if (serverCode != null && serverCode.isNotEmpty) {
      code = serverCode;
    } else {
      switch (status) {
        case 401:
          code = EasyLiveChatErrorCode.unauthenticated;
          break;
        case 403:
          code = EasyLiveChatErrorCode.forbidden;
          break;
        case 413:
          code = EasyLiveChatErrorCode.fileTooLarge;
          break;
        case 415:
          code = EasyLiveChatErrorCode.unsupportedType;
          break;
        case 429:
          code = EasyLiveChatErrorCode.rateLimited;
          break;
        default:
          code = EasyLiveChatErrorCode.unknown;
      }
    }

    throw EasyLiveChatError(
      code,
      fieldId: fieldId,
      httpStatus: status,
      message: message,
      reason: (reason != null && reason.isNotEmpty) ? reason : null,
    );
  }

  /// Map a dio transport failure to a typed error. Timeouts and socket-level
  /// failures become `NETWORK`; an [EasyLiveChatError] raised inside an
  /// interceptor/handler is passed through untouched.
  EasyLiveChatError _networkError(DioException e) {
    if (e.error is EasyLiveChatError) return e.error as EasyLiveChatError;
    // A response that slipped through (validateStatus normally returns true,
    // but a custom dio might not) still decodes via throwFor.
    final res = e.response;
    if (res != null && !_ok(res.statusCode)) {
      try {
        throwFor(res);
      } on EasyLiveChatError catch (typed) {
        return typed;
      }
    }
    return EasyLiveChatError(
      EasyLiveChatErrorCode.network,
      message: e.message,
      cause: e,
    );
  }
}
