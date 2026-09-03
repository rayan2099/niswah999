import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/network/supabase_client.dart';
import '../../domain/entities/pregnancy_profile.dart';

/// Persists [PregnancyProfile] to the `pregnancy_profile` table.
///
/// Unlike [PregnancyTrackingRepositoryImpl]'s local-first/best-effort-remote
/// pattern (fine for a daily journal note), a failed write here means the
/// "طبيبة" chat silently reverts to generic, unpersonalized advice — so
/// [upsert] surfaces failures to the caller instead of swallowing them.
/// Supabase is the only source of truth this repository writes to; it does
/// no local caching itself (screens that want a quick offline "week N"
/// display should keep using [PregnancyStatusController] alongside this).
class PregnancyProfileRepository {
  PregnancyProfileRepository({SupabaseClient? supabaseClient})
    : _supabaseClient = supabaseClient ?? NiswahSupabase.clientOrNull;

  final SupabaseClient? _supabaseClient;

  static const String _tableName = 'pregnancy_profile';

  Future<PregnancyProfile?> getForUser(String userId) async {
    final client = _supabaseClient;
    if (client == null) return null;

    final response = await client
        .from(_tableName)
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (response == null) return null;
    return PregnancyProfile.fromJson(response);
  }

  /// Creates or updates the caller's single `pregnancy_profile` row.
  /// Throws if Supabase isn't configured or the write fails — callers
  /// should surface this to the user rather than pretend it succeeded.
  Future<PregnancyProfile> upsert(PregnancyProfile profile) async {
    final client = _supabaseClient;
    if (client == null) {
      throw StateError('Supabase is not initialized.');
    }

    // `id` is DB-generated on first insert and unused by any reader — never
    // send it, so an empty/placeholder id from the caller can't be written
    // as an invalid UUID.
    final payload = profile.copyWith(updatedAt: DateTime.now()).toJson()
      ..remove('id');
    final response = await client
        .from(_tableName)
        .upsert(payload, onConflict: 'user_id')
        .select()
        .single();

    return PregnancyProfile.fromJson(response);
  }

  /// Convenience for the "Log birth & start Nifas" flow (dashboard and
  /// profile screens): flips `is_postpartum`/`postpartum_start_date` on the
  /// caller's existing row, or creates a bare postpartum-only row if none
  /// exists yet. Throws on failure — same contract as [upsert].
  Future<void> markPostpartumStarted(
    String userId, {
    DateTime? startDate,
  }) async {
    final existing = await getForUser(userId);
    await upsert(
      (existing ?? PregnancyProfile(id: '', userId: userId)).copyWith(
        isPostpartum: true,
        postpartumStartDate: startDate ?? DateTime.now(),
      ),
    );
  }
}
