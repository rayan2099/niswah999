import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/preferences/calendar_system_controller.dart';
import 'package:niswah/core/utils/app_clock.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/repositories/cycle_tracking_repository.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/cycle_tracking/presentation/viewmodels/cycle_tracking_view_model.dart';
import 'package:niswah/features/insights/domain/period_history.dart';
import 'package:niswah/features/insights/presentation/screens/insights_screen.dart';
import 'package:niswah/features/insights/presentation/widgets/period_history_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/parity_test_harness.dart';

/// TestFlight Feedback 2, page 5 ("سجل الدورة"). Synthetic data.
CycleLog _log(
  String id,
  DateTime date,
  FlowLevel flow, {
  int cycleDay = 1,
  List<String> symptoms = const [],
}) => CycleLog(
  id: id,
  userId: 'local-user',
  date: date,
  flow: flow,
  cycleDay: cycleDay,
  symptoms: symptoms,
);

final _oct27 = DateTime(2026, 10, 27);
final _oct30 = DateTime(2026, 10, 30);
final _today = DateTime(2026, 10, 31, 12);

class _Repo implements CycleTrackingRepository {
  _Repo(this.logs, {this.fail = false});
  final List<CycleLog> logs;
  final bool fail;
  @override
  Future<List<CycleLog>> getCycleLogs({
    DateTime? from,
    DateTime? to,
    int limit = 200,
  }) async {
    if (fail) throw StateError('offline');
    return logs;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<CycleTrackingViewModel> _pumpInsights(
  WidgetTester tester, {
  required List<CycleLog> logs,
  required List<CanonicalEpisodeTiming> episodes,
  bool arabic = true,
  bool fail = false,
  Size size = const Size(390, 4200),
  double textScale = 1,
}) async {
  final vm = CycleTrackingViewModel(
    repository: _Repo(logs, fail: fail),
    canonicalEpisodeLoader: (_) async => episodes,
  );
  await ParityTestHarness.pump(
    tester,
    arabic: arabic,
    size: size,
    homeOverride: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: Directionality(
          textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(body: InsightsScreen(viewModel: vm)),
        ),
      ),
    ),
  );
  AppClock.now = () => _today;
  await vm.loadLogs();
  await tester.pumpAndSettle();
  return vm;
}

