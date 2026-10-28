import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/device_timezone.dart';
import '../storage/secure_local_store.dart';
import 'user_scoped_preferences.dart';

/// A resolved location to compute prayer times for: real coordinates plus a
/// short display label (a preset city name, or the city the phone's GPS fix
/// resolved to).
class PrayerLocation extends Equatable {
  const PrayerLocation({
    required this.latitude,
    required this.longitude,
    required this.label,
    this.labelAr,
    this.fromDevice = false,
    this.timezoneId,
    this.timezoneConfirmed = true,
  });

  final double latitude;
  final double longitude;
  final String label;

  /// Arabic name of a GPS-detected city, when the phone's geocoder gave one.
  final String? labelAr;

  /// True when this came from the phone's GPS rather than a preset, so the
  /// app keeps it current as the user moves (see
  /// [PrayerLocationController.refreshDeviceLocationIfAllowed]).
  final bool fromDevice;

  /// IANA zone for the selected place, independent of the phone timezone.
  final String? timezoneId;
  final bool timezoneConfirmed;

  @override
  List<Object?> get props => [
    latitude,
    longitude,
    label,
    labelAr,
    fromDevice,
    timezoneId,
    timezoneConfirmed,
  ];
}

/// Thrown by [PrayerLocationController.useDeviceLocation] so the UI can show
/// a real message instead of the button silently doing nothing.
class LocationPermissionDenied implements Exception {
  const LocationPermissionDenied();
}

class LocationServiceDisabled implements Exception {
  const LocationServiceDisabled();
}

const _arabicLabels = {
  'Riyadh': 'الرياض',
  'Jeddah': 'جدة',
  'Mecca': 'مكة',
  'Medina': 'المدينة',
  'Dubai': 'دبي',
  'Cairo': 'القاهرة',
  'Current location': 'الموقع الحالي',
};

/// The display label for [location] in the given language — shared by
/// every screen that shows a [PrayerLocation] so the same city (or "current
/// location") always reads the same way everywhere.
String prayerLocationLabel(PrayerLocation location, {required bool isArabic}) {
  if (!isArabic) return location.label;
  return location.labelAr ?? _arabicLabels[location.label] ?? location.label;
}

class PrayerLocationController extends ChangeNotifier {
  PrayerLocationController._();

  static final PrayerLocationController instance = PrayerLocationController._();

  static const _latKey = 'niswah_prayer_location_lat';
  static const _lngKey = 'niswah_prayer_location_lng';
  static const _labelKey = 'niswah_prayer_location_label';
  static const _labelArKey = 'niswah_prayer_location_label_ar';
  static const _fromDeviceKey = 'niswah_prayer_location_from_device';
  static const _zoneKey = 'niswah_prayer_location_zone';
  static const _confirmedKey = 'niswah_prayer_zone_confirmed';
  static const _methodKey = 'niswah_prayer_method';
  static const _asrKey = 'niswah_prayer_hanafi_asr';
  static const _ramadanKey = 'niswah_prayer_ramadan_until';

  String method = 'muslimWorldLeague';
  bool hanafiAsr = false;
  DateTime? ramadanAdjustmentUntil;

