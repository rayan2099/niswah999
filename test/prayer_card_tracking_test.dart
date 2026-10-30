import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide TimeOfDay;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/preferences/madhhab_controller.dart';
import 'package:niswah/core/preferences/prayer_location_controller.dart';
import 'package:niswah/core/utils/app_clock.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/load_result.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:niswah/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:niswah/features/prayer_tracking/data/repositories/prayer_tracking_repository_impl.dart';
import 'package:niswah/features/prayer_tracking/domain/entities/prayer_entry.dart';
import 'package:niswah/features/prayer_tracking/presentation/viewmodels/prayer_tracking_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/parity_test_harness.dart';
import 'support/secure_storage_test_support.dart';

/// Testing feedback 2026-10-30: the prayer card only showed times, and its
/// "لم تُسجّل" badge mixed "is it obligatory" with "did she pray". The badge
/// now shows the obligation; completion is a separate control only she sets,
/// with undo, stored per account, local date and prayer.
const riyadh = PrayerLocation(
  latitude: 24.7136,
  longitude: 46.6753,
  label: 'Riyadh',
  timezoneId: 'Asia/Riyadh',
);

class _Episodes extends BleedingEpisodeRepositoryImpl {
  _Episodes(this.episodes) : super(client: null);
  final List<BleedingEpisode> episodes;
  @override
  Future<LoadResult<List<BleedingEpisode>>> getEpisodesForUser(
    String u,
  ) async => LoadSuccess(episodes);
  @override
  Future<LoadResult<List<BleedingObservation>>> getAllObservationsForUser(
    String u,
  ) async => const LoadSuccess([]);
}

BleedingEpisode _ended(String id, DateTime s, DateTime e) => BleedingEpisode(
  id: id,
  userId: 'user-1',
  lifecycleStatus: LifecycleStatus.ended,
  startDate: s,
  startPrecision: ObservationPrecision.dateOnly,
  startSource: ObservationSource.userObserved,
  endDate: e,
  endPrecision: ObservationPrecision.dateOnly,
  endSource: ObservationSource.userObserved,
);

