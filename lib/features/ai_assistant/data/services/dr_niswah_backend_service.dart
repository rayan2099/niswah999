import '../../../../core/network/ai_function_gateway.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../ai_advisor/ai_advisor_service.dart';

class DrNiswahBackendResponse {
  const DrNiswahBackendResponse({
    required this.reply,
    required this.urgent,
    this.citations = const [],
    this.knowledgeGrounded = false,
  });

  final String reply;
  final bool urgent;

  /// Pre-Merge Integration Validation, Phase 5 (Finding 7): the backend has
  /// always sent these two fields; this model silently dropped both before
  /// this fix. Reuses [FiqhCitation] since both edge functions' citation
  /// payload shape is identical (kb_retrieval.ts's `citationPayload()`).
  final List<FiqhCitation> citations;
  final bool knowledgeGrounded;

  /// Main-vs-PR#4 merge resolution (2026-10-08): extracted out of `send()`
  /// so this combined validation (strict reply checking, carried over from
  /// PR #4) + extraction (citations/knowledgeGrounded, carried over from
  /// main's Knowledge-Base grounding work) is directly unit-testable with a
  /// plain `Map` — `send()` itself can't be driven in a plain unit test
  /// (`DrNiswahBackendService` is a hardcoded singleton with no DI seam; see
  /// `test/dr_niswah_red_flag_dual_state_test.dart`'s own doc comment).
  ///
  /// A reply must be real text. An empty/missing/non-string reply is a
  /// failure — EXCEPT when the server flagged the message urgent, where the
  /// caller shows the safety banner instead of model text. This check
  /// applies regardless of citations/knowledgeGrounded — a grounded reply
  /// still has to actually contain text, and an ungrounded one is never
  /// allowed to fabricate grounding to work around this validation.
  factory DrNiswahBackendResponse.fromBackendJson(Map<dynamic, dynamic> data) {
    final urgent = data['urgent'] == true;
    final reply = data['reply'];
    final citations = (data['citations'] as List<dynamic>? ?? [])
        .map((item) => FiqhCitation.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    final knowledgeGrounded = data['knowledgeGrounded'] == true;
    if (reply is! String || reply.trim().isEmpty) {
      if (!urgent) {
        throw StateError('Doctor Niswah returned an empty or malformed reply.');
      }
      return DrNiswahBackendResponse(
        reply: '',
        urgent: true,
        citations: citations,
        knowledgeGrounded: knowledgeGrounded,
      );
    }
    return DrNiswahBackendResponse(
      reply: reply,
      urgent: urgent,
      citations: citations,
      knowledgeGrounded: knowledgeGrounded,
    );
  }
}

/// Calls the `dr-niswah-chat` Supabase Edge Function, which owns the
/// persona system prompt, the pregnancy-context lookup, the red-flag check,
/// and the model call server-side (OpenAI's Responses API since the
/// 2026-09-30 provider migration) — the function persists both the user
/// and assistant chat_messages rows itself.
class DrNiswahBackendService {
  const DrNiswahBackendService._();

  static const instance = DrNiswahBackendService._();

  bool get isAvailable => NiswahSupabase.clientOrNull != null;

  Future<DrNiswahBackendResponse> send({
    required String threadId,
    required String content,
  }) async {
    final client = NiswahSupabase.clientOrNull;
    if (client == null) {
      throw StateError('Supabase is not initialized.');
    }

    final response = await AiFunctionGateway.invoke(
      client,
      'dr-niswah-chat',
      body: {'threadId': threadId, 'content': content},
    );

    final data = response.data;
    if (data is! Map || response.status != 200) {
      final error = data is Map ? data['error']?.toString() : null;
      throw StateError(
        error ?? 'Doctor Niswah service failed (${response.status}).',
      );
    }

    return DrNiswahBackendResponse.fromBackendJson(data);
  }
}
