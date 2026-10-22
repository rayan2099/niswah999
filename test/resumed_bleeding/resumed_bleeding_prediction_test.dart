// Resumed bleeding (2026-10-22, proposed): bleeding that resumes after a
// short clean gap is uncertain for PREDICTIONS only. It never moves the
// prediction anchor and never becomes a learned cycle interval; every
// logged date stays in the record and the fiqh engine is untouched (see
// resumed_bleeding_fiqh_parity_test.dart). Synthetic histories only.
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/utils/calendar_days.dart';
import 'package:niswah/features/cycle_tracking/domain/controllers/cycle_tracking_controller.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/notifications/domain/services/notification_scheduler.dart';

var _id = 0;

final _origin = DateTime(2026, 1, 1);
DateTime _d(int offset) => addCalendarDays(_origin, offset);

CycleLog _log(int offset, FlowLevel flow) => CycleLog(
  id: 'r${_id++}',
  userId: 'local-user',
  date: _d(offset),
  flow: flow,
  cycleDay: 2,
);

/// Bleeding on [from]..[to] (inclusive day offsets), then a clean day.
List<CycleLog> _period(int from, int to) => [
  for (var i = from; i <= to; i++) _log(i, FlowLevel.medium),
  _log(to + 1, FlowLevel.none),
];

const _service = CycleCalculationService();
const _controller = CycleTrackingController();

CycleCalculationResult _calc(
  List<CycleLog> logs,
  int today, {
  List<CanonicalEpisodeTiming> canonical = const [],
  CycleBaseline? baseline,
}) => _service.calculate(
  logs,
  asOf: _d(today),
  canonicalEpisodes: canonical,
  statedBaseline: baseline,
);

CycleTrackingSummary _summary(CycleCalculationResult c, int today) =>
    _controller.summarizeCalculation(c, today: _d(today));

/// Regular 28-day cycles, five bleeding days each, starting at 0, 28, 56.
List<CycleLog> _regular() => [
  ..._period(0, 4),
  ..._period(28, 32),
  ..._period(56, 60),
];

