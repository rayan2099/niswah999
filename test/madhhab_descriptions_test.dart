// Requirement 1/6: one shared description per madhhab, derived from
// MadhhabRuleEvaluator's own duration constants (never re-typed), with
// text that matches what the engine actually computes.
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:niswah/features/madhhab/domain/madhhab_descriptions.dart';

void main() {
  test(
    'Hanafi: 72h/240h render as 3-day/10-day — matches the engine exactly',
    () {
      final d = describeMadhhab(Madhhab.hanafi);
      expect(d.shortRuleEn, '3-day min · 10-day max');
      expect(d.shortRuleAr, 'حد أدنى 3 يوماً · حد أقصى 10 يوماً');
      expect(
        MadhhabRuleEvaluator.minimumHaidFor(Madhhab.hanafi),
        const Duration(hours: 72),
      );
      expect(
        MadhhabRuleEvaluator.maximumHaidFor(Madhhab.hanafi),
        const Duration(hours: 240),
      );
    },
  );

  for (final m in [Madhhab.shafii, Madhhab.maliki, Madhhab.hanbali]) {
    test('${m.name}: exactly-24-hour minimum renders as "24-hour", never '
        '"1-day" (readability regression fixed after adversarial review)', () {
      final d = describeMadhhab(m);
      expect(d.shortRuleEn, '24-hour min · 15-day max');
      expect(d.shortRuleAr, 'حد أدنى 24 ساعة · حد أقصى 15 يوماً');
      expect(MadhhabRuleEvaluator.minimumHaidFor(m), const Duration(hours: 24));
      expect(
        MadhhabRuleEvaluator.maximumHaidFor(m),
        const Duration(hours: 360),
      );
    });
  }

  test('Maliki carries the ʿāda longNote; the other three share generic '
      'wording — no jurisprudential content invented beyond the engine\'s '
      'own personalHabit/isWithinPersonalHabit logic', () {
    final maliki = describeMadhhab(Madhhab.maliki);
    expect(maliki.longNoteEn, contains("'āda"));
    for (final m in [Madhhab.hanafi, Madhhab.shafii, Madhhab.hanbali]) {
      expect(describeMadhhab(m).longNoteEn, isNot(contains("'āda")));
    }
  });
}
