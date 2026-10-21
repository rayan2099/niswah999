// The three surfaces that present a Fiqh state, composed exactly as the
// app composes them (pure parts only; the async loaders are cross-checked
// separately in fiqh_properties_test.dart):
//   * Today dashboard — dashboard_screen.dart `_refreshCanonicalStatus` +
//     build(): resolver status, adapter logs, material-uncertainty flag,
//     CanonicalFiqhAssessment.assess with the resolver's episodeTimings
//     (round-2 hardening: canonicalEpisodes is now required everywhere).
//   * Fiqh report — FiqhReportInsightsEngine.analyze with the
//     ReportCanonicalEvidence that ReportCanonicalEvidence.load builds.
//   * AI advisor — ClientFiqhStateProvider.currentClassification.
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/canonical_bleeding_status_resolver.dart';
import 'package:niswah/features/cycle_tracking/domain/services/canonical_fiqh_assessment.dart';
import 'package:niswah/features/cycle_tracking/domain/services/canonical_fiqh_evidence_adapter.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:niswah/features/cycle_tracking/domain/services/report_canonical_evidence.dart';
import 'package:niswah/features/fiqh_report/domain/services/fiqh_report_insights_engine.dart';

class CanonicalInputs {
  CanonicalInputs({
    required this.logs,
    required this.hasOpenEpisode,
    required this.evidenceUnresolved,
    required this.timing,
    required this.episodes,
  });
  final List<CycleLog> logs;
  final bool hasOpenEpisode;
  final bool evidenceUnresolved;
  final List<CanonicalEpisodeTiming> timing;
  final List<BleedingEpisode> episodes;
}

CanonicalInputs canonicalInputs(
  List<BleedingEpisode> episodes,
  List<BleedingObservation> observations,
  DateTime now,
) {
  final status = CanonicalBleedingStatusResolver.resolveFromEpisodes(
    episodes: episodes,
    now: now,
  );
  return CanonicalInputs(
    logs: CanonicalFiqhEvidenceAdapter.buildEffectiveLogs(
      observations: observations,
    ),
    hasOpenEpisode: status.state == RingFactualState.factualOpenEpisode,
    evidenceUnresolved: ReportCanonicalEvidence.hasMaterialUnresolvedEvidence(
      observations: observations,
      openEpisodeStart: status.openEpisode?.startDate,
    ),
    timing: [
      for (final e in episodes)
        CanonicalEpisodeTiming(startDate: e.startDate, endDate: e.endDate),
    ],
    episodes: episodes,
  );
}

/// Today's label: haid / tahara / needsAdvisory / madhhabUnresolved /
/// insufficientHistory / evidenceUnresolved.
String dashboardLabel(CanonicalInputs c, Madhhab? m, DateTime now) {
  final a = dashboardAssessment(c, m, now);
  return switch (a.verdict) {
    CanonicalFiqhVerdict.evidenceUnresolved => 'evidenceUnresolved',
    CanonicalFiqhVerdict.insufficientHistory => 'insufficientHistory',
    CanonicalFiqhVerdict.evaluated => switch (a.snapshot.state) {
      FiqhCycleState.insufficientHistory => 'tahara', // mapped in the UI
      final s => s.name,
    },
  };
}

CanonicalFiqhAssessment dashboardAssessment(
  CanonicalInputs c,
  Madhhab? m,
  DateTime now,
) => CanonicalFiqhAssessment.assess(
  effectiveLogs: c.logs,
  hasOpenEpisode: c.hasOpenEpisode,
  evidenceUnresolved: c.evidenceUnresolved,
  madhhab: m,
  now: now,
  canonicalEpisodes: CanonicalBleedingStatusResolver.resolveFromEpisodes(
    episodes: c.episodes,
    now: now,
  ).episodeTimings,
);

/// AI advisor `clientFiqhState` (null = omitted).
String? aiLabel(CanonicalInputs c, Madhhab? m, DateTime now) {
  final a = dashboardAssessment(c, m, now);
  return switch (a.verdict) {
    CanonicalFiqhVerdict.evaluated => a.state!.name,
    CanonicalFiqhVerdict.insufficientHistory =>
      FiqhCycleState.insufficientHistory.name,
    CanonicalFiqhVerdict.evidenceUnresolved => null,
  };
}

FiqhReportInsights reportInsights(
  CanonicalInputs c,
  Madhhab? m,
  DateTime now, {
  List<CycleLog> legacyLogs = const [],
}) => FiqhReportInsightsEngine.analyze(
  cycleLogs: legacyLogs,
  madhhab: m,
  now: now,
  canonical: ReportCanonicalEvidence(
    effectiveLogs: c.logs,
    episodes: c.timing,
    hasOpenEpisode: c.hasOpenEpisode,
    evidenceUnresolved: c.evidenceUnresolved,
  ),
);

/// The report's state in the dashboard's vocabulary (the report shows
/// "insufficient" for both unresolved and insufficient verdicts).
String reportLabel(CanonicalInputs c, Madhhab? m, DateTime now) {
  final r = reportInsights(c, m, now);
  final s = r.cycleState!;
  return s == FiqhCycleState.insufficientHistory
      ? 'insufficientHistory'
      : s.name;
}

String dashboardInReportVocabulary(String label) =>
    label == 'evidenceUnresolved' ? 'insufficientHistory' : label;

String aiInDashboardVocabulary(String? label) => label ?? 'evidenceUnresolved';
