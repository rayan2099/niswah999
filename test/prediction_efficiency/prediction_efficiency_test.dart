import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/utils/app_clock.dart';
import 'package:niswah/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:niswah/features/auth/domain/entities/app_user.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/load_result.dart';
import 'package:niswah/features/cycle_tracking/domain/controllers/cycle_tracking_controller.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/repositories/cycle_tracking_repository.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/cycle_tracking/presentation/screens/cycle_tracking_screen.dart';
import 'package:niswah/features/cycle_tracking/presentation/viewmodels/cycle_tracking_view_model.dart';
import 'package:niswah/features/notifications/domain/services/notification_scheduler.dart';
import 'package:niswah/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secure_storage_test_support.dart';

/// Prediction-efficiency audit (2026-10-21, proposed). Synthetic histories
/// only. The DST case is meaningful under `TZ=Europe/London` and skipped
/// in zones without a spring-forward on 31 March 2024.

var _nextId = 0;

CycleLog _log(DateTime date, FlowLevel flow, {int cycleDay = 2}) => CycleLog(
  id: '${_nextId++}',
  userId: 'local-user',
  date: date,
  flow: flow,
  cycleDay: cycleDay,
);

/// [days] bleeding days from each start, then a Tahara day.
List<CycleLog> _history(List<DateTime> starts, {int days = 4}) => [
  for (final start in starts) ...[
    for (var i = 0; i < days; i++)
      _log(
        DateTime(start.year, start.month, start.day + i),
        FlowLevel.medium,
        cycleDay: i + 1,
      ),
    _log(
      DateTime(start.year, start.month, start.day + days),
      FlowLevel.none,
      cycleDay: days + 1,
    ),
  ],
];

class _FakeRepository implements CycleTrackingRepository {
  _FakeRepository(this.logs);
  final List<CycleLog> logs;
  final limits = <int>[];

  @override
  Future<List<CycleLog>> getCycleLogs({
    DateTime? from,
    DateTime? to,
    int limit = 200,
  }) async {
    limits.add(limit);
    return logs;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SignedInAuth implements AuthRepositoryImpl {
  @override
  Future<AppUser?> get currentUser async =>
      const AppUser(id: 'user-1', email: 'user@example.com');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EpisodeRepository extends BleedingEpisodeRepositoryImpl {
  _EpisodeRepository(this.episodes, {this.quarantined = 0})
    : super(client: null);
  final List<BleedingEpisode> episodes;
  final int quarantined;

  @override
  Future<LoadResult<List<BleedingEpisode>>> getEpisodesForUser(
    String userId,
  ) async => quarantined > 0
      ? LoadDegraded(episodes, quarantined)
      : LoadSuccess(episodes);
}

BleedingEpisode _ended(String id, DateTime start, DateTime end) =>
    BleedingEpisode(
      id: id,
      userId: 'user-1',
      lifecycleStatus: LifecycleStatus.ended,
      startDate: start,
      startPrecision: ObservationPrecision.dateOnly,
      startSource: ObservationSource.userObserved,
      endDate: end,
      endPrecision: ObservationPrecision.dateOnly,
      endSource: ObservationSource.userObserved,
    );

class _CountingCalculationService extends CycleCalculationService {
  _CountingCalculationService();
  int calls = 0;

  @override
  CycleCalculationResult calculate(
    List<CycleLog> logs, {
    DateTime? asOf,
    List<CanonicalEpisodeTiming> canonicalEpisodes = const [],
    CycleBaseline? statedBaseline,
  }) {
    calls++;
    return super.calculate(
      logs,
      asOf: asOf,
      canonicalEpisodes: canonicalEpisodes,
      statedBaseline: statedBaseline,
    );
  }
}

class _CountingSecureStorage extends TestFlutterSecureStoragePlatform {
  _CountingSecureStorage() : super({});
  int cycleLogReads = 0;

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) {
    if (key.startsWith('cycle_tracking_logs')) cycleLogReads++;
    return super.read(key: key, options: options);
  }
}

CycleTrackingViewModel _viewModel(
  List<CycleLog> logs, {
  CycleCalculationService service = const CycleCalculationService(),
}) => CycleTrackingViewModel(
  repository: _FakeRepository(logs),
  canonicalEpisodeLoader: (_) async => const [],
  statedBaselineLoader: (_) async => null,
  calculationService: service,
);

List<String> _texts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .where((s) => s.trim().isNotEmpty)
    .toList();

String _metric(WidgetTester tester, String label) {
  final texts = _texts(tester);
  return texts[texts.indexOf(label) + 1];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSecureLocalStoreForTest();
    AppLocaleController.instance.setArabic(false);
  });

  tearDown(() => AppClock.now = DateTime.now);

