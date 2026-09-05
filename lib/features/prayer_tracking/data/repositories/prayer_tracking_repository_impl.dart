import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/app_error_reporter.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/network/supabase_client.dart';
import '../../domain/entities/prayer_entry.dart';
import '../../domain/repositories/prayer_tracking_repository.dart';
import '../datasources/local_prayer_tracking_data_source.dart';

/// `prayer_log`'s live `status` CHECK constraint accepts exactly
/// `{'prayed', 'qadha_required', 'lifted', 'missed'}` — confirmed against
/// the live-captured schema (`supabase/live_schema_capture/2026-09-04_public.sql`),
/// not assumed. This does **not** match `PrayerStatus`'s Dart enum names
/// (`{pending, completed, missed, excused}`) — only `missed` coincides.
/// Sending `entry.status.name` directly (the pre-fix behavior) made every
/// write with `completed`/`pending`/`excused` fail with a `23514`
/// constraint violation (`W0-003`). This mapping is scoped to exactly the
/// remote boundary — `PrayerEntry.toJson()`/`fromJson()` (used for local
/// on-device storage) are deliberately left untouched, since local storage
/// has no such external contract to satisfy.
///
/// [PrayerStatus.pending] has no database representation: it is a
/// local-only, not-yet-recorded placeholder computed by
/// `PrayerTimeCalculator.statusFor()` for display before any real entry
/// exists — the UI's `togglePrayerStatus` only ever offers
/// completed/missed/excused, so `pending` is never actually sent to
/// [savePrayer] today. If it ever were, failing loudly here is correct:
/// silently inventing a database value for a state the schema has no slot
/// for would be worse than an explicit, diagnosable error.
@visibleForTesting
String prayerStatusToDbValue(PrayerStatus status) {
  switch (status) {
    case PrayerStatus.completed:
      return 'prayed';
    case PrayerStatus.missed:
      return 'missed';
    case PrayerStatus.excused:
      return 'lifted';
    case PrayerStatus.pending:
      throw ArgumentError(
        'PrayerStatus.pending has no prayer_log database representation — '
        'it must never be sent to the remote table.',
      );
  }
}

/// The inverse of [prayerStatusToDbValue]. `qadha_required` is a real,
/// valid database value with no current app-side UI concept for it — rather
/// than silently normalizing any unrecognized value to `pending` (which
/// would misrepresent a real, meaningful database state as "nothing
/// recorded yet" with zero trace — exactly the `ROOT-005` silent-failure
/// pattern this app has repeatedly been found to have elsewhere), an
/// unmapped value is reported via [AppErrorReporter] before falling back —
/// deliberately observable, not silently coerced.
@visibleForTesting
PrayerStatus prayerStatusFromDbValue(
  String? value, {
  required String context,
  String? recordId,
}) {
  switch (value) {
    case 'prayed':
      return PrayerStatus.completed;
    case 'missed':
      return PrayerStatus.missed;
    case 'lifted':
      return PrayerStatus.excused;
    default:
      AppErrorReporter.report(
        StateError('Unmapped prayer_log status value: $value'),
        StackTrace.current,
        context: context,
        feature: 'prayer_tracking',
        recordId: recordId,
      );
      return PrayerStatus.pending;
  }
}

/// A second, distinct, currently-live production bug found while validating
/// `W0-003` — separate from the status mismatch, and fixed alongside it
/// because it sits in the exact same write path and otherwise blocks any
/// prayer_log write from succeeding regardless of status: `scheduled_time`
/// is `timestamp with time zone` in the live schema (confirmed against the
/// live capture), not the `{hour, minute}` JSON shape `TimeOfDay.toJson()`
/// produces or the `"HH:MM"` string `TimeOfDay.fromJson()` expects back.
/// This pair of helpers converts at exactly the remote boundary, the same
/// way the status mapping does — `PrayerEntry`'s own `toJson()`/`fromJson()`
/// (local storage) are untouched.
/// `scheduledTime` is a local wall-clock concept throughout this app (Fajr
/// at 5:30 means 5:30 wherever the person is — `PrayerTrackingViewModel`
/// itself only ever populates it from `.toLocal()`'d prayer-time
/// calculations, never a true cross-timezone instant). The database column
/// is `timestamp with time zone` — an absolute-instant type — so encoding
/// via `.toLocal()`/the reading machine's own timezone would make the
/// stored/round-tripped hour silently depend on whichever timezone
/// happened to be active wherever the code last ran. UTC is used here only
/// as a neutral, unambiguous wire encoding of the same wall-clock
/// hour/minute — not a real timezone conversion — so the round trip is
/// deterministic regardless of device/server timezone.
@visibleForTesting
String prayerScheduledTimeToDbValue(TimeOfDay time, DateTime date) =>
    DateTime.utc(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).toIso8601String();

@visibleForTesting
TimeOfDay prayerScheduledTimeFromDbValue(String? value) {
  if (value == null) return TimeOfDay.zero;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return TimeOfDay.zero;
  final asUtc = parsed.toUtc();
  return TimeOfDay(hour: asUtc.hour, minute: asUtc.minute);
}

