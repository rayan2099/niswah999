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

    final response = await client.functions.invoke(
      'dr-niswah-chat',
      body: {'threadId': threadId, 'content': content},
    );

    final data = response.data;
    if (data is! Map || response.status != 200) {
      final error = data is Map ? data['error']?.toString() : null;
      throw StateError(error ?? 'Doctor Niswah service failed (${response.status}).');
    }

    return DrNiswahBackendResponse(
      reply: data['reply']?.toString() ?? '',
      urgent: data['urgent'] == true,
    );
  }
}
