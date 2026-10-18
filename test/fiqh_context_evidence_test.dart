import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/ai_advisor/client_fiqh_state_provider.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/load_result.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:niswah/features/cycle_tracking/domain/services/report_canonical_evidence.dart';
import 'package:niswah/features/fiqh_report/domain/services/fiqh_report_insights_engine.dart';

void main() {
  final now = DateTime(2026, 10, 17, 12);
  CycleLog log(DateTime date, FlowLevel flow) => CycleLog(
    id: date.toIso8601String(),
    userId: 'synthetic',
    date: date,
    flow: flow,
  );
  for (final episodes in <LoadResult<List<BleedingEpisode>>>[
    const LoadDegraded([], 1),
    const LoadUnavailable(LoadErrorCategory.network),
  ]) {
    test(
      '${episodes.runtimeType}: chat and reports both refuse a ruling',
      () async {
        final evidence = ReportCanonicalEvidence.fromResults(
          episodesResult: episodes,
          observationsResult: const LoadSuccess([]),
          now: now,
        );
        final provider = ClientFiqhStateProvider(
          evidenceLoader: (_) async => evidence,
          clock: () => now,
        );
        expect(
          await provider.currentClassification(Madhhab.hanafi),
          'insufficientHistory',
        );
        final report = FiqhReportInsightsEngine.analyze(
          cycleLogs: [log(DateTime(2026, 10, 1), FlowLevel.none)],
          canonical: evidence,
          madhhab: Madhhab.hanafi,
          now: now,
        );
        expect(report.cycleState, FiqhCycleState.insufficientHistory);
      },
    );
  }

  test('chat has no legacy fallback after a canonical read fails', () async {
    final provider = ClientFiqhStateProvider(
      evidenceLoader: (_) async => throw StateError('synthetic failure'),
      clock: () => now,
    );
    expect(await provider.currentClassification(Madhhab.hanafi), isNull);
  });
}
