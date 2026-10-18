import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/controllers/cycle_tracking_controller.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/repositories/cycle_tracking_repository.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/cycle_tracking/presentation/viewmodels/cycle_tracking_view_model.dart';
import 'package:niswah/features/cycle_tracking/presentation/widgets/predicted_range_text.dart';
import 'package:niswah/features/insights/presentation/screens/insights_screen.dart';
import 'package:niswah/features/notifications/domain/services/notification_scheduler.dart';

import 'support/parity_test_harness.dart';

CycleBaseline _baseline({int? cycle, int? period}) => CycleBaseline(
  userId: 'user_1',
  usualCycleLengthDays: cycle,
  usualBleedingDurationDays: period,
);

var _nextId = 0;

/// One log per bleeding day for each period start, then a Tahara log the
/// day after it ends.
List<CycleLog> _history(List<DateTime> starts, {int days = 5}) => [
  for (final start in starts) ...[
    for (var i = 0; i < days; i++)
      CycleLog(
        id: '${_nextId++}',
        userId: 'local-user',
        date: DateTime(start.year, start.month, start.day + i),
        flow: FlowLevel.medium,
        cycleDay: i + 1,
      ),
    CycleLog(
      id: '${_nextId++}',
      userId: 'local-user',
      date: DateTime(start.year, start.month, start.day + days),
      flow: FlowLevel.none,
      cycleDay: days + 1,
    ),
  ],
];

class _FakeRepository implements CycleTrackingRepository {
  _FakeRepository(this.logs);
  final List<CycleLog> logs;

  @override
  Future<List<CycleLog>> getCycleLogs({
    DateTime? from,
    DateTime? to,
    int limit = 200,
  }) async => logs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('predictFromIntervals with her stated cycle length', () {
    test('no logged cycle: her estimate alone, with a wider spread', () {
      final prediction = CycleCalculationService.predictFromIntervals(
        const [],
        statedCycleLength: 30,
      );
      expect(prediction?.length, 30);
      expect(prediction?.spreadDays, 4);
      expect(prediction?.basis, PredictionBasis.statedEstimate);
    });

    test('no logged cycle and no estimate: nothing', () {
      expect(CycleCalculationService.predictFromIntervals(const []), isNull);
    });

    test('one logged cycle counts 1/3, the estimate 2/3', () {
      final prediction = CycleCalculationService.predictFromIntervals(const [
        28,
      ], statedCycleLength: 35);
      // 28 × 1/3 + 35 × 2/3 = 32.7
      expect(prediction?.length, 33);
      expect(prediction?.basis, PredictionBasis.historyAndEstimate);
    });

    test('three logged cycles count 3/5', () {
      final prediction = CycleCalculationService.predictFromIntervals(const [
        28,
        28,
        28,
      ], statedCycleLength: 35);
      // 28 × 3/5 + 35 × 2/5 = 30.8
      expect(prediction?.length, 31);
    });

    test('six logged cycles: the estimate is no longer used', () {
      final prediction = CycleCalculationService.predictFromIntervals(const [
        28,
        28,
        28,
        28,
        28,
        28,
      ], statedCycleLength: 35);
      expect(prediction?.length, 28);
      expect(prediction?.basis, PredictionBasis.history);
    });

    test('an implausible estimate is ignored', () {
      expect(
        CycleCalculationService.statedCycleLength(_baseline(cycle: 10)),
        isNull,
      );
      expect(
        CycleCalculationService.statedCycleLength(_baseline(cycle: 120)),
        isNull,
      );
      expect(
        CycleCalculationService.statedCycleLength(_baseline(cycle: 29)),
        29,
      );
    });
  });

  group('calculate with a stated baseline', () {
    const service = CycleCalculationService();

    test('one logged start predicts from the estimate, but no statistic '
        'is fabricated', () {
      final result = service.calculate(
        _history([DateTime(2026, 10, 1)]),
        asOf: DateTime(2026, 10, 10),
        statedBaseline: _baseline(cycle: 30, period: 6),
      );
      expect(result.canPredict, isTrue);
      expect(result.canPredictFromHistory, isFalse);
      expect(result.predictedCycleLength, 30);
      expect(result.averageCycleLength, isNull);
      expect(result.currentCycleDay, isNull);
      // Her logged period (5 days) wins over the stated 6.
      expect(result.averagePeriodLength, 5);
      expect(result.predictedPeriodLength, 5);
    });

    test('stated period length is used only when none is logged', () {
      final result = service.calculate(
        [
          CycleLog(
            id: 'start',
            userId: 'user_1',
            date: DateTime(2026, 10, 1),
            flow: FlowLevel.medium,
            cycleDay: 1,
          ),
        ],
        asOf: DateTime(2026, 10, 2),
        statedBaseline: _baseline(cycle: 30, period: 6),
      );
      expect(result.averagePeriodLength, isNull);
      expect(result.predictedPeriodLength, 6);
    });

    test('without a baseline nothing changes', () {
      final result = service.calculate(
        _history([DateTime(2026, 10, 1)]),
        asOf: DateTime(2026, 10, 10),
      );
      expect(result.canPredict, isFalse);
      expect(result.predictionBasis, isNull);
    });
  });