void main() {
  group('buildPeriodHistory', () {
    test('page 5: the 30 Oct record is the period\'s first clean day, '
        'shown under the 27–29 Oct period, not as a separate "day 1"', () {
      final items = buildPeriodHistory(
        periods: [HistoryPeriodInput(startDate: _oct27, firstCleanDay: _oct30)],
        logs: [_log('closing', _oct30, FlowLevel.none)],
        today: _today,
      );
      expect(items, hasLength(1));
      final period = items.single as PeriodItem;
      expect(period.status, PeriodStatus.completed);
      expect(period.lengthDays, 3);
      expect(period.lastBleedingDay, DateTime(2026, 10, 29));
      expect(period.firstCleanDay, _oct30);
      expect(period.observations, hasLength(1));
      expect(period.observations.single.isFirstCleanDay, isTrue);
      expect(period.observations.single.log.id, 'closing');
    });

    test('every record appears exactly once; none is dropped or merged', () {
      final logs = [
        _log('d1', _oct27, FlowLevel.heavy),
        _log('d2', DateTime(2026, 10, 28), FlowLevel.medium, cycleDay: 2),
        _log('d2-again', DateTime(2026, 10, 28), FlowLevel.light, cycleDay: 2),
        _log('closing', _oct30, FlowLevel.none),
        _log('later-spotting', DateTime(2026, 11, 5), FlowLevel.spotting),
        _log(
          'symptoms',
          DateTime(2026, 9, 2),
          FlowLevel.none,
          symptoms: [CycleLog.symptomsOnlyMarker, 'cramps'],
        ),
      ];
      final items = buildPeriodHistory(
        periods: [HistoryPeriodInput(startDate: _oct27, firstCleanDay: _oct30)],
        logs: logs,
        today: DateTime(2026, 11, 6),
      );
      final ids = <String>[
        for (final item in items)
          ...switch (item) {
            final PeriodItem p => p.observations.map((o) => o.log.id),
            final StandaloneObservationItem s => [s.observation.log.id],
          },
      ];
      expect(ids..sort(), [for (final l in logs) l.id]..sort());
      // Newest first: the separate 5 Nov record, the period, the September note.
      expect(items[0], isA<StandaloneObservationItem>());
      expect(items[1], isA<PeriodItem>());
      final period = items[1] as PeriodItem;
      expect(period.observations.map((o) => o.dayOfPeriod), [1, 2, 2, null]);
      expect(
        (items[2] as StandaloneObservationItem).observation.kind,
        ObservationKind.symptomsOnly,
      );
    });

    test('ongoing and end-unknown periods', () {
      final items = buildPeriodHistory(
        periods: [
          HistoryPeriodInput(startDate: DateTime(2026, 10, 29)),
          HistoryPeriodInput(startDate: DateTime(2026, 9, 1), endUnknown: true),
        ],
        logs: [_log('today', DateTime(2026, 10, 31), FlowLevel.medium)],
        today: _today,
      );
      final ongoing = items[0] as PeriodItem;
      expect(ongoing.status, PeriodStatus.ongoing);
      expect(ongoing.currentDay, 3);
      expect(ongoing.observations.single.dayOfPeriod, 3);
      final unknown = items[1] as PeriodItem;
      expect(unknown.status, PeriodStatus.endUnknown);
      expect(unknown.lengthDays, isNull);
    });
  });

  group('Insights سجل الدورة', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await CalendarSystemController.instance.setHijri(false);
    });

    testWidgets('page 5 is no longer ambiguous', (tester) async {
      await _pumpInsights(
        tester,
        logs: [_log('closing', _oct30, FlowLevel.none)],
        episodes: [CanonicalEpisodeTiming(startDate: _oct27, endDate: _oct30)],
      );
      expect(find.text('يوم الدورة 1'), findsNothing);
      expect(find.textContaining('30/10/2026'), findsNothing);
      expect(find.text('27 – 29 أكتوبر 2026'), findsOneWidget);
      expect(find.text('مكتملة'), findsOneWidget);
      expect(find.textContaining('3 أيام نزول'), findsOneWidget);
      expect(find.textContaining('توقف النزول (أول يوم طهر)'), findsOneWidget);
      expect(find.text('تسجيل منفصل'), findsNothing);

      await tester.tap(find.byType(PeriodHistoryTile));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('period-history-details')), findsOneWidget);
      expect(find.text('آخر يوم نزول'), findsOneWidget);
      expect(find.text('29 أكتوبر 2026'), findsOneWidget);
      expect(find.text('أول يوم طهر'), findsOneWidget);
      expect(find.text('التعديل من التقويم'), findsOneWidget);
    });

    testWidgets('a record outside every period is labelled separate', (
      tester,
    ) async {
      await _pumpInsights(
        tester,
        logs: [_log('lone', DateTime(2026, 10, 12), FlowLevel.spotting)],
        episodes: [CanonicalEpisodeTiming(startDate: _oct27, endDate: _oct30)],
      );
      expect(find.text('تسجيل منفصل'), findsOneWidget);
      expect(find.text('ليس ضمن دورة مسجّلة'), findsOneWidget);
    });

    testWidgets('Hijri calendar, English digits', (tester) async {
      await CalendarSystemController.instance.setHijri(true);
      addTearDown(() => CalendarSystemController.instance.setHijri(false));
      await _pumpInsights(
        tester,
        logs: const [],
        episodes: [CanonicalEpisodeTiming(startDate: _oct27, endDate: _oct30)],
      );
      final title = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(PeriodHistoryTile),
              matching: find.byType(Text),
            ),
          )
          .first
          .data!;
      expect(title, contains('1448'));
      expect(title, isNot(contains('أكتوبر')));
      expect(RegExp(r'[٠-٩]').hasMatch(title), isFalse);
    });

    testWidgets('empty state inside Insights', (tester) async {
      await _pumpInsights(tester, logs: const [], episodes: const []);
      expect(find.byKey(const Key('period-history-empty')), findsOneWidget);
    });

    testWidgets('loading, error (with retry) and incomplete states', (
      tester,
    ) async {
      var retried = 0;
      Future<void> show(PeriodHistoryBody body) =>
          tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
      await show(
        PeriodHistoryBody(
          items: const [],
          isLoading: true,
          error: null,
          incomplete: false,
          onRetry: () {},
          onOpen: (_) {},
        ),
      );
      expect(find.byKey(const Key('period-history-loading')), findsOneWidget);

      await show(
        PeriodHistoryBody(
          items: const [],
          isLoading: false,
          error: 'offline',
          incomplete: false,
          onRetry: () => retried++,
          onOpen: (_) {},
        ),
      );
      expect(find.byKey(const Key('period-history-error')), findsOneWidget);
      await tester.tap(find.text('إعادة المحاولة'));
      expect(retried, 1);

      await show(
        PeriodHistoryBody(
          items: buildPeriodHistory(
            periods: [
              HistoryPeriodInput(startDate: _oct27, firstCleanDay: _oct30),
            ],
            logs: const [],
            today: _today,
          ),
          isLoading: false,
          error: null,
          incomplete: true,
          onRetry: () {},
          onOpen: (_) {},
        ),
      );
      expect(find.textContaining('قد تكون القائمة ناقصة'), findsOneWidget);
    });

    testWidgets(
      '320pt wide, text at 200%: the history list does not overflow',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 1600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final items = buildPeriodHistory(
          periods: [
            HistoryPeriodInput(startDate: _oct27, firstCleanDay: _oct30),
            HistoryPeriodInput(startDate: DateTime(2026, 10, 29)),
            HistoryPeriodInput(
              startDate: DateTime(2026, 9, 1),
              endUnknown: true,
            ),
            HistoryPeriodInput(
              startDate: DateTime(2026, 8, 30),
              firstCleanDay: DateTime(2026, 9, 5),
            ),
          ],
          logs: [
            _log('closing', _oct30, FlowLevel.none),
            _log('lone', DateTime(2026, 10, 12), FlowLevel.spotting),
          ],
          today: _today,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 1600),
                textScaler: TextScaler.linear(2),
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: PeriodHistoryBody(
                      items: items,
                      isLoading: false,
                      error: null,
                      incomplete: false,
                      onRetry: () {},
                      onOpen: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(PeriodHistoryTile), findsNWidgets(items.length));
      },
    );

    testWidgets('"عرض الكل" opens the full history', (tester) async {
      await _pumpInsights(
        tester,
        logs: [
          _log('closing', _oct30, FlowLevel.none),
          _log('lone', DateTime(2026, 10, 12), FlowLevel.spotting),
        ],
        episodes: [
          CanonicalEpisodeTiming(startDate: _oct27, endDate: _oct30),
          CanonicalEpisodeTiming(
            startDate: DateTime(2026, 9, 28),
            endDate: DateTime(2026, 10, 4),
          ),
          CanonicalEpisodeTiming(
            startDate: DateTime(2026, 8, 30),
            endDate: DateTime(2026, 9, 5),
          ),
        ],
      );
      expect(find.byType(PeriodHistoryTile), findsNWidgets(3));
      await tester.tap(find.byKey(const Key('period-history-view-all')));
      await tester.pumpAndSettle();
      expect(find.byType(PeriodHistoryScreen), findsOneWidget);
      expect(find.byType(PeriodHistoryTile), findsNWidgets(4));
    });

    testWidgets('English', (tester) async {
      AppLocaleController.instance.setArabic(false);
      await _pumpInsights(
        tester,
        arabic: false,
        logs: [_log('closing', _oct30, FlowLevel.none)],
        episodes: [CanonicalEpisodeTiming(startDate: _oct27, endDate: _oct30)],
      );
      expect(find.text('27 – 29 Oct 2026'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
    });
  });
}
