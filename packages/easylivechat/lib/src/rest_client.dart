import 'package:dio/dio.dart';

import 'config.dart';
import 'errors.dart';
import 'models/results.dart';
import 'models/widget_config.dart';

/// 1:1 wrapper over the six widget HTTP endpoints + `/api/uploads`.
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
  static const String _protocolVersionHeader = 'X-EasyLiveChat-Protocol-Version';
  static const String _protocolVersion = '1';

  /// Base headers attached to every request, optionally adding a Bearer token.
  Map<String, dynamic> _headers([String? token]) => {
        _protocolVersionHeader: _protocolVersion,
        if (token != null && token.isNotEmpty) 'authorization': 'Bearer $token',
      };

  /// True when [status] is a 2xx success code.
  bool _ok(int? status) => status != null && status >= 200 && status < 300;

  /// Coerce any decoded response body into a `Map<String, dynamic>`.
  Map<String, dynamic> _asMap(Object? data) {
    if (data is Map) return data.cast<String, dynamic>();
    return const <String, dynamic>{};
  }

  /// `GET /:slug/config?origin=` — public. Soft `allowedOrigins` gate only when
  /// an origin is supplied (native should usually omit it).
  Future<ConfigResponse> getConfig() async {
    try {
      final res = await _dio.get<dynamic>(
        '$_base/$_slug/config',
        queryParameters: {
          if (config.originHeader != null && config.originHeader!.isNotEmpty)
            'origin': config.originHeader,
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
  /// Body keys: visitorId (required), name?, email?, page?, locale?,
  /// resumeOnly?, fields? (keyed by PreChatField.id). On pre-chat failure the
  /// server returns 400 `{ error, fieldId }` => throw [EasyLiveChatError].
  /// On `resumeOnly:true` with no active conversation the response has no
  /// `token` (and `hasActiveConversation:false`) — return it as-is.
  Future<SessionResult> postSession({
    required String visitorId,
    String? name,
    String? email,
    String? page,
    String? locale,
    bool resumeOnly = false,
    Map<String, String>? fields,
  }) async {
    try {
      final res = await _dio.post<dynamic>(
        '$_base/$_slug/session',
        data: {
          'visitorId': visitorId,
          if (name != null) 'name': name,
          if (email != null) 'email': email,
          if (page != null) 'page': page,
          // Prefer the explicit per-call locale, fall back to config.locale.
          if ((locale ?? config.locale) != null) 'locale': locale ?? config.locale,
          if (resumeOnly) 'resumeOnly': true,
          if (fields != null && fields.isNotEmpty) 'fields': fields,
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
  Future<String> postOfflineForm({
    String? name,
    String? email,
    required String message,
  }) async {
    try {
      final res = await _dio.post<dynamic>(
        '$_base/$_slug/offline-form',
        data: {
          if (name != null) 'name': name,
          if (email != null) 'email': email,
          'message': message,
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
          contentType: contentType != null
              ? DioMediaType.parse(contentType)
              : null,
        ),
      });
      final res = await _dio.post<dynamic>(
        '${config.normalizedApiBase}/api/uploads',
        data: form,
        options: Options(headers: _headers(token)),
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
        default:
          code = EasyLiveChatErrorCode.unknown;
      }
    }

    throw EasyLiveChatError(
      code,
      fieldId: fieldId,
      httpStatus: status,
      message: message,
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
