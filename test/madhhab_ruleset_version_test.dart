// Adversarial review, 2026-10-07: an earlier draft recorded
// `ruleset_version` in `madhhab_history` purely via the migration's SQL
// `DEFAULT` clause — nothing in application code ever wrote it
// explicitly, so it was cosmetic: a future change to the actual Fiqh
// duration values would have silently kept writing the old, now-wrong
// version string forever, with no way to distinguish "the user changed
// Madhhab" from "the same Madhhab now means something different."
//
// `MadhhabController._recordHistory` has no network client in this test
// environment (`NiswahSupabase.clientOrNull` is null without a real
// Supabase session), so its `.insert(...)` call is never reached here —
// the same structural limitation this repo's own
// `app_localization_delegates_test.dart` works around by asserting on
// the actual source text rather than a live call. That is the pattern
// followed below: verify the constant itself, then verify the insert
// call is actually built from it, not a re-typed literal.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';

void main() {
  test('MadhhabRuleEvaluator.rulesetVersion is a real, defined constant', () {
    expect(MadhhabRuleEvaluator.rulesetVersion, isNotEmpty);
    expect(MadhhabRuleEvaluator.rulesetVersion, 'v1-2026-09-09');
  });

  test('MadhhabController writes MadhhabRuleEvaluator.rulesetVersion into '
      'madhhab_history explicitly — never a hardcoded literal, never left '
      'to rely on the SQL column default', () {
    final source = File('lib/core/preferences/madhhab_controller.dart')
        .readAsStringSync();

    final recordHistoryStart = source.indexOf('_recordHistory(');
    expect(
      recordHistoryStart,
      greaterThan(-1),
      reason: '_recordHistory must still exist',
    );
    final insertStart = source.indexOf(
      "from('madhhab_history').insert(",
      recordHistoryStart,
    );
    expect(
      insertStart,
      greaterThan(-1),
      reason: '_recordHistory must still insert into madhhab_history',
    );
    final insertEnd = source.indexOf('});', insertStart);
    final insertCall = source.substring(insertStart, insertEnd);

    expect(
      insertCall,
      contains("'ruleset_version': MadhhabRuleEvaluator.rulesetVersion"),
      reason:
          'the insert payload must read the version from the evaluator\'s '
          'own constant, not a hardcoded string — this is what makes a '
          'future ruleset-value change structurally force a version bump',
    );
  });

  test('the madhhab_history migration keeps a defensive SQL default, but the '
      'application never depends on it', () {
    final migration = File(
      'supabase/migrations/20261007090000_madhhab_change_history.sql',
    ).readAsStringSync();
    expect(migration, contains('ruleset_version TEXT NOT NULL DEFAULT'));
  });
}
