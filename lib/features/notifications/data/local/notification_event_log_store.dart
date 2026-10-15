import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/errors/app_error_reporter.dart';
import '../../domain/entities/notification_event.dart';

/// Closure Blocker 13 — the structural scheduling-audit store itself.
/// Deliberately SharedPreferences (not [SecureLocalStore]): every field
/// here is already documented as non-sensitive structural metadata, the
/// same category [NotificationLogController] already stores in plain
/// SharedPreferences.
///
/// Applies the same corrupt-data resilience [PendingBleedingOperationStore]
/// does for Closure Blocker 11: a malformed outer JSON blob, a wrong
/// top-level shape, or one invalid item among valid ones must never
/// crash a read nor discard every other genuinely valid event — this is
/// an audit trail, and a partially-unreadable audit trail is still far
/// more useful than one that throws and returns nothing.
class NotificationEventLogStore {
  NotificationEventLogStore._();

  static const _storageKey = 'niswah_notification_event_log';

  /// Caps unbounded growth — this is an audit trail for recent behavior,
  /// not a permanent ledger; the oldest events are dropped first.
  static const _maxEntries = 500;

  static Future<void> record(NotificationEvent event) async {
    final existing = await loadAll();
    final updated = [event, ...existing];
    final capped = updated.length > _maxEntries
        ? updated.sublist(0, _maxEntries)
        : updated;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode(capped.map((e) => e.toJson()).toList()),
    );
  }

  static Future<List<NotificationEvent>> loadAll() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const [];

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'NotificationEventLogStore.loadAll — malformed outer JSON, quarantined',
      );
      return const [];
    }

    if (decoded is! List) {
      AppErrorReporter.report(
        StateError(
          'notification event log held a non-list top-level value '
          '(${decoded.runtimeType}) — quarantined',
        ),
        StackTrace.current,
        context: 'NotificationEventLogStore.loadAll',
      );
      return const [];
    }

    final events = <NotificationEvent>[];
    for (final item in decoded) {
      final parsed = item is Map<String, dynamic>
          ? NotificationEvent.tryFromJson(item)
          : null;
      if (parsed != null) events.add(parsed);
    }
    return events;
  }

  /// Every recorded event for one specific reminder id, oldest first —
  /// the full lifecycle (scheduled → opened → responded, or scheduled →
  /// cancelled) for a single logical reminder.
  static Future<List<NotificationEvent>> loadForReminder(
    String reminderId,
  ) async {
    final all = await loadAll();
    return all.where((e) => e.reminderId == reminderId).toList()
      ..sort((a, b) => a.eventTimestamp.compareTo(b.eventTimestamp));
  }
}
