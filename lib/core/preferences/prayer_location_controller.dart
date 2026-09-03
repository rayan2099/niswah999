import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A resolved location to compute prayer times for: real coordinates plus a
/// short display label (a preset city name, or "Current location").
class PrayerLocation extends Equatable {
  const PrayerLocation({
    required this.latitude,
    required this.longitude,
    required this.label,
  });

  final double latitude;
  final double longitude;
  final String label;

  @override
  List<Object?> get props => [latitude, longitude, label];
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
  return _arabicLabels[location.label] ?? location.label;
}

class PrayerLocationController extends ChangeNotifier {
  PrayerLocationController._();

  static final PrayerLocationController instance = PrayerLocationController._();

  static const _latKey = 'niswah_prayer_location_lat';
  static const _lngKey = 'niswah_prayer_location_lng';
  static const _labelKey = 'niswah_prayer_location_label';

  /// A religiously-neutral, always-sensible default when no location has
  /// ever been resolved — never falls back to the old flat hardcoded clock
  /// times, which weren't correct for any real place or date.
  static const PrayerLocation mecca = PrayerLocation(
    latitude: 21.4225,
    longitude: 39.8262,
    label: 'Mecca',
  );

  static const List<PrayerLocation> presets = [
    PrayerLocation(latitude: 24.7136, longitude: 46.6753, label: 'Riyadh'),
    PrayerLocation(latitude: 21.4858, longitude: 39.1925, label: 'Jeddah'),
    mecca,
    PrayerLocation(latitude: 24.5247, longitude: 39.5692, label: 'Medina'),
    PrayerLocation(latitude: 25.2048, longitude: 55.2708, label: 'Dubai'),
    PrayerLocation(latitude: 30.0444, longitude: 31.2357, label: 'Cairo'),
  ];

  PrayerLocation? _selected;

  /// The location to compute prayer times for right now — never null, so
  /// callers never need their own fallback branch.
  PrayerLocation get resolved => _selected ?? mecca;

  /// Null until the user has actually picked something — used by UI that
  /// needs to distinguish "nothing chosen yet" from "chose Mecca".
  PrayerLocation? get selectedOrNull => _selected;

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final lat = preferences.getDouble(_latKey);
    final lng = preferences.getDouble(_lngKey);
    final label = preferences.getString(_labelKey);
    if (lat != null && lng != null && label != null) {
      _selected = PrayerLocation(latitude: lat, longitude: lng, label: label);
    }
  }

  Future<void> select(PrayerLocation location) async {
    _selected = location;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(_latKey, location.latitude);
    await preferences.setDouble(_lngKey, location.longitude);
    await preferences.setString(_labelKey, location.label);
  }

  /// Requests location permission, gets a real GPS fix, persists it, and
  /// returns it. Throws [LocationServiceDisabled] or
  /// [LocationPermissionDenied] on failure so the caller can show a real
  /// message rather than silently doing nothing (the bug this replaces).
  Future<PrayerLocation> useDeviceLocation() async {
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

    final position = await Geolocator.getCurrentPosition();
    final location = PrayerLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      label: 'Current location',
    );
    await select(location);
    return location;
  }
}
