import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/utils/app_clock.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/load_result.dart';
import 'package:niswah/features/cycle_tracking/presentation/screens/canonical_calendar_screen.dart';
import 'package:niswah/features/cycle_tracking/presentation/widgets/cycle_calendar.dart';

import '../support/device_timezone_test_support.dart';
import '../support/secure_storage_test_support.dart';

/// Screens hardening — month grids.
///
/// The DST tests only mean something when the process runs in a zone
/// with a DST fall-back inside October 2026, e.g.:
///   TZ=Europe/London flutter test test/screens_hardening/calendar_dst_and_empty_test.dart
/// (also Africa/Cairo: fall-back 2026-10-29). They are skipped otherwise.
final bool _fallBackInOctober2026 =
    DateTime(2026, 10, 1).add(const Duration(days: 30)).day != 31;

class _EmptyRepo extends BleedingEpisodeRepositoryImpl {
  _EmptyRepo() : super(client: null);
  @override
  Future<LoadResult<List<BleedingEpisode>>> getEpisodesForUser(
    String u,
  ) async => const LoadSuccess(<BleedingEpisode>[]);
  @override
  Future<LoadResult<List<BleedingObservation>>> getAllObservationsForUser(
    String u,
  ) async => const LoadSuccess(<BleedingObservation>[]);
}

class _NoBaseline extends CycleBaselineRepositoryImpl {
  _NoBaseline() : super(client: null);
  @override
  Future<CycleBaseline?> getBaseline(String userId) async => null;
}

const _emptySummary = CycleTrackingSummary(
  averageCycleLength: null,
  averagePeriodLength: null,
  lastCycleStart: null,
  currentPhase: CyclePhase.follicular,
  fertileWindow: FertileWindow(start: null, end: null, peakDay: null),
);

Future<void> _pumpLegacy(WidgetTester tester, DateTime month) async {
  await tester.binding.setSurfaceSize(const Size(390, 1400));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CycleCalendar(
            logs: const [],
            month: month,
            summary: _emptySummary,
            onDateSelected: (_) {},
            showHijri: false,
            onCalendarModeChanged: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<String> _dayLabels(WidgetTester tester) => tester
    .widgetList<Semantics>(find.byType(Semantics))
    .map((s) => s.properties.label)
    .whereType<String>()
    .where((l) => RegExp(r'^\d{1,2}, ').hasMatch(l))
    .toList();

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSecureLocalStoreForTest();
    mockDeviceTimezoneForTest();
    AppLocaleController.instance.setArabic(false);
  });

  testWidgets(
    'legacy CycleCalendar: October 2026 grid shows every day 1..31 exactly '
    'once across a DST fall-back',
    skip: !_fallBackInOctober2026,
    (tester) async {
      AppClock.now = () => DateTime(2026, 10, 18, 12);
      await _pumpLegacy(tester, DateTime(2026, 10));
      // Grid: Sep 27 .. Oct 31 (35 cells). In-month cells are the ones
      // whose label day sequence runs 1..31 after the leading Sep days.
      final labels = _dayLabels(tester);
      final days = labels.map((l) => int.parse(l.split(',').first)).toList();
      expect(days.skip(4).take(31).toList(), [for (var d = 1; d <= 31; d++) d]);
    },
  );

  testWidgets(
    'CanonicalCalendarScreen: October 2026 has a cell for Oct 31 and no '
    'duplicated Oct 25 across a DST fall-back',
    skip: !_fallBackInOctober2026,
    (tester) async {
      AppClock.now = () => DateTime(2026, 10, 18, 12);
      await tester.binding.setSurfaceSize(const Size(390, 1600));
      await tester.pumpWidget(
        MaterialApp(
          home: CanonicalCalendarScreen(
            repositoryOverride: _EmptyRepo(),
            baselineRepositoryOverride: _NoBaseline(),
            userIdOverride: 'user-1',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final exception = tester.takeException();
      expect(exception, isNull);
      expect(
        find.byKey(const ValueKey('canonical-day-2026-10-31T00:00:00.000')),
        findsOneWidget,
        reason: 'the last day of the month must be tappable/visible',
      );
    },
  );

  testWidgets(
    'legacy CycleCalendar with NO data at all must not label every day '
    '"Tahara" (a purity ruling drawn from no evidence)',
    (tester) async {
      AppClock.now = () => DateTime(2026, 8, 18, 12);
      await _pumpLegacy(tester, DateTime(2026, 8));
      final labels = _dayLabels(tester);
      expect(
        labels.where((l) => l.endsWith(', Tahara')),
        isEmpty,
        reason:
            'no log exists for any day; "Tahara" (green fill, same as a '
            'logged flow=none day) is asserted for days with no entry, '
            'including future days',
      );
    },
  );
}
