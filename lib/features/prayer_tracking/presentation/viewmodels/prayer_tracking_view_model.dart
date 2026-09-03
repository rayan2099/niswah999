import 'package:adhan_dart/adhan_dart.dart' as adhan;
import 'package:flutter/foundation.dart';

import '../../../../core/preferences/prayer_location_controller.dart';
import '../../../../core/utils/app_clock.dart';
import '../../domain/controllers/prayer_time_calculator.dart';
import '../../domain/entities/prayer_entry.dart';
import '../../domain/repositories/prayer_tracking_repository.dart';
import '../../data/repositories/prayer_tracking_repository_impl.dart';

class PrayerTrackingViewModel extends ChangeNotifier {
  PrayerTrackingViewModel({
    PrayerTrackingRepository? repository,
    PrayerLocationController? locationController,
  }) : _repository = repository ?? PrayerTrackingRepositoryImpl(),
       _locationController =
           locationController ?? PrayerLocationController.instance;

  final PrayerTrackingRepository _repository;
  final PrayerLocationController _locationController;

  bool isLoading = false;
  String? errorMessage;
  List<PrayerEntry> entries = const <PrayerEntry>[];

  /// Real, location-based prayer times for today — computed fresh from
  /// [PrayerLocationController]'s resolved coordinates (Mecca until the
  /// user picks somewhere else) rather than a fixed hardcoded clock.
  PrayerSchedule get schedule => _buildSchedule(AppClock.now());

  PrayerSchedule _buildSchedule(DateTime date) {
    final location = _locationController.resolved;
    final times = adhan.PrayerTimes(
      date: date,
      coordinates: adhan.Coordinates(location.latitude, location.longitude),
      calculationParameters: adhan.CalculationMethodParameters
          .muslimWorldLeague(),
    );
    return PrayerSchedule(
      date: date,
      fajr: _toTimeOfDay(times.fajr),
      dhuhr: _toTimeOfDay(times.dhuhr),
      asr: _toTimeOfDay(times.asr),
      maghrib: _toTimeOfDay(times.maghrib),
      isha: _toTimeOfDay(times.isha),
    );
  }

  TimeOfDay _toTimeOfDay(DateTime utc) {
    final local = utc.toLocal();
    return TimeOfDay(hour: local.hour, minute: local.minute);
  }

  Future<void> loadToday({required String userId}) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final today = AppClock.now();
      entries = await _repository.getDailyPrayerLog(today, userId: userId);
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> togglePrayerStatus({
    required String userId,
    required PrayerName prayerName,
    required PrayerStatus status,
    String? notes,
  }) async {
    final date = AppClock.now();
    final scheduledTime =
        schedule.timeFor(prayerName) ?? const TimeOfDay(hour: 0, minute: 0);
    final existing = entries.firstWhere(
      (entry) =>
          entry.prayerName == prayerName &&
          entry.userId == userId &&
          DateTime(
            entry.date.year,
            entry.date.month,
            entry.date.day,
          ).isAtSameMomentAs(DateTime(date.year, date.month, date.day)),
      orElse: () => PrayerEntry(
        id: '${userId}_${prayerName.name}_${date.year}-${date.month}-${date.day}',
        userId: userId,
        prayerName: prayerName,
        date: date,
        scheduledTime: scheduledTime,
        status: PrayerStatus.pending,
      ),
    );

    final updated = existing.copyWith(
      status: status,
      notes: notes ?? existing.notes,
      completedAt: status == PrayerStatus.completed ? AppClock.now() : null,
      updatedAt: AppClock.now(),
    );

    await _repository.savePrayer(updated);
    entries = await _repository.getDailyPrayerLog(date, userId: userId);
    notifyListeners();
  }

  PrayerStatus statusFor(PrayerName prayerName) {
    final entry = entries.firstWhere(
      (item) => item.prayerName == prayerName,
      orElse: () => PrayerEntry(
        id: '${prayerName.name}_placeholder',
        userId: 'local',
        prayerName: prayerName,
        date: AppClock.now(),
        scheduledTime:
            schedule.timeFor(prayerName) ?? const TimeOfDay(hour: 0, minute: 0),
        status: PrayerTimeCalculator.statusFor(
          schedule: schedule,
          prayerName: prayerName,
          now: AppClock.now(),
        ),
      ),
    );

    return entry.status;
  }

  PrayerSchedule getTodaySchedule() => schedule;
}
