import 'dart:async';

import 'package:flutter/material.dart' hide TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/preferences/prayer_location_controller.dart';
import 'package:niswah/core/utils/app_clock.dart';
import 'package:niswah/features/prayer_tracking/domain/controllers/prayer_time_calculator.dart';
import 'package:niswah/features/prayer_tracking/domain/entities/prayer_entry.dart';
import 'package:niswah/features/prayer_tracking/domain/repositories/prayer_tracking_repository.dart';
import 'package:niswah/features/prayer_tracking/domain/services/prayer_schedule_builder.dart';
import 'package:niswah/features/prayer_tracking/presentation/viewmodels/prayer_tracking_view_model.dart';
import 'package:niswah/features/prayer_tracking/presentation/screens/prayer_tracking_screen.dart';
import 'package:niswah/features/prayer_tracking/presentation/widgets/prayer_settings_sheet.dart';

const raleigh = PrayerLocation(
  latitude: 35.775,
  longitude: -78.6336,
  label: 'Raleigh',
  timezoneId: 'America/New_York',
);
const riyadh = PrayerLocation(
  latitude: 24.7136,
  longitude: 46.6753,
  label: 'Riyadh',
  timezoneId: 'Asia/Riyadh',
);

PrayerSchedule build(
  PrayerLocation location,
  DateTime now, {
  String method = 'muslimWorldLeague',
  bool hanafi = false,
  DateTime? until,
}) => PrayerScheduleBuilder.build(
  location: location,
  now: now,
  method: method,
  hanafiAsr: hanafi,
  ramadanAdjustmentUntil: until,
);

List<String> clockTimes(PrayerSchedule s) => PrayerName.values.map((p) {
  final t = s.timeFor(p)!;
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}).toList();

PrayerEntry log(String user, DateTime day, PrayerStatus status) => PrayerEntry(
  id: '$user-fajr',
  userId: user,
  prayerName: PrayerName.fajr,
  date: day,
  scheduledTime: const TimeOfDay(hour: 4, minute: 42),
  status: status,
);

class MemoryRepo implements PrayerTrackingRepository {
  List<PrayerEntry> logs = [];
  final requests = <(String, DateTime)>[];
  Completer<List<PrayerEntry>>? delayed;
  @override
  Future<List<PrayerEntry>> getDailyPrayerLog(
    DateTime date, {
    required String userId,
  }) async {
    requests.add((userId, date));
    final waiting = delayed;
    delayed = null;
    return waiting == null ? List.of(logs) : waiting.future;
  }

  @override
  Future<void> savePrayer(PrayerEntry entry) async {
    logs.removeWhere((e) => e.id == entry.id);
    logs.add(entry);
  }

