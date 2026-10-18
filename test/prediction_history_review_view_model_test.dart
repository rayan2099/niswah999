import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/utils/app_clock.dart';
import 'package:niswah/core/utils/calendar_day.dart';
import 'package:niswah/features/cycle_tracking/data/local/prediction_history_review_store.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/period_prediction.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/prediction_history_review.dart';
import 'package:niswah/features/cycle_tracking/domain/repositories/cycle_tracking_repository.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/cycle_tracking/presentation/viewmodels/cycle_tracking_view_model.dart';

class _ReadOnlyRepository implements CycleTrackingRepository {
  @override
  Future<List<CycleLog>> getCycleLogs({
    DateTime? from,
    DateTime? to,
    int limit = 200,
  }) async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No health-record writes are expected');
}

void main() {
  late List<CanonicalEpisodeTiming> episodes;
  late PredictionHistoryReviewStore store;
  late Map<String, String> disk;
  var canonicalLoads = 0;
  final today = DateTime(2026, 10, 1, 12);
  setUp(() {
    AppClock.now = () => today;
    var date = DateTime(2026, 10, 1);
    final starts = [date];
    for (final length in [28, 29, 200, 28]) {
      date = addCalendarDays(date, -length);
      starts.insert(0, date);
    }
    episodes = [
      for (final start in starts)
        CanonicalEpisodeTiming(
          startDate: start,
          endDate: addCalendarDays(start, 5),
        ),
    ];
    disk = {};
    canonicalLoads = 0;
    store = PredictionHistoryReviewStore(
      read: (owner) async => disk[owner],
      write: (owner, raw) async {
        disk[owner] = raw;
      },
    );
  });
  tearDown(() => AppClock.reset());

  CycleTrackingViewModel model({PredictionHistoryReviewStore? override}) =>
      CycleTrackingViewModel(
        repository: _ReadOnlyRepository(),
        predictionReviewStore: override ?? store,
        canonicalEpisodeLoader: (_) async {
          canonicalLoads++;
          return episodes;
        },
      );

  test(
    'saved gap answers recalculate predictions and survive model recreation',
    () async {
      final vm = model();
      await vm.loadLogs();
      expect(
        vm.summary.periodPrediction.reviewReason,
        PredictionReviewReason.unexplainedGap,
      );
      final gap = vm.summary.periodPrediction.reviewGaps.single;
      await vm.savePredictionHistoryReview(
        PredictionHistoryReview(
          start: gap.start,
          end: gap.end,
          resolution: PredictionGapResolution.unsure,
          reportedAt: today.toUtc(),
        ),
      );
      expect(vm.summary.periodPrediction.hasFutureEstimate, isTrue);
      expect(
        canonicalLoads,
        2,
        reason: 'one initial load and one completed save refresh',
      );
      expect(vm.summary.periodPrediction.intervalCount, 2);
      expect(vm.canonicalEpisodes.length, 5);
      vm.dispose();
      final reopened = model();
      await reopened.loadLogs();
      expect(reopened.summary.periodPrediction.hasFutureEstimate, isTrue);
      expect(reopened.summary.periodPrediction.intervalCount, 2);
      reopened.dispose();
    },
  );
  test('an unavailable review store withholds predictions while keeping actual records', () async {
    final vm = model(
      override: PredictionHistoryReviewStore(
        read: (_) async => throw StateError('unavailable'),
        write: (_, _) async {},
      ),
    );
    await vm.loadLogs();
    expect(
      vm.summary.periodPrediction.reviewReason,
      PredictionReviewReason.unverifiedHistory,
    );
    expect(vm.summary.nextPeriodStart, isNull);
    expect(vm.summary.fertileWindow.peakDay, isNull);
    expect(vm.canonicalEpisodes.length, 5);
    vm.dispose();
  });
  test(
    'overlapping history saves do not start duplicate writes or refreshes',
    () async {
      final vm = model();
      await vm.loadLogs();
      final gap = vm.summary.periodPrediction.reviewGaps.single;
      final review = PredictionHistoryReview(
        start: gap.start,
        end: gap.end,
        resolution: PredictionGapResolution.unsure,
        reportedAt: today.toUtc(),
      );
      final first = vm.savePredictionHistoryReview(review);
      final duplicate = expectLater(
        vm.savePredictionHistoryReview(review),
        throwsStateError,
      );
      await Future.wait([first, duplicate]);
      expect(vm.summary.periodPrediction.hasFutureEstimate, isTrue);
      expect(canonicalLoads, 2);
      vm.dispose();
    },
  );

  test(
    'an edited history cannot accept an answer from the old interval',
    () async {
      final vm = model();
      await vm.loadLogs();
      final gap = vm.summary.periodPrediction.reviewGaps.single;
      episodes = [
        for (final episode in episodes)
          CanonicalEpisodeTiming(
            startDate: addCalendarDays(episode.startDate, -1),
            endDate: episode.endDate,
          ),
      ];
      await vm.loadLogs();
      await expectLater(
        vm.savePredictionHistoryReview(
          PredictionHistoryReview(
            start: gap.start,
            end: gap.end,
            resolution: PredictionGapResolution.missedRecords,
            reportedAt: today.toUtc(),
          ),
        ),
        throwsStateError,
      );
      expect(disk, isEmpty);
      vm.dispose();
    },
  );
}
