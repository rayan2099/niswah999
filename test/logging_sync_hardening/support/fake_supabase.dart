import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Logging/sync hardening test harness: a real [SupabaseClient] whose HTTP
/// transport is a [MockClient], so repository code paths (RPC calls,
/// PostgrestException parsing, transport errors) run unmodified against
/// scripted responses.
typedef RpcHandler = Future<http.Response> Function(
  String rpcName,
  Map<String, dynamic> body,
);

class FakeSupabase {
  FakeSupabase(this.onRpc);

  RpcHandler onRpc;
  final List<String> rpcCalls = [];

  /// Fallback for non-RPC REST calls (table selects/upserts): empty list.
  Future<http.Response> Function(http.Request request)? onTable;

  late final SupabaseClient client = SupabaseClient(
    'http://fake.supabase.local',
    'anon-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((request) async {
      final r = await _route(request);
      // postgrest reads response.request on the error path.
      return http.Response(
        r.body,
        r.statusCode,
        headers: r.headers,
        request: request,
      );
    }),
  );

  Future<http.Response> _route(http.Request request) async {
    final path = request.url.path;
    if (path.startsWith('/rest/v1/rpc/')) {
      final name = path.substring('/rest/v1/rpc/'.length);
      rpcCalls.add(name);
      final body = request.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(request.body) as Map<String, dynamic>;
      return onRpc(name, body);
    }
    final handler = onTable;
    if (handler != null) return handler(request);
    return http.Response(
      '[]',
      200,
      headers: {'content-type': 'application/json'},
    );
  }

  /// Gives the client a signed-in user without any network round trip.
  Future<void> signIn(String userId) =>
      client.auth.setInitialSession(fakeSessionJson(userId));
}

/// A stored-session JSON (unsigned JWT, far-future expiry) that
/// `GoTrueClient.setInitialSession` accepts — a signed-in user with no
/// network round trip.
String fakeSessionJson(String userId) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final exp =
      DateTime.now().add(const Duration(days: 365)).millisecondsSinceEpoch ~/
      1000;
  final token =
      '${encode({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${encode({'sub': userId, 'exp': exp, 'role': 'authenticated'})}.sig';
  return jsonEncode({
    'access_token': token,
    'token_type': 'bearer',
    'expires_in': 31536000,
    'refresh_token': 'refresh',
    'user': {
      'id': userId,
      'aud': 'authenticated',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'created_at': '2026-01-01T00:00:00Z',
    },
  });
}

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

/// A PostgREST-shaped error body, exactly what a plpgsql RAISE EXCEPTION
/// (SQLSTATE P0001) or a constraint violation surfaces as.
http.Response pgError(String code, String message, [int status = 400]) =>
    jsonResponse({
      'code': code,
      'message': message,
      'details': null,
      'hint': null,
    }, status);
