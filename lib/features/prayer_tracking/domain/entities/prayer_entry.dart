import 'package:equatable/equatable.dart';

enum PrayerName { fajr, dhuhr, asr, maghrib, isha }

enum PrayerStatus { pending, completed, missed, excused }

class TimeOfDay extends Equatable {
  const TimeOfDay({required this.hour, required this.minute});

  final int hour;
  final int minute;

  static const TimeOfDay zero = TimeOfDay(hour: 0, minute: 0);

  bool get isValid => hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;

  DateTime toDateTime(DateTime date) {
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  Map<String, dynamic> toJson() => {'hour': hour, 'minute': minute};

  factory TimeOfDay.fromJson(dynamic value) {
    if (value is String) {
      final parts = value.split(':');
      if (parts.length == 2) {
        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);
        if (hour != null && minute != null) {
          return TimeOfDay(hour: hour, minute: minute);
        }
      }
      return zero;
    }

    if (value is Map<String, dynamic>) {
      final hour = value['hour'] as int? ?? 0;
      final minute = value['minute'] as int? ?? 0;
      return TimeOfDay(hour: hour, minute: minute);
    }

    return zero;
  }

  @override
  List<Object?> get props => [hour, minute];
}

class PrayerSchedule extends Equatable {
  const PrayerSchedule({
    required this.date,
    required this.fajr,
    required this.dhuhr,
    required this.asr,
    required this.maghrib,
    required this.isha,
  });

  final DateTime date;
  final TimeOfDay fajr;
  final TimeOfDay dhuhr;
  final TimeOfDay asr;
  final TimeOfDay maghrib;
  final TimeOfDay isha;

  TimeOfDay? timeFor(PrayerName prayerName) {
    switch (prayerName) {
      case PrayerName.fajr:
        return fajr;
      case PrayerName.dhuhr:
        return dhuhr;
      case PrayerName.asr:
        return asr;
      case PrayerName.maghrib:
        return maghrib;
      case PrayerName.isha:
        return isha;
    }
  }

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'fajr': fajr.toJson(),
    'dhuhr': dhuhr.toJson(),
    'asr': asr.toJson(),
    'maghrib': maghrib.toJson(),
    'isha': isha.toJson(),
  };

  factory PrayerSchedule.fromJson(Map<String, dynamic> json) {
    return PrayerSchedule(
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      fajr: TimeOfDay.fromJson(json['fajr']),
      dhuhr: TimeOfDay.fromJson(json['dhuhr']),
      asr: TimeOfDay.fromJson(json['asr']),
      maghrib: TimeOfDay.fromJson(json['maghrib']),
      isha: TimeOfDay.fromJson(json['isha']),
    );
  }

  @override
  List<Object?> get props => [date, fajr, dhuhr, asr, maghrib, isha];
}

class PrayerTimeSlot extends Equatable {
  const PrayerTimeSlot({
    required this.name,
    required this.time,
    required this.scheduledAt,
  });

  final PrayerName name;
  final TimeOfDay time;
  final DateTime scheduledAt;

  @override
  List<Object?> get props => [name, time, scheduledAt];
}

class PrayerEntry extends Equatable {
  const PrayerEntry({
    required this.id,
    required this.userId,
    required this.prayerName,
    required this.date,
    required this.scheduledTime,
    required this.status,
    this.notes,
    this.completedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String userId;
  final PrayerName prayerName;
  final DateTime date;
  final TimeOfDay scheduledTime;
  final PrayerStatus status;
  final String? notes;
  final DateTime? completedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  PrayerEntry copyWith({
    String? id,
    String? userId,
    PrayerName? prayerName,
    DateTime? date,
    TimeOfDay? scheduledTime,
    PrayerStatus? status,
    String? notes,
    DateTime? completedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PrayerEntry(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      prayerName: prayerName ?? this.prayerName,
      date: date ?? this.date,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'prayer_name': prayerName.name,
    'date': date.toIso8601String(),
    'scheduled_time': scheduledTime.toJson(),
    'status': status.name,
    'notes': notes,
    'completed_at': completedAt?.toIso8601String(),
    'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
    'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
  };

  factory PrayerEntry.fromJson(Map<String, dynamic> json) {
    return PrayerEntry(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      prayerName: PrayerName.values.firstWhere(
        (value) => value.name == (json['prayer_name'] as String? ?? 'fajr'),
        orElse: () => PrayerName.fajr,
      ),
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      scheduledTime: TimeOfDay.fromJson(json['scheduled_time']),
      status: PrayerStatus.values.firstWhere(
        (value) => value.name == (json['status'] as String? ?? 'pending'),
        orElse: () => PrayerStatus.pending,
      ),
      notes: json['notes'] as String?,
      completedAt: json['completed_at'] == null
          ? null
          : DateTime.tryParse(json['completed_at'] as String),
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'] as String),
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.tryParse(json['updated_at'] as String),
    );
  }

  @override
  List<Object?> get props => [
    id,
    userId,
    prayerName,
    date,
    scheduledTime,
    status,
    notes,
    completedAt,
    createdAt,
    updatedAt,
  ];
}
