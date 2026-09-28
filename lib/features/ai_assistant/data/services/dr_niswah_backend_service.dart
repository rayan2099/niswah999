import '../../../../core/network/ai_function_gateway.dart';
import '../../../../core/network/supabase_client.dart';

class DrNiswahBackendResponse {
  const DrNiswahBackendResponse({required this.reply, required this.urgent});

  final String reply;
  final bool urgent;
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

    final response = await AiFunctionGateway.invoke(
      client,
      'dr-niswah-chat',
      body: {'threadId': threadId, 'content': content},
    );

    final data = response.data;
    if (data is! Map || response.status != 200) {
      final error = data is Map ? data['error']?.toString() : null;
      throw StateError(error ?? 'Doctor Niswah service failed (${response.status}).');
    }

    final urgent = data['urgent'] == true;
    final reply = data['reply'];
    // A reply must be real text. An empty/missing/non-string reply is a
    // failure — EXCEPT when the server flagged the message urgent, where the
    // caller shows the safety banner instead of model text.
    if (reply is! String || reply.trim().isEmpty) {
      if (!urgent) {
        throw StateError('Doctor Niswah returned an empty or malformed reply.');
      }
      return const DrNiswahBackendResponse(reply: '', urgent: true);
    }
    return DrNiswahBackendResponse(reply: reply, urgent: urgent);
  }
}
