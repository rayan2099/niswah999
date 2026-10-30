import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'ai_failure.dart';

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
    Map<String, String>? headers,
  }) {
    final override = testOverride;
    if (override != null) return override(name, body);
    return client.functions.invoke(name, body: body, headers: headers);
  }

  /// Longest the app waits for a chat reply. The functions give the model
  /// 25-30 seconds plus retrieval; past this the person gets a timeout
  /// message and can retry, instead of a spinner that never ends.
  static const chatTimeout = Duration(seconds: 50);

  /// Calls an AI chat function and returns its JSON body, or throws an
  /// [AiFailure] whose category says what went wrong (testing feedback
  /// 2026-10-30). Every attempt carries an `x-niswah-request-id` that the
  /// function logs with its failure category, so a reported failure can be
  /// found without anyone reading the conversation.
  ///
  /// An expired session (401) is refreshed once and the call repeated; the
  /// function itself never sees the message twice because the first attempt
  /// was rejected before it ran.
  static Future<Map<String, dynamic>> invokeChat(
    SupabaseClient client,
    String name, {
    required Map<String, dynamic> body,
    String? requestId,
  }) async {
    final id = requestId ?? const Uuid().v4();
    try {
      return await _invokeChatOnce(client, name, body, id);
    } on AiFailure catch (failure) {
      if (failure.category != AiFailureCategory.authExpired ||
          testOverride != null) {
        rethrow;
      }
      try {
        await client.auth.refreshSession();
      } catch (_) {
        throw failure;
      }
      return _invokeChatOnce(client, name, body, id);
    }
  }

  static Future<Map<String, dynamic>> _invokeChatOnce(
    SupabaseClient client,
    String name,
    Map<String, dynamic> body,
    String requestId,
  ) async {
    final FunctionResponse response;
    try {
      response = await invoke(
        client,
        name,
        body: body,
        headers: {'x-niswah-request-id': requestId},
      ).timeout(chatTimeout);
    } on TimeoutException {
      throw AiFailure(AiFailureCategory.timeout, correlationId: requestId);
    } on FunctionsFetchException {
      throw AiFailure(AiFailureCategory.offline, correlationId: requestId);
    } on FunctionException catch (error) {
      throw failureFrom(error.status, error.details, requestId);
    } on SocketException {
      throw AiFailure(AiFailureCategory.offline, correlationId: requestId);
    } on http.ClientException {
      throw AiFailure(AiFailureCategory.offline, correlationId: requestId);
    }
    final data = response.data;
    if (response.status != 200) {
      throw failureFrom(response.status, data, requestId);
    }
    if (data is! Map) {
      throw AiFailure(
        AiFailureCategory.malformedResponse,
        correlationId: requestId,
        status: response.status,
      );
    }
    return Map<String, dynamic>.from(data);
  }

  /// Reads the category the function sent, falling back to the status for
  /// an older deployment or a gateway rejection.
  @visibleForTesting
  static AiFailure failureFrom(int status, Object? details, String requestId) {
    final map = details is Map ? details : const {};
    final retryAfter = (map['retryAfterSeconds'] as num?)?.toInt();
    return AiFailure(
      AiFailureCategory.fromServer(map['category']?.toString(), status),
      correlationId: map['correlationId']?.toString() ?? requestId,
      retryAfter: retryAfter == null ? null : Duration(seconds: retryAfter),
      status: status,
    );
  }

  /// Returns [data]`[field]` when it is a non-empty string; otherwise throws a
  /// [StateError] that callers surface as an honest failure.
  static String requireText(Object? data, String field, String service) {
    final value = data is Map ? data[field] : null;
    if (value is String && value.trim().isNotEmpty) return value;
    throw AiFailure(
      AiFailureCategory.malformedResponse,
      correlationId: data is Map ? data['correlationId']?.toString() : null,
    );
  }
}
