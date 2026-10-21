import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/presentation/widgets/observation_detail_sheet.dart';

/// Logging/sync hardening — the canonical calendar's day sheet offers "Add
/// missing entry" only inside an OPEN episode: record_bleeding_observation
/// deterministically rejects a new fact on an ended one.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLocaleController.instance.setArabic(false);
  });

  BleedingEpisode episode(LifecycleStatus status) => BleedingEpisode(
    id: 'episode-1',
    userId: 'user-A',
    lifecycleStatus: status,
    continuationCertainty: status == LifecycleStatus.open
        ? ContinuationCertainty.confirmed
        : null,
    startDate: DateTime(2026, 10, 1),
    startPrecision: ObservationPrecision.dateOnly,
    startSource: ObservationSource.userReportedHistorical,
    endDate: status == LifecycleStatus.ended ? DateTime(2026, 10, 6) : null,
    endPrecision: status == LifecycleStatus.ended
        ? ObservationPrecision.dateOnly
        : null,
    endSource: status == LifecycleStatus.ended
        ? ObservationSource.userReportedHistorical
        : null,
  );

  Future<void> openFor(WidgetTester tester, BleedingEpisode e) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showObservationDetailSheet(
              context,
              day: DateTime(2026, 10, 3),
              episodeForDay: e,
              observationsForDay: const [],
              repository: BleedingEpisodeRepositoryImpl(client: null),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('an empty day inside an ENDED episode offers no backfill', (
    tester,
  ) async {
    await openFor(tester, episode(LifecycleStatus.ended));
    expect(find.text('Add missing entry'), findsNothing);
  });

  testWidgets('an empty day inside an OPEN episode still offers backfill', (
    tester,
  ) async {
    await openFor(tester, episode(LifecycleStatus.open));
    expect(find.text('Add missing entry'), findsOneWidget);
  });
}
