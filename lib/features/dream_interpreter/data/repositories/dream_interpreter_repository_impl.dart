import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/network/supabase_client.dart';
import '../../domain/entities/dream_entry.dart';
import '../../domain/repositories/dream_interpreter_repository.dart';

class DreamInterpreterRepositoryImpl implements DreamInterpreterRepository {
  DreamInterpreterRepositoryImpl({SupabaseClient? client})
    : _client = client ?? NiswahSupabase.clientOrNull;

  final SupabaseClient? _client;

  static const String _tableName = 'dream_entries';

  @override
  Future<List<DreamEntry>> getEntries({required String userId}) async {
    final client = _client;
    if (client == null) {
      return const [];
    }

    try {
      final response = await client
          .from(_tableName)
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return (response as List<dynamic>)
          .map((item) => DreamEntry.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } on PostgrestException {
      return const [];
    }
  }

  @override
  Future<DreamEntry> saveEntry({
    required String userId,
    required DreamEntry entry,
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError('Supabase is not initialized.');
    }

    final payload = {...entry.toJson(), 'user_id': userId};

    final response = await client
        .from(_tableName)
        .upsert(payload)
        .select()
        .single();
    return DreamEntry.fromJson(Map<String, dynamic>.from(response));
  }

  @override
  Future<void> deleteEntry({
    required String userId,
    required String entryId,
  }) async {
    final client = _client;
    if (client == null) {
      return;
    }

    await client
        .from(_tableName)
        .delete()
        .eq('id', entryId)
        .eq('user_id', userId);
  }
}
