// Regression test for production-readiness-results/fiqh-engine/golden_fiqh_dataset.json
// (FIQH_ENGINE_ACCURACY_AUDIT_MASTER.md Phase 9). Every expected value here is
// ENGINEERING-DERIVED from the current MadhhabRuleEvaluator implementation —
// not a claim of religious correctness. See that JSON file's `_meta.warning`
// and FIQH_AICTX_findings.md's Scholar Review Gate section.
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';

void main() {
  const evaluator = MadhhabRuleEvaluator();

  group('golden fiqh dataset (engineering-derived, NOT_REVIEWED religiously)', () {
    test('FIQH-CASE-001 simple normal case (hanafi, haid)', () {
      final result = evaluator.evaluate(
        madhhab: Madhhab.hanafi,
        hasSufficientHistory: true,
        isBleeding: true,
        bleedingDuration: const Duration(hours: 120),
        purityBefore: const Duration(days: 20),
      );
      expect(result.state, FiqhCycleState.haid);
    });

    test('FIQH-CASE-002 exact minimum boundary (hanafi, 72h, haid)', () {
      final result = evaluator.evaluate(
        madhhab: Madhhab.hanafi,
        hasSufficientHistory: true,
        isBleeding: true,
        bleedingDuration: const Duration(hours: 72),
        purityBefore: const Duration(days: 20),
      );
      expect(result.state, FiqhCycleState.haid);
    });

    test('FIQH-CASE-003 one unit below minimum (hanafi, 71h59m, needsAdvisory)', () {
      final result = evaluator.evaluate(
        madhhab: Madhhab.hanafi,
        hasSufficientHistory: true,
        isBleeding: true,
        bleedingDuration: const Duration(hours: 71, minutes: 59),
        purityBefore: const Duration(days: 20),
      );
      expect(result.state, FiqhCycleState.needsAdvisory);
    });

    test('FIQH-CASE-004 exact maximum boundary (shafii, 15 days, haid)', () {
      final result = evaluator.evaluate(
        madhhab: Madhhab.shafii,
        hasSufficientHistory: true,
        isBleeding: true,
        bleedingDuration: const Duration(days: 15),
        purityBefore: const Duration(days: 20),
      );
      expect(result.state, FiqhCycleState.haid);
    });

    test('FIQH-CASE-005 one unit above maximum (shafii, 15d1m, needsAdvisory)', () {
      final result = evaluator.evaluate(
        madhhab: Madhhab.shafii,
        hasSufficientHistory: true,
        isBleeding: true,
        bleedingDuration: const Duration(days: 15, minutes: 1),
        purityBefore: const Duration(days: 20),
      );
      expect(result.state, FiqhCycleState.needsAdvisory);
    });

    test('FIQH-CASE-006 insufficient history (hanbali)', () {
      final result = evaluator.evaluate(
        madhhab: Madhhab.hanbali,
        hasSufficientHistory: false,
        isBleeding: true,
        bleedingDuration: const Duration(days: 5),
      );
      expect(result.state, FiqhCycleState.insufficientHistory);
    });

    test('FIQH-CASE-007 changed habit (maliki, within general range, habit exceeded)', () {
      final result = evaluator.evaluate(
        madhhab: Madhhab.maliki,
        hasSufficientHistory: true,
        isBleeding: true,
        bleedingDuration: const Duration(days: 7),
        purityBefore: const Duration(days: 20),
        personalHabit: const Duration(days: 6),
      );
      expect(result.state, FiqhCycleState.haid);
      expect(result.isWithinPersonalHabit, false);
    });

    test('FIQH-CASE-008 purity boundary (hanafi, one minute short of 15-day minimum)', () {
      final result = evaluator.evaluate(
        madhhab: Madhhab.hanafi,
        hasSufficientHistory: true,
        isBleeding: true,
        bleedingDuration: const Duration(days: 5),
        purityBefore: const Duration(days: 14, hours: 23, minutes: 59),
      );
      expect(result.state, FiqhCycleState.needsAdvisory);
    });

    test('FIQH-CASE-009 not bleeding (hanbali, tahara)', () {
      final result = evaluator.evaluate(
        madhhab: Madhhab.hanbali,
        hasSufficientHistory: true,
        isBleeding: false,
        bleedingDuration: Duration.zero,
      );
      expect(result.state, FiqhCycleState.tahara);
    });

    test('FIQH-CASE-010 madhhab-difference case: identical 30h bleeding, four madhahib', () {
      final duration = const Duration(hours: 30);
      final purity = const Duration(days: 20);

      expect(
        evaluator
            .evaluate(
              madhhab: Madhhab.hanafi,
              hasSufficientHistory: true,
              isBleeding: true,
              bleedingDuration: duration,
              purityBefore: purity,
            )
            .state,
        FiqhCycleState.needsAdvisory,
        reason: '30h < Hanafi 72h minimum',
      );
      expect(
        evaluator
            .evaluate(
              madhhab: Madhhab.maliki,
              hasSufficientHistory: true,
              isBleeding: true,
              bleedingDuration: duration,
              purityBefore: purity,
            )
            .state,
        FiqhCycleState.haid,
        reason: '30h > Maliki 24h minimum',
      );
      expect(
        evaluator
            .evaluate(
              madhhab: Madhhab.shafii,
              hasSufficientHistory: true,
              isBleeding: true,
              bleedingDuration: duration,
              purityBefore: purity,
            )
            .state,
        FiqhCycleState.haid,
        reason: '30h > Shafii 24h minimum',
      );
      expect(
        evaluator
            .evaluate(
              madhhab: Madhhab.hanbali,
              hasSufficientHistory: true,
              isBleeding: true,
              bleedingDuration: duration,
              purityBefore: purity,
            )
            .state,
        FiqhCycleState.haid,
        reason: '30h > Hanbali 24h minimum',
      );
    });

    test('FIQH-CASE-012 deliberately ambiguous (hanafi, fails two boundaries at once)', () {
      final result = evaluator.evaluate(
        madhhab: Madhhab.hanafi,
        hasSufficientHistory: true,
        isBleeding: true,
        bleedingDuration: const Duration(hours: 71),
        purityBefore: const Duration(days: 14, hours: 20),
      );
      expect(result.state, FiqhCycleState.needsAdvisory);
    });
  });
}
