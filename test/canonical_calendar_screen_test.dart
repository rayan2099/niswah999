import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/utils/app_clock.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/load_result.dart';
import 'package:niswah/features/cycle_tracking/presentation/screens/canonical_calendar_screen.dart';

import 'support/device_timezone_test_support.dart';
import 'support/secure_storage_test_support.dart';

/// F8 (menstrual-data-integrity charter) — the canonical calendar's
/// widget-level coverage. A full write round trip (save → server →
/// refreshed calendar) requires a real Supabase session and RPC, which
/// cannot be exercised in a plain widget test — the exact same,
/// already-established scope boundary `correction_sheet_test.dart`
/// documents for [showCorrectObservationSheet] itself. What this file
/// legitimately covers: the calendar renders genuine canonical evidence
/// (never the legacy projection), distinguishes multi-observation days
/// and predicted days, opens the correct action for a given day's real
/// state, and degrades honestly when a canonical read fails.
class _FakeCanonicalRepository extends BleedingEpisodeRepositoryImpl {
  _FakeCanonicalRepository({
    this.episodes = const [],
    this.observations = const [],
    this.episodesUnavailable = false,
  }) : super(client: null);

  final List<BleedingEpisode> episodes;
  final List<BleedingObservation> observations;
  final bool episodesUnavailable;

  @override
  Future<LoadResult<List<BleedingEpisode>>> getEpisodesForUser(
    String userId,
  ) async {
    if (episodesUnavailable) {
      return const LoadUnavailable(LoadErrorCategory.network);
    }
    return LoadSuccess(episodes);
  }

  @override
  Future<LoadResult<List<BleedingObservation>>> getAllObservationsForUser(
    String userId,
  ) async {
    return LoadSuccess(observations);
  }
}

BleedingEpisode _episode({
  String id = 'ep-1',
  required DateTime start,
  DateTime? end,
}) => BleedingEpisode(
  id: id,
  userId: 'user-1',
  lifecycleStatus: end == null ? LifecycleStatus.open : LifecycleStatus.ended,
  continuationCertainty: end == null ? ContinuationCertainty.confirmed : null,
  startDate: start,
  startPrecision: ObservationPrecision.dateOnly,
  startSource: ObservationSource.userObserved,
  endDate: end,
  endPrecision: end == null ? null : ObservationPrecision.dateOnly,
  endSource: end == null ? null : ObservationSource.userObserved,
);

