import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/network/supabase_client.dart';
import '../../domain/entities/flagged_conversation.dart';

/// Reads the caller's own rows from `flagged_conversations` — the table
/// the dr-niswah-chat edge function writes to on a red-flag keyword match.
/// Read-only self-access (see the migration adding this SELECT policy);
/// there is intentionally no write path here — only the edge function's
/// service role inserts.
///
/// Mirrors [WellbeingRepository]'s shape: a signed-out user is a normal,
/// silent empty result, not an error.
class FlaggedConversationsRepository {
  FlaggedConversationsRepository({SupabaseClient? client})
    : _client = client ?? NiswahSupabase.clientOrNull;

  final SupabaseClient? _client;

  static const String _tableName = 'flagged_conversations';

  Future<List<FlaggedConversation>> getRecent({required DateTime since}) async {
    final client = _client;
    if (client == null) return const [];

    final sessionUser = client.auth.currentUser;
    if (sessionUser == null) return const [];

    try {
      final response = await client
          .from(_tableName)
          .select()
          .eq('user_id', sessionUser.id)
          .gte('created_at', since.toIso8601String())
          .order('created_at', ascending: false);

      return (response as List<dynamic>)
          .map(
            (item) =>
                FlaggedConversation.fromJson(item as Map<String, dynamic>),
          )
          .toList();
    } on PostgrestException catch (error) {
      throw NetworkFailure(error.message);
    }
  }
}
