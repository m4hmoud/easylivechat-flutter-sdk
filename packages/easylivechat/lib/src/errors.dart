/// Canonical error codes surfaced by the SDK. The first group are server
/// `{ error }` codes from the widget protocol; the rest are client/transport.
abstract final class EasyLiveChatErrorCode {
  // Server (HTTP `{ error, fieldId? }`)
  static const notFound = 'NOT_FOUND';
  static const originNotAllowed = 'ORIGIN_NOT_ALLOWED';
  static const unauthenticated = 'UNAUTHENTICATED';
  static const forbidden = 'FORBIDDEN';
  // Pre-chat validation (carry `fieldId`)
  static const expectedObject = 'EXPECTED_OBJECT';
  static const required = 'REQUIRED';
  static const invalidEmail = 'INVALID_EMAIL';
  static const invalidNumber = 'INVALID_NUMBER';
  static const invalidOption = 'INVALID_OPTION';

  /// A required consent checkbox was left unticked. `fieldId` names it.
  static const consentRequired = 'CONSENT_REQUIRED';
  // Feedback
  static const invalidRating = 'INVALID_RATING';
  static const alreadyRated = 'ALREADY_RATED';
  // Post-chat survey — the same one-shot rule, under its own server code.
  static const alreadySubmitted = 'ALREADY_SUBMITTED';
  // Uploads
  static const fileTooLarge = 'FILE_TOO_LARGE';
  static const unsupportedType = 'UNSUPPORTED_TYPE';
  static const contentTypeMismatch = 'CONTENT_TYPE_MISMATCH';
  // Identity verification — see [EasyLiveChatError.isIdentityNotVerified].
  static const identityNotVerified = 'IDENTITY_NOT_VERIFIED';
  // Help articles (and any other throttled public route).
  static const rateLimited = 'RATE_LIMITED';
  static const invalidPayload = 'INVALID_PAYLOAD';
  // Client/transport
  static const network = 'NETWORK';
  static const noToken = 'NO_TOKEN';
  static const sendRejected = 'SEND_REJECTED';
  static const socket = 'SOCKET';
  static const unknown = 'UNKNOWN';
}

/// Why the server refused a claimed identity — the `reason` of an
/// [EasyLiveChatErrorCode.identityNotVerified] error.
abstract final class IdentityNotVerifiedReason {
  /// The workspace requires verification but never generated an identity
  /// secret. Nothing the app sends can pass: generate the secret in the
  /// dashboard (Settings → AI assistant → "Know who is signed in").
  static const noSecret = 'NO_SECRET';

  /// A `userId` was sent without a `userHash`. Pass the hash your backend
  /// computed to `identify(userId: …, userHash: …)`.
  static const noHash = 'NO_HASH';

  /// The `userHash` does not match. It must be the lowercase hex
  /// `HMAC_SHA256(identitySecret, userId)` of exactly the `userId` sent, signed
  /// with the CURRENT secret (a regenerated secret invalidates old hashes).
  static const badHash = 'BAD_HASH';
}

/// Typed error for every failure path. [code] is one of
/// [EasyLiveChatErrorCode]; [fieldId] is set for per-field pre-chat errors.
class EasyLiveChatError implements Exception {
  final String code;
  final String? fieldId;
  final int? httpStatus;
  final String? message;
  final Object? cause;

  /// The server's `reason`, when it gives one. Set on
  /// [EasyLiveChatErrorCode.identityNotVerified] — one of
  /// [IdentityNotVerifiedReason].
  final String? reason;

  const EasyLiveChatError(
    this.code, {
    this.fieldId,
    this.httpStatus,
    this.message,
    this.cause,
    this.reason,
  });

  bool get isAuthError =>
      code == EasyLiveChatErrorCode.unauthenticated ||
      code == EasyLiveChatErrorCode.forbidden;

  /// The workspace ENFORCES identity verification and refused the `userId`
  /// passed to `EasyLiveChat.identify` (HTTP 403).
  ///
  /// This is an integration error, not something the visitor can fix: the
  /// session was not opened, so the chat cannot start as that user. [reason]
  /// says what to fix ([IdentityNotVerifiedReason]):
  ///  • `NO_SECRET` — generate the identity secret in the dashboard;
  ///  • `NO_HASH` — pass `userHash` alongside `userId`;
  ///  • `BAD_HASH` — the hash must be the hex `HMAC_SHA256(secret, userId)`
  ///    computed by YOUR BACKEND for exactly that `userId`, with the current
  ///    secret. Never compute it in the app — the secret must not ship in it.
  ///
  /// Anonymous visitors (no `userId`) are never refused, so a visitor who is
  /// not signed in can always chat.
  bool get isIdentityNotVerified =>
      code == EasyLiveChatErrorCode.identityNotVerified;

  @override
  String toString() =>
      'EasyLiveChatError($code${httpStatus != null ? ' http=$httpStatus' : ''}'
      '${fieldId != null ? ' field=$fieldId' : ''}'
      '${reason != null ? ' reason=$reason' : ''}'
      '${message != null ? ': $message' : ''})';
}
