import 'package:equatable/equatable.dart';

/// Thrown when a `bleeding_episodes` row's required enum-like columns
/// (`status`, `*_precision`, `*_source`) cannot be recognized — mirrors
/// [CycleLogParseException]'s policy of an honest failure over a
/// silently-substituted default for required health-record fields.
class BleedingEpisodeParseException implements Exception {
  const BleedingEpisodeParseException(this.field, this.rawValue);

  final String field;
  final Object? rawValue;

  @override
  String toString() =>
      'BleedingEpisodeParseException: invalid or missing "$field" ($rawValue)';
}

/// Data taxonomy class 1/2 distinction (menstrual-data-integrity charter,
/// Section 3): [userObserved] means reported live, at/near the same real
/// time as the event; [userReportedHistorical] means reported after the
/// fact (backfill, onboarding, a correction) — never conflated.
enum ObservationSource {
  userObserved,
  userReportedHistorical;

  String get value => switch (this) {
    ObservationSource.userObserved => 'user_observed',
    ObservationSource.userReportedHistorical => 'user_reported_historical',
  };

  static ObservationSource parse(String? raw) => switch (raw) {
    'user_observed' => ObservationSource.userObserved,
    'user_reported_historical' => ObservationSource.userReportedHistorical,
    _ => throw BleedingEpisodeParseException('source', raw),
  };
}

/// How exact a reported date/time actually is (Section 5) — never silently
/// promoted to a more precise class than what was actually reported.
enum ObservationPrecision {
  exactTime,
  approximateTime,
  dateOnly;

  String get value => switch (this) {
    ObservationPrecision.exactTime => 'exact_time',
    ObservationPrecision.approximateTime => 'approximate_time',
    ObservationPrecision.dateOnly => 'date_only',
  };

  static ObservationPrecision parse(String? raw) => switch (raw) {
    'exact_time' => ObservationPrecision.exactTime,
    'approximate_time' => ObservationPrecision.approximateTime,
    'date_only' => ObservationPrecision.dateOnly,
    _ => throw BleedingEpisodeParseException('precision', raw),
  };
}

/// The episode lifecycle (Section 12): [active] (currently bleeding, no
/// end reported yet), [ended] (a real end date was reported), [uncertain]
/// (the user does not know whether it has ended — never silently forced
/// into either of the other two states).
enum EpisodeStatus {
  active,
  ended,
  uncertain;

  String get value => switch (this) {
    EpisodeStatus.active => 'active',
    EpisodeStatus.ended => 'ended',
    EpisodeStatus.uncertain => 'uncertain',
  };

  static EpisodeStatus parse(String? raw) => switch (raw) {
    'active' => EpisodeStatus.active,
    'ended' => EpisodeStatus.ended,
    'uncertain' => EpisodeStatus.uncertain,
    _ => throw BleedingEpisodeParseException('status', raw),
  };
}

/// A first-class bleeding episode — the explicit lifecycle entity the
/// menstrual-data-integrity charter requires in place of re-deriving
/// "currently bleeding since when" from raw flat log rows on every read.
/// [startDate]/[endDate] are always the honest, factual calendar dates the
/// user reported; never a Fiqh-adjusted or truncated value (raw fact vs.
/// Fiqh classification stay strictly separate — see the Fiqh evaluation
/// layer, which already consumes durations like this one without ever
/// mutating them).
class BleedingEpisode extends Equatable {
  const BleedingEpisode({
    this.id,
    required this.userId,
    required this.status,
    required this.startDate,
    required this.startPrecision,
    required this.startSource,
    this.endDate,
    this.endPrecision,
    this.endSource,
  }) : assert(
         (status == EpisodeStatus.ended) == (endDate != null),
         'endDate must be set if and only if status is ended',
       );

  /// Null before the row is inserted — the database assigns it.
  final String? id;
  final String userId;
  final EpisodeStatus status;
  final DateTime startDate;
  final ObservationPrecision startPrecision;
  final ObservationSource startSource;
  final DateTime? endDate;
  final ObservationPrecision? endPrecision;
  final ObservationSource? endSource;

  static String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toInsertJson() => {
    'user_id': userId,
    'status': status.value,
    'start_date': _dateOnly(startDate),
    'start_precision': startPrecision.value,
    'start_source': startSource.value,
    if (endDate != null) 'end_date': _dateOnly(endDate!),
    if (endPrecision != null) 'end_precision': endPrecision!.value,
    if (endSource != null) 'end_source': endSource!.value,
  };

  /// Throws [BleedingEpisodeParseException] on an unparseable/missing
  /// required field — never substitutes a plausible-looking default (see
  /// [CycleLogParseException] for the same policy applied to `CycleLog`).
  factory BleedingEpisode.fromJson(Map<String, dynamic> json) {
    final rawStart = json['start_date'] as String?;
    final startDate = rawStart == null ? null : DateTime.tryParse(rawStart);
    if (startDate == null) {
      throw BleedingEpisodeParseException('start_date', rawStart);
    }

    final rawEnd = json['end_date'] as String?;
    final endDate = rawEnd == null ? null : DateTime.tryParse(rawEnd);
    if (rawEnd != null && endDate == null) {
      throw BleedingEpisodeParseException('end_date', rawEnd);
    }

    return BleedingEpisode(
      id: json['id'] as String?,
      userId: json['user_id'] as String? ?? '',
      status: EpisodeStatus.parse(json['status'] as String?),
      startDate: startDate,
      startPrecision: ObservationPrecision.parse(
        json['start_precision'] as String?,
      ),
      startSource: ObservationSource.parse(json['start_source'] as String?),
      endDate: endDate,
      endPrecision: json['end_precision'] == null
          ? null
          : ObservationPrecision.parse(json['end_precision'] as String?),
      endSource: json['end_source'] == null
          ? null
          : ObservationSource.parse(json['end_source'] as String?),
    );
  }

  @override
  List<Object?> get props => [
    id,
    userId,
    status,
    startDate,
    startPrecision,
    startSource,
    endDate,
    endPrecision,
    endSource,
  ];
}

/// A user's stated USUAL bleeding duration / cycle length — data taxonomy
/// class 3 (USER_REPORTED_ESTIMATE, Section 3). Never itself an
/// observation and never versioned as history (Section 4): a new answer
/// simply replaces the old one, one row per user.
class CycleBaseline extends Equatable {
  const CycleBaseline({
    required this.userId,
    this.usualBleedingDurationDays,
    this.usualCycleLengthDays,
  });

  final String userId;
  final int? usualBleedingDurationDays;
  final int? usualCycleLengthDays;

  Map<String, dynamic> toUpsertJson() => {
    'user_id': userId,
    'usual_bleeding_duration_days': usualBleedingDurationDays,
    'usual_cycle_length_days': usualCycleLengthDays,
  };

  factory CycleBaseline.fromJson(Map<String, dynamic> json) => CycleBaseline(
    userId: json['user_id'] as String? ?? '',
    usualBleedingDurationDays: json['usual_bleeding_duration_days'] as int?,
    usualCycleLengthDays: json['usual_cycle_length_days'] as int?,
  );

  @override
  List<Object?> get props => [
    userId,
    usualBleedingDurationDays,
    usualCycleLengthDays,
  ];
}
