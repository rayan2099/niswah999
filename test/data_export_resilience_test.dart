import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/legal/domain/data_export_builder.dart';

/// A deterministic, per-table fake — configure which tables should throw
/// and with what, then assert exactly what `buildDataExport` produces.
/// Exercises the per-section failure-isolation redesign (PC-006/RR-001
/// data-export resilience audit) without a live/mocked SupabaseClient
/// (Reliability Evidence Closure wave, 2026-09-06).
class _FakeExportSectionFetcher implements ExportSectionFetcher {
  final Map<String, Object> failingTables = {};
  final Set<String> calledTables = {};

  @override
  Future<Map<String, dynamic>?> fetchOne(
    String table,
    String userId, {
    String idColumn = 'user_id',
  }) async {
    calledTables.add(table);
    if (failingTables.containsKey(table)) {
      throw failingTables[table]!;
    }
    return {'user_id': userId, '_table': table};
  }

  @override
  Future<List<Map<String, dynamic>>> fetchMany(
    String table,
    String userId,
  ) async {
    calledTables.add(table);
    if (failingTables.containsKey(table)) {
      throw failingTables[table]!;
    }
    return [
      {'user_id': userId, '_table': table},
    ];
  }
}

void main() {
  const userId = 'user-1';

  group('buildDataExport (PC-006 / RR-001 resilience redesign)', () {
    test('A. all sections succeed — export_complete is true, nothing '
        'listed as unavailable', () async {
      final fetcher = _FakeExportSectionFetcher();
      final reported = <String>[];

      final result = await buildDataExport(
        fetcher: fetcher,
        userId: userId,
        onSectionError: (error, stack, section) => reported.add(section),
      );

      expect(result.isComplete, isTrue);
      expect(result.failedSections, isEmpty);
      expect(reported, isEmpty);
      expect(result.export['export_complete'], isTrue);
      expect(result.export.containsKey('sections_unavailable'), isFalse);
      // Every section that exists in exportSections was actually fetched.
      for (final section in exportSections) {
        expect(result.export.containsKey(section.key), isTrue);
      }
    });

    test('B. one section fails — export is still produced, that one '
        'section is explicitly listed unavailable, others are intact', () async {
      final fetcher = _FakeExportSectionFetcher()
        ..failingTables['community_posts'] = Exception('table unreachable');
      final reported = <String>[];

      final result = await buildDataExport(
        fetcher: fetcher,
        userId: userId,
        onSectionError: (error, stack, section) => reported.add(section),
      );

      expect(result.isComplete, isFalse);
      expect(result.failedSections, ['community_posts']);
      expect(reported, ['community_posts']);
      expect(result.export['export_complete'], isFalse);
      expect(result.export['sections_unavailable'], ['community_posts']);
      // The failed section's key is absent, not a fabricated empty value.
      expect(result.export.containsKey('community_posts'), isFalse);
      // Every other section still succeeded and is present.
      expect(result.export['account'], isNotNull);
      expect(result.export['cycle_entries'], isNotEmpty);
      expect(result.export['chat_messages'], isNotEmpty);
    });

    test('C. multiple sections fail — all are listed, all others remain '
        'intact', () async {
      final fetcher = _FakeExportSectionFetcher()
        ..failingTables['prayer_log'] = Exception('timeout')
        ..failingTables['chat_threads'] = Exception('RLS denied')
        ..failingTables['pregnancy_profile'] = Exception('502');
      final reported = <String>[];

      final result = await buildDataExport(
        fetcher: fetcher,
        userId: userId,
        onSectionError: (error, stack, section) => reported.add(section),
      );

      expect(result.isComplete, isFalse);
      expect(
        result.failedSections.toSet(),
        {'prayer_log', 'chat_threads', 'pregnancy_profile'},
      );
      expect(reported.toSet(), result.failedSections.toSet());
      expect(
        (result.export['sections_unavailable'] as List).toSet(),
        result.failedSections.toSet(),
      );
      // Untouched sections remain present and correct.
      expect(result.export['account'], isNotNull);
      expect(result.export['profile'], isNotNull);
      expect(result.export['cycle_entries'], isNotEmpty);
      expect(result.export['community_posts'], isNotEmpty);
      expect(result.export['chat_messages'], isNotEmpty);
    });

    test('D. the core identity section ("account") fails — this does '
        'NOT abort the rest of the export (no all-or-nothing behavior)', () async {
      final fetcher = _FakeExportSectionFetcher()
        ..failingTables['users'] = Exception('users table unreachable');
      final reported = <String>[];

      final result = await buildDataExport(
        fetcher: fetcher,
        userId: userId,
        onSectionError: (error, stack, section) => reported.add(section),
      );

      expect(
        result.isComplete,
        isFalse,
        reason: 'a failed core section still marks the export incomplete',
      );
      expect(result.failedSections, ['account']);
      // Every other section — the entire point of this redesign — is
      // still fully present, proving one bad table can no longer cascade
      // into a total export failure (the exact live regression this
      // architecture replaced).
      expect(result.export['profile'], isNotNull);
      expect(result.export['pregnancy_profile'], isNotNull);
      expect(result.export['cycle_entries'], isNotEmpty);
      expect(result.export['prayer_log'], isNotEmpty);
      expect(result.export['community_posts'], isNotEmpty);
      expect(result.export['chat_threads'], isNotEmpty);
      expect(result.export['chat_messages'], isNotEmpty);
    });

    test('E. a backend-timeout-shaped failure is isolated the same as '
        'any other error', () async {
      final fetcher = _FakeExportSectionFetcher()
        ..failingTables['cycle_entries'] = Exception('Connection timed out');

      final result = await buildDataExport(
        fetcher: fetcher,
        userId: userId,
        onSectionError: (_, _, _) {},
      );

      expect(result.failedSections, ['cycle_entries']);
      expect(result.export.containsKey('cycle_entries'), isFalse);
    });

    test('F. an unauthorized-read-shaped failure (RLS denial) is '
        'isolated the same as any other error — never surfaces another '
        "user's data, never crashes the whole export", () async {
      final fetcher = _FakeExportSectionFetcher()
        ..failingTables['chat_messages'] = Exception('permission denied for table');

      final result = await buildDataExport(
        fetcher: fetcher,
        userId: userId,
        onSectionError: (_, _, _) {},
      );

      expect(result.failedSections, ['chat_messages']);
      expect(result.export.containsKey('chat_messages'), isFalse);
      // No other section leaked cross-user content — the fake only ever
      // returns rows tagged with the requested userId.
      for (final key in [
        'account',
        'profile',
        'cycle_entries',
        'prayer_log',
        'community_posts',
      ]) {
        final value = result.export[key];
        if (value is Map) expect(value['user_id'], userId);
        if (value is List) {
          for (final row in value) {
            expect((row as Map)['user_id'], userId);
          }
        }
      }
    });

    test('G. an empty dataset (no rows in a many-section) is not treated '
        'as a failure — it is a real, successful, empty result', () async {
      final fetcher = _EmptyResultFetcher();

      final result = await buildDataExport(
        fetcher: fetcher,
        userId: userId,
        onSectionError: (_, _, _) {
          fail('an empty dataset must not be reported as an error');
        },
      );

      expect(result.isComplete, isTrue);
      expect(result.export['cycle_entries'], isEmpty);
      expect(result.export['account'], isNull);
    });

    test(
      'the resulting export is always valid JSON, even with multiple '
      'section failures',
      () async {
        final fetcher = _FakeExportSectionFetcher()
          ..failingTables['prayer_log'] = Exception('boom')
          ..failingTables['users'] = Exception('boom2');

        final result = await buildDataExport(
          fetcher: fetcher,
          userId: userId,
          onSectionError: (_, _, _) {},
        );

        expect(
          () => jsonEncode(result.export),
          returnsNormally,
        );
      },
    );

    test(
      'section keys/order are stable across runs for user comprehension',
      () async {
        final fetcher = _FakeExportSectionFetcher();

        final first = await buildDataExport(
          fetcher: fetcher,
          userId: userId,
          onSectionError: (_, _, _) {},
        );
        final second = await buildDataExport(
          fetcher: fetcher,
          userId: userId,
          onSectionError: (_, _, _) {},
        );

        expect(first.export.keys, second.export.keys);
      },
    );
  });
}

class _EmptyResultFetcher implements ExportSectionFetcher {
  @override
  Future<Map<String, dynamic>?> fetchOne(
    String table,
    String userId, {
    String idColumn = 'user_id',
  }) async => null;

  @override
  Future<List<Map<String, dynamic>>> fetchMany(
    String table,
    String userId,
  ) async => const [];
}
