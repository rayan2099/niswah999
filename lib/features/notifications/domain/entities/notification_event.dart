import 'package:collection/collection.dart';

/// Closure Blocker 13 — finishes Commit E8's admitted gap: a genuine
/// scheduling *audit* trail, structurally distinct from
/// [NotificationLogController]'s own display feed (the "bell icon" the
/// user actually reads, which necessarily carries title/body text). This
/// event log carries ONLY structural metadata — a logical reminder id,
/// the notification type, opaque user/episode ids, a logical local date,
/// an event timestamp, and which lifecycle state fired — and NEVER
/// health content (flow, Fiqh state, symptoms, notes). "Shown in the
/// notification feed" (an entry existing in [NotificationLogController])
/// is not itself a scheduling audit event and must never be conflated
/// with one — this is the separate, structural record of what the
/// scheduler itself actually did and what she actually did with it.
enum NotificationEventState { scheduled, cancelled, opened, responded }

class NotificationEvent {
  const NotificationEvent({
    required this.reminderId,
    required this.notificationType,
    required this.state,
    required this.eventTimestamp,
    this.userId,
    this.episodeId,
    this.logicalLocalDate,
  });

  /// The same stable logical id the scheduler itself computed (e.g.
  /// [ActiveBleedingReminderScheduler.reminderId]) — never re-derived
  /// differently here, so every event for "the same reminder" genuinely
  /// shares one id across its whole lifecycle.
  final String reminderId;
  final String notificationType;
  final NotificationEventState state;
  final DateTime eventTimestamp;

  /// Opaque ids only — never a name, a flow level, or any other health
  /// content.
  final String? userId;
  final String? episodeId;

  /// `yyyy-MM-dd` — the logical local calendar day this reminder was
  /// about, not the event's own timestamp (which is real wall-clock
  /// time the event itself occurred).
  final String? logicalLocalDate;

  Map<String, dynamic> toJson() => {
    'reminder_id': reminderId,
    'notification_type': notificationType,
    'state': state.name,
    'event_timestamp': eventTimestamp.toIso8601String(),
    if (userId != null) 'user_id': userId,
    if (episodeId != null) 'episode_id': episodeId,
    if (logicalLocalDate != null) 'logical_local_date': logicalLocalDate,
  };

  static NotificationEvent? tryFromJson(Map<String, dynamic> json) {
    final reminderId = json['reminder_id'] as String?;
    final notificationType = json['notification_type'] as String?;
    final rawState = json['state'] as String?;
    final state = NotificationEventState.values.firstWhereOrNull(
      (value) => value.name == rawState,
    );
    final eventTimestamp = json['event_timestamp'] == null
        ? null
        : DateTime.tryParse(json['event_timestamp'] as String);
    if (reminderId == null ||
        notificationType == null ||
        state == null ||
        eventTimestamp == null) {
      // Quarantine, not crash — this is an audit trail, not a source of
      // truth anything else depends on; a malformed entry must never
      // block reading the rest of it.
      return null;
    }
    return NotificationEvent(
      reminderId: reminderId,
      notificationType: notificationType,
      state: state,
      eventTimestamp: eventTimestamp,
      userId: json['user_id'] as String?,
      episodeId: json['episode_id'] as String?,
      logicalLocalDate: json['logical_local_date'] as String?,
    );
  }
}
