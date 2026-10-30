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

  /// Rows of [table] owned by [userId]: rows where ANY of [matchAny] equals
  /// [userId]. An empty [matchAny] fetches every row the caller's RLS
  /// policy exposes — used only for tables whose read policy is already
  /// "her own" (see `private_messages` in [exportSections]).
  Future<List<Map<String, dynamic>>> fetchMany(
    String table,
    String userId, {
    List<String> matchAny = const ['user_id'],
  });
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
    String userId, {
    List<String> matchAny = const ['user_id'],
  }) async {
    final query = _client.from(table).select();
    final rows = switch (matchAny.length) {
      0 => await query,
      1 => await query.eq(matchAny.single, userId),
      _ => await query.or(
        matchAny.map((column) => '$column.eq.$userId').join(','),
      ),
    };
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }
}

/// The tables making up a personal-data export, and how each is fetched.
/// `flagged_conversations` is deliberately absent — a service-role-only
/// internal safety-audit log with no user-facing RLS read policy at all,
/// `UNAVAILABLE_BY_DESIGN`, not a section that can "fail."
///
/// Onboarding/server hardening (proposed, finding #10): every user-owned
/// table the app writes is now exported. Previously wellbeing logs (with
/// free-text notes), dream entries, Madhhab history, legacy cycle logs,
/// private conversations/messages and community comments/likes were
/// missing while the export still reported `export_complete: true`.
/// `matchAny` lists the owner columns (any match counts); empty means
/// "every row RLS lets her read", used only for `private_messages`, whose
/// read policy is participant-only (messages she sent and received).
typedef ExportSection = ({
  String key,
  String table,
  bool many,
  String idColumn,
  List<String> matchAny,
});

const List<ExportSection> exportSections = [
  // `users`' key column is `id` (it has no `user_id`): querying `user_id`
  // made this section fail for EVERY user, so the export always reported
  // "account could not be loaded" (found live, D-012).
  (key: 'account', table: 'users', many: false, idColumn: 'id', matchAny: []),
  (
    key: 'profile',
    table: 'profiles',
    many: false,
    idColumn: 'id',
    matchAny: [],
  ),
  (
    key: 'pregnancy_profile',
    table: 'pregnancy_profile',
    many: false,
    idColumn: 'user_id',
    matchAny: [],
  ),
  (
    key: 'cycle_entries',
    table: 'cycle_entries',
    many: true,
    idColumn: '',
    matchAny: ['user_id'],
  ),
  (
    key: 'cycle_logs',
    table: 'cycle_logs',
    many: true,
    idColumn: '',
    matchAny: ['user_id'],
  ),
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
    matchAny: ['user_id'],
  ),
  (
    key: 'bleeding_observations',
    table: 'bleeding_observations',
    many: true,
    idColumn: '',
    matchAny: ['user_id'],
  ),
  (
    key: 'cycle_baselines',
    table: 'cycle_baselines',
    many: true,
    idColumn: '',
    matchAny: ['user_id'],
  ),
  (
    key: 'madhhab_history',
    table: 'madhhab_history',
    many: true,
    idColumn: '',
    matchAny: ['user_id'],
  ),
  (
    key: 'wellbeing_logs',
    table: 'wellbeing_logs',
    many: true,
    idColumn: '',
    matchAny: ['user_id'],
  ),
  (
    key: 'prayer_log',
    table: 'prayer_log',
    many: true,
    idColumn: '',
    matchAny: ['user_id'],
  ),
  (
    key: 'dream_entries',
    table: 'dream_entries',
    many: true,
    idColumn: '',
    matchAny: ['user_id'],
  ),
  (
    key: 'community_posts',
    table: 'community_posts',
    many: true,
    idColumn: '',
    matchAny: ['user_id'],
  ),
  (
    key: 'community_comments',
    table: 'community_comments',
    many: true,
    idColumn: '',
    matchAny: ['user_id'],
  ),
  (
    key: 'community_likes',
    table: 'community_likes',
    many: true,
    idColumn: '',
    matchAny: ['user_id'],
  ),
  (
    key: 'chat_threads',
    table: 'chat_threads',
    many: true,
    idColumn: '',
    matchAny: ['user_id'],
  ),
  (
    key: 'chat_messages',
    table: 'chat_messages',
    many: true,
    idColumn: '',
    matchAny: ['user_id'],
  ),
  (
    key: 'private_conversations',
    table: 'private_conversations',
    many: true,
    idColumn: '',
    matchAny: ['participant_one', 'participant_two'],
  ),
  (
    key: 'private_messages',
    table: 'private_messages',
    many: true,
    idColumn: '',
    matchAny: [],
  ),
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
/// Thrown when the signed-in account stopped being [userId] while the
/// export ran (NJ-232). Nothing fetched so far is returned: a section read
/// with another account's session (for example `private_messages`, which
/// relies on RLS alone) could otherwise end up in this account's export,
/// also after switching back (A→B→A).
class ExportAccountChanged implements Exception {
  const ExportAccountChanged();
}

Future<DataExportResult> buildDataExport({
  required ExportSectionFetcher fetcher,
  required String userId,
  required void Function(Object error, StackTrace stack, String section)
  onSectionError,
  DateTime? now,
  bool Function()? isCurrentAccount,
}) async {
  void ensureCurrent() {
    if (isCurrentAccount != null && !isCurrentAccount()) {
      throw const ExportAccountChanged();
    }
  }

  final export = <String, dynamic>{
    'exported_at': (now ?? DateTime.now()).toIso8601String(),
  };
  final failedSections = <String>[];

  for (final section in exportSections) {
    ensureCurrent();
    try {
      if (section.many) {
        export[section.key] = await fetcher.fetchMany(
          section.table,
          userId,
          matchAny: section.matchAny,
        );
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
    ensureCurrent();
  }

  export['export_complete'] = failedSections.isEmpty;
  if (failedSections.isNotEmpty) {
    export['sections_unavailable'] = failedSections;
  }

  return DataExportResult(export: export, failedSections: failedSections);
}
