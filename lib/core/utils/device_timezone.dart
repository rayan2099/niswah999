import 'package:flutter_timezone/flutter_timezone.dart';

/// PR #4 completion wave, Fix B: a real IANA timezone identifier
/// ("Asia/Riyadh", "America/Vancouver") — never inferred from a city, GPS
/// coordinates, or a UTC offset (an offset alone cannot distinguish, say,
/// a country that observes DST from one at the same current offset that
/// doesn't; only a named zone can be reinterpreted correctly as rules
/// change over time, which matters for *future* local-time interpretation
/// — reminder scheduling — even though it is not needed for reconstructing
/// what a past instant's local date already was).
///
/// `DateTime.timeZoneName` (Dart core) only ever returns a
/// platform-dependent abbreviation ("AST", "GMT+3") — ambiguous, and
/// intentionally never used for this reason (see
/// `ObservationSource`/`utc_offset_minutes` for the offset-based fields
/// this app already relies on for exact historical reconstruction).
class DeviceTimezone {
  DeviceTimezone._();

  static String? _cached;

  /// Best-effort: returns null (never throws) if the platform channel is
  /// unavailable — a caller must treat this as optional metadata, not a
  /// required field, exactly as the schema already models it
  /// (`bleeding_observations.timezone` is nullable).
  static Future<String?> currentId() async {
    final cached = _cached;
    if (cached != null) return cached;
    try {
      final id = await FlutterTimezone.getLocalTimezone();
      _cached = id;
      return id;
    } catch (_) {
      return null;
    }
  }
}
