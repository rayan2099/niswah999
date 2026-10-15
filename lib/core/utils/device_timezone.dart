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

  /// Hardening 3: a lifetime cache was a real bug, not a hypothetical one
  /// — a woman who boards a flight while the app stays alive in the
  /// background (or simply changes her phone's timezone manually) would
  /// have every future reminder computed against a stale zone forever,
  /// with no way to recover short of reinstalling. `_cached` still exists
  /// (repeatedly hitting the platform channel for every observation write
  /// would be wasteful and this value rarely changes second-to-second),
  /// but it is no longer permanent: [invalidateCache] must be called
  /// whenever the zone may plausibly have changed — app resume is the one
  /// wired up today (see `main.dart`'s `didChangeAppLifecycleState`) —
  /// and any future timezone-sensitive scheduling path (Commit E's
  /// reminder recomputation) must call it, or pass [forceRefresh], before
  /// trusting the result for that decision.
  ///
  /// Never retroactively affects already-recorded observations —
  /// `timezone_id_at_observation`/`utc_offset_minutes_at_observation` are
  /// historical snapshots taken at write time and must never be rewritten
  /// after a later travel/zone change; this cache only ever feeds *new*
  /// writes and *future* reminder computation.
  static String? _cached;

  /// Best-effort: returns null (never throws) if the platform channel is
  /// unavailable — a caller must treat this as optional metadata, not a
  /// required field, exactly as the schema already models it
  /// (`bleeding_observations.timezone` is nullable).
  ///
  /// Pass [forceRefresh] when the caller specifically needs the current
  /// real value regardless of what was last cached (a timezone-sensitive
  /// reminder recomputation should always do this rather than relying on
  /// [invalidateCache] having already been called).
  static Future<String?> currentId({bool forceRefresh = false}) async {
    final cached = _cached;
    if (!forceRefresh && cached != null) return cached;
    try {
      final id = await FlutterTimezone.getLocalTimezone();
      _cached = id;
      return id;
    } catch (_) {
      return null;
    }
  }

  /// Clears the cache so the next [currentId] call genuinely re-queries
  /// the platform instead of returning a value that may now be stale —
  /// call this whenever the device's timezone may plausibly have changed
  /// (app resume; before any timezone-sensitive reminder recomputation).
  static void invalidateCache() {
    _cached = null;
  }
}
