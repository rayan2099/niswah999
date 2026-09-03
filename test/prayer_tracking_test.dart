import 'package:adhan_dart/adhan_dart.dart' as adhan;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:niswah/core/preferences/prayer_location_controller.dart';
import 'package:niswah/core/utils/app_clock.dart';
import 'package:niswah/features/prayer_tracking/domain/entities/prayer_entry.dart';
import 'package:niswah/features/prayer_tracking/domain/controllers/prayer_time_calculator.dart';
import 'package:niswah/features/prayer_tracking/data/repositories/prayer_tracking_repository_impl.dart';
import 'package:niswah/features/prayer_tracking/presentation/viewmodels/prayer_tracking_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('PrayerTimeCalculator', () {
    test('computes the next prayer from a daily schedule', () {
      final schedule = PrayerSchedule(
        date: DateTime(2026, 8, 18),
        fajr: const TimeOfDay(hour: 5, minute: 30),
        dhuhr: const TimeOfDay(hour: 13, minute: 0),
        asr: const TimeOfDay(hour: 16, minute: 30),
        maghrib: const TimeOfDay(hour: 19, minute: 5),
        isha: const TimeOfDay(hour: 21, minute: 0),
      );

      final next = PrayerTimeCalculator.nextPrayer(
        schedule: schedule,
        now: DateTime(2026, 8, 18, 12, 45),
      );

      expect(next.name, PrayerName.dhuhr);
    });

    test('marks prayers as missed when the scheduled time has already passed', () {
      final schedule = PrayerSchedule(
        date: DateTime(2026, 8, 18),
        fajr: const TimeOfDay(hour: 5, minute: 30),
        dhuhr: const TimeOfDay(hour: 13, minute: 0),
        asr: const TimeOfDay(hour: 16, minute: 30),
        maghrib: const TimeOfDay(hour: 19, minute: 5),
        isha: const TimeOfDay(hour: 21, minute: 0),
      );

      final status = PrayerTimeCalculator.statusFor(
        schedule: schedule,
        prayerName: PrayerName.fajr,
        now: DateTime(2026, 8, 18, 6, 20),
      );

      expect(status, PrayerStatus.missed);
    });
  });

  group('PrayerTrackingRepositoryImpl', () {
    test('persists and reads prayer logs for the active day', () async {
      final repository = PrayerTrackingRepositoryImpl();
      final date = DateTime(2026, 8, 18);

      final entry = PrayerEntry(
        id: 'entry-1',
        userId: 'user-1',
        prayerName: PrayerName.fajr,
        date: date,
        scheduledTime: const TimeOfDay(hour: 5, minute: 30),
        status: PrayerStatus.completed,
        notes: 'On time',
      );

      await repository.savePrayer(entry);
      final pattern = await repository.getDailyPrayerLog(date, userId: 'user-1');

      expect(pattern.length, 1);
      expect(pattern.first.id, 'entry-1');
      expect(pattern.first.status, PrayerStatus.completed);
    });
  });

  group('PrayerTrackingViewModel.schedule', () {
    tearDown(AppClock.reset);

    test('falls back to Mecca when no location has ever been selected', () {
      final controller = PrayerLocationController.instance;
      expect(controller.resolved, PrayerLocationController.mecca);

      final viewModel = PrayerTrackingViewModel(
        locationController: controller,
      );
      // Doesn't crash, and produces a schedule for today.
      expect(viewModel.schedule.fajr.isValid, isTrue);
    });

    test(
      'computes real, location-based times instead of the old flat clock',
      () async {
        AppClock.now = () => DateTime(2026, 8, 18, 12);

        final controller = PrayerLocationController.instance;
        await controller.select(
          const PrayerLocation(
            latitude: 24.7136,
            longitude: 46.6753,
            label: 'Riyadh',
          ),
        );

        final viewModel = PrayerTrackingViewModel(
          locationController: controller,
        );

        // Independently computed via adhan_dart directly, using the same
        // inputs the view model uses — this is the oracle, not a hardcoded
        // wall-clock string (which would only hold on this machine's
        // timezone).
        final reference = adhan.PrayerTimes(
          date: AppClock.now(),
          coordinates: const adhan.Coordinates(24.7136, 46.6753),
          calculationParameters:
              adhan.CalculationMethodParameters.muslimWorldLeague(),
        );
        TimeOfDay expected(DateTime utc) {
          final local = utc.toLocal();
          return TimeOfDay(hour: local.hour, minute: local.minute);
        }

        final schedule = viewModel.schedule;
        expect(schedule.fajr, expected(reference.fajr));
        expect(schedule.dhuhr, expected(reference.dhuhr));
        expect(schedule.asr, expected(reference.asr));
        expect(schedule.maghrib, expected(reference.maghrib));
        expect(schedule.isha, expected(reference.isha));
      },
    );
  });
}
