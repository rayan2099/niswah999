import 'package:supabase_flutter/supabase_flutter.dart';

/// Abstraction over "fetch this user's rows from one table" — lets
/// [buildDataExport] be unit-tested with a fake, deterministic
/// implementation instead of a live/mocked [SupabaseClient] (Reliability
/// Evidence Closure wave, 2026-09-06).
abstract class ExportSectionFetcher {
  Future<Map<String, dynamic>?> fetchOne(
    String table,
    String userId, {
    String idColumn = 'user_id',
  });

  Future<List<Map<String, dynamic>>> fetchMany(String table, String userId);
}

class SupabaseExportSectionFetcher implements ExportSectionFetcher {
  SupabaseExportSectionFetcher(this._client);

  final SupabaseClient _client;

  @override
  Future<Map<String, dynamic>?> fetchOne(
    String table,
    String userId, {
    String idColumn = 'user_id',
  }) async {
    final row = await _client
        .from(table)
        .select()
        .eq(idColumn, userId)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchMany(
    String table,
    String userId,
  ) async {
    final rows = await _client.from(table).select().eq('user_id', userId);
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }
}

/// The tables making up a personal-data export, and how each is fetched.
/// `flagged_conversations` is deliberately absent — a service-role-only
/// internal safety-audit log with no user-facing RLS read policy at all,
/// `UNAVAILABLE_BY_DESIGN`, not a section that can "fail."
const List<({String key, String table, bool many, String idColumn})>
exportSections = [
  (key: 'account', table: 'users', many: false, idColumn: 'user_id'),
  (key: 'profile', table: 'profiles', many: false, idColumn: 'id'),
  (
    key: 'pregnancy_profile',
    table: 'pregnancy_profile',
    many: false,
    idColumn: 'user_id',
  ),
  (key: 'cycle_entries', table: 'cycle_entries', many: true, idColumn: ''),
  // Menstrual Data Integrity charter, PR #4 final wave — EXPORT/DELETION
  // audit: the canonical bleeding_episodes/bleeding_observations/
  // cycle_baselines tables (Commits A/D) were never added here. Deletion
  // was never a gap (both cascade-delete via the existing auth.users ->
  // public.users -> these tables ON DELETE CASCADE chain, verified
  // against the canonical baseline's own FK definitions), but export
  // was genuinely missing them until now.
  (
    key: 'bleeding_episodes',
    table: 'bleeding_episodes',
    many: true,
    idColumn: '',
  ),
  (
    key: 'bleeding_observations',
    table: 'bleeding_observations',
    many: true,
    idColumn: '',
  ),
  (key: 'cycle_baselines', table: 'cycle_baselines', many: true, idColumn: ''),
  (key: 'prayer_log', table: 'prayer_log', many: true, idColumn: ''),
  (key: 'community_posts', table: 'community_posts', many: true, idColumn: ''),
  (key: 'chat_threads', table: 'chat_threads', many: true, idColumn: ''),
  (key: 'chat_messages', table: 'chat_messages', many: true, idColumn: ''),
];

class DataExportResult {
  const DataExportResult({required this.export, required this.failedSections});

  final Map<String, dynamic> export;
  final List<String> failedSections;

  bool get isComplete => failedSections.isEmpty;
}

/// Fetches every section in [exportSections] independently — a failure on
/// any one section is isolated, reported via [onSectionError], and never
/// hides data another section could still provide (RR-001 data-export
/// resilience audit, 2026-09-06; this replaced a single shared try block
/// where one bad/unreachable table — `pregnancy_milestones`, before it
/// was retired — aborted the entire export for every user).
///
/// `export['export_complete']` is `true` only when every section
/// succeeded; a failed section's key is never silently omitted from the
/// output — it is listed under `export['sections_unavailable']` instead,
/// and simply absent from the export map itself (never a fabricated empty
/// value standing in for "couldn't fetch this").
Future<DataExportResult> buildDataExport({
  required ExportSectionFetcher fetcher,
  required String userId,
  required void Function(Object error, StackTrace stack, String section)
  onSectionError,
  DateTime? now,
}) async {
  final export = <String, dynamic>{
    'exported_at': (now ?? DateTime.now()).toIso8601String(),
  };
  final failedSections = <String>[];

  for (final section in exportSections) {
    try {
      if (section.many) {
        export[section.key] = await fetcher.fetchMany(section.table, userId);
      } else {
        export[section.key] = await fetcher.fetchOne(
          section.table,
          userId,
          idColumn: section.idColumn,
        );
      }
    } catch (error, stack) {
      failedSections.add(section.key);
      onSectionError(error, stack, section.key);
    }
  }

  export['export_complete'] = failedSections.isEmpty;
  if (failedSections.isNotEmpty) {
    export['sections_unavailable'] = failedSections;
  }

  return DataExportResult(export: export, failedSections: failedSections);
}
