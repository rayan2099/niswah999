import 'package:equatable/equatable.dart';

enum NotificationType {
  prayer,
  cycle,
  pregnancy,
  wellbeing,
  // Menstrual Data Integrity charter, Commit E — ACTIVE_BLEEDING_CHECKIN.
  // Deliberately its own type, never folded into [cycle] (which is a
  // *prediction* reminder — "your period may be approaching"): this one
  // only ever fires while a real episode is open, asking a factual
  // question, and must never be conflated with a Fiqh conclusion or a
  // forecast.
  activeBleeding,
}

class NotificationPreference extends Equatable {
  const NotificationPreference({
    required this.type,
    required this.enabled,
    required this.leadTimeMinutes,
    required this.channels,
    this.preferredHour,
    this.preferredMinute,
  });

  final NotificationType type;
  final bool enabled;
  final int leadTimeMinutes;
  final List<String> channels;

  /// Closure Blocker 7 — a real, persisted, user-choosable time of day.
  /// Only meaningful for [NotificationType.activeBleeding] (the daily
  /// check-in reminder, asked once a day while a real episode is open —
  /// never a "lead time" before some other event, so [leadTimeMinutes]
  /// was never the right control for it). Null means "not yet customized
  /// — use the scheduler's own documented default", never "midnight";
  /// both are set together or not at all.
  final int? preferredHour;
  final int? preferredMinute;

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'enabled': enabled,
    'lead_time_minutes': leadTimeMinutes,
    'channels': channels,
    if (preferredHour != null) 'preferred_hour': preferredHour,
    if (preferredMinute != null) 'preferred_minute': preferredMinute,
  };

  factory NotificationPreference.fromJson(Map<String, dynamic> json) {
    return NotificationPreference(
      type: NotificationType.values.firstWhere(
        (type) => type.name == (json['type'] as String? ?? 'prayer'),
        orElse: () => NotificationType.prayer,
      ),
      enabled: json['enabled'] as bool? ?? false,
      leadTimeMinutes: json['lead_time_minutes'] as int? ?? 0,
      channels: List<String>.from(
        json['channels'] as List? ?? const <String>[],
      ),
      preferredHour: json['preferred_hour'] as int?,
      preferredMinute: json['preferred_minute'] as int?,
    );
  }

  NotificationPreference copyWith({
    NotificationType? type,
    bool? enabled,
    int? leadTimeMinutes,
    List<String>? channels,
    int? preferredHour,
    int? preferredMinute,
  }) {
    return NotificationPreference(
      type: type ?? this.type,
      enabled: enabled ?? this.enabled,
      leadTimeMinutes: leadTimeMinutes ?? this.leadTimeMinutes,
      channels: channels ?? this.channels,
      preferredHour: preferredHour ?? this.preferredHour,
      preferredMinute: preferredMinute ?? this.preferredMinute,
    );
  }

  @override
  List<Object?> get props => [
    type,
    enabled,
    leadTimeMinutes,
    channels,
    preferredHour,
    preferredMinute,
  ];
}

Map<NotificationType, NotificationPreference> buildReminderSchedule({
  required Map<NotificationType, NotificationPreference> preferences,
  required DateTime now,
}) {
  final schedule = <NotificationType, NotificationPreference>{};
  for (final type in NotificationType.values) {
    final existing = preferences[type];
    schedule[type] =
        existing ??
        NotificationPreference(
          type: type,
          enabled: type == NotificationType.prayer,
          leadTimeMinutes: type == NotificationType.prayer ? 15 : 30,
          channels: const <String>[],
        );
  }

  return schedule;
}
