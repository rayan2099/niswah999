import 'package:equatable/equatable.dart';

/// How the user told us where they are in their pregnancy. Never inferred —
/// always the direct result of explicit user input (a date picker or the
/// "just tell me the week" flow).
enum TrackingBasis { lmp, dueDate, conceptionDate, manualWeek }

enum FastingStatus { notApplicable, fasting, notFasting, unsure }

String _trackingBasisToJson(TrackingBasis value) => switch (value) {
  TrackingBasis.lmp => 'lmp',
  TrackingBasis.dueDate => 'due_date',
  TrackingBasis.conceptionDate => 'conception_date',
  TrackingBasis.manualWeek => 'manual_week',
};

TrackingBasis? _trackingBasisFromJson(String? value) => switch (value) {
  'lmp' => TrackingBasis.lmp,
  'due_date' => TrackingBasis.dueDate,
  'conception_date' => TrackingBasis.conceptionDate,
  'manual_week' => TrackingBasis.manualWeek,
  _ => null,
};

String _fastingStatusToJson(FastingStatus value) => switch (value) {
  FastingStatus.notApplicable => 'not_applicable',
  FastingStatus.fasting => 'fasting',
  FastingStatus.notFasting => 'not_fasting',
  FastingStatus.unsure => 'unsure',
};

FastingStatus _fastingStatusFromJson(String? value) => switch (value) {
  'fasting' => FastingStatus.fasting,
  'not_fasting' => FastingStatus.notFasting,
  'unsure' => FastingStatus.unsure,
  _ => FastingStatus.notApplicable,
};

/// Personalization record backing the "طبيبة" pregnancy chat — maps 1:1 to
/// the `pregnancy_profile` table (one row per user). Never derive this from
/// anything but explicit user input; if a field is missing, the assistant's
/// job is to ask for it conversationally rather than guess.
class PregnancyProfile extends Equatable {
  const PregnancyProfile({
    required this.id,
    required this.userId,
    this.trackingBasis,
    this.referenceDate,
    this.manualWeekValue,
    this.manualWeekSetAt,
    this.isPostpartum = false,
    this.postpartumStartDate,
    this.highRiskFlags = const [],
    this.fastingStatus = FastingStatus.notApplicable,
    this.locale = 'ar',
    this.updatedAt,
  });

  final String id;
  final String userId;
  final TrackingBasis? trackingBasis;
  final DateTime? referenceDate;
  final int? manualWeekValue;
  final DateTime? manualWeekSetAt;
  final bool isPostpartum;
  final DateTime? postpartumStartDate;
  final List<String> highRiskFlags;
  final FastingStatus fastingStatus;
  final String locale;
  final DateTime? updatedAt;

  PregnancyProfile copyWith({
    TrackingBasis? trackingBasis,
    DateTime? referenceDate,
    int? manualWeekValue,
    DateTime? manualWeekSetAt,
    bool? isPostpartum,
    DateTime? postpartumStartDate,
    List<String>? highRiskFlags,
    FastingStatus? fastingStatus,
    String? locale,
    DateTime? updatedAt,
  }) {
    return PregnancyProfile(
      id: id,
      userId: userId,
      trackingBasis: trackingBasis ?? this.trackingBasis,
      referenceDate: referenceDate ?? this.referenceDate,
      manualWeekValue: manualWeekValue ?? this.manualWeekValue,
      manualWeekSetAt: manualWeekSetAt ?? this.manualWeekSetAt,
      isPostpartum: isPostpartum ?? this.isPostpartum,
      postpartumStartDate: postpartumStartDate ?? this.postpartumStartDate,
      highRiskFlags: highRiskFlags ?? this.highRiskFlags,
      fastingStatus: fastingStatus ?? this.fastingStatus,
      locale: locale ?? this.locale,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'tracking_basis': trackingBasis == null
        ? null
        : _trackingBasisToJson(trackingBasis!),
    'reference_date': referenceDate?.toIso8601String(),
    'manual_week_value': manualWeekValue,
    'manual_week_set_at': manualWeekSetAt?.toIso8601String(),
    'is_postpartum': isPostpartum,
    'postpartum_start_date': postpartumStartDate?.toIso8601String(),
    'high_risk_flags': highRiskFlags,
    'fasting_status': _fastingStatusToJson(fastingStatus),
    'locale': locale,
    'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
  };

  factory PregnancyProfile.fromJson(Map<String, dynamic> json) {
    return PregnancyProfile(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      trackingBasis: _trackingBasisFromJson(
        json['tracking_basis'] as String?,
      ),
      referenceDate: DateTime.tryParse(
        json['reference_date'] as String? ?? '',
      ),
      manualWeekValue: json['manual_week_value'] as int?,
      manualWeekSetAt: DateTime.tryParse(
        json['manual_week_set_at'] as String? ?? '',
      ),
      isPostpartum: json['is_postpartum'] as bool? ?? false,
      postpartumStartDate: DateTime.tryParse(
        json['postpartum_start_date'] as String? ?? '',
      ),
      highRiskFlags:
          (json['high_risk_flags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      fastingStatus: _fastingStatusFromJson(
        json['fasting_status'] as String?,
      ),
      locale: json['locale'] as String? ?? 'ar',
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
    id,
    userId,
    trackingBasis,
    referenceDate,
    manualWeekValue,
    manualWeekSetAt,
    isPostpartum,
    postpartumStartDate,
    highRiskFlags,
    fastingStatus,
    locale,
    updatedAt,
  ];
}
