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
    this.observationsUnavailable = false,
    this.observationsQuarantinedCount = 0,
    this.episodesQuarantinedCount = 0,
  }) : super(client: null);

  final List<BleedingEpisode> episodes;
  final List<BleedingObservation> observations;
  final bool episodesUnavailable;
  final bool observationsUnavailable;

  /// > 0 makes [getAllObservationsForUser] return [LoadDegraded] instead
  /// of [LoadSuccess] — a genuinely distinct outcome, never conflated
  /// with either a clean success or a full failure.
  final int observationsQuarantinedCount;
  final int episodesQuarantinedCount;

  @override
  Future<LoadResult<List<BleedingEpisode>>> getEpisodesForUser(
    String userId,
  ) async {
    if (episodesUnavailable) {
      return const LoadUnavailable(LoadErrorCategory.network);
    }
    if (episodesQuarantinedCount > 0) {
      return LoadDegraded(episodes, episodesQuarantinedCount);
    }
    return LoadSuccess(episodes);
  }

  @override
  Future<LoadResult<List<BleedingObservation>>> getAllObservationsForUser(
    String userId,
  ) async {
    if (observationsUnavailable) {
      return const LoadUnavailable(LoadErrorCategory.network);
    }
    if (observationsQuarantinedCount > 0) {
      return LoadDegraded(observations, observationsQuarantinedCount);
    }
    return LoadSuccess(observations);
  }
}

class _FakeBaselineRepository extends CycleBaselineRepositoryImpl {
  _FakeBaselineRepository({this.baseline}) : super(client: null);
  final CycleBaseline? baseline;

