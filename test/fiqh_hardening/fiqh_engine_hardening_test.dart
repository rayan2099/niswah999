// Fiqh hardening regression tests (findings first proven failing on
// 2026-10-18). Each test asserts the behaviour the repo's own documented
// rule matrix (haidfigh.md, ENGINE_TO_KB_ATOM_CROSSWALK.md,
// FOUNDER_DECISIONS.md FD-7) requires — or, where that matrix does not
// settle a case, that no confident ruling is shown.
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/canonical_bleeding_status_resolver.dart';
import 'package:niswah/features/cycle_tracking/domain/services/canonical_fiqh_assessment.dart';
import 'package:niswah/features/cycle_tracking/domain/services/canonical_fiqh_evidence_adapter.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_status_engine.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:niswah/features/cycle_tracking/domain/services/report_canonical_evidence.dart';
import 'package:niswah/features/fiqh_report/domain/services/fiqh_report_insights_engine.dart';

int _seq = 0;

BleedingObservation obs(
  DateTime day,
  ObservationFlow flow, {
  DateTime? observedTime,
  DateTime? reportedAt,
  String episode = 'ep',
}) => BleedingObservation(
  id: 'o${_seq++}',
  userId: 'u',
  episodeId: episode,
  observedDate: day,
  observedTime: observedTime,
  precision: observedTime == null
      ? ObservationPrecision.dateOnly
      : ObservationPrecision.exactTime,
  flow: flow,
  source: ObservationSource.userObserved,
  reportedAt: reportedAt,
  utcOffsetMinutes: 0,
);

/// Daily observations [from]..[to] inclusive, then the closing `none`
/// observation the `end_bleeding_episode` RPC writes on the stop date.
List<BleedingObservation> episode(
  DateTime from,
  DateTime to, {
  DateTime? stoppedOn,
  ObservationFlow flow = ObservationFlow.medium,
}) {
  final out = <BleedingObservation>[];
  for (var d = from; !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) {
    out.add(obs(d, flow));
  }
  if (stoppedOn != null) out.add(obs(stoppedOn, ObservationFlow.none));
  return out;
}

/// Exactly what DashboardScreen.build does with canonical evidence: the
/// shared [CanonicalFiqhAssessment]. Null means no ruling may be shown
/// ("Unable to verify" / "Not enough history yet").
FiqhCycleState? dashboardState(
  List<BleedingObservation> observations,
  Madhhab? madhhab,
  DateTime now, {
  bool hasOpenEpisode = true,
}) {
  final logs = CanonicalFiqhEvidenceAdapter.buildEffectiveLogs(
    observations: observations,
  );
  return CanonicalFiqhAssessment.assess(
    effectiveLogs: logs,
    hasOpenEpisode: hasOpenEpisode,
    evidenceUnresolved: false,
    madhhab: madhhab,
    now: now,
    // Every fixture episode here starts with a flowed observation, so its
    // start is already in the logs; the timings would add nothing.
    canonicalEpisodes: const [],
  ).state;
}

// Two prior, normal, well-separated cycles so hasSufficientHistory holds.
List<BleedingObservation> history() => [
  ...episode(
    DateTime(2026, 1, 1),
    DateTime(2026, 1, 6),
    stoppedOn: DateTime(2026, 1, 7),
  ),
  ...episode(
    DateTime(2026, 1, 29),
    DateTime(2026, 2, 3),
    stoppedOn: DateTime(2026, 2, 4),
  ),
];

