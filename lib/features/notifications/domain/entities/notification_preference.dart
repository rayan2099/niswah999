import 'package:equatable/equatable.dart';

enum NotificationType { prayer, cycle, pregnancy, wellbeing }

class NotificationPreference extends Equatable {
  const NotificationPreference({
    required this.type,
    required this.enabled,
    required this.leadTimeMinutes,
    required this.channels,
  });

  final NotificationType type;
  final bool enabled;
  final int leadTimeMinutes;
  final List<String> channels;

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'enabled': enabled,
    'lead_time_minutes': leadTimeMinutes,
    'channels': channels,
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
    );
  }

  NotificationPreference copyWith({
    NotificationType? type,
    bool? enabled,
    int? leadTimeMinutes,
    List<String>? channels,
  }) {
    return NotificationPreference(
      type: type ?? this.type,
      enabled: enabled ?? this.enabled,
      leadTimeMinutes: leadTimeMinutes ?? this.leadTimeMinutes,
      channels: channels ?? this.channels,
    );
  }

  @override
  List<Object?> get props => [type, enabled, leadTimeMinutes, channels];
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
