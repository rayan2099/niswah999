import 'package:adhan_dart/adhan_dart.dart' as adhan;
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../../../core/preferences/prayer_location_controller.dart';
import '../entities/prayer_entry.dart';

/// Astronomical start times only. This does not decide worship, menstruation,
/// qadha, or the end of a prayer's valid/preferred window.
class PrayerScheduleBuilder {
  static bool _initialized = false;

  static void initializeZones() {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    _initialized = true;
  }

  static tz.Location zoneFor(PrayerLocation location) {
    initializeZones();
    final id = location.timezoneId;
    if (!location.timezoneConfirmed || id == null || id.isEmpty) {
      throw StateError('Confirm the location timezone');
    }
    return tz.getLocation(id);
  }

  static PrayerSchedule build({
    required PrayerLocation location,
    required DateTime now,
    required String method,
    required bool hanafiAsr,
    DateTime? ramadanAdjustmentUntil,
  }) {
    if (!location.latitude.isFinite ||
        !location.longitude.isFinite ||
        location.latitude.abs() > 90 ||
        location.longitude.abs() > 180) {
      throw ArgumentError('Invalid prayer coordinates');
    }
    final zone = zoneFor(location);
    final date = tz.TZDateTime.from(now, zone);
    final parameters = switch (method) {
      'ummAlQura' => adhan.CalculationMethodParameters.ummAlQura(),
      'egyptian' => adhan.CalculationMethodParameters.egyptian(),
      'dubai' => adhan.CalculationMethodParameters.dubai(),
      'northAmerica' => adhan.CalculationMethodParameters.northAmerica(),
      'karachi' => adhan.CalculationMethodParameters.karachi(),
      'muslimWorldLeague' =>
        adhan.CalculationMethodParameters.muslimWorldLeague(),
      _ => throw ArgumentError('Unsupported prayer calculation method'),
    };
    parameters.madhab = hanafiAsr ? adhan.Madhab.hanafi : adhan.Madhab.shafi;
    // The user explicitly confirms the local Ramadan end date. No guessed
    // lunar calendar; the adjustment stops on the selected inclusive date.
    if (method == 'ummAlQura' &&
        ramadanAdjustmentUntil != null &&
        !DateTime.utc(date.year, date.month, date.day).isAfter(
          DateTime.utc(
            ramadanAdjustmentUntil.year,
            ramadanAdjustmentUntil.month,
            ramadanAdjustmentUntil.day,
          ),
        )) {
      parameters.adjustments[adhan.Prayer.isha] = 30;
    }
    final times = adhan.PrayerTimes(
      coordinates: adhan.Coordinates(location.latitude, location.longitude),
      date: DateTime.utc(date.year, date.month, date.day),
      calculationParameters: parameters,
    );
    final instants = <PrayerName, DateTime>{
      PrayerName.fajr: times.fajr.toUtc(),
      PrayerName.dhuhr: times.dhuhr.toUtc(),
      PrayerName.asr: times.asr.toUtc(),
      PrayerName.maghrib: times.maghrib.toUtc(),
      PrayerName.isha: times.isha.toUtc(),
    };
    DateTime? previous;
    for (final instant in instants.values) {
      // At polar extremes the library may not produce a usable schedule.
      // Never present a placeholder date or a reversed sequence as real times.
      if (instant.difference(now.toUtc()).inHours.abs() > 48 ||
          (previous != null && !instant.isAfter(previous))) {
        throw StateError('Prayer times unavailable for this place and date');
      }
      previous = instant;
    }
    TimeOfDay display(PrayerName name) {
      final local = tz.TZDateTime.from(instants[name]!, zone);
      return TimeOfDay(hour: local.hour, minute: local.minute);
    }

    return PrayerSchedule(
      date: tz.TZDateTime(zone, date.year, date.month, date.day),
      fajr: display(PrayerName.fajr),
      dhuhr: display(PrayerName.dhuhr),
      asr: display(PrayerName.asr),
      maghrib: display(PrayerName.maghrib),
      isha: display(PrayerName.isha),
      instants: Map.unmodifiable(instants),
    );
  }
}
