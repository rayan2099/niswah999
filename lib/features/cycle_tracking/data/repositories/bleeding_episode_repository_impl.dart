import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/app_error_reporter.dart';
import '../../../../core/network/supabase_client.dart';
import '../../domain/entities/bleeding_episode.dart';

/// Writes/reads the first-class `bleeding_episodes` / `cycle_baselines`
/// model (menstrual-data-integrity charter, Commit A schema). Deliberately
/// server-only for this initial slice — every caller today (onboarding) is
/// only ever reached already-authenticated (see OnboardingScreen's own
/// routing contract doc comment), so a real session always exists; a
/// local-first/offline path mirroring [CycleTrackingRepositoryImpl] is
/// follow-up work once a consumer needs to read this data offline.
class BleedingEpisodeRepositoryImpl {
  BleedingEpisodeRepositoryImpl({SupabaseClient? client})
    : _client = client ?? NiswahSupabase.clientOrNull;

  final SupabaseClient? _client;

  /// Best-effort: returns null (reported, not thrown) on any failure so a
  /// caller like onboarding completion is never blocked by a network
  /// hiccup — matching the existing best-effort pattern already used for
  /// `AuthRepositoryImpl.markOnboardingCompleted`.
  Future<BleedingEpisode?> createEpisode(BleedingEpisode episode) async {
    final client = _client;
    if (client == null) return null;

    try {
      final response = await client
          .from('bleeding_episodes')
          .insert(episode.toInsertJson())
          .select()
          .single();
      return BleedingEpisode.fromJson(response);
    } on PostgrestException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'BleedingEpisodeRepositoryImpl.createEpisode',
        feature: 'cycle_tracking',
        recordId: episode.userId,
      );
      return null;
    } on BleedingEpisodeParseException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'BleedingEpisodeRepositoryImpl.createEpisode',
        feature: 'cycle_tracking',
        recordId: episode.userId,
      );
      return null;
    }
  }

  Future<BleedingEpisode?> getActiveEpisode(String userId) async {
    final client = _client;
    if (client == null) return null;

    try {
      final response = await client
          .from('bleeding_episodes')
          .select()
          .eq('user_id', userId)
          .eq('status', 'active')
          .maybeSingle();
      if (response == null) return null;
      return BleedingEpisode.fromJson(response);
    } on PostgrestException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'BleedingEpisodeRepositoryImpl.getActiveEpisode',
        feature: 'cycle_tracking',
        recordId: userId,
      );
      return null;
    } on BleedingEpisodeParseException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'BleedingEpisodeRepositoryImpl.getActiveEpisode',
        feature: 'cycle_tracking',
        recordId: userId,
      );
      return null;
    }
  }
}

/// Writes/reads a user's `cycle_baselines` row (their stated usual
/// duration/cycle length — always USER_REPORTED_ESTIMATE, never observed
/// history). See [BleedingEpisodeRepositoryImpl]'s doc comment for why
/// this is server-only in this initial slice.
class CycleBaselineRepositoryImpl {
  CycleBaselineRepositoryImpl({SupabaseClient? client})
    : _client = client ?? NiswahSupabase.clientOrNull;

  final SupabaseClient? _client;

  Future<CycleBaseline?> saveBaseline(CycleBaseline baseline) async {
    final client = _client;
    if (client == null) return null;

    try {
      final response = await client
          .from('cycle_baselines')
          .upsert(baseline.toUpsertJson(), onConflict: 'user_id')
          .select()
          .single();
      return CycleBaseline.fromJson(response);
    } on PostgrestException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'CycleBaselineRepositoryImpl.saveBaseline',
        feature: 'cycle_tracking',
        recordId: baseline.userId,
      );
      return null;
    }
  }

  Future<CycleBaseline?> getBaseline(String userId) async {
    final client = _client;
    if (client == null) return null;

    try {
      final response = await client
          .from('cycle_baselines')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      if (response == null) return null;
      return CycleBaseline.fromJson(response);
    } on PostgrestException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'CycleBaselineRepositoryImpl.getBaseline',
        feature: 'cycle_tracking',
        recordId: userId,
      );
      return null;
    }
  }
}