  Future<void> configure({
    required String method,
    required bool hanafiAsr,
    DateTime? ramadanAdjustmentUntil,
  }) async {
    if (!{
      'muslimWorldLeague',
      'ummAlQura',
      'egyptian',
      'dubai',
      'northAmerica',
      'karachi',
    }.contains(method)) {
      throw ArgumentError('Unsupported prayer calculation method');
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(UserScopedPreferences.key(_methodKey), method);
    await preferences.setBool(UserScopedPreferences.key(_asrKey), hanafiAsr);
    if (ramadanAdjustmentUntil == null) {
      await preferences.remove(UserScopedPreferences.key(_ramadanKey));
    } else {
      await preferences.setString(
        UserScopedPreferences.key(_ramadanKey),
        ramadanAdjustmentUntil.toIso8601String(),
      );
    }
    this.method = method;
    this.hanafiAsr = hanafiAsr;
    this.ramadanAdjustmentUntil = ramadanAdjustmentUntil;
    notifyListeners();
  }

  /// A selectable preset. Prayer calculations require selectedOrNull;
  /// this must not be silently substituted for an unconfirmed location.
  static const PrayerLocation mecca = PrayerLocation(
    latitude: 21.4225,
    longitude: 39.8262,
    label: 'Mecca',
    timezoneId: 'Asia/Riyadh',
  );

  static const List<PrayerLocation> presets = [
    PrayerLocation(
      latitude: 24.7136,
      longitude: 46.6753,
      label: 'Riyadh',
      timezoneId: 'Asia/Riyadh',
    ),
    PrayerLocation(
      latitude: 21.4858,
      longitude: 39.1925,
      label: 'Jeddah',
      timezoneId: 'Asia/Riyadh',
    ),
    mecca,
    PrayerLocation(
      latitude: 24.5247,
      longitude: 39.5692,
      label: 'Medina',
      timezoneId: 'Asia/Riyadh',
    ),
    PrayerLocation(
      latitude: 25.2048,
      longitude: 55.2708,
      label: 'Dubai',
      timezoneId: 'Asia/Dubai',
    ),
    PrayerLocation(
      latitude: 30.0444,
      longitude: 31.2357,
      label: 'Cairo',
      timezoneId: 'Africa/Cairo',
    ),
  ];

  PrayerLocation? _selected;

  /// Legacy display compatibility only. Calculations use selectedOrNull.
  PrayerLocation get resolved => _selected ?? mecca;

  /// Null until the user has actually picked something — used by UI that
  /// needs to distinguish "nothing chosen yet" from "chose Mecca".
  PrayerLocation? get selectedOrNull => _selected;

  /// Reads the signed-in user's own location (never another user's).
  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    await UserScopedPreferences.adoptLegacy(preferences, const [
      _latKey,
      _lngKey,
      _labelKey,
      _labelArKey,
      _fromDeviceKey,
      _zoneKey,
      _confirmedKey,
      _methodKey,
      _asrKey,
      _ramadanKey,
    ]);
    final lat = preferences.getDouble(UserScopedPreferences.key(_latKey));
    final lng = preferences.getDouble(UserScopedPreferences.key(_lngKey));
    final label = preferences.getString(UserScopedPreferences.key(_labelKey));
    final labelAr = preferences.getString(
      UserScopedPreferences.key(_labelArKey),
    );
    final zone = preferences.getString(UserScopedPreferences.key(_zoneKey));
    method =
        preferences.getString(UserScopedPreferences.key(_methodKey)) ??
        'muslimWorldLeague';
    hanafiAsr =
        preferences.getBool(UserScopedPreferences.key(_asrKey)) ?? false;
    ramadanAdjustmentUntil = DateTime.tryParse(
      preferences.getString(UserScopedPreferences.key(_ramadanKey)) ?? '',
    );
    // Upgrade known presets only. Legacy GPS coordinates without a known
    // timezone must be confirmed again, rather than guessing an offset.
    String? presetZone;
    for (final preset in presets) {
      if (preset.latitude == lat && preset.longitude == lng) {
        presetZone = preset.timezoneId;
      }
    }
    _selected = (lat != null && lng != null && label != null)
        ? PrayerLocation(
            latitude: lat,
            longitude: lng,
            label: label,
            labelAr: labelAr,
            // Older builds saved GPS fixes as "Current location" without
            // this flag. An unconfirmed one is treated as device-based so it
            // gets a real city and zone on the next refresh; one whose zone
            // she confirmed by hand keeps that choice.
            fromDevice:
                preferences.getBool(
                  UserScopedPreferences.key(_fromDeviceKey),
                ) ??
                (label == _legacyDeviceLabel &&
                    preferences.getBool(
                          UserScopedPreferences.key(_confirmedKey),
                        ) !=
                        true),
            timezoneId: zone ?? presetZone,
            timezoneConfirmed:
                preferences.getBool(UserScopedPreferences.key(_confirmedKey)) ??
                presetZone != null,
          )
        : null;
    notifyListeners();
  }

  /// Forgets the in-memory location (sign-out) so the next account can never
  /// observe it before its own [load] completes.
  void resetInMemory() {
    _selected = null;
    method = 'muslimWorldLeague';
    hanafiAsr = false;
    ramadanAdjustmentUntil = null;
    notifyListeners();
  }

  Future<void> select(PrayerLocation location) async {
    if (!location.latitude.isFinite ||
        !location.longitude.isFinite ||
        location.latitude.abs() > 90 ||
        location.longitude.abs() > 180) {
      throw ArgumentError('Invalid prayer coordinates');
    }
    final owner = SecureLocalStore.currentUserId();
    final keys = {for (final key in [_latKey, _lngKey, _labelKey, _labelArKey, _fromDeviceKey, _zoneKey, _confirmedKey]) key: UserScopedPreferences.key(key)};
    final preferences = await SharedPreferences.getInstance();
    if (SecureLocalStore.currentUserId() != owner) return;
    await preferences.setDouble(
      keys[_latKey]!,
      location.latitude,
    );
    await preferences.setDouble(
      keys[_lngKey]!,
      location.longitude,
    );
    await preferences.setString(
      keys[_labelKey]!,
      location.label,
    );
    if (location.labelAr != null) {
      await preferences.setString(
        keys[_labelArKey]!,
        location.labelAr!,
      );
    } else {
      await preferences.remove(keys[_labelArKey]!);
    }
    await preferences.setBool(
      keys[_fromDeviceKey]!,
      location.fromDevice,
    );
    if (location.timezoneId != null) {
      await preferences.setString(
        keys[_zoneKey]!,
        location.timezoneId!,
      );
    } else {
      await preferences.remove(keys[_zoneKey]!);
    }
    await preferences.setBool(
      keys[_confirmedKey]!,
      location.timezoneConfirmed,
    );
    if (SecureLocalStore.currentUserId() != owner) return;
    _selected = location;
    notifyListeners();
  }