/// Converts one raw `prayer_log` row (real database status/scheduled_time
/// values) into a [PrayerEntry] — translates both via the mappers above
/// first, then delegates to [PrayerEntry.fromJson] for everything else
/// (reusing its existing parsing rather than duplicating it).
@visibleForTesting
PrayerEntry prayerEntryFromRemoteJson(Map<String, dynamic> json) {
  final id = json['id'] as String?;
  final domainStatus = prayerStatusFromDbValue(
    json['status'] as String?,
    context: 'PrayerTrackingRepositoryImpl.prayerEntryFromRemoteJson',
    recordId: id,
  );
  final scheduledTime = prayerScheduledTimeFromDbValue(
    json['scheduled_time'] as String?,
  );
  return PrayerEntry.fromJson({
    ...json,
    'status': domainStatus.name,
    'scheduled_time': scheduledTime.toJson(),
  });
}

class PrayerTrackingRepositoryImpl implements PrayerTrackingRepository {
  PrayerTrackingRepositoryImpl({
    SupabaseClient? client,
    LocalPrayerTrackingDataSource? localDataSource,
  }) : _client = client ?? NiswahSupabase.clientOrNull,
       _localDataSource = localDataSource ?? LocalPrayerTrackingDataSource();

  final SupabaseClient? _client;
  final LocalPrayerTrackingDataSource _localDataSource;

  @override
  Future<List<PrayerEntry>> getDailyPrayerLog(
    DateTime date, {
    required String userId,
  }) async {
    final localLogs = await _localDataSource.loadLogsForDate(
      date,
      userId: userId,
    );
    final client = _client;
    if (client == null) {
      return localLogs;
    }

    final sessionUser = client.auth.currentUser;
    if (sessionUser == null) {
      return localLogs;
    }

    try {
      final response = await client
          .from('prayer_log')
          .select()
          .eq('user_id', sessionUser.id)
          .eq('date', date.toIso8601String().substring(0, 10));

      final remote = (response as List<dynamic>)
          .map(
            (item) =>
                prayerEntryFromRemoteJson(item as Map<String, dynamic>),
          )
          .toList();

      final merged = <String, PrayerEntry>{};
      for (final entry in [...localLogs, ...remote]) {
        merged[entry.id] = entry;
      }

      final ordered = merged.values.toList()
        ..sort((a, b) => a.prayerName.index.compareTo(b.prayerName.index));
      return ordered;
    } on PostgrestException catch (error) {
      throw NetworkFailure(error.message);
    } catch (_) {
      return localLogs;
    }
  }

  @override
  Future<List<PrayerEntry>> getPrayerHistory({
    required String userId,
    DateTime? from,
    DateTime? to,
  }) async {
    final localLogs = await _localDataSource.loadLogs();
    final filteredLocal = localLogs
        .where((entry) => entry.userId == userId)
        .where((entry) {
          if (from != null && entry.date.isBefore(from)) {
            return false;
          }
          if (to != null && entry.date.isAfter(to)) {
            return false;
          }
          return true;
        })
        .toList();

    final client = _client;
    if (client == null || client.auth.currentUser == null) {
      return filteredLocal;
    }

    try {
      var query = client.from('prayer_log').select().eq('user_id', userId);
      if (from != null) {
        query = query.gte('date', from.toIso8601String().substring(0, 10));
      }
      if (to != null) {
        query = query.lte('date', to.toIso8601String().substring(0, 10));
      }

      final response = await query.order('date', ascending: false);
      final remote = (response as List<dynamic>)
          .map(
            (item) =>
                prayerEntryFromRemoteJson(item as Map<String, dynamic>),
          )
          .toList();

      final merged = <String, PrayerEntry>{};
      for (final entry in [...filteredLocal, ...remote]) {
        merged[entry.id] = entry;
      }
      final ordered = merged.values.toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      return ordered;
    } on PostgrestException catch (error) {
      throw NetworkFailure(error.message);
    } catch (_) {
      return filteredLocal;
    }
  }

  @override
  Future<void> savePrayer(PrayerEntry entry) async {
    await _localDataSource.upsert(entry);
    final client = _client;
    if (client == null) {
      return;
    }

    final sessionUser = client.auth.currentUser;
    if (sessionUser == null || sessionUser.id != entry.userId) {
      return;
    }

    try {
      // `prayer_log` (the live table — see W0-001) predates `completed_at`/
      // `created_at`/`updated_at`; sending them would be rejected as unknown
      // columns, so the remote payload is built explicitly from the columns
      // that actually exist, rather than spreading entry.toJson() wholesale.
      final payload = {
        'id': entry.id,
        'user_id': sessionUser.id,
        'prayer_name': entry.prayerName.name,
        'date': entry.date.toIso8601String(),
        'scheduled_time': prayerScheduledTimeToDbValue(
          entry.scheduledTime,
          entry.date,
        ),
        'status': prayerStatusToDbValue(entry.status),
        'notes': entry.notes,
      };

      await client.from('prayer_log').upsert(payload, onConflict: 'id');
    } on PostgrestException catch (error) {
      throw NetworkFailure(error.message);
    }
  }

  @override
  Future<void> deletePrayer(String id) async {
    await _localDataSource.delete(id);
    final client = _client;
    if (client == null) {
      return;
    }

    try {
      await client.from('prayer_log').delete().eq('id', id);
    } on PostgrestException catch (error) {
      throw NetworkFailure(error.message);
    }
  }
}
