abstract class Failure implements Exception {
  const Failure(
    this.message, {
    this.cause,
    this.stackTrace,
    this.retryable = false,
    this.context,
  });

  /// User-safe message — never contains raw exception text, internal
  /// identifiers, or secrets. Safe to show directly in the UI.
  final String message;

  /// The original error, preserved for diagnostics/observability. Never
  /// shown to the user directly — read this from `AppErrorReporter`
  /// call sites, not from UI code.
  final Object? cause;
  final StackTrace? stackTrace;

  /// Whether retrying the same operation again might succeed (a transient
  /// network condition) as opposed to being certain to fail again
  /// identically (a validation/auth/policy rejection). Retry logic must
  /// consult this rather than retrying blindly.
  final bool retryable;

  /// Which operation/repository this came from (e.g.
  /// `'CycleTrackingRepositoryImpl.saveCycleLog'`) — for observability
  /// only, never shown to the user.
  final String? context;

  @override
  String toString() => message;
}

class AuthFailure extends Failure {
  const AuthFailure(
    super.message, {
    super.cause,
    super.stackTrace,
    super.retryable,
    super.context,
  });
}

class NetworkFailure extends Failure {
  const NetworkFailure(
    super.message, {
    super.cause,
    super.stackTrace,
    super.retryable = true,
    super.context,
  });
}

class ValidationFailure extends Failure {
  const ValidationFailure(
    super.message, {
    super.cause,
    super.stackTrace,
    super.retryable,
    super.context,
  });
}

/// Postgres error codes known to indicate a transient server-side condition
/// (worth retrying) rather than a request the server will reject identically
/// every time. Deliberately conservative — everything else defaults to
/// non-retryable, matching "do not retry non-retryable validation/auth
/// errors blindly".
const _retryablePostgresCodes = {
  '53300', // too_many_connections
  '57014', // query_canceled
  '40001', // serialization_failure
  '40P01', // deadlock_detected
  '08000', '08003', '08006', // connection_exception family
};

/// Shared classifier used by repositories to turn a caught Supabase/network
/// error into a [Failure] with a user-safe message and a retryability
/// verdict, instead of each repository inventing its own ad hoc mapping
/// (AB-010) or losing the original exception/stack (OB-007).
///
/// Deliberately conservative about retryability: a genuine Dart-level
/// network exception (the request never reached the server) is retryable;
/// a `PostgrestException` (the server responded) is only retryable for a
/// short, explicit allow-list of known-transient Postgres error codes —
/// everything else (RLS denial, constraint violation, bad input) is not,
/// since retrying it will fail identically every time.
Failure mapRepositoryError(
  Object error,
  StackTrace stackTrace, {
  required String context,
  String? userMessage,
}) {
  final typeName = error.runtimeType.toString();
  final looksLikePostgrest = typeName == 'PostgrestException';

  if (looksLikePostgrest) {
    final code = _tryGetField(error, 'code')?.toString();
    final retryable = code != null && _retryablePostgresCodes.contains(code);
    return NetworkFailure(
      userMessage ?? 'Something went wrong. Please try again.',
      cause: error,
      stackTrace: stackTrace,
      retryable: retryable,
      context: context,
    );
  }

  // Checked before the general "auth"-named-type branch below: despite its
  // name containing "Auth", this one specifically represents a *network*
  // failure during an auth-related fetch (e.g. a token refresh that
  // couldn't reach the server) — retrying is exactly the right response,
  // unlike an actual credential/session rejection.
  if (typeName == 'AuthRetryableFetchException') {
    return NetworkFailure(
      userMessage ?? 'Could not connect. Please check your connection.',
      cause: error,
      stackTrace: stackTrace,
      retryable: true,
      context: context,
    );
  }

  final typeLower = typeName.toLowerCase();
  final looksLikeAuth =
      typeLower.contains('auth') || typeLower.contains('unauthorized');
  if (looksLikeAuth) {
    return AuthFailure(
      userMessage ?? 'Please sign in again to continue.',
      cause: error,
      stackTrace: stackTrace,
      retryable: false,
      context: context,
    );
  }

  // Anything else (SocketException, TimeoutException, http.ClientException,
  // generic connection errors) means the request likely never reached the
  // server at all — a transient, retryable condition.
  return NetworkFailure(
    userMessage ?? 'Could not connect. Please check your connection.',
    cause: error,
    stackTrace: stackTrace,
    retryable: true,
    context: context,
  );
}

Object? _tryGetField(Object error, String field) {
  try {
    // PostgrestException exposes `code` as a public getter; this indirection
    // just keeps the classifier from having a hard import dependency on the
    // supabase package for a single field read.
    final dynamic dyn = error;
    return switch (field) {
      'code' => dyn.code,
      _ => null,
    };
  } catch (_) {
    return null;
  }
}
