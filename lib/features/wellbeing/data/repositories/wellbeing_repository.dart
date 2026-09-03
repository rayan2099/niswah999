import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/utils/app_clock.dart';
import '../../domain/entities/wellbeing_log.dart';

/// Persists daily mood/energy/sleep check-ins to `wellbeing_logs`.
///
/// Like [CycleTrackingRepositoryImpl]'s write path (not
/// [PregnancyProfileRepository]'s throw-hard contract): a signed-out or
/// demo-mode user is a normal, silent no-op rather than an error, since the
/// dashboard check-in this backs is available without an account. A real
/// network/Postgrest failure while signed in is still surfaced as a
/// [NetworkFailure] so the caller's existing error UI can show it.
class WellbeingRepository {
  WellbeingRepository({SupabaseClient? client})
    : _client = client ?? NiswahSupabase.clientOrNull;

  final SupabaseClient? _client;

  static const String _tableName = 'wellbeing_logs';

  String _dateOnly(DateTime date) => date.toIso8601String().substring(0, 10);

  /// Upserts today's check-in (one row per user per day, see the table's
  /// UNIQUE(user_id, log_date) constraint).
  Future<void> upsertToday({
    required int mood,
    required int energy,
    required int sleep,
    String? notes,
  }) async {
    final client = _client;
    if (client == null) return;

    final sessionUser = client.auth.currentUser;
    if (sessionUser == null) return;

    try {
      final now = AppClock.now();
      final payload = {
        'user_id': sessionUser.id,
        'log_date': _dateOnly(now),
        'mood': mood,
        'energy': energy,
        'sleep': sleep,
        // Always written, even when null — an edit that clears a
        // previous note must overwrite it, not leave stale text behind.
        'notes': notes,
        'updated_at': now.toIso8601String(),
      };
      await client
          .from(_tableName)
          .upsert(payload, onConflict: 'user_id,log_date');
    } on PostgrestException catch (error) {
      throw NetworkFailure(error.message);
    }
  }

  /// Returns the caller's check-ins in `[from, to]` (inclusive), newest
  /// first. Empty (never throws) when signed out or in demo mode, so
  /// report screens can treat "no account" the same as "no data yet".
  Future<List<WellbeingLog>> getLogs({DateTime? from, DateTime? to}) async {
    final client = _client;
    if (client == null) return const [];

    final sessionUser = client.auth.currentUser;
    if (sessionUser == null) return const [];

    try {
      var query = client
          .from(_tableName)
          .select()
          .eq('user_id', sessionUser.id);

      if (from != null) {
        query = query.filter('log_date', 'gte', _dateOnly(from));
      }
      if (to != null) {
        query = query.filter('log_date', 'lte', _dateOnly(to));
      }

      final response = await query.order('log_date', ascending: false);
      return (response as List<dynamic>)
          .map((item) => WellbeingLog.fromJson(item as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (error) {
      throw NetworkFailure(error.message);
    }
  }
}