  group('summarizeHistory next-period range', () {
    const controller = CycleTrackingController();
    // Last of three 28-day cycles starts Oct 1; next expected Oct 29.
    final regular = _history([
      DateTime(2026, 7, 9),
      DateTime(2026, 8, 6),
      DateTime(2026, 9, 3),
      DateTime(2026, 10, 1),
    ]);

    test('regular history: 2 days early to 3 days late', () {
      final summary = controller.summarizeHistory(
        regular,
        now: DateTime(2026, 10, 10, 15),
      );
      expect(summary.nextPeriodStart, DateTime(2026, 10, 29));
      expect(
        summary.nextPeriodRange,
        PredictedDateRange(
          earliest: DateTime(2026, 10, 27),
          latest: DateTime(2026, 11, 1),
        ),
      );
      expect(summary.predictionBasis, PredictionBasis.history);
    });

    test('never starts before today', () {
      final summary = controller.summarizeHistory(
        regular,
        now: DateTime(2026, 10, 28),
      );
      expect(summary.nextPeriodRange?.earliest, DateTime(2026, 10, 28));
      expect(summary.nextPeriodRange?.latest, DateTime(2026, 11, 1));
    });

    test('late within the window: from today', () {
      final summary = controller.summarizeHistory(
        regular,
        now: DateTime(2026, 10, 31),
      );
      expect(summary.daysLate, 2);
      expect(summary.nextPeriodRange?.earliest, DateTime(2026, 10, 31));
      expect(summary.nextPeriodRange?.latest, DateTime(2026, 11, 1));
    });

    test('clearly late: no range', () {
      final summary = controller.summarizeHistory(
        regular,
        now: DateTime(2026, 11, 5),
      );
      expect(summary.nextPeriodRange, isNull);
      expect(summary.nextPeriodStart, isNull);
    });

    test('a short history is pulled toward her estimate and says so', () {
      final summary = controller.summarizeHistory(
        _history([DateTime(2026, 9, 3), DateTime(2026, 10, 1)]),
        now: DateTime(2026, 10, 10),
        statedBaseline: _baseline(cycle: 31),
      );
      // 28 × 1/3 + 31 × 2/3 = 30 → Oct 31, spread 3: Oct 28 – Nov 5.
      expect(summary.predictedCycleLength, 30);
      expect(summary.nextPeriodStart, DateTime(2026, 10, 31));
      expect(
        summary.nextPeriodRange,
        PredictedDateRange(
          earliest: DateTime(2026, 10, 28),
          latest: DateTime(2026, 11, 5),
        ),
      );
      expect(summary.predictionBasis, PredictionBasis.historyAndEstimate);
      expect(summary.fertileWindow.peakDay, isNotNull);
    });

    test('estimate alone: only a labeled range, nothing presented as her '
        'pattern', () {
      final summary = controller.summarizeHistory(
        _history([DateTime(2026, 10, 1)]),
        now: DateTime(2026, 10, 10),
        statedBaseline: _baseline(cycle: 30),
      );
      // Expected Oct 31, spread 4: Oct 27 – Nov 6.
      expect(
        summary.nextPeriodRange,
        PredictedDateRange(
          earliest: DateTime(2026, 10, 27),
          latest: DateTime(2026, 11, 6),
        ),
      );
      expect(summary.predictionBasis, PredictionBasis.statedEstimate);
      expect(summary.nextPeriodStart, isNull);
      expect(summary.predictedCycleLength, isNull);
      expect(summary.hasPlausibleAverage, isFalse);
      expect(summary.fertileWindow.start, isNull);
      expect(summary.fertileWindow.peakDay, isNull);
    });

    test('estimate alone, clearly late: nothing', () {
      final summary = controller.summarizeHistory(
        _history([DateTime(2026, 10, 1)]),
        now: DateTime(2026, 11, 10),
        statedBaseline: _baseline(cycle: 30),
      );
      expect(summary.nextPeriodRange, isNull);
      expect(summary.predictionBasis, isNull);
    });
  });

  test('no reminder is scheduled from her estimate alone', () {
    // Two starts 10 days apart: no usable logged cycle, so only the
    // estimate could predict.
    final calculation = const CycleCalculationService().calculate(
      [
        ..._history([DateTime(2026, 10, 1)], days: 3),
        ..._history([DateTime(2026, 10, 11)], days: 3),
      ],
      asOf: DateTime(2026, 10, 12),
      statedBaseline: _baseline(cycle: 30),
    );
    expect(calculation.hasSufficientHistory, isTrue);
    expect(calculation.predictionBasis, PredictionBasis.statedEstimate);
    expect(
      NotificationScheduler.planCycleReminder(
        calculation: calculation,
        now: DateTime(2026, 10, 12),
      ),
      isNull,
    );
  });

  test('range and basis labels', () {
    final range = PredictedDateRange(
      earliest: DateTime(2026, 10, 27),
      latest: DateTime(2026, 11, 1),
    );
    expect(formatPredictedRange(range, isArabic: false), '27 Oct – 1 Nov');
    expect(formatPredictedRange(range, isArabic: true), '27 أكتوبر – 1 نوفمبر');
    expect(
      predictionBasisNote(PredictionBasis.statedEstimate, isArabic: false),
      'Based on the estimate you gave us',
    );
    expect(predictionBasisNote(PredictionBasis.history, isArabic: false), null);
  });

  testWidgets('Insights shows the estimate range, labeled, after one logged '
      'start', (tester) async {
    // ParityTestHarness pins AppClock to 2026-08-18 12:00.
    final vm = CycleTrackingViewModel(
      repository: _FakeRepository(_history([DateTime(2026, 8, 10)])),
      canonicalEpisodeLoader: (_) async => const [],
      statedBaselineLoader: (_) async => _baseline(cycle: 30),
    );
    await ParityTestHarness.pump(
      tester,
      arabic: false,
      size: const Size(390, 4000),
      homeOverride: Scaffold(body: InsightsScreen(viewModel: vm)),
    );
    await vm.loadLogs();
    await tester.pumpAndSettle();

    // Expected Sep 9, spread 4: Sep 5 – Sep 15.
    expect(find.text('5 Sep – 15 Sep'), findsOneWidget);
    expect(find.text('Based on the estimate you gave us'), findsOneWidget);
  });
}