  @override
  Future<void> deletePrayer(String id) async =>
      logs.removeWhere((e) => e.id == id);
  @override
  Future<List<PrayerEntry>> getPrayerHistory({
    required String userId,
    DateTime? from,
    DateTime? to,
  }) async => logs;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final controller = PrayerLocationController.instance;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    controller.resetInMemory();
    AppClock.now = () => DateTime.utc(2015, 7, 12, 16);
  });
  tearDown(() {
    controller.resetInMemory();
    AppClock.reset();
  });

  // Fixed numerical vectors from the upstream adhan-js / adhan_dart suite,
  // rather than re-running the same library as an expected-value oracle.
  // https://github.com/prayer-timetable/adhan_dart/blob/master/test/prayer_times_test.dart
  test('summer DST Raleigh reference, ISNA + Hanafi, all five starts', () {
    expect(
      clockTimes(
        build(raleigh, AppClock.now(), method: 'northAmerica', hanafi: true),
      ),
      ['04:42', '13:21', '18:22', '20:32', '21:57'],
    );
  });
  test('winter standard-time Raleigh reference, MWL + standard Asr', () {
    expect(clockTimes(build(raleigh, DateTime.utc(2015, 12, 1, 17))), [
      '05:35',
      '12:05',
      '14:42',
      '17:01',
      '18:26',
    ]);
  });
  test('Makkah Umm al-Qura fixed reference vectors across three seasons', () {
    const makkah = PrayerLocation(
      latitude: 21.427009,
      longitude: 39.828685,
      label: 'Makkah reference',
      timezoneId: 'Asia/Riyadh',
    );
    final fixtures = <(DateTime, List<String>)>[
      (
        DateTime.utc(2016, 1, 5, 12),
        ['05:38', '12:26', '15:31', '17:52', '19:22'],
      ),
      (
        DateTime.utc(2016, 7, 8, 12),
        ['04:18', '12:26', '15:43', '19:07', '20:37'],
      ),
      (
        DateTime.utc(2016, 11, 5, 12),
        ['05:08', '12:04', '15:18', '17:42', '19:12'],
      ),
    ];
    for (final fixture in fixtures) {
      expect(
        clockTimes(build(makkah, fixture.$1, method: 'ummAlQura')),
        fixture.$2,
      );
    }
  });
  test('all supported methods produce ordered starts for every preset across the year', () {
    for (final location in PrayerLocationController.presets) {
      for (final method in prayerMethods.keys) {
        for (var month = 1; month <= 12; month++) {
          final s = build(
            location,
            DateTime.utc(2026, month, 15, 12),
            method: method,
          );
          expect(s.instants.length, 5);
          expect(s.instants.values.every((instant) => instant.isUtc), isTrue);
          expect(
            PrayerName.values.every((name) => s.timeFor(name)!.isValid),
            isTrue,
          );
        }
      }
    }
  });
  test('selected city controls civil date even across UTC midnight', () {
    final s = build(riyadh, DateTime.utc(2026, 8, 18, 22));
    expect([s.date.year, s.date.month, s.date.day], [2026, 8, 19]);
    expect(s.date.timeZoneOffset, const Duration(hours: 3));
    expect(s.instants.length, 5);
    for (final name in PrayerName.values) {
      final local = tz.TZDateTime.from(
        s.instants[name]!,
        PrayerScheduleBuilder.zoneFor(riyadh),
      );
      expect(
        s.timeFor(name),
        TimeOfDay(hour: local.hour, minute: local.minute),
      );
    }
  });
  test('Cairo observes its actual daylight-saving rules', () {
    final cairo = PrayerLocationController.presets.last;
    expect(
      build(cairo, DateTime.utc(2026, 1, 15, 12)).date.timeZoneOffset,
      const Duration(hours: 2),
    );
    expect(
      build(cairo, DateTime.utc(2026, 7, 15, 12)).date.timeZoneOffset,
      const Duration(hours: 3),
    );
  });
  test('method and Asr choices change the appropriate starts', () {
    final mwl = build(riyadh, AppClock.now());
    final umm = build(riyadh, AppClock.now(), method: 'ummAlQura');
    final hanafi = build(riyadh, AppClock.now(), hanafi: true);
    expect(
      umm.instants[PrayerName.isha]!.difference(
        umm.instants[PrayerName.maghrib]!,
      ),
      const Duration(minutes: 90),
    );
    expect(umm.fajr, isNot(mwl.fajr));
    expect(
      hanafi.instants[PrayerName.asr]!.isAfter(mwl.instants[PrayerName.asr]!),
      isTrue,
    );
    expect(hanafi.fajr, mwl.fajr);
  });
  test('Ramadan Isha adjustment expires after confirmed final local date', () {
    final until = DateTime(2015, 7, 12);
    final normal = build(riyadh, AppClock.now(), method: 'ummAlQura');
    final ramadan = build(
      riyadh,
      AppClock.now(),
      method: 'ummAlQura',
      until: until,
    );
    expect(
      ramadan.instants[PrayerName.isha]!.difference(
        normal.instants[PrayerName.isha]!,
      ),
      const Duration(minutes: 30),
    );
    final next = DateTime.utc(2015, 7, 13, 12);
    expect(
      clockTimes(build(riyadh, next, method: 'ummAlQura', until: until)),
      clockTimes(build(riyadh, next, method: 'ummAlQura')),
    );
  });
  test(
    'missing/invalid timezone, coordinates or method never fabricate times',
    () {
      expect(
        () => build(
          const PrayerLocation(latitude: 24, longitude: 46, label: 'Unknown'),
          AppClock.now(),
        ),
        throwsA(anything),
      );
      expect(
        () => build(
          const PrayerLocation(
            latitude: 24,
            longitude: 46,
            label: 'Unknown',
            timezoneId: 'Not/AZone',
          ),
          AppClock.now(),
        ),
        throwsA(anything),
      );
      expect(
        () => build(
          const PrayerLocation(
            latitude: 100,
            longitude: 46,
            label: 'Bad',
            timezoneId: 'UTC',
          ),
          AppClock.now(),
        ),
        throwsArgumentError,
      );
      expect(
        () => build(riyadh, AppClock.now(), method: 'unknown'),
        throwsArgumentError,
      );
    },
  );
  test('Unconfirmed GPS timezone cannot produce prayer times', () {
    expect(
      () => build(
        const PrayerLocation(
          latitude: 24.7136,
          longitude: 46.6753,
          label: 'Current location',
          timezoneId: 'America/New_York',
          timezoneConfirmed: false,
        ),
        AppClock.now(),
      ),
      throwsStateError,
    );
  });
  test(
    'polar extremes are unavailable rather than plausible placeholder times',
    () {
      expect(
        () => build(
          const PrayerLocation(
            latitude: 90,
            longitude: 0,
            label: 'North Pole',
            timezoneId: 'UTC',
          ),
          DateTime.utc(2026, 6, 21, 12),
        ),
        throwsA(anything),
      );
    },
  );
  test(
    'clock never marks an unrecorded prayer completed, missed or excused',
    () {
      final s = build(raleigh, AppClock.now());
      for (final name in PrayerName.values) {
        for (final delta in [-1, 0, 1, 60, 86400]) {
          expect(
            PrayerTimeCalculator.statusFor(
              schedule: s,
              prayerName: name,
              now: s.instants[name]!.add(Duration(seconds: delta)),
            ),
            PrayerStatus.pending,
          );
        }
      }
    },
  );
  test('next prayer crosses midnight using real tomorrow Fajr', () {
    final today = build(raleigh, AppClock.now());
    final tomorrow = build(raleigh, DateTime.utc(2015, 7, 13, 16));
    final now = today.instants[PrayerName.isha]!.add(
      const Duration(minutes: 1),
    );
    expect(PrayerTimeCalculator.nextPrayer(schedule: today, now: now), isNull);
    final next = PrayerTimeCalculator.nextPrayer(
      schedule: today,
      tomorrow: tomorrow,
      now: now,
    )!;
    expect(next.name, PrayerName.fajr);
    expect(next.scheduledAt, tomorrow.instants[PrayerName.fajr]);
    expect(
      PrayerTimeCalculator.nextPrayer(
        schedule: today,
        now: today.instants[PrayerName.dhuhr]!,
      )!.name,
      PrayerName.dhuhr,
    );
  });
  test(
    'settings persist and legacy known cities acquire their actual timezone',
    () async {
      SharedPreferences.setMockInitialValues({
        'niswah_prayer_location_lat': 24.7136,
        'niswah_prayer_location_lng': 46.6753,
        'niswah_prayer_location_label': 'Riyadh',
      });
      await controller.load();
      expect(controller.selectedOrNull!.timezoneId, 'Asia/Riyadh');
      await controller.configure(
        method: 'ummAlQura',
        hanafiAsr: true,
        ramadanAdjustmentUntil: DateTime(2015, 7, 12),
      );
      controller.resetInMemory();
      expect(controller.selectedOrNull, isNull);
      expect(controller.hanafiAsr, isFalse);
      await controller.load();
      expect(controller.method, 'ummAlQura');
      expect(controller.hanafiAsr, isTrue);
      expect(controller.ramadanAdjustmentUntil, DateTime(2015, 7, 12));
    },
  );
  test('legacy GPS without zone remains unavailable until confirmed', () async {
    SharedPreferences.setMockInitialValues({
      'niswah_prayer_location_lat': 35.775,
      'niswah_prayer_location_lng': -78.6336,
      'niswah_prayer_location_label': 'Current location',
    });
    await controller.load();
    final vm = PrayerTrackingViewModel();
    addTearDown(vm.dispose);
    expect(vm.schedule, isNull);
  });
  test(
    'recorded status belongs to the active user and selected city day',
    () async {
      await controller.select(riyadh);
      AppClock.now = () => DateTime.utc(2026, 8, 18, 22); // Riyadh Aug 19
      final repo = MemoryRepo()
        ..logs = [
          log('u1', DateTime(2026, 8, 18), PrayerStatus.completed),
          log('other', DateTime(2026, 8, 19), PrayerStatus.excused),
        ];
      final vm = PrayerTrackingViewModel(repository: repo);
      addTearDown(vm.dispose);
      await vm.loadToday(userId: 'u1');
      expect(repo.requests.last.$2.day, 19);
      expect(vm.statusFor(PrayerName.fajr), PrayerStatus.pending);
      await vm.togglePrayerStatus(
        userId: 'u1',
        prayerName: PrayerName.fajr,
        status: PrayerStatus.completed,
      );
      expect(vm.statusFor(PrayerName.fajr), PrayerStatus.completed);
      await vm.togglePrayerStatus(
        userId: 'u1',
        prayerName: PrayerName.fajr,
        status: PrayerStatus.missed,
      );
      expect(repo.logs.last.completedAt, isNull);
      AppClock.now = () => DateTime.utc(2026, 8, 19, 22); // next city day
      expect(vm.statusFor(PrayerName.fajr), PrayerStatus.pending);
      vm.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(repo.requests.last.$2.day, 20);
    },
  );
  test('late account A load cannot replace account B status', () async {
    await controller.select(raleigh);
    final pending = Completer<List<PrayerEntry>>();
    final repo = MemoryRepo()..delayed = pending;
    final vm = PrayerTrackingViewModel(repository: repo);
    addTearDown(vm.dispose);
    final a = vm.loadToday(userId: 'a');
    repo.logs = [log('b', DateTime(2015, 7, 12), PrayerStatus.excused)];
    await vm.loadToday(userId: 'b');
    pending.complete([log('a', DateTime(2015, 7, 12), PrayerStatus.completed)]);
    await a;
    expect(vm.statusFor(PrayerName.fajr), PrayerStatus.excused);
  });
  test(
    'missing setup blocks writes and disposal tolerates late completion',
    () async {
      final pending = Completer<List<PrayerEntry>>();
      final repo = MemoryRepo()..delayed = pending;
      final vm = PrayerTrackingViewModel(repository: repo);
      final loading = vm.loadToday(userId: 'u');
      await expectLater(
        vm.togglePrayerStatus(
          userId: 'u',
          prayerName: PrayerName.fajr,
          status: PrayerStatus.completed,
        ),
        throwsStateError,
      );
      vm.dispose();
      pending.complete([]);
      await loading;
    },
  );
  testWidgets(
    'screen with missing setup displays an action and no invented clock',
    (tester) async {
      AppLocaleController.instance.setArabic(false);
      await tester.pumpWidget(const MaterialApp(home: PrayerTrackingScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Set prayer location'), findsOneWidget);
      expect(find.textContaining('Prayer times unavailable.'), findsOneWidget);
      expect(find.text('00:00'), findsNothing);
      await tester.tap(find.text('Set prayer location'));
      await tester.pumpAndSettle();
      expect(find.text('Prayer settings'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Calculation method'),
        240,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Calculation method'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'screen shows the selected city and reacts to a location change',
    (tester) async {
      AppLocaleController.instance.setArabic(false);
      await controller.select(riyadh);
      await tester.pumpWidget(const MaterialApp(home: PrayerTrackingScreen()));
      await tester.pumpAndSettle();
      expect(find.textContaining('Riyadh · Asia/Riyadh'), findsOneWidget);
      expect(find.textContaining('Mecca'), findsNothing);
      await controller.select(PrayerLocationController.presets[4]);
      await tester.pumpAndSettle();
      expect(find.textContaining('Dubai · Asia/Dubai'), findsOneWidget);
      expect(find.textContaining('Riyadh · Asia/Riyadh'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Arabic GPS setup can confirm a timezone and enable real times', (
    tester,
  ) async {
    AppLocaleController.instance.setArabic(true);
    await controller.select(
      const PrayerLocation(
        latitude: 24.7136,
        longitude: 46.6753,
        label: 'Current location',
        timezoneConfirmed: false,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showPrayerSettings(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final zone = find.text('المنطقة الزمنية — اضغطي للتأكيد أو التغيير');
    await tester.scrollUntilVisible(
      zone,
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(zone);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'الرياض');
    await tester.pumpAndSettle();
    await tester.tap(find.text('السعودية — الرياض'));
    await tester.pumpAndSettle();
    expect(controller.selectedOrNull!.timezoneId, 'Asia/Riyadh');
    expect(controller.selectedOrNull!.timezoneConfirmed, isTrue);
    final vm = PrayerTrackingViewModel();
    expect(vm.schedule, isNotNull);
    vm.dispose();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('settings are accessible in Arabic RTL without overflow', (
    tester,
  ) async {
    AppLocaleController.instance.setArabic(true);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPrayerSettings(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('إعدادات مواقيت الصلاة'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('طريقة الحساب'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
