import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/community/safety/community_safety_models.dart';
import 'package:niswah/features/community/safety/community_terms.dart';
import 'package:niswah/features/community/safety/community_write_error.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The app and supabase/migrations/20261030090000_community_ugc_safety.sql
/// must agree on these names, or reports/acceptances silently fail.
void main() {
  final migration = File(
    'supabase/migrations/20261030090000_community_ugc_safety.sql',
  ).readAsStringSync();

  List<String> quotedIn(String constraint) {
    final start = migration.indexOf(constraint);
    expect(start, isNonNegative, reason: '$constraint not found');
    final open = RegExp(r'IN\s*\(').firstMatch(migration.substring(start))!;
    final from = start + open.end;
    final list = migration.substring(from, migration.indexOf(')', from));
    return RegExp(r"'([a-z_]+)'").allMatches(list).map((m) => m[1]!).toList();
  }

  test('terms version matches community_terms_version()', () {
    final match = RegExp(
      r"community_terms_version\(\)\s+RETURNS text[\s\S]*?SELECT '([^']+)'::text",
    ).firstMatch(migration);
    expect(match, isNotNull);
    expect(CommunityTerms.version, match![1]);
  });

  test('report reasons match the database check constraint', () {
    expect(
      ReportReason.values.map((reason) => reason.dbValue).toSet(),
      quotedIn('community_reports_reason_check').toSet(),
    );
  });

  test('report target types match the database check constraint', () {
    expect(
      ReportTargetType.values.map((type) => type.name).toSet(),
      quotedIn('community_reports_target_type_check').toSet(),
    );
  });

  test('moderation actions match resolve_community_report()', () {
    expect(
      ModerationAction.values.map((action) => action.dbValue).toSet(),
      quotedIn('community_reports_resolution_action_check').toSet(),
    );
  });

  test('every NSW error code raised by the database is mapped', () {
    final raised = RegExp(r"ERRCODE = '(NSW\d\d)'")
        .allMatches(migration)
        .map((m) => m[1]!)
        .toSet();
    expect(raised, isNotEmpty);
    for (final code in raised) {
      expect(
        CommunityWriteError.from(PostgrestException(message: 'x', code: code)),
        isNotNull,
        reason: '$code has no app message',
      );
    }
    expect(
      CommunityWriteError.from(
        const PostgrestException(message: 'x', code: '42501'),
      ),
      isNull,
    );
  });
}