  @override
  Future<CycleBaseline?> getBaseline(String userId) async => baseline;
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
    bool observationsUnavailable = false,
    int observationsQuarantinedCount = 0,
    int episodesQuarantinedCount = 0,
    CycleBaseline? baseline,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    await tester.pumpWidget(
      MaterialApp(
        home: CanonicalCalendarScreen(
          repositoryOverride: _FakeCanonicalRepository(
            episodes: episodes,
            observations: observations,
            episodesUnavailable: episodesUnavailable,
            observationsUnavailable: observationsUnavailable,
            observationsQuarantinedCount: observationsQuarantinedCount,
            episodesQuarantinedCount: episodesQuarantinedCount,
          ),
          baselineRepositoryOverride: _FakeBaselineRepository(
            baseline: baseline,
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

  group('Fix 2 — calendar uncertainty semantics (four genuinely distinct '
      'states, never collapsed into one another)', () {
    testWidgets('a day with no report at all is announced as "no entry," never '
        'confused with an explicit uncertain report', (tester) async {
      await pumpCalendar(tester);

      final semantics = tester.getSemantics(
        find.byKey(const ValueKey('canonical-day-2026-08-05T00:00:00.000')),
      );
      expect(semantics.label, contains('No entry recorded'));
      expect(semantics.label, isNot(contains('uncertain')));
      expect(semantics.label, isNot(contains('No recorded bleeding')));
    });

    testWidgets(
      'a day with an explicit "I\'m not sure" observation is announced as '
      'reported-uncertain — never as "no recorded bleeding," which would '
      'wrongly imply nothing was reported at all',
      (tester) async {
        final episode = _episode(start: DateTime(2026, 8, 1));
        final uncertainObservation = _observation(
          id: 'obs-uncertain',
          date: DateTime(2026, 8, 5),
          flow: ObservationFlow.uncertain,
        );
        await pumpCalendar(
          tester,
          episodes: [episode],
          observations: [uncertainObservation],
        );

        final semantics = tester.getSemantics(
          find.byKey(const ValueKey('canonical-day-2026-08-05T00:00:00.000')),
        );
        expect(semantics.label, contains('Reported as uncertain'));
        expect(
          semantics.label,
          isNot(contains('No recorded bleeding')),
          reason:
              'an explicit "I\'m not sure" is a real, present answer — '
              'never announced as if nothing were recorded',
        );
        expect(semantics.label, isNot(contains('No entry recorded')));
      },
    );

    testWidgets('a day with an explicit "no bleeding" observation is announced '
        'distinctly from both "no entry" and "reported uncertain"', (
      tester,
    ) async {
      final episode = _episode(start: DateTime(2026, 8, 1));
      final noBleedingObservation = _observation(
        id: 'obs-none',
        date: DateTime(2026, 8, 5),
        flow: ObservationFlow.none,
      );
      await pumpCalendar(
        tester,
        episodes: [episode],
        observations: [noBleedingObservation],
      );

      final semantics = tester.getSemantics(
        find.byKey(const ValueKey('canonical-day-2026-08-05T00:00:00.000')),
      );
      expect(semantics.label, contains('Reported: no bleeding'));
      expect(semantics.label, isNot(contains('Reported as uncertain')));
      expect(semantics.label, isNot(contains('No entry recorded')));
    });

    testWidgets(
      'a day with a real bleeding observation is announced distinctly '
      'from all three other states, and includes its provenance',
      (tester) async {
        final episode = _episode(
          start: DateTime(2026, 8, 1),
          end: DateTime(2026, 8, 8),
        );
        final bleedingObservation = _observation(
          id: 'obs-medium',
          date: DateTime(2026, 8, 5),
          flow: ObservationFlow.medium,
        );
        await pumpCalendar(
          tester,
          episodes: [episode],
          observations: [bleedingObservation],
        );

        final semantics = tester.getSemantics(
          find.byKey(const ValueKey('canonical-day-2026-08-05T00:00:00.000')),
        );
        expect(semantics.label, contains('Reported: bleeding'));
        expect(semantics.label, isNot(contains('Reported as uncertain')));
        expect(semantics.label, isNot(contains('Reported: no bleeding')));
        expect(semantics.label, isNot(contains('No entry recorded')));
      },
    );

    testWidgets(
      'all four states remain distinct together on the same calendar, '
      'each keeping its own honest announcement',
      (tester) async {
        final episode = _episode(
          start: DateTime(2026, 8, 1),
          end: DateTime(2026, 8, 8),
        );
        await pumpCalendar(
          tester,
          episodes: [episode],
          observations: [
            _observation(
              id: 'obs-medium',
              date: DateTime(2026, 8, 2),
              flow: ObservationFlow.medium,
            ),
            _observation(
              id: 'obs-none',
              date: DateTime(2026, 8, 3),
              flow: ObservationFlow.none,
            ),
            _observation(
              id: 'obs-uncertain',
              date: DateTime(2026, 8, 4),
              flow: ObservationFlow.uncertain,
            ),
          ],
        );

        String labelFor(String iso) => tester
            .getSemantics(find.byKey(ValueKey('canonical-day-$iso')))
            .label;

        expect(
          labelFor('2026-08-02T00:00:00.000'),
          contains('Reported: bleeding'),
        );
        expect(
          labelFor('2026-08-03T00:00:00.000'),
          contains('Reported: no bleeding'),
        );
        expect(
          labelFor('2026-08-04T00:00:00.000'),
          contains('Reported as uncertain'),
        );
        expect(
          labelFor('2026-08-06T00:00:00.000'),
          contains('No entry recorded'),
        );
      },
    );
  });

  group('Fix 3 — corrections are detected via supersedes_id, never via '
      'same-day observation count', () {
    testWidgets('A: three independent same-day observations show no correction '
        'indicator merely because there are three of them', (tester) async {
      final episode = _episode(
        start: DateTime(2026, 8, 1),
        end: DateTime(2026, 8, 8),
      );
      await pumpCalendar(
        tester,
        episodes: [episode],
        observations: [
          _observation(
            id: 'obs-a',
            date: DateTime(2026, 8, 3),
            flow: ObservationFlow.light,
            reportedAt: DateTime(2026, 8, 3, 8),
          ),
          _observation(
            id: 'obs-b',
            date: DateTime(2026, 8, 3),
            flow: ObservationFlow.medium,
            reportedAt: DateTime(2026, 8, 3, 14),
          ),
          _observation(
            id: 'obs-c',
            date: DateTime(2026, 8, 3),
            flow: ObservationFlow.heavy,
            reportedAt: DateTime(2026, 8, 3, 20),
          ),
        ],
      );

      final semantics = tester.getSemantics(
        find.byKey(const ValueKey('canonical-day-2026-08-03T00:00:00.000')),
      );
      expect(
        semantics.label,
        isNot(contains('Has a correction')),
        reason:
            'none of these three observations supersedes another — '
            'three independent reports are not a correction',
      );
    });

    testWidgets('B: one observation followed by one correction shows the '
        'correction indicator', (tester) async {
      final episode = _episode(
        start: DateTime(2026, 8, 1),
        end: DateTime(2026, 8, 8),
      );
      await pumpCalendar(
        tester,
        episodes: [episode],
        observations: [
          _observation(
            id: 'obs-orig',
            date: DateTime(2026, 8, 3),
            flow: ObservationFlow.light,
            reportedAt: DateTime(2026, 8, 3, 8),
          ),
          _observation(
            id: 'obs-corr',
            date: DateTime(2026, 8, 3),
            flow: ObservationFlow.heavy,
            source: ObservationSource.userReportedHistorical,
            supersedesId: 'obs-orig',
            reportedAt: DateTime(2026, 8, 3, 20),
          ),
        ],
      );

      final semantics = tester.getSemantics(
        find.byKey(const ValueKey('canonical-day-2026-08-03T00:00:00.000')),
      );
      expect(semantics.label, contains('Has a correction'));
    });

    testWidgets(
      'C: a correction of a correction retains the complete history and '
      'resolves to the correct effective tip',
      (tester) async {
        final episode = _episode(
          start: DateTime(2026, 8, 1),
          end: DateTime(2026, 8, 8),
        );
        await pumpCalendar(
          tester,
          episodes: [episode],
          observations: [
            _observation(
              id: 'obs-v1',
              date: DateTime(2026, 8, 3),
              flow: ObservationFlow.light,
              reportedAt: DateTime(2026, 8, 3, 8),
            ),
            _observation(
              id: 'obs-v2',
              date: DateTime(2026, 8, 3),
              flow: ObservationFlow.medium,
              source: ObservationSource.userReportedHistorical,
              supersedesId: 'obs-v1',
              reportedAt: DateTime(2026, 8, 3, 14),
            ),
            _observation(
              id: 'obs-v3',
              date: DateTime(2026, 8, 3),
              flow: ObservationFlow.heavy,
              source: ObservationSource.userReportedHistorical,
              supersedesId: 'obs-v2',
              reportedAt: DateTime(2026, 8, 3, 20),
            ),
          ],
        );

        final semantics = tester.getSemantics(
          find.byKey(const ValueKey('canonical-day-2026-08-03T00:00:00.000')),
        );
        expect(semantics.label, contains('Has a correction'));

        await tester.tap(
          find.byKey(const ValueKey('canonical-day-2026-08-03T00:00:00.000')),
        );
        await tester.pumpAndSettle();

        // All three revisions remain visible — nothing in the chain is
        // ever discarded — and exactly one ("Heavy") is marked current.
        expect(find.text('Light'), findsWidgets);
        expect(find.text('Medium'), findsWidgets);
        expect(find.text('Heavy'), findsWidgets);
        expect(find.text('Current'), findsOneWidget);
        expect(find.text('Superseded'), findsNWidgets(2));
      },
    );

    testWidgets(
      'D: multiple independent observations, one of which is corrected, '
      'still show an accurate combined display',
      (tester) async {
        final episode = _episode(
          start: DateTime(2026, 8, 1),
          end: DateTime(2026, 8, 8),
        );
        await pumpCalendar(
          tester,
          episodes: [episode],
          observations: [
            // Independent observation, never touched by a correction.
            _observation(
              id: 'obs-indep',
              date: DateTime(2026, 8, 3),
              flow: ObservationFlow.spotting,
              reportedAt: DateTime(2026, 8, 3, 6),
            ),
            // A second, separate observation that IS later corrected.
            _observation(
              id: 'obs-orig',
              date: DateTime(2026, 8, 3),
              flow: ObservationFlow.light,
              reportedAt: DateTime(2026, 8, 3, 8),
            ),
            _observation(
              id: 'obs-corr',
              date: DateTime(2026, 8, 3),
              flow: ObservationFlow.heavy,
              source: ObservationSource.userReportedHistorical,
              supersedesId: 'obs-orig',
              reportedAt: DateTime(2026, 8, 3, 20),
            ),
          ],
        );

        final semantics = tester.getSemantics(
          find.byKey(const ValueKey('canonical-day-2026-08-03T00:00:00.000')),
        );
        expect(
          semantics.label,
          contains('Has a correction'),
          reason:
              'a real correction exists among this day\'s observations, '
              'even though an unrelated independent one also exists',
        );

        await tester.tap(
          find.byKey(const ValueKey('canonical-day-2026-08-03T00:00:00.000')),
        );
        await tester.pumpAndSettle();

        // All three rows shown honestly: the independent one, the
        // superseded original, and the corrected (current) value.
        expect(find.text('Spotting'), findsWidgets);
        expect(find.text('Light'), findsWidgets);
        expect(find.text('Heavy'), findsWidgets);
      },
    );
  });

  group('Fix 4 — clean empty, unavailable, degraded, and complete are '
      'four genuinely distinct outcomes, never conflated', () {
    testWidgets('clean empty: zero episodes, zero observations — a real, '
        'verified "nothing here yet," not an error', (tester) async {
      await pumpCalendar(tester);

      expect(find.text("Couldn't load your calendar"), findsNothing);
      expect(
        find.text(
          'Some entries could not be verified right now — this month '
          'may be incomplete.',
        ),
        findsNothing,
      );
    });

    testWidgets('unavailable: the episodes read genuinely failed — the whole '
        'calendar shows the honest unavailable card, not an empty one', (
      tester,
    ) async {
      await pumpCalendar(tester, episodesUnavailable: true);

      expect(find.text("Couldn't load your calendar"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets(
      'degraded: the observations read partially succeeded (a row was '
      'quarantined) — a distinct, non-alarming, retryable notice, never '
      'silently treated as a clean success',
      (tester) async {
        final episode = _episode(
          start: DateTime(2026, 8, 1),
          end: DateTime(2026, 8, 8),
        );
        await pumpCalendar(
          tester,
          episodes: [episode],
          observationsQuarantinedCount: 1,
        );

        expect(
          find.text(
            'Some entries could not be verified right now — this month '
            'may be incomplete.',
          ),
          findsOneWidget,
        );
        expect(
          find.text("Couldn't load your calendar"),
          findsNothing,
          reason:
              'a degraded (partial) read is not the same as a full '
              'failure — the calendar itself still renders',
        );
        expect(find.text('Retry'), findsOneWidget);
      },
    );

    testWidgets(
      'degraded episodes read suppresses the forward prediction — never '
      'fabricates a projection from a data set known to have a gap',
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
        await pumpCalendar(
          tester,
          episodes: [firstEpisode, secondEpisode],
          episodesQuarantinedCount: 1,
        );
        await tester.tap(find.byIcon(Icons.chevron_left_rounded));
        await tester.pumpAndSettle();
        expect(find.text('July 2026'), findsOneWidget);

        // The same fixture produces a real prediction (see the
        // "predicted day" test above) when the read is clean — here,
        // with the episodes read degraded, the predicted-day marker
        // must not appear at all.
        final predictedCell = find.descendant(
          of: find.byKey(
            const ValueKey('canonical-day-2026-07-31T00:00:00.000'),
          ),
          matching: find.byType(CustomPaint),
        );
        final painter = tester
            .widget<CustomPaint>(predictedCell.first)
            .foregroundPainter;
        expect(
          painter,
          isNull,
          reason:
              'no prediction may be computed from a degraded episodes '
              'read — a quarantined row could be exactly the episode '
              'that would have changed the answer',
        );
      },
    );

    testWidgets(
      'complete: a genuinely clean, fully verified read shows real data '
      'with no degraded/unavailable notice at all',
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

        expect(find.text("Couldn't load your calendar"), findsNothing);
        expect(
          find.text(
            'Some entries could not be verified right now — this month '
            'may be incomplete.',
          ),
          findsNothing,
        );
      },
    );
  });

  group('Fix 5 — user-reported estimate has a real UI surface, never '
      'attached to a specific calendar day', () {
    testWidgets('a real baseline estimate is shown as its own labeled summary, '
        'badged as an estimate', (tester) async {
      await pumpCalendar(
        tester,
        baseline: const CycleBaseline(
          userId: 'user-1',
          usualBleedingDurationDays: 6,
          usualCycleLengthDays: 28,
        ),
      );

      expect(
        find.textContaining('6 days'),
        findsOneWidget,
        reason: 'the real stated estimate must actually be displayed',
      );
      expect(find.textContaining('28 days'), findsOneWidget);
      expect(
        find.text('Estimate'),
        findsOneWidget,
        reason:
            'must be explicitly badged as an estimate, using the '
            'shared EvidenceProvenance taxonomy',
      );
    });

    testWidgets(
      'no baseline at all shows no estimate summary — never fabricated',
      (tester) async {
        await pumpCalendar(tester);

        expect(find.text('Estimate'), findsNothing);
      },
    );

    testWidgets(
      'the estimate summary is never attached to any specific calendar '
      'day — it carries no day key, unlike every real observation-backed '
      'marker',
      (tester) async {
        final episode = _episode(
          start: DateTime(2026, 8, 1),
          end: DateTime(2026, 8, 5),
        );
        await pumpCalendar(
          tester,
          episodes: [episode],
          observations: [
            _observation(
              id: 'obs-1',
              date: DateTime(2026, 8, 3),
              flow: ObservationFlow.medium,
            ),
          ],
          baseline: const CycleBaseline(
            userId: 'user-1',
            usualBleedingDurationDays: 6,
            usualCycleLengthDays: 28,
          ),
        );

        // The real observed day keeps its own honest provenance —
        // never silently replaced or augmented by the unrelated
        // estimate value.
        final semantics = tester.getSemantics(
          find.byKey(const ValueKey('canonical-day-2026-08-03T00:00:00.000')),
        );
        expect(semantics.label, contains('Reported: bleeding'));
        expect(semantics.label, isNot(contains('Estimate')));
      },
    );
  });
}
