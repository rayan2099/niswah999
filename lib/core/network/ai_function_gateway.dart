import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The single place the app calls an AI Edge Function, plus the one rule for
/// reading its reply.
///
/// Why it exists: acceptance tests must be able to (a) see exactly what the
/// app SENDS (e.g. the madhhab/state context) and (b) feed the app a
/// controlled, possibly malformed reply — without a live model. Tests set
/// [testOverride]; production never does.
///
/// [requireText] exists because a malformed 200 (a Map with no/empty/non-
/// string text, a bare string, …) used to be shown as a blank bubble, saved as
/// an empty history row, or — for Doctor Niswah — replaced by the urgent
/// red-flag banner, which is alarming and wrong for a routine question.
class AiFunctionGateway {
  const AiFunctionGateway._();

  /// Test seam. Receives the function name and request body.
  @visibleForTesting
  static Future<FunctionResponse> Function(
    String name,
    Map<String, dynamic>? body,
  )?
  testOverride;

  static Future<FunctionResponse> invoke(
    SupabaseClient client,
    String name, {
    Map<String, dynamic>? body,
  }) {
    final override = testOverride;
    if (override != null) return override(name, body);
    return client.functions.invoke(name, body: body);
  }

  /// Returns [data]`[field]` when it is a non-empty string; otherwise throws a
  /// [StateError] that callers surface as an honest failure.
  static String requireText(Object? data, String field, String service) {
    final value = data is Map ? data[field] : null;
    if (value is String && value.trim().isNotEmpty) return value;
    throw StateError('$service returned an empty or malformed reply.');
  }
}
