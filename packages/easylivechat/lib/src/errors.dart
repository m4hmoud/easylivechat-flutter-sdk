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
  // Feedback
  static const invalidRating = 'INVALID_RATING';
  static const alreadyRated = 'ALREADY_RATED';
  // Post-chat survey — the same one-shot rule, under its own server code.
  static const alreadySubmitted = 'ALREADY_SUBMITTED';
  // Uploads
  static const fileTooLarge = 'FILE_TOO_LARGE';
  static const unsupportedType = 'UNSUPPORTED_TYPE';
  static const contentTypeMismatch = 'CONTENT_TYPE_MISMATCH';
  // Client/transport
  static const network = 'NETWORK';
  static const noToken = 'NO_TOKEN';
  static const sendRejected = 'SEND_REJECTED';
  static const socket = 'SOCKET';
  static const unknown = 'UNKNOWN';
}

/// Typed error for every failure path. [code] is one of
/// [EasyLiveChatErrorCode]; [fieldId] is set for per-field pre-chat errors.
class EasyLiveChatError implements Exception {
  final String code;
  final String? fieldId;
  final int? httpStatus;
  final String? message;
  final Object? cause;

  const EasyLiveChatError(
    this.code, {
    this.fieldId,
    this.httpStatus,
    this.message,
    this.cause,
  });

  bool get isAuthError =>
      code == EasyLiveChatErrorCode.unauthenticated ||
      code == EasyLiveChatErrorCode.forbidden;

  @override
  String toString() =>
      'EasyLiveChatError($code${httpStatus != null ? ' http=$httpStatus' : ''}'
      '${fieldId != null ? ' field=$fieldId' : ''}'
      '${message != null ? ': $message' : ''})';
}