  group('the view model computes the cycle calculation once per load', () {
    test('every read of cycleCalculation and summary on the same day reuses '
        'one calculation', () async {
      AppClock.now = () => DateTime(2026, 8, 18, 12);
      final service = _CountingCalculationService();
      final vm = _viewModel(
        _history([DateTime(2026, 6, 23), DateTime(2026, 7, 21)]),
        service: service,
      );
      await vm.loadLogs();
      // Before: loadLogs ran it once for the summary, and every read of
      // cycleCalculation (Today, the Calendar tab and Insights, on every
      // rebuild) ran it again.
      expect(service.calls, 1);
      final first = vm.cycleCalculation;
      for (var i = 0; i < 10; i++) {
        expect(identical(vm.cycleCalculation, first), isTrue);
        vm.summary;
      }
      expect(service.calls, 1);
      expect(first.currentCycleDay, 29);
      expect(vm.summary.nextPeriodStart, DateTime(2026, 8, 18));

      // A new calendar day: the cycle day and the summary move on.
      AppClock.now = () => DateTime(2026, 8, 19, 9);
      expect(vm.cycleCalculation.currentCycleDay, 30);
      expect(vm.summary.nextPeriodStart, DateTime(2026, 8, 19));
      expect(service.calls, 2);

      // A reload computes from the new data.
      await vm.loadLogs();
      expect(service.calls, 3);
    });

    test(
      'the Calendar tab month summary is cached per range and day',
      () async {
        AppClock.now = () => DateTime(2026, 8, 18, 12);
        final service = _CountingCalculationService();
        final vm = _viewModel(
          _history([DateTime(2026, 6, 23), DateTime(2026, 7, 21)]),
          service: service,
        );
        await vm.loadLogs();
        final calls = service.calls;
        final july = vm.calculationUpTo(
          lastDay: DateTime(2026, 7, 31),
          asOf: DateTime(2026, 7, 31),
        );
        for (var i = 0; i < 5; i++) {
          expect(
            identical(
              vm.calculationUpTo(
                lastDay: DateTime(2026, 7, 31),
                asOf: DateTime(2026, 7, 31, 18),
              ),
              july,
            ),
            isTrue,
          );
        }
        expect(service.calls, calls + 1);
        expect(july.haidStarts, [DateTime(2026, 6, 23), DateTime(2026, 7, 21)]);
        final june = vm.calculationUpTo(
          lastDay: DateTime(2026, 6, 30),
          asOf: DateTime(2026, 6, 30),
        );
        expect(june.haidStarts, [DateTime(2026, 6, 23)]);
        expect(service.calls, calls + 2);
      },
    );
  });

