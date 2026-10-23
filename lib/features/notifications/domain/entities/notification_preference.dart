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

  /// Wall-clock time for non-prayer reminders. Prayer uses event lead time.
  /// Null uses the scheduler default; hour and minute are supplied together.
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
    final type = NotificationType.values
        .where((t) => t.name == json['type'])
        .firstOrNull;
    final enabled = json['enabled'];
    final lead = json['lead_time_minutes'];
    final hour = json['preferred_hour'];
    final minute = json['preferred_minute'];
    final channels = json['channels'];
    if (type == null ||
        enabled is! bool ||
        lead is! int ||
        lead < 0 ||
        lead > 120 ||
        channels is! List ||
        channels.any((c) => c is! String) ||
        ((hour == null) != (minute == null)) ||
        (hour != null &&
            (hour is! int ||
                hour < 0 ||
                hour > 23 ||
                minute is! int ||
                minute < 0 ||
                minute > 59))) {
      throw const FormatException('Invalid notification preference');
    }
    return NotificationPreference(
      type: type,
      enabled: enabled,
      leadTimeMinutes: lead,
      channels: List<String>.from(channels),
      preferredHour: hour as int?,
      preferredMinute: minute as int?,
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
