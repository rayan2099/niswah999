import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:niswah/core/preferences/prayer_location_controller.dart';
import 'package:niswah/features/notifications/domain/services/prayer_reminder_scheduler.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);
  const makkah = PrayerLocation(
    latitude: 21.427009,
    longitude: 39.828685,
    label: 'Mecca',
    timezoneId: 'Asia/Riyadh',
  );
  test('Makkah reference Fajr with fifteen-minute lead is 02:23 UTC', () {
    final plans = PrayerReminderScheduler.plan(
      userId: 'u',
      location: makkah,
      now: DateTime.utc(2016, 1, 4, 22),
      method: 'ummAlQura',
      hanafiAsr: false,
      leadMinutes: 15,
    );
    expect(plans.length, 25);
    expect(plans.first.fireAt, DateTime.utc(2016, 1, 5, 2, 23));
    expect(plans.map((p) => p.id).toSet().length, 25);
    expect(plans.every((p) => p.fireAt.isUtc), isTrue);
  });
  test('Raleigh Hanafi reference Asr and Fajr preserve selected zone', () {
    const location = PrayerLocation(
      latitude: 35.775,
      longitude: -78.6336,
      label: 'Raleigh',
      timezoneId: 'America/New_York',
    );
    final plans = PrayerReminderScheduler.plan(
      userId: 'u',
      location: location,
      now: DateTime.utc(2015, 7, 12, 4),
      method: 'northAmerica',
      hanafiAsr: true,
      leadMinutes: 15,
    );
    expect(plans[0].fireAt, DateTime.utc(2015, 7, 12, 8, 27));
    expect(plans[2].fireAt, DateTime.utc(2015, 7, 12, 22, 7));
  });
  test('DST window covers five distinct calendar days within slot budget', () {
    const location = PrayerLocation(
      latitude: 40.7128,
      longitude: -74.006,
      label: 'New York',
      timezoneId: 'America/New_York',
    );
    final now = DateTime.utc(2030, 11, 2, 4);
    final plans = PrayerReminderScheduler.plan(
      userId: 'u',
      location: location,
      now: now,
      method: 'northAmerica',
      hanafiAsr: false,
      leadMinutes: 0,
    );
    final zone = tz.getLocation('America/New_York');
    expect(plans.length, 25);
    expect(plans.map((p) => tz.TZDateTime.from(p.fireAt, zone).day).toSet(), {
      2,
      3,
      4,
      5,
      6,
    });
    expect(plans.every((p) => p.fireAt.isAfter(now)), isTrue);
    expect(plans.length + 30 + 4, lessThan(64));
  });
  test(
    'unconfirmed location or invalid lead cannot create guessed reminders',
    () {
      for (final location in [
        null,
        const PrayerLocation(
          latitude: 21.4,
          longitude: 39.8,
          label: 'Mecca',
          timezoneId: 'Asia/Riyadh',
          timezoneConfirmed: false,
        ),
      ]) {
        expect(
          PrayerReminderScheduler.plan(
            userId: 'u',
            location: location,
            now: DateTime.utc(2030),
            method: 'ummAlQura',
            hanafiAsr: false,
            leadMinutes: 15,
          ),
          isEmpty,
        );
      }
      expect(
        PrayerReminderScheduler.plan(
          userId: 'u',
          location: makkah,
          now: DateTime.utc(2030),
          method: 'ummAlQura',
          hanafiAsr: false,
          leadMinutes: 121,
        ),
        isEmpty,
      );
    },
  );
}
