// Round-2 hardening (2026-10-21, proposed) — regressions found by the
// adversarial review of fix/tracking-hardening. Each test failed on that
// branch's tip (d77cd14) and passes with the round-2 fixes.
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/services/canonical_bleeding_status_resolver.dart';
import 'package:niswah/features/cycle_tracking/domain/services/canonical_fiqh_assessment.dart';
import 'package:niswah/features/cycle_tracking/domain/services/canonical_fiqh_evidence_adapter.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:niswah/features/cycle_tracking/domain/services/report_canonical_evidence.dart';
import 'package:niswah/features/fiqh_report/domain/services/fiqh_report_insights_engine.dart';

int _seq = 0;

BleedingObservation _obs(
  DateTime day,
  ObservationFlow flow, {
  String episode = 'ep',
  DateTime? reportedAt,
}) => BleedingObservation(
  id: 'r2-${_seq++}',
  userId: 'u',
  episodeId: episode,
  observedDate: day,
  precision: ObservationPrecision.dateOnly,
  flow: flow,
  source: ObservationSource.userObserved,
  reportedAt: reportedAt,
  utcOffsetMinutes: 0,
);

List<BleedingObservation> _days(
  DateTime from,
  DateTime to, {
  String episode = 'ep',
}) => [
  for (var d = from; !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1))
    _obs(d, ObservationFlow.medium, episode: episode),
];

void main() {
  test(
    'Today/AI and the Fiqh report reach the SAME verdict for the same '
    'canonical evidence (onboarding-reported past period + open episode)',
    () {
      // record_onboarding_menstrual_history writes the reported start as an
      // `uncertain` observation (dropped by the adapter) and the end as a
      // `none` observation; the current period was started from the app.
      final observations = [
        _obs(DateTime(2026, 7, 1), ObservationFlow.uncertain, episode: 'onb'),
        _obs(DateTime(2026, 7, 6), ObservationFlow.none, episode: 'onb'),
        ..._days(DateTime(2026, 8, 1), DateTime(2026, 8, 5), episode: 'cur'),
      ];
      // The canonical episode rows the resolver reads.
      final episodeRows = [
        BleedingEpisode(
          id: 'onb',
          userId: 'u',
          lifecycleStatus: LifecycleStatus.ended,
          startDate: DateTime(2026, 7, 1),
          startPrecision: ObservationPrecision.dateOnly,
          startSource: ObservationSource.userReportedHistorical,
          endDate: DateTime(2026, 7, 6),
        ),
        BleedingEpisode(
          id: 'cur',
          userId: 'u',
          lifecycleStatus: LifecycleStatus.open,
          continuationCertainty: ContinuationCertainty.confirmed,
          startDate: DateTime(2026, 8, 1),
          startPrecision: ObservationPrecision.dateOnly,
          startSource: ObservationSource.userObserved,
        ),
      ];
      final episodes = [
        for (final e in episodeRows)
          CanonicalEpisodeTiming(startDate: e.startDate, endDate: e.endDate),
      ];
      final now = DateTime(2026, 8, 5, 12);
      final logs = CanonicalFiqhEvidenceAdapter.buildEffectiveLogs(
        observations: observations,
      );

      // Exactly what DashboardScreen.build passes: the timings of the
      // episodes its CanonicalBleedingStatusResolver read (the AI provider
      // passes ReportCanonicalEvidence.episodes, built the same way).
      final status = CanonicalBleedingStatusResolver.resolveFromEpisodes(
        episodes: episodeRows,
        now: now,
      );
      final today = CanonicalFiqhAssessment.assess(
        effectiveLogs: logs,
        hasOpenEpisode: true,
        evidenceUnresolved: false,
        madhhab: Madhhab.hanafi,
        now: now,
        canonicalEpisodes: status.episodeTimings,
      );
      // The Fiqh report passes canonical.episodes.
      final report = FiqhReportInsightsEngine.analyze(
        cycleLogs: const [],
        madhhab: Madhhab.hanafi,
        now: now,
        canonical: ReportCanonicalEvidence(
          effectiveLogs: logs,
          episodes: episodes,
          hasOpenEpisode: true,
          evidenceUnresolved: false,
        ),
      );

      final todayState =
          today.state ??
          (today.verdict == CanonicalFiqhVerdict.insufficientHistory
              ? FiqhCycleState.insufficientHistory
              : null);
      expect(
        report.cycleState,
        todayState,
        reason:
            'Today/AI: ${today.verdict} -> $todayState; report: '
            '${report.cycleState}. The assessment is the ONE combination all '
            'surfaces share; before round-2 only the report fed it '
            'canonicalEpisodes, so hasSufficientHistory differed.',
      );
    },
  );

  test('minimum purity is only "met" when it holds under the shortest '
      'reading of date-only stop/start days (as minimum haid already is)', () {
    // Two normal earlier cycles for sufficient history.
    final observations = [
      ..._days(DateTime(2026, 1, 1), DateTime(2026, 1, 6)),
      _obs(DateTime(2026, 1, 7), ObservationFlow.none),
      ..._days(DateTime(2026, 1, 29), DateTime(2026, 2, 3)),
      _obs(DateTime(2026, 2, 4), ObservationFlow.none),
      // Haid Mar 1-6. She logged bleeding on the morning of Mar 6, then
      // answered "it stopped today" that evening (closing obs on Mar 6).
      ..._days(DateTime(2026, 3, 1), DateTime(2026, 3, 5)),
      _obs(
        DateTime(2026, 3, 6),
        ObservationFlow.medium,
        reportedAt: DateTime(2026, 3, 6, 8),
      ),
      _obs(
        DateTime(2026, 3, 6),
        ObservationFlow.none,
        reportedAt: DateTime(2026, 3, 6, 20),
      ),
      // Bleeding again, date-only, from Mar 19.
      ..._days(DateTime(2026, 3, 19), DateTime(2026, 3, 21)),
    ];
    final logs = CanonicalFiqhEvidenceAdapter.buildEffectiveLogs(
      observations: observations,
    );
    final assessment = CanonicalFiqhAssessment.assess(
      effectiveLogs: logs,
      hasOpenEpisode: true,
      evidenceUnresolved: false,
      madhhab: Madhhab.hanbali,
      now: DateTime(2026, 3, 21, 12),
      canonicalEpisodes: const [],
    );
    // Bleeding was present on Mar 6 and may have begun at 00:00 on Mar 19:
    // the clean interval can be as short as ~12 days, below Hanbali's 13
    // (FD-7). Calendar-day counting (Mar 6 -> Mar 19 = 13) says "met".
    expect(
      assessment.state,
      isNot(FiqhCycleState.haid),
      reason:
          'purity counted as calendarDaysBetween(stopDay, startDay) — the '
          'most generous reading — while the same engine requires the '
          'minimum HAID to hold under the shortest reading',
    );
  });
}