void main() {
  group('F1 minimum tuhr (15d; Hanbali 13d) not enforced for 3 madhahib', () {
    // haidfigh.md §3/§4 + crosswalk SHF-HAID-06 / HNB-HAID-06 / MLK-HAID-06:
    // a later bleed is only a fresh Haid after the minimum complete purity.
    // Ten-day haid Mar 1-10 (stopped Mar 11), bleeding resumes Mar 14 —
    // only 3 clean days.
    final obsList = [
      ...history(),
      ...episode(
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 10),
        stoppedOn: DateTime(2026, 3, 11),
      ),
      ...episode(DateTime(2026, 3, 14), DateTime(2026, 3, 17)),
    ];
    final now = DateTime(2026, 3, 17, 12);

    for (final m in [Madhhab.shafii, Madhhab.hanbali, Madhhab.maliki]) {
      test('${m.name}: bleeding 3 days after a 10-day haid is NOT a fresh '
          'confident haid', () {
        expect(
          dashboardState(obsList, m, now),
          isNot(FiqhCycleState.haid),
          reason:
              'purity of 3 days < documented minimum tuhr (was gated for '
              'Hanafi only)',
        );
      });
    }
  });

  test('F2 date-only start is treated as 00:00 — Hanafi 72h minimum is '
      'reached ~a day early (bleeding began 23:00 Mar 1; now 00:30 Mar 4 = '
      '49.5 real hours)', () {
    final obsList = [
      ...history(),
      obs(
        DateTime(2026, 3, 1),
        ObservationFlow.heavy,
        observedTime: DateTime(2026, 3, 1, 23),
      ),
      obs(DateTime(2026, 3, 2), ObservationFlow.heavy),
      obs(DateTime(2026, 3, 3), ObservationFlow.heavy),
    ];
    final now = DateTime(2026, 3, 4, 0, 30);
    expect(
      dashboardState(obsList, Madhhab.hanafi, now),
      isNot(FiqhCycleState.haid),
      reason:
          'haidfigh.md §1: <72h is istihadah (she does not stop praying). '
          'The adapter used to drop observedTime and the engine measured '
          'from local midnight.',
    );
  });

  test('F3 every canonical bleeding day 2+ days after the previous "start" '
      'is counted as a NEW haid start (adapter leaves cycleDay=1), so a '
      'first-ever single episode passes hasSufficientHistory', () {
    // Brand-new user, very first episode, logged daily Mar 1..Mar 5.
    final logs = CanonicalFiqhEvidenceAdapter.buildEffectiveLogs(
      observations: episode(DateTime(2026, 3, 1), DateTime(2026, 3, 5)),
    );
    final calc = const CycleCalculationService().calculate(
      logs,
      asOf: DateTime(2026, 3, 5, 12),
    );
    expect(
      calc.haidStarts.length,
      1,
      reason: 'one continuous episode has one start',
    );
    expect(
      calc.hasSufficientHistory,
      isFalse,
      reason:
          'haidfigh.md "Engine Implementation Directives" 1: fewer than '
          '2 logged cycles must show the insufficient-history state',
    );
  });

  test('F3b the Fiqh report computes a 2-day "average cycle length" from '
      'one ordinary episode', () {
    final logs = CanonicalFiqhEvidenceAdapter.buildEffectiveLogs(
      observations: [
        ...episode(
          DateTime(2026, 3, 1),
          DateTime(2026, 3, 6),
          stoppedOn: DateTime(2026, 3, 7),
        ),
      ],
    );
    final insights = FiqhReportInsightsEngine.analyze(
      cycleLogs: const [],
      madhhab: Madhhab.shafii,
      now: DateTime(2026, 3, 10),
      canonical: ReportCanonicalEvidence(
        effectiveLogs: logs,
        episodes: [
          CanonicalEpisodeTiming(
            startDate: DateTime(2026, 3, 1),
            endDate: DateTime(2026, 3, 7),
          ),
        ],
        hasOpenEpisode: false,
        evidenceUnresolved: false,
      ),
    );
    expect(insights.hasEnoughForAverages, isFalse);
    expect(insights.averageCycleLengthDays, isNull);
  });

  test('F4 Hanafi: tuhr is measured from the last stop of ANY bleeding, '
      'so a <72h istihadah spotting episode breaks a 25-day purity', () {
    // Haid Mar 1-6 (stopped Mar 7). Spotting Mar 24 (stopped Mar 25) —
    // certainly under 72h even if it lasted to the end of its stop day,
    // i.e. istihadah per haidfigh.md §1, not a haid. New bleeding Apr 1:
    // clean-of-haid since the end of Mar 7 = 24 days >= 15.
    // (Round-2 hardening: the fixture was Mar 24-25 stopped Mar 26, which
    // can reach exactly 72h when "stopped on Mar 26" is read as bleeding
    // until the end of that day — no longer certainly below the minimum.)
    final obsList = [
      ...history(),
      ...episode(
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 6),
        stoppedOn: DateTime(2026, 3, 7),
      ),
      ...episode(
        DateTime(2026, 3, 24),
        DateTime(2026, 3, 24),
        stoppedOn: DateTime(2026, 3, 25),
        flow: ObservationFlow.spotting,
      ),
      ...episode(DateTime(2026, 4, 1), DateTime(2026, 4, 5)),
    ];
    expect(
      dashboardState(obsList, Madhhab.hanafi, DateTime(2026, 4, 5, 12)),
      FiqhCycleState.haid,
      reason:
          'haidfigh.md §1: min purity is between two *menstrual* cycles; '
          'the engine used purityBefore = 6 days (Mar 25 -> Apr 1)',
    );
  });

  test("F5 Shafi'i cumulative 24h (talfiq) across a clean day is NOT "
      'modelled — it must fall to needsAdvisory, never a confident ruling', () {
    // Bleeding Mar 1 & Mar 2 (>24h), clean Mar 3, bleeding again Mar 4.
    // haidfigh.md §3: 24 cumulative hours, need not be continuous. The
    // engine measures runs separately (talfiq is deliberately not
    // implemented — see docs); the honest result is "consult".
    final obsList = [
      ...history(),
      ...episode(
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 2),
        stoppedOn: DateTime(2026, 3, 3),
      ),
      obs(DateTime(2026, 3, 4), ObservationFlow.medium),
    ];
    expect(
      dashboardState(obsList, Madhhab.shafii, DateTime(2026, 3, 4, 10)),
      FiqhCycleState.needsAdvisory,
    );
  });

  test('date-only start: the minimum must hold even if bleeding began at '
      'the END of the start day', () {
    // Hanafi, bleeding logged date-only from Mar 1. At Mar 4 12:00 the
    // 72h minimum holds only under a midnight start (84h) — from the end
    // of Mar 1 it is 60h.
    final obsList = [
      ...history(),
      ...episode(DateTime(2026, 3, 1), DateTime(2026, 3, 4)),
    ];
    final logs = CanonicalFiqhEvidenceAdapter.buildEffectiveLogs(
      observations: obsList,
    );
    final calc = const CycleCalculationService().calculate(
      logs,
      asOf: DateTime(2026, 3, 4, 12),
    );
    final early = const CycleStatusEngine().evaluate(
      logs: logs,
      calculation: calc,
      madhhab: Madhhab.hanafi,
      now: DateTime(2026, 3, 4, 12),
    );
    expect(early.state, FiqhCycleState.needsAdvisory);
    expect(early.confirmAt, DateTime(2026, 3, 5));
    expect(
      dashboardState(obsList, Madhhab.hanafi, DateTime(2026, 3, 5, 0, 1)),
      FiqhCycleState.haid,
    );
  });

  test('Hanbali minimum purity is 13 days (FD-7), not 15', () {
    // Haid Mar 1-6 (stopped Mar 7); new bleeding Mar 21 = 14 clean days.
    final obsList = [
      ...history(),
      ...episode(
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 6),
        stoppedOn: DateTime(2026, 3, 7),
      ),
      ...episode(DateTime(2026, 3, 21), DateTime(2026, 3, 23)),
    ];
    final now = DateTime(2026, 3, 23, 12);
    expect(dashboardState(obsList, Madhhab.hanbali, now), FiqhCycleState.haid);
    expect(
      dashboardState(obsList, Madhhab.shafii, now),
      FiqhCycleState.needsAdvisory,
    );
  });

  test('an exact observed start time is carried through by the adapter', () {
    final logs = CanonicalFiqhEvidenceAdapter.buildEffectiveLogs(
      observations: [
        obs(
          DateTime(2026, 3, 1),
          ObservationFlow.heavy,
          observedTime: DateTime(2026, 3, 1, 23),
        ),
        obs(DateTime(2026, 3, 2), ObservationFlow.heavy),
        obs(DateTime(2026, 3, 3), ObservationFlow.none),
        obs(DateTime(2026, 3, 20), ObservationFlow.light),
      ],
    );
    expect(logs.map((l) => l.observedTime).toList(), [
      DateTime(2026, 3, 1, 23),
      null,
      null,
      null,
    ]);
    expect(logs.map((l) => l.cycleDay).toList(), [1, 2, 3, 1]);
  });

  test('F6 an episode ended with a stop date earlier than a later logged '
      'bleeding day keeps the engine on "haid" while the ring says no open '
      'episode', () {
    // Open Mar 1, daily YES through Mar 5, then "When did it stop?" ->
    // picks Mar 3 (picker allows any date >= start, daily_checkin_sheet
    // .dart:315-319; RPC only checks end >= start).
    final obsList = [
      ...history(),
      ...episode(DateTime(2026, 3, 1), DateTime(2026, 3, 5)),
      obs(
        DateTime(2026, 3, 3),
        ObservationFlow.none,
        reportedAt: DateTime(2026, 3, 6, 9),
      ),
    ];
    final now = DateTime(2026, 3, 6, 12);
    final ring = CanonicalBleedingStatusResolver.resolveFromEpisodes(
      episodes: [
        BleedingEpisode(
          id: 'ep',
          userId: 'u',
          lifecycleStatus: LifecycleStatus.ended,
          startDate: DateTime(2026, 3, 1),
          startPrecision: ObservationPrecision.dateOnly,
          startSource: ObservationSource.userObserved,
          endDate: DateTime(2026, 3, 3),
          endPrecision: ObservationPrecision.dateOnly,
          endSource: ObservationSource.userObserved,
        ),
      ],
      now: now,
    );
    expect(ring.state, isNot(RingFactualState.factualOpenEpisode));
    final state = dashboardState(
      obsList,
      Madhhab.shafii,
      now,
      hasOpenEpisode: ring.state == RingFactualState.factualOpenEpisode,
    );
    expect(
      state,
      isNot(FiqhCycleState.haid),
      reason:
          'no open episode exists, yet "Salah is lifted" would be shown '
          'until day 15',
    );
    expect(state, isNot(FiqhCycleState.tahara));
  });

  test('F7 DST: ring "day N" uses Duration.inDays between local midnights '
      '(run with TZ=America/New_York)', () {
    final start = DateTime(2026, 3, 7); // US DST begins 2026-03-08
    final now = DateTime(2026, 3, 9, 12);
    final status = CanonicalBleedingStatusResolver.resolveFromEpisodes(
      episodes: [
        BleedingEpisode(
          id: 'ep',
          userId: 'u',
          lifecycleStatus: LifecycleStatus.open,
          continuationCertainty: ContinuationCertainty.confirmed,
          startDate: start,
          startPrecision: ObservationPrecision.dateOnly,
          startSource: ObservationSource.userObserved,
        ),
      ],
      now: now,
    );
    expect(status.daysIntoOpenEpisode, 3, reason: 'Mar 7, 8, 9 = day 3');

    final snap = const CycleStatusEngine().evaluate(
      logs: [
        CycleLog(id: 'a', userId: 'u', date: start, flow: FlowLevel.medium),
      ],
      calculation: const CycleCalculationService().calculate(const []),
      madhhab: null,
      now: DateTime(2026, 3, 8, 23, 30),
    );
    expect(snap.daysIntoCurrentEpisode, 2, reason: 'Mar 8 is day 2');
  });

  test('F8 report rules confidently while dashboard shows "Unable to '
      'verify" (quarantined row, no open episode)', () {
    final logs = CanonicalFiqhEvidenceAdapter.buildEffectiveLogs(
      observations: [
        ...history(),
        ...episode(
          DateTime(2026, 3, 1),
          DateTime(2026, 3, 6),
          stoppedOn: DateTime(2026, 3, 7),
        ),
      ],
    );
    final insights = FiqhReportInsightsEngine.analyze(
      cycleLogs: const [],
      madhhab: Madhhab.hanafi,
      now: DateTime(2026, 3, 10),
      canonical: ReportCanonicalEvidence(
        effectiveLogs: logs,
        episodes: const [],
        hasOpenEpisode: false,
        evidenceUnresolved: true, // quarantined > 0
      ),
    );
    // Dashboard: a quarantined row => "Unable to verify" regardless of
    // whether an episode is open; the report must agree.
    expect(insights.cycleState, isNot(FiqhCycleState.tahara));
    expect(insights.evidenceNote, isNot(ReportEvidenceNote.none));
  });
}
