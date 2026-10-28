import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:niswah/core/preferences/prayer_location_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final controller = PrayerLocationController.instance;
  final originalLookup = PrayerLocationController.placemarkLookup;
  final originalZone = PrayerLocationController.deviceTimezone;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    controller.resetInMemory();
    PrayerLocationController.deviceTimezone = () async => 'Asia/Riyadh';
  });

  tearDown(() {
    PrayerLocationController.placemarkLookup = originalLookup;
    PrayerLocationController.deviceTimezone = originalZone;
  });

  test('a GPS fix resolves to the city name in both languages and the '
      'phone timezone, confirmed', () async {
    final locales = <String>[];
    PrayerLocationController.placemarkLookup = (lat, lng, locale) async {
      locales.add(locale.languageCode);
      return [
        Placemark(
          locality: locale.languageCode == 'ar' ? 'الخبر' : 'Al Khobar',
          administrativeArea: 'Eastern Province',
        ),
      ];
    };

    final location = await controller.resolveDeviceLocation(26.2172, 50.1971);

    expect(locales, ['en', 'ar']);
    expect(location.label, 'Al Khobar');
    expect(location.labelAr, 'الخبر');
    expect(location.fromDevice, isTrue);
    expect(location.timezoneId, 'Asia/Riyadh');
    expect(location.timezoneConfirmed, isTrue);
    expect(prayerLocationLabel(location, isArabic: true), 'الخبر');
    expect(prayerLocationLabel(location, isArabic: false), 'Al Khobar');
  });

  test('falls back to the region when the geocoder has no locality', () async {
    PrayerLocationController.placemarkLookup = (lat, lng, locale) async => [
      const Placemark(subAdministrativeArea: '  ', administrativeArea: 'Asir'),
    ];

    final location = await controller.resolveDeviceLocation(18.2, 42.5);

    expect(location.label, 'Asir');
  });

  test('offline geocoder keeps a generic label but still sets the zone, '
      'so prayer times work', () async {
    PrayerLocationController.placemarkLookup = (lat, lng, locale) async =>
        throw Exception('network');

    final location = await controller.resolveDeviceLocation(26.2, 50.2);

    expect(location.label, 'Current location');
    expect(location.labelAr, isNull);
    expect(location.timezoneId, 'Asia/Riyadh');
    expect(location.timezoneConfirmed, isTrue);
  });

  test('no phone timezone leaves the zone unconfirmed', () async {
    PrayerLocationController.placemarkLookup = (lat, lng, locale) async => [];
    PrayerLocationController.deviceTimezone = () async => null;

    final location = await controller.resolveDeviceLocation(26.2, 50.2);

    expect(location.timezoneConfirmed, isFalse);
  });

  test('detected city and its Arabic name survive a restart', () async {
    await controller.select(
      const PrayerLocation(
        latitude: 26.2172,
        longitude: 50.1971,
        label: 'Al Khobar',
        labelAr: 'الخبر',
        fromDevice: true,
        timezoneId: 'Asia/Riyadh',
      ),
    );
    controller.resetInMemory();
    await controller.load();

    final loaded = controller.selectedOrNull!;
    expect(loaded.label, 'Al Khobar');
    expect(loaded.labelAr, 'الخبر');
    expect(loaded.fromDevice, isTrue);
  });

  test('an older build\'s "Current location" is treated as GPS-based so it '
      'gets refreshed', () async {
    SharedPreferences.setMockInitialValues({
      'niswah_prayer_location_lat': 26.2,
      'niswah_prayer_location_lng': 50.2,
      'niswah_prayer_location_label': 'Current location',
    });
    await controller.load();

    expect(controller.selectedOrNull!.fromDevice, isTrue);
  });

  test(
    'a hand-picked city is never replaced by the background refresh',
    () async {
      var lookups = 0;
      PrayerLocationController.placemarkLookup = (lat, lng, locale) async {
        lookups++;
        return [];
      };
      final cairo = PrayerLocationController.presets.last;
      await controller.select(cairo);

      await controller.refreshDeviceLocationIfAllowed();

      expect(controller.selectedOrNull, cairo);
      expect(lookups, 0);
    },
  );
}
