import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/preferences/prayer_location_controller.dart';
import '../../../../core/utils/app_clock.dart';
import '../../domain/services/prayer_schedule_builder.dart';
import '../../domain/entities/prayer_entry.dart';
import '../../domain/repositories/prayer_tracking_repository.dart';
import '../../data/repositories/prayer_tracking_repository_impl.dart';

class PrayerTrackingViewModel extends ChangeNotifier {
  PrayerTrackingViewModel({
    PrayerTrackingRepository? repository,
    PrayerLocationController? locationController,
  }) : _repository = repository ?? PrayerTrackingRepositoryImpl(),
       _locationController =
           locationController ?? PrayerLocationController.instance {
    _locationController.addListener(_locationChanged);
  }

  void _locationChanged() {
    // A location change may cross a civil date boundary. Always reload so
    // the new city's day cannot inherit the previous day's visible entries.
    final userId = _userId;
    if (userId != null) unawaited(loadToday(userId: userId));
    if (!_disposed) notifyListeners();
  }

  DateTime? _loadedDate;
  void refresh() {
    if (_disposed) return;
    final userId = _userId;
    if (userId != null &&
        (_loadedDate == null || !_sameDate(_loadedDate!, prayerDate))) {
      unawaited(loadToday(userId: userId));
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _locationController.removeListener(_locationChanged);
    super.dispose();
  }

  bool _disposed = false;
  int _loadGeneration = 0;
  String? _userId;
  PrayerLocation? get location => _locationController.selectedOrNull;
  PrayerLocationController get settings => _locationController;

  final PrayerTrackingRepository _repository;
  final PrayerLocationController _locationController;

  bool isLoading = false;
  String? errorMessage;
  List<PrayerEntry> entries = const <PrayerEntry>[];

  /// No silently substituted city or device timezone. Unavailable times
  /// are represented explicitly so both prayer surfaces can ask for setup.
  PrayerSchedule? get schedule {
    final selected = location;
    if (selected == null) return null;
    try {
      return PrayerScheduleBuilder.build(
        location: selected,
        now: AppClock.now(),
        method: settings.method,
        hanafiAsr: settings.hanafiAsr,
        ramadanAdjustmentUntil: settings.ramadanAdjustmentUntil,
      );
    } catch (_) {
      return null;
    }
  }

  DateTime get prayerDate {
    final local = schedule?.date ?? AppClock.now();
    // A log key is a civil calendar date, not midnight as an instant.
    // Offset-bearing midnight strings otherwise deserialize as yesterday UTC.
    return DateTime(local.year, local.month, local.day);
  }

  static bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> loadToday({required String userId}) async {
    final generation = ++_loadGeneration;
    _userId = userId;
    entries = const [];
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final today = prayerDate;
      _loadedDate = today;
      final loaded = await _repository.getDailyPrayerLog(today, userId: userId);
      if (!_disposed && generation == _loadGeneration) entries = loaded;
    } catch (error) {
      if (!_disposed && generation == _loadGeneration) {
        errorMessage = error.toString();
      }
    } finally {
      if (!_disposed && generation == _loadGeneration) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> togglePrayerStatus({
    required String userId,
    required PrayerName prayerName,
    required PrayerStatus status,
    String? notes,
  }) async {
    if (status == PrayerStatus.pending) {
      throw ArgumentError('Choose a recorded prayer status');
    }
    final currentSchedule = schedule;
    if (currentSchedule == null) {
      throw StateError('Confirm prayer settings first');
    }
    if (userId != _userId) throw StateError('Prayer account changed');
    final day = currentSchedule.date;
    final date = DateTime(day.year, day.month, day.day);
    final scheduledTime = currentSchedule.timeFor(prayerName)!;
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

    final generation = _loadGeneration;
    await _repository.savePrayer(updated);
    final loaded = await _repository.getDailyPrayerLog(date, userId: userId);
    if (!_disposed && generation == _loadGeneration) {
      entries = loaded;
      notifyListeners();
    }
  }

  PrayerStatus statusFor(PrayerName prayerName) {
    final date = prayerDate;
    for (final entry in entries) {
      if (entry.userId == _userId &&
          entry.prayerName == prayerName &&
          _sameDate(entry.date, date)) {
        return entry.status;
      }
    }
    return PrayerStatus.pending;
  }

  PrayerSchedule? getTodaySchedule() => schedule;
}
