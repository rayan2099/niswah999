// Round-2 hardening (2026-10-21, proposed) — the Fiqh regressions R2-1..R2-3
// found by the round-2 property suite (the prediction ones, R2-4..,
// are in round2_regressions_test.dart). One minimal (shrunk) history per violation; each
// failed on fix/tracking-hardening (d77cd14). R2-2 only fails under a DST
// zone (TZ=Europe/London, America/New_York); it passes trivially under UTC.
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/utils/calendar_days.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';

import 'support/fiqh_surfaces.dart';
import 'support/synthetic_history.dart';

const _m = ObservationFlow.medium;

CanonicalInputs _inputsAt(SynthHistory h, int t, DateTime now) {
  final ev = evidenceAsOf(h, t);
  return canonicalInputs(ev.episodes, ev.observations, now);
}

void main() {
  test('R2-1 Fiqh report rules on an onboarding episode Today/AI ignore '
      '(fiqh report != Today == AI)', () {
    // Onboarding-reported period 2025-08-31..09-01 (start flow uncertain,
    // never projected), then her first tracked bleeding on 2025-09-29.
    final h = SynthHistory(
      kind: 'R2-1',
      seed: 330225,
      anchor: DateTime(2025, 8, 31),
      episodes: const [
        SynthEpisode(start: 0, flows: [_m], onboarding: true),
        SynthEpisode(start: 29, flows: [_m, _m, _m, _m, _m], ended: false),
      ],
    );
    for (final m in [null, Madhhab.hanafi, Madhhab.shafii]) {
      final now = DateTime(2025, 10, 3, 12); // day 5 of the open episode
      final c = _inputsAt(h, 33, now);
      final today = dashboardLabel(c, m, now);
      final ai = aiInDashboardVocabulary(aiLabel(c, m, now));
      final report = reportLabel(c, m, now);
      // Round-2 hardening: the property is report == Today == AI. The
      // copied test also pinned Today to 'insufficientHistory' — the
      // pre-fix behaviour (onboarding episode ignored). Today now counts
      // that episode too, exactly like the report.
      expect(ai, today);
      expect(
        report,
        dashboardInReportVocabulary(today),
        reason: 'madhhab=${m?.name}: report says $report',
      );
    }
  });

  test('R2-2 purity anchor: a 3-day Hanafi run across spring-forward is '
      'still a possible haid (calendar days, not wall hours)', () {
    // Run 2025-03-28..03-30 bleeding, none on 03-31 (UK clocks change on
    // 03-30): 3 calendar days = the 72h minimum, but 71 wall-clock hours.
    final h = SynthHistory(
      kind: 'R2-2',
      seed: 0,
      anchor: DateTime(2025, 1, 27),
      episodes: [
        SynthEpisode(start: 0, flows: List.filled(5, _m)),
        SynthEpisode(start: 30, flows: List.filled(5, _m)),
        SynthEpisode(start: 60, flows: List.filled(3, _m)), // 2025-03-28
        SynthEpisode(start: 68, flows: List.filled(8, _m), ended: false),
      ],
    );
    expect(ymd(h.day(60)), '2025-03-28');
    final now = DateTime(2025, 4, 9, 12); // day 6 of bleeding from 04-04
    final c = _inputsAt(h, calendarDaysBetween(h.anchor, now), now);
    // Only 5 clean days since a run that could have been haid: never a
    // confident fresh haid (§16 items 2 and 5).
    expect(dashboardLabel(c, Madhhab.hanafi, now), 'needsAdvisory');
  });

  test(
    'R2-3 open episode whose latest effective day was corrected to '
    '"none": no confident Tahara while the episode is open (madhhab unset)',
    () {
      final h = SynthHistory(
        kind: 'R2-3',
        seed: 300020,
        anchor: DateTime(2027, 4, 9),
        episodes: const [
          SynthEpisode(start: 0, flows: [_m]),
          SynthEpisode(
            start: 30,
            flows: [
              ObservationFlow.heavy,
              ObservationFlow.light,
              ObservationFlow.none,
            ],
            ended: false,
          ),
        ],
      );
      final now = DateTime(2027, 5, 11, 0, 0, 1);
      final c = _inputsAt(h, 32, now);
      expect(c.hasOpenEpisode, isTrue);
      expect(dashboardLabel(c, null, now), isNot(anyOf('tahara', 'haid')));
    },
  );
}