/// Writes a PNG of the screen when SCREENSHOT_DIR is set (PR evidence).
Future<void> _capture(WidgetTester tester, String name) async {
  final dir = Platform.environment['SCREENSHOT_DIR'];
  if (dir == null || dir.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find
        .descendant(
          of: find.byType(Navigator),
          matching: find.byType(RepaintBoundary),
        )
        .first,
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final location = PrayerLocationController.instance;

  group('completion record', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      resetSecureLocalStoreForTest();
      location.resetInMemory();
      await location.select(riyadh);
      AppClock.now = () => DateTime.utc(2026, 10, 30, 10); // 13:00 Riyadh
    });
    tearDown(() {
      location.resetInMemory();
      AppClock.reset();
    });

    test('only after the prayer time has begun', () async {
      final vm = PrayerTrackingViewModel(
        repository: PrayerTrackingRepositoryImpl(client: null),
      );
      addTearDown(vm.dispose);
      expect(vm.hasStarted(PrayerName.fajr), isTrue);
      expect(vm.hasStarted(PrayerName.dhuhr), isTrue);
      expect(vm.hasStarted(PrayerName.isha), isFalse);
    });

    test(
      'survives a restart, belongs to one account, and undo removes it',
      () async {
        final first = PrayerTrackingViewModel(
          repository: PrayerTrackingRepositoryImpl(client: null),
        );
        await first.loadToday(userId: 'a');
        await first.togglePrayerStatus(
          userId: 'a',
          prayerName: PrayerName.fajr,
          status: PrayerStatus.completed,
        );
        first.dispose();

        // A new view model on the same device: the app restarted.
        final restarted = PrayerTrackingViewModel(
          repository: PrayerTrackingRepositoryImpl(client: null),
        );
        addTearDown(restarted.dispose);
        await restarted.loadToday(userId: 'a');
        expect(restarted.statusFor(PrayerName.fajr), PrayerStatus.completed);
        expect(
          restarted.statusFor(PrayerName.dhuhr),
          PrayerStatus.pending,
          reason: 'never inferred',
        );

        // Another account on the same device sees nothing of it.
        await restarted.loadToday(userId: 'b');
        expect(restarted.statusFor(PrayerName.fajr), PrayerStatus.pending);
        await expectLater(
          restarted.clearPrayerStatus(userId: 'a', prayerName: PrayerName.fajr),
          throwsStateError,
          reason: 'a late tap from account A cannot change account B',
        );

        await restarted.loadToday(userId: 'a');
        await restarted.clearPrayerStatus(
          userId: 'a',
          prayerName: PrayerName.fajr,
        );
        expect(
          restarted.statusFor(PrayerName.fajr),
          PrayerStatus.pending,
          reason: 'undo returns to not recorded, never to missed',
        );
      },
    );

    test('is keyed by the city\'s local date, not the phone\'s', () async {
      // 22:00 UTC on Oct 30 is already Oct 31 in Riyadh.
      AppClock.now = () => DateTime.utc(2026, 10, 30, 22);
      final vm = PrayerTrackingViewModel(
        repository: PrayerTrackingRepositoryImpl(client: null),
      );
      addTearDown(vm.dispose);
      await vm.loadToday(userId: 'a');
      await vm.togglePrayerStatus(
        userId: 'a',
        prayerName: PrayerName.fajr,
        status: PrayerStatus.completed,
      );
      expect(vm.entries.single.date, DateTime(2026, 10, 31));
    });
  });

  group('dashboard card', () {
    Future<void> pumpCard(WidgetTester tester, {required bool arabic}) async {
      await ParityTestHarness.pump(tester, arabic: arabic);
      resetSecureLocalStoreForTest();
      location.resetInMemory();
      await location.select(riyadh);
      await MadhhabController.instance.selectMadhhab(Madhhab.hanafi);
      // Two completed cycles in June and July and nothing since: tahara on
      // the harness date (2026-08-18 12:00, i.e. 15:00 in Riyadh).
      await ParityTestHarness.pump(
        tester,
        arabic: arabic,
        homeOverride: DashboardScreen(
          canonicalRepositoryOverride: _Episodes([
            _ended('jun', DateTime(2026, 6, 1), DateTime(2026, 6, 7)),
            _ended('jul', DateTime(2026, 7, 1), DateTime(2026, 7, 7)),
          ]),
          canonicalUserIdOverride: 'user-1',
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('prayer-complete-fajr')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    }

    tearDown(() {
      location.resetInMemory();
    });

    testWidgets('obligation badge, then her own completion with undo', (
      tester,
    ) async {
      await pumpCard(tester, arabic: false);
      expect(find.text('Salah is obligatory'), findsOneWidget);
      expect(find.text('Obligatory'), findsNWidgets(5));
      expect(find.text('Not recorded'), findsNothing);
      expect(find.text('Not yet time'), findsWidgets, reason: 'Maghrib, Isha');
      expect(find.text('Prayed'), findsNothing, reason: 'never inferred');

      await tester.tap(find.byKey(const Key('prayer-complete-fajr')));
      await tester.pumpAndSettle();
      expect(find.text('Prayed'), findsOneWidget);
      expect(find.text('Fajr recorded as prayed'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('prayer-complete-fajr'))).height,
        greaterThanOrEqualTo(44),
      );

      // Undo from the snackbar.
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Prayed'), findsNothing);

      // A prayer whose time has not come cannot be marked.
      await tester.tap(
        find.byKey(const Key('prayer-complete-isha')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.text('Prayed'), findsNothing);
    });

    testWidgets('Arabic: "واجبة", and the city sits in the top-left corner', (
      tester,
    ) async {
      await pumpCard(tester, arabic: true);
      expect(find.text('واجبة'), findsNWidgets(5));
      expect(find.text('لم تُسجّل'), findsNothing);
      final chip = tester.getRect(
        find.byKey(const Key('prayer-location-chip')),
      );
      final title = tester.getRect(find.text('الصلاة واجبة عليكِ'));
      expect(
        chip.right,
        lessThan(title.left),
        reason: 'left of the title in RTL',
      );
      expect(
        (chip.top - title.top).abs(),
        lessThan(12),
        reason: 'top row, not beside the subtitle',
      );
      expect(chip.height, greaterThanOrEqualTo(44));

      await tester.tap(find.byKey(const Key('prayer-complete-fajr')));
      await tester.pumpAndSettle();
      expect(find.text('أدّيتُها'), findsOneWidget);
      await tester.ensureVisible(find.text('الصلاة واجبة عليكِ'));
      await tester.pumpAndSettle();
      await _capture(tester, 'after_prayer_card_ar');
    });
  });
}
