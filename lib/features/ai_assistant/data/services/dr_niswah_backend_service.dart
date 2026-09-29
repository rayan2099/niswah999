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
}

/// Calls the `dr-niswah-chat` Supabase Edge Function, which owns the
/// persona system prompt, the pregnancy-context lookup, the red-flag check,
/// and the Gemini call server-side — the function persists both the user
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

    final response = await client.functions.invoke(
      'dr-niswah-chat',
      body: {'threadId': threadId, 'content': content},
    );

    final data = response.data;
    if (data is! Map || response.status != 200) {
      final error = data is Map ? data['error']?.toString() : null;
      throw StateError(error ?? 'Doctor Niswah service failed (${response.status}).');
    }

    final citations = (data['citations'] as List<dynamic>? ?? [])
        .map((item) => FiqhCitation.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    return DrNiswahBackendResponse(
      reply: data['reply']?.toString() ?? '',
      urgent: data['urgent'] == true,
      citations: citations,
      knowledgeGrounded: data['knowledgeGrounded'] == true,
    );
  }
}
