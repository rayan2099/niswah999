// Round-2 hardening (2026-10-21, proposed): logCanonicalBleedingForDay
// dropped the day she tapped when no episode was open (failed on
// fix/tracking-hardening d77cd14), and opened a start sheet that
// start_bleeding_episode could only reject for a day on/before the end of
// an already-ended episode.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:niswah/core/preferences/madhhab_controller.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/load_result.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:niswah/features/cycle_tracking/presentation/screens/cycle_tracking_screen.dart';
import 'package:niswah/features/cycle_tracking/presentation/widgets/log_day_entry_router.dart';

import '../support/parity_test_harness.dart';

Map<String, Object?> _log(String id, String date, String flow) => {
  'id': id,
  'user_id': 'local-user',
  'date': '${date}T08:00:00.000',
  'flow': flow,
  'cycle_day': 1,
  'sync_status': 'synced',
};

/// No open episode; one episode Aug 1-6 already ended.
class _EndedEpisodeRepository extends BleedingEpisodeRepositoryImpl {
  _EndedEpisodeRepository() : super(client: null);

  @override
  Future<LoadResult<BleedingEpisode?>> getOpenEpisode(String u) async =>
      const LoadSuccess(null);

  @override
  Future<LoadResult<List<BleedingEpisode>>> getEpisodesForUser(
    String u,
  ) async => LoadSuccess([
    BleedingEpisode(
      id: 'ended',
      userId: u,
      lifecycleStatus: LifecycleStatus.ended,
      startDate: DateTime(2026, 8, 1),
      startPrecision: ObservationPrecision.dateOnly,
      startSource: ObservationSource.userObserved,
      endDate: DateTime(2026, 8, 6),
      endPrecision: ObservationPrecision.dateOnly,
      endSource: ObservationSource.userObserved,
    ),
  ]);
}

Future<void> _route(WidgetTester tester, DateTime day) async {
  await ParityTestHarness.pump(
    tester,
    arabic: false,
    homeOverride: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => logCanonicalBleedingForDay(
            context,
            day: day,
            repositoryOverride: _EndedEpisodeRepository(),
            userIdOverride: 'user-1',
          ),
          child: const Text('route'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('route'));
  await tester.pumpAndSettle();
}

void main() {
  for (final (label, day) in [
    ('inside', DateTime(2026, 8, 3)),
    ('before', DateTime(2026, 7, 20)),
    ('on the stop day of', DateTime(2026, 8, 6)),
  ]) {
    testWidgets('a day $label an ended episode shows the correction '
        'guidance, not a start sheet the server would reject', (tester) async {
      await _route(tester, day);
      expect(
        find.byKey(const Key('log-day-ended-episode-guidance')),
        findsOneWidget,
      );
      expect(find.text('Bleeding started'), findsNothing);
    });
  }

  testWidgets('a day after every ended episode opens the start sheet on '
      'that day', (tester) async {
    await _route(tester, DateTime(2026, 8, 10));
    expect(find.text('Bleeding started'), findsOneWidget);
    expect(find.text('2026-08-10'), findsOneWidget);
    expect(
      find.byKey(const Key('log-day-ended-episode-guidance')),
      findsNothing,
    );
  });

  testWidgets('the chooser no longer promises "add a missing day" for any '
      'period', (tester) async {
    await ParityTestHarness.pump(
      tester,
      arabic: false,
      homeOverride: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showLogDayChooser(context, day: DateTime(2026, 8, 10)),
            child: const Text('choose'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('choose'));
    await tester.pumpAndSettle();
    expect(find.textContaining('missing day'), findsNothing);
    expect(
      find.text("Start a period, or log a day of the one you're tracking now"),
      findsOneWidget,
    );
  });

  testWidgets('Calendar tab: tapping Aug 10 -> Bleeding opens the start '
      'sheet for Aug 10, not a blank one that offers Today', (tester) async {
    final logsJson = jsonEncode([_log('1', '2026-07-18', 'medium')]);
    await ParityTestHarness.pump(
      tester,
      arabic: false,
      size: const Size(390, 2400),
      extraPrefs: {
        'niswah_cycle_tracking_logs': logsJson,
        'flutter.niswah_cycle_tracking_logs': logsJson,
      },
      homeOverride: const CycleTrackingScreen(),
    );
    await MadhhabController.instance.selectMadhhab(Madhhab.hanafi);
    await tester.pumpAndSettle();

    // Harness clock: 2026-08-18. Tap Aug 10 (a past day).
    await tester.tap(find.bySemanticsLabel(RegExp(r'^10, ')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('log-day-choice-bleeding')));
    await tester.pumpAndSettle();

    expect(find.text('Bleeding started'), findsOneWidget);
    expect(
      find.text('2026-08-10'),
      findsOneWidget,
      reason:
          'the tapped day is dropped: showStartBleedingSheet(context) '
          'takes no date, so she must re-pick it (and "Today" is the '
          'first chip — starting a NEW open episode today by mistake)',
    );
  });
}