BleedingObservation _observation({
  required String id,
  String episodeId = 'ep-1',
  required DateTime date,
  required ObservationFlow flow,
  ObservationSource source = ObservationSource.userObserved,
  String? supersedesId,
  DateTime? reportedAt,
}) => BleedingObservation(
  id: id,
  userId: 'user-1',
  episodeId: episodeId,
  observedDate: date,
  precision: ObservationPrecision.dateOnly,
  flow: flow,
  source: source,
  utcOffsetMinutes: 0,
  supersedesId: supersedesId,
  reportedAt: reportedAt,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSecureLocalStoreForTest();
    mockDeviceTimezoneForTest();
    AppClock.now = () => DateTime(2026, 8, 18, 12);
    AppLocaleController.instance.setArabic(false);
  });

  Future<void> pumpCalendar(
    WidgetTester tester, {
    List<BleedingEpisode> episodes = const [],
    List<BleedingObservation> observations = const [],
    bool episodesUnavailable = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    await tester.pumpWidget(
      MaterialApp(
        home: CanonicalCalendarScreen(
          repositoryOverride: _FakeCanonicalRepository(
            episodes: episodes,
            observations: observations,
            episodesUnavailable: episodesUnavailable,
          ),
          userIdOverride: 'user-1',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'renders a real bleeding day from canonical evidence, not the legacy '
    'projection, and its detail sheet shows the real flow',
    (tester) async {
      final episode = _episode(
        start: DateTime(2026, 8, 1),
        end: DateTime(2026, 8, 5),
      );
      final observation = _observation(
        id: 'obs-1',
        date: DateTime(2026, 8, 3),
        flow: ObservationFlow.medium,
      );
      await pumpCalendar(
        tester,
        episodes: [episode],
        observations: [observation],
      );

      expect(find.text('August 2026'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('canonical-day-2026-08-03T00:00:00.000')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Medium'), findsWidgets);
      expect(find.text('Current'), findsOneWidget);
      expect(find.text('Correct this entry'), findsOneWidget);
    },
  );

  testWidgets('a corrected day shows the full revision chain — current vs '
      'superseded, never silently collapsed to one value', (tester) async {
    final episode = _episode(
      start: DateTime(2026, 8, 1),
      end: DateTime(2026, 8, 5),
    );
    final original = _observation(
      id: 'obs-orig',
      date: DateTime(2026, 8, 3),
      flow: ObservationFlow.light,
      reportedAt: DateTime(2026, 8, 3, 9),
    );
    final correction = _observation(
      id: 'obs-corr',
      date: DateTime(2026, 8, 3),
      flow: ObservationFlow.heavy,
      source: ObservationSource.userReportedHistorical,
      supersedesId: 'obs-orig',
      reportedAt: DateTime(2026, 8, 3, 20),
    );
    await pumpCalendar(
      tester,
      episodes: [episode],
      observations: [original, correction],
    );

    await tester.tap(
      find.byKey(const ValueKey('canonical-day-2026-08-03T00:00:00.000')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Revision history — oldest first'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);
    expect(find.text('Superseded'), findsOneWidget);
    expect(
      find.text('Heavy'),
      findsWidgets,
      reason: 'the corrected (current) value must be shown',
    );
    expect(
      find.text('Light'),
      findsWidgets,
      reason:
          'the original, superseded value must still be visible, never '
          'deleted from view',
    );
  });

  testWidgets(
    'an empty day within an episode offers to add the missing entry, and '
    'opens the real backfill sheet',
    (tester) async {
      final episode = _episode(
        start: DateTime(2026, 8, 1),
        end: DateTime(2026, 8, 5),
      );
      await pumpCalendar(tester, episodes: [episode], observations: const []);

      await tester.tap(
        find.byKey(const ValueKey('canonical-day-2026-08-02T00:00:00.000')),
      );
      await tester.pumpAndSettle();

      expect(find.text('No entry recorded for this day yet.'), findsOneWidget);
      await tester.tap(find.text('Add missing entry'));
      await tester.pumpAndSettle();

      expect(find.text('Add a missing day'), findsOneWidget);
    },
  );

  testWidgets('a day with no episode at all offers no fabricated action, only '
      'honest guidance', (tester) async {
    await pumpCalendar(tester, episodes: const [], observations: const []);

    await tester.tap(
      find.byKey(const ValueKey('canonical-day-2026-08-10T00:00:00.000')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add missing entry'), findsNothing);
    expect(find.textContaining('Start Bleeding'), findsOneWidget);
  });

  testWidgets(
    'a future day never offers to add or correct an entry, even when an '
    'open episode exists (future-date rejection)',
    (tester) async {
      final openEpisode = _episode(start: DateTime(2026, 8, 14));
      await pumpCalendar(
        tester,
        episodes: [openEpisode],
        observations: const [],
      );

      // 2026-08-25 is in the future relative to the fixed test clock
      // (2026-08-18) — must never be treated as backfillable even
      // though the open episode has no end date to bound it.
      await tester.tap(
        find.byKey(const ValueKey('canonical-day-2026-08-25T00:00:00.000')),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Add missing entry'), findsNothing);
    },
  );

  testWidgets('month navigation moves forward and back', (tester) async {
    await pumpCalendar(tester);
    expect(find.text('August 2026'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    expect(find.text('September 2026'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pumpAndSettle();
    expect(find.text('July 2026'), findsOneWidget);
  });

  testWidgets(
    'a leap day (Feb 29) renders without crashing when navigated to',
    (tester) async {
      AppClock.now = () => DateTime(2028, 2, 18, 12);
      await pumpCalendar(tester);
      expect(find.text('February 2028'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('canonical-day-2028-02-29T00:00:00.000')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an episodes read failure shows an honest unavailable card with '
      'retry — never fabricated/default data', (tester) async {
    await pumpCalendar(tester, episodesUnavailable: true);

    expect(find.text("Couldn't load your calendar"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('August 2026'), findsNothing);
  });

  testWidgets(
    'a predicted day is visually distinct from a confirmed bleeding day '
    '— dashed border, never the same solid fill',
    (tester) async {
      final firstEpisode = _episode(
        id: 'ep-first',
        start: DateTime(2026, 6, 1),
        end: DateTime(2026, 6, 5),
      );
      final secondEpisode = _episode(
        id: 'ep-second',
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 7, 5),
      );
      // Average gap: 30 days -> predicted next start ~2026-07-31,
      // safely inside the fixed test clock's own month (August 2026)
      // once navigated there is unnecessary; predicted start actually
      // lands July 31 — navigate to July to see it alongside real data.
      await pumpCalendar(
        tester,
        episodes: [firstEpisode, secondEpisode],
        observations: const [],
      );
      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();
      expect(find.text('July 2026'), findsOneWidget);

      final predictedCell = tester.widget<CustomPaint>(
        find
            .descendant(
              of: find.byKey(
                const ValueKey('canonical-day-2026-07-31T00:00:00.000'),
              ),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      expect(
        predictedCell.foregroundPainter,
        isNotNull,
        reason:
            'a predicted day must be painted with the dashed marker, '
            'never rendered plain like a real bleeding day',
      );
    },
  );

  testWidgets('Arabic: renders RTL with the Arabic title', (tester) async {
    AppLocaleController.instance.setArabic(true);
    await pumpCalendar(tester);

    expect(find.text('تقويم الدورة'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Directionality &&
            widget.textDirection == TextDirection.rtl,
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
    AppLocaleController.instance.setArabic(false);
  });
}