void main() {
  group('one-day gap', () {
    // Bleeding 56-60, clean 61, bleeding again 62-63, clean 64.
    final withGap = [..._regular(), ..._period(62, 63)];

    test('does not move the next-period date, range, fertile window, cycle '
        'day or reminder compared with the same history without the gap', () {
      const today = 66;
      final base = _calc(_regular(), today);
      final gap = _calc(withGap, today);
      final baseSummary = _summary(base, today);
      final gapSummary = _summary(gap, today);

      expect(baseSummary.nextPeriodStart, _d(84));
      expect(gapSummary.nextPeriodStart, baseSummary.nextPeriodStart);
      expect(gapSummary.nextPeriodRange, baseSummary.nextPeriodRange);
      expect(gapSummary.fertileWindow, baseSummary.fertileWindow);
      expect(gapSummary.lastCycleStart, _d(56));
      expect(gapSummary.predictedCycleLength, baseSummary.predictedCycleLength);
      expect(gapSummary.currentPhase, baseSummary.currentPhase);
      expect(gapSummary.daysLate, baseSummary.daysLate);
      expect(gap.predictionCycleDay, base.currentCycleDay);
      expect(gap.canPredictFromHistory, isTrue);

      final now = _d(today).add(const Duration(hours: 9));
      expect(
        NotificationScheduler.planCycleReminder(calculation: gap, now: now),
        NotificationScheduler.planCycleReminder(calculation: base, now: now),
      );
    });

    test('keeps every logged date in the record (read-side only)', () {
      final gap = _calc(withGap, 66);
      // The resumption is still a detected start for the fiqh engine...
      expect(gap.haidStarts, [_d(0), _d(28), _d(56), _d(62)]);
      expect(gap.lastHaidStart, _d(62));
      expect(gap.currentCycleDay, 5);
      expect(gap.cycleLengths, [28, 28, 6]);
      // ...but not a confirmed cycle start for predictions.
      expect(gap.predictionCycleStarts, [_d(0), _d(28), _d(56)]);
      expect(gap.uncertainCycleStarts, [_d(62)]);
      expect(gap.predictionCycleLengths, [28, 28]);
      expect(gap.predictionCycleDay, 11);
    });

    test('canonical episodes (canonical calendar, view model) behave the '
        'same', () {
      // end_date is the first day without bleeding.
      final base = [
        CanonicalEpisodeTiming(startDate: _d(0), endDate: _d(5)),
        CanonicalEpisodeTiming(startDate: _d(28), endDate: _d(33)),
        CanonicalEpisodeTiming(startDate: _d(56), endDate: _d(61)),
      ];
      final withResumption = [
        ...base,
        CanonicalEpisodeTiming(startDate: _d(62), endDate: _d(64)),
      ];
      final a = _summary(_calc(const [], 66, canonical: base), 66);
      final b = _summary(_calc(const [], 66, canonical: withResumption), 66);
      expect(a.nextPeriodStart, _d(84));
      expect(b.nextPeriodStart, a.nextPeriodStart);
      expect(b.nextPeriodRange, a.nextPeriodRange);
      expect(b.lastCycleStart, _d(56));
    });
  });

  test('an interval with an uncertain boundary is excluded from learning, '
      'not merged into a longer one', () {
    // Starts 0, 28, resumption 33 (bleeding 28-31, clean 32), then 58 and 86.
    final logs = [
      ..._period(0, 4),
      ..._period(28, 31),
      ..._period(33, 34),
      ..._period(58, 62),
      ..._period(86, 90),
    ];
    final c = _calc(logs, 95);
    expect(c.cycleLengths, [28, 5, 25, 28]); // factual, unchanged
    expect(c.uncertainCycleStarts, [_d(33)]);
    expect(c.predictionCycleStarts, [_d(0), _d(28), _d(58), _d(86)]);
    // 28 -> 58 (30 days, spanning the uncertain start) is not learned.
    expect(c.predictionCycleLengths, [28, 28]);
    expect(c.predictedCycleLength, 28);
    expect(_summary(c, 95).nextPeriodStart, _d(114));
  });

  group('a genuine new period still counts', () {
    test('after a normal cycle', () {
      final c = _calc(_regular(), 66);
      expect(c.uncertainCycleStarts, isEmpty);
      expect(c.predictionCycleStarts, c.haidStarts);
      expect(c.predictionCycleLengths, c.cycleLengths);
      expect(_summary(c, 66).lastCycleStart, _d(56));
    });

    test('at the heuristic threshold, measured from the last confirmed '
        'start', () {
      expect(CycleCalculationService.resumedBleedingPredictionWindowDays, 15);
      // 15 days after the last confirmed start is a confirmed start; 14 days
      // after it is uncertain.
      final at15 = _calc([..._period(0, 4), ..._period(15, 17)], 25);
      expect(at15.predictionCycleStarts, [_d(0), _d(15)]);
      final at14 = _calc([..._period(0, 4), ..._period(14, 16)], 25);
      expect(at14.predictionCycleStarts, [_d(0)]);
      expect(at14.uncertainCycleStarts, [_d(14)]);
    });

    test('a genuine short cycle with a longer period is never uncertain', () {
      // 18-day cycles with 7 bleeding days: an 11-day clean gap, but each
      // start is a plausible cycle after the last one.
      final c = _calc([
        ..._period(0, 6),
        ..._period(18, 24),
        ..._period(36, 42),
      ], 45);
      expect(c.uncertainCycleStarts, isEmpty);
      expect(c.predictedCycleLength, 18);
      expect(_summary(c, 45).nextPeriodStart, _d(54));
    });

    test('repeated resumptions are all measured from the confirmed start', () {
      // Start 0; bleeding resumes at 6 and again at 12; next period at 28.
      final c = _calc([
        ..._period(0, 4),
        ..._period(6, 7),
        ..._period(12, 13),
        ..._period(28, 32),
      ], 35);
      expect(c.uncertainCycleStarts, [_d(6), _d(12)]);
      expect(c.predictionCycleStarts, [_d(0), _d(28)]);
      expect(c.predictionCycleLengths, isEmpty);
    });
  });

  group('too few confirmed intervals', () {
    // Bleeding 0-2, clean 3, resumes 4-5, clean 6; next period at 29.
    final logs = [..._period(0, 2), ..._period(4, 5), ..._period(29, 32)];

    test('falls back to no prediction', () {
      final c = _calc(logs, 35);
      expect(c.cycleLengths, [4, 25]);
      expect(c.averageCycleLength, 15); // the factual gate alone would pass
      expect(c.predictionCycleLengths, isEmpty);
      expect(c.canPredictFromHistory, isFalse);
      final s = _summary(c, 35);
      expect(s.nextPeriodStart, isNull);
      expect(s.nextPeriodRange, isNull);
      expect(s.fertileWindow.start, isNull);
      expect(s.hasPlausibleAverage, isFalse);
      expect(
        NotificationScheduler.planCycleReminder(
          calculation: c,
          now: _d(35).add(const Duration(hours: 9)),
        ),
        isNull,
      );
    });

    test('falls back to the stated-estimate range when she gave one', () {
      final c = _calc(
        logs,
        35,
        baseline: const CycleBaseline(
          userId: 'local-user',
          usualCycleLengthDays: 28,
          usualBleedingDurationDays: 5,
        ),
      );
      final s = _summary(c, 35);
      expect(c.predictionBasis, PredictionBasis.statedEstimate);
      expect(s.predictionBasis, PredictionBasis.statedEstimate);
      expect(s.nextPeriodStart, isNull);
      expect(s.lastCycleStart, _d(29));
      expect(s.nextPeriodRange, isNotNull);
    });
  });
}