  testWidgets('the home shell loads the shared cycle view model once at '
      'startup', (tester) async {
    AppClock.now = () => DateTime(2026, 8, 18, 12);
    final storage = _CountingSecureStorage();
    FlutterSecureStoragePlatform.instance = storage;

    // Reads one standalone load makes.
    await tester.runAsync(() => CycleTrackingViewModel().loadLogs());
    final readsPerLoad = storage.cycleLogReads;
    expect(readsPerLoad, greaterThan(0));
    storage.cycleLogReads = 0;

    await tester.pumpWidget(const MaterialApp(home: NiswahHomeShell()));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Before: the shell loaded it and the Today screen (always mounted in
    // the IndexedStack) loaded it again — every startup read twice.
    expect(storage.cycleLogReads, readsPerLoad);
  });

  group('degraded canonical history and the history window', () {
    final episodes = [
      _ended('a', DateTime(2026, 6, 23), DateTime(2026, 6, 28)),
      _ended('b', DateTime(2026, 7, 21), DateTime(2026, 7, 26)),
    ];

    Future<CycleTrackingViewModel> load({int quarantined = 0}) async {
      AppClock.now = () => DateTime(2026, 8, 10, 12);
      final vm = CycleTrackingViewModel(
        repository: _FakeRepository(const []),
        authRepository: _SignedInAuth(),
        statedBaselineLoader: (_) async => null,
        bleedingEpisodeRepository: _EpisodeRepository(
          episodes,
          quarantined: quarantined,
        ),
      );
      await vm.loadLogs();
      return vm;
    }

    test('a clean read predicts (control)', () async {
      final vm = await load();
      expect(vm.canonicalHistoryComplete, isTrue);
      expect(vm.cycleCalculation.canPredictFromHistory, isTrue);
      expect(vm.summary.nextPeriodStart, DateTime(2026, 8, 18));
    });

    test('a degraded read (a quarantined row) predicts nothing, like the '
        'reminder and the canonical calendar, but keeps the logged '
        'statistics', () async {
      final vm = await load(quarantined: 1);
      expect(vm.canonicalHistoryComplete, isFalse);
      final calculation = vm.cycleCalculation;
      expect(calculation.canPredict, isFalse);
      expect(calculation.canPredictFromHistory, isFalse);
      expect(calculation.averageCycleLength, 28);
      expect(calculation.currentCycleDay, 21);
      expect(vm.summary.nextPeriodStart, isNull);
      expect(vm.summary.nextPeriodRange, isNull);
      expect(vm.summary.fertileWindow.peakDay, isNull);
      expect(vm.summary.hasPlausibleAverage, isFalse);
    });

    test('the view model reads the same history window as the reminder and '
        'reports', () async {
      final repository = _FakeRepository(const []);
      final vm = CycleTrackingViewModel(
        repository: repository,
        canonicalEpisodeLoader: (_) async => const [],
        statedBaselineLoader: (_) async => null,
      );
      await vm.loadLogs();
      expect(repository.limits, [CycleCalculationService.historyLogLimit]);
      expect(CycleCalculationService.historyLogLimit, 1000);
    });
  });

  group('one prediction gate everywhere', () {
    // Starts Jan 1, Jan 4 (re-logged as a new start) and Jan 24: intervals
    // 3 and 20, plain average 12 days. Today and Insights already showed
    // nothing; the Calendar tab, husband report, canonical calendar and the
    // reminder still predicted Feb 13 from the 20-day interval alone.
    final logs = [
      _log(DateTime(2026, 1, 1), FlowLevel.medium, cycleDay: 1),
      _log(DateTime(2026, 1, 4), FlowLevel.medium, cycleDay: 1),
      _log(DateTime(2026, 1, 7), FlowLevel.none),
      _log(DateTime(2026, 1, 24), FlowLevel.medium, cycleDay: 1),
      _log(DateTime(2026, 1, 28), FlowLevel.none),
    ];
    final now = DateTime(2026, 1, 30, 12);

    test('an implausible average predicts nothing, in the summary and the '
        'reminder alike', () {
      final calculation = const CycleCalculationService().calculate(
        logs,
        asOf: now,
      );
      expect(calculation.cycleLengths, [3, 20]);
      expect(calculation.hasPlausibleAverage, isFalse);
      expect(calculation.canPredictFromHistory, isFalse);

      final summary = const CycleTrackingController().summarizeHistory(
        logs,
        now: now,
      );
      expect(summary.nextPeriodStart, isNull);
      expect(summary.nextPeriodRange, isNull);
      expect(summary.hasPlausibleAverage, isFalse);
      expect(summary.fertileWindow.peakDay, isNull);

      expect(
        NotificationScheduler.planCycleReminder(
          calculation: calculation,
          now: now,
        ),
        isNull,
      );
    });

    test('a plausible history still predicts (control)', () {
      final regular = [...logs.where((l) => l.date != DateTime(2026, 1, 4))];
      final summary = const CycleTrackingController().summarizeHistory(
        regular,
        now: now,
      );
      expect(summary.nextPeriodStart, isNotNull);
    });
  });

  group('Calendar tab summaries count calendar days', () {
    Future<void> pumpCalendarTab(
      WidgetTester tester,
      CycleTrackingViewModel vm,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 4000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CycleTrackingScreen(viewModel: vm)),
        ),
      );
      await vm.loadLogs();
      await tester.pumpAndSettle();
    }

    final springForwardOnMarch31 =
        DateTime(2024, 3, 31).add(const Duration(days: 1)).hour != 0;

    testWidgets(
      'a month ending on a spring-forward day does not count the next '
      "month's first day",
      (tester) async {
        AppClock.now = () => DateTime(2024, 4, 10, 12);
        final vm = _viewModel(
          _history([
            DateTime(2024, 2, 1),
            DateTime(2024, 3, 1),
            DateTime(2024, 4, 1),
          ]),
        );
        await pumpCalendarTab(tester, vm);
        await tester.tap(find.byTooltip('Previous month'));
        await tester.pumpAndSettle();

        // March: bleeding Mar 1-4 only. The range end used to be
        // `31 Mar + 24 h` = 1 Apr 01:00, so 1 April's log (and its cycle
        // start) counted in March.
        expect(_metric(tester, 'TOTAL HAID DAYS'), '4');
        expect(_metric(tester, 'AVG CYCLE LENGTH'), '29');
      },
      skip: !springForwardOnMarch31,
    );

    testWidgets("the custom '30 days' preset includes its first day", (
      tester,
    ) async {
      AppClock.now = () => DateTime(2026, 8, 18, 12);
      // The 30 days ending Aug 18 start on Jul 20, the first day of a period.
      final vm = _viewModel(
        _history([DateTime(2026, 6, 20), DateTime(2026, 7, 20)], days: 2),
      );
      await pumpCalendarTab(tester, vm);
      await tester.tap(find.text('Custom period'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('30 days'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apply-custom-summary-range')));
      await tester.pumpAndSettle();

      // Bleeding Jul 20 and 21. The preset used to start at "now − 29
      // days" with the clock time (Jul 20 12:00), so Jul 20's log fell
      // outside it.
      expect(_metric(tester, 'TOTAL HAID DAYS'), '2');
    });
  });
}