  /// Requests location permission, gets a real GPS fix, persists it, and
  /// returns it. Throws [LocationServiceDisabled] or
  /// [LocationPermissionDenied] on failure so the caller can show a real
  /// message rather than silently doing nothing (the bug this replaces).
  Future<PrayerLocation> useDeviceLocation() async {
    final owner = SecureLocalStore.currentUserId();
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationServiceDisabled();
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const LocationPermissionDenied();
    }

    // Bounded: with permission granted but no GPS fix (indoors, emulator, GPS
    // off) getCurrentPosition() otherwise never completes and the screen
    // spins on "detecting" forever (found live on Android). A timeout falls
    // into the caller's honest "Unable to get your location" path.
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        timeLimit: Duration(seconds: 20),
      ),
    );
    final location = await resolveDeviceLocation(
      position.latitude,
      position.longitude,
    );
    if (SecureLocalStore.currentUserId() != owner) {
      throw StateError('Account changed during location lookup.');
    }
    await select(location);
    return location;
  }

  /// Keeps a GPS-based location current without asking the user: when the
  /// saved place came from the phone and location
  /// permission was already granted, takes a fresh fix and updates the city
  /// and timezone if she has moved. Never shows a permission prompt and
  /// never replaces a city she picked by hand. Best-effort: any failure
  /// leaves the saved location as it was.
  Future<void> refreshDeviceLocationIfAllowed() async {
    final current = _selected;
    if (current == null || !current.fromDevice) return;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
      // A manual pick made while the fix was in flight wins.
      if (_selected != current) return;
      final zone = await deviceTimezone();
      // Without the phone's zone the refresh would save an unusable,
      // unconfirmed location over a working one; keep what is saved.
      if (zone == null || zone.isEmpty) return;
      if (current.label != _legacyDeviceLabel &&
          current.timezoneConfirmed &&
          current.timezoneId == zone &&
          Geolocator.distanceBetween(
                current.latitude,
                current.longitude,
                position.latitude,
                position.longitude,
              ) <
              refreshDistanceMeters) {
        return;
      }
      final location = await resolveDeviceLocation(
        position.latitude,
        position.longitude,
      );
      if (_selected != current) return;
      await select(location);
    } catch (error) {
      debugPrint('PrayerLocationController: background refresh failed: $error');
    }
  }

  /// How far she has to move before a background refresh re-resolves the
  /// city; small enough that crossing into a neighbouring city updates it.
  static const double refreshDistanceMeters = 3000;

  /// Test seam for the phone's reverse geocoder.
  @visibleForTesting
  static Future<List<Placemark>> Function(
    double latitude,
    double longitude,
    Locale locale,
  )
  placemarkLookup = _nativePlacemarks;

  /// Test seam for the phone's IANA timezone.
  @visibleForTesting
  static Future<String?> Function() deviceTimezone = () =>
      DeviceTimezone.currentId(forceRefresh: true);

  static Future<List<Placemark>> _nativePlacemarks(
    double latitude,
    double longitude,
    Locale locale,
  ) =>
      Geocoding().placemarkFromCoordinates(latitude, longitude, locale: locale);

  /// Turns a GPS fix into a named place: the city from the phone's own
  /// reverse geocoder (Apple/Google, no key, no extra service), in English
  /// and Arabic, and the phone's IANA timezone. The phone's zone is used
  /// because the fix is where the phone is right now, and phones set their
  /// zone from the network. If the geocoder is unreachable (offline) the
  /// label stays generic and the next refresh fills it in.
  @visibleForTesting
  Future<PrayerLocation> resolveDeviceLocation(
    double latitude,
    double longitude,
  ) async {
    final english = await _cityName(latitude, longitude, const Locale('en'));
    final arabic = english == null
        ? null
        : await _cityName(latitude, longitude, const Locale('ar'));
    final zone = await deviceTimezone();
    return PrayerLocation(
      latitude: latitude,
      longitude: longitude,
      label: english ?? _legacyDeviceLabel,
      labelAr: arabic,
      fromDevice: true,
      timezoneId: zone,
      timezoneConfirmed: zone != null && zone.isNotEmpty,
    );
  }

  static Future<String?> _cityName(
    double latitude,
    double longitude,
    Locale locale,
  ) async {
    try {
      final places = await placemarkLookup(latitude, longitude, locale);
      for (final place in places) {
        for (final name in [
          place.locality,
          place.subAdministrativeArea,
          place.administrativeArea,
        ]) {
          final trimmed = name?.trim();
          if (trimmed != null && trimmed.isNotEmpty) return trimmed;
        }
      }
    } catch (error) {
      debugPrint('PrayerLocationController: reverse geocoding failed: $error');
    }
    return null;
  }
}

const _legacyDeviceLabel = 'Current location';
