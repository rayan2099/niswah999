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

/// A single day's flow report on an active episode's daily check-in
/// (Section 14). Distinct from [FlowLevel] (`lib/.../cycle_log.dart`)
/// because `uncertain` — "I'm not sure" — is itself a first-class answer
/// here (Section 15: absence of a response is not an observation, but an
/// explicit "I don't know" response IS one), not merely the absence of a
/// flow value.
enum ObservationFlow {
  uncertain,
  none,
  spotting,
  light,
  medium,
  heavy;

  String get value => switch (this) {
    ObservationFlow.uncertain => 'uncertain',
    ObservationFlow.none => 'none',
    ObservationFlow.spotting => 'spotting',
    ObservationFlow.light => 'light',
    ObservationFlow.medium => 'medium',
    ObservationFlow.heavy => 'heavy',
  };

  static ObservationFlow parse(String? raw) => switch (raw) {
    'uncertain' => ObservationFlow.uncertain,
    'none' => ObservationFlow.none,
    'spotting' => ObservationFlow.spotting,
    'light' => ObservationFlow.light,
    'medium' => ObservationFlow.medium,
    'heavy' => ObservationFlow.heavy,
    _ => throw BleedingEpisodeParseException('flow', raw),
  };
}

/// One immutable fact about a specific day/moment of an episode
/// (Section 4). A correction is never an in-place edit — it is a new row
/// whose [supersedesId] points at the fact it replaces (Section 17); the
/// database enforces both that a row can't supersede itself and that at
/// most one row ever supersedes a given id (see the migration).
class BleedingObservation extends Equatable {
  const BleedingObservation({
    this.id,
    required this.userId,
    required this.episodeId,
    required this.observedDate,
    this.observedTime,
    required this.precision,
    required this.flow,
    required this.source,
    this.reportedAt,
    required this.timezone,
    this.symptoms,
    this.notes,
    this.supersedesId,
  });

  /// Null before insert — the database assigns it.
  final String? id;
  final String userId;
  final String episodeId;
  final DateTime observedDate;
  final DateTime? observedTime;
  final ObservationPrecision precision;
  final ObservationFlow flow;
  final ObservationSource source;

  /// Null lets the database's own `default now()` stamp the real insert
  /// time — never set this to a client-computed "now" that could drift
  /// from when the row is actually written.
  final DateTime? reportedAt;
  final String timezone;
  final List<String>? symptoms;
  final String? notes;
  final String? supersedesId;

  static String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toInsertJson() => {
    'user_id': userId,
    'episode_id': episodeId,
    'observed_date': _dateOnly(observedDate),
    if (observedTime != null) 'observed_time': observedTime!.toIso8601String(),
    'precision': precision.value,
    'flow': flow.value,
    'source': source.value,
    'timezone': timezone,
    if (symptoms != null) 'symptoms': symptoms,
    if (notes != null) 'notes': notes,
    if (supersedesId != null) 'supersedes_id': supersedesId,
  };

  factory BleedingObservation.fromJson(Map<String, dynamic> json) {
    final rawObservedDate = json['observed_date'] as String?;
    final observedDate = rawObservedDate == null
        ? null
        : DateTime.tryParse(rawObservedDate);
    if (observedDate == null) {
      throw BleedingEpisodeParseException('observed_date', rawObservedDate);
    }

    return BleedingObservation(
      id: json['id'] as String?,
      userId: json['user_id'] as String? ?? '',
      episodeId: json['episode_id'] as String? ?? '',
      observedDate: observedDate,
      observedTime: json['observed_time'] == null
          ? null
          : DateTime.tryParse(json['observed_time'] as String),
      precision: ObservationPrecision.parse(json['precision'] as String?),
      flow: ObservationFlow.parse(json['flow'] as String?),
      source: ObservationSource.parse(json['source'] as String?),
      reportedAt: json['reported_at'] == null
          ? null
          : DateTime.tryParse(json['reported_at'] as String),
      timezone: json['timezone'] as String? ?? '',
      symptoms: (json['symptoms'] as List<dynamic>?)
          ?.map((item) => item.toString())
          .toList(),
      notes: json['notes'] as String?,
      supersedesId: json['supersedes_id'] as String?,
    );
  }

  @override
  List<Object?> get props => [
    id,
    userId,
    episodeId,
    observedDate,
    observedTime,
    precision,
    flow,
    source,
    reportedAt,
    timezone,
    symptoms,
    notes,
    supersedesId,
  ];
}
