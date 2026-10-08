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

  /// The one canonical source-classification rule (PR #4 hardening,
  /// Blocker 4): provenance is derived from *which date the user
  /// reported*, never from which screen created the row — a screen that
  /// happens to offer "Today" and "Yesterday" side by side (the Start/End
  /// Bleeding sheets) must classify each answer independently, not stamp
  /// every write from that screen as [userObserved] regardless of which
  /// date was actually chosen. [reportedDate] is the date being recorded;
  /// [localToday] is the reporter's own local "today" (derived from her
  /// UTC offset, never guessed) — reporting today's date is
  /// [userObserved]; reporting any other (necessarily past) date is
  /// [userReportedHistorical].
  static ObservationSource classify({
    required DateTime reportedDate,
    required DateTime localToday,
  }) {
    final normalizedReported = DateTime(
      reportedDate.year,
      reportedDate.month,
      reportedDate.day,
    );
    final normalizedToday = DateTime(
      localToday.year,
      localToday.month,
      localToday.day,
    );
    return normalizedReported == normalizedToday
        ? ObservationSource.userObserved
        : ObservationSource.userReportedHistorical;
  }
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

/// The episode lifecycle (Section 12; PR #4 hardening, Blocker 5):
/// [open] (still being tracked — bleeding may be ongoing or its
/// continuation may be uncertain) or [ended] (a real end date was
/// reported). Deliberately just these two — see [ContinuationCertainty]
/// for the orthogonal question of whether continuation is confirmed.
/// The original three-way active/ended/uncertain conflated those two
/// questions, which meant marking uncertain silently vacated the
/// one-active-episode slot (the DB's uniqueness only ever protected
/// `status = 'active'`) and let a second, genuinely concurrent episode
/// start while the first was still unresolved. The one-per-user
/// uniqueness now covers every [open] episode regardless of certainty.
enum LifecycleStatus {
  open,
  ended;

  String get value => switch (this) {
    LifecycleStatus.open => 'open',
    LifecycleStatus.ended => 'ended',
  };

  static LifecycleStatus parse(String? raw) => switch (raw) {
    'open' => LifecycleStatus.open,
    'ended' => LifecycleStatus.ended,
    _ => throw BleedingEpisodeParseException('lifecycle_status', raw),
  };
}

/// Whether continuation of an OPEN episode is [confirmed] (she reported
/// still bleeding) or [uncertain] ("I'm not sure" — Section 9's NOT SURE
/// branch). Only meaningful while [LifecycleStatus.open]; null once
/// [LifecycleStatus.ended] since there is nothing left to be uncertain
/// about. "I'm not sure" never itself closes the episode and never
/// forces a positive/negative bleeding fact.
enum ContinuationCertainty {
  confirmed,
  uncertain;

  String get value => switch (this) {
    ContinuationCertainty.confirmed => 'confirmed',
    ContinuationCertainty.uncertain => 'uncertain',
  };

  static ContinuationCertainty parse(String? raw) => switch (raw) {
    'confirmed' => ContinuationCertainty.confirmed,
    'uncertain' => ContinuationCertainty.uncertain,
    _ => throw BleedingEpisodeParseException('continuation_certainty', raw),
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
    required this.lifecycleStatus,
    this.continuationCertainty,
    required this.startDate,
    required this.startPrecision,
    required this.startSource,
    this.endDate,
    this.endPrecision,
    this.endSource,
    this.clientOperationId,
    this.endClientOperationId,
  }) : assert(
         (lifecycleStatus == LifecycleStatus.ended) == (endDate != null),
         'endDate must be set if and only if lifecycleStatus is ended',
       ),
       assert(
         (lifecycleStatus == LifecycleStatus.open) ==
             (continuationCertainty != null),
         'continuationCertainty must be set if and only if lifecycleStatus is open',
       );

  /// Null before the row is inserted — the database assigns it.
  final String? id;
  final String userId;
  final LifecycleStatus lifecycleStatus;
  final ContinuationCertainty? continuationCertainty;
  final DateTime startDate;
  final ObservationPrecision startPrecision;
  final ObservationSource startSource;
  final DateTime? endDate;
  final ObservationPrecision? endPrecision;
  final ObservationSource? endSource;

  /// The idempotency key the "start" operation was created under — see
  /// `start_bleeding_episode`'s own doc comment.
  final String? clientOperationId;

  /// The idempotency key the "end" operation was performed under, once
  /// ended — see `end_bleeding_episode`.
  final String? endClientOperationId;

  static String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toInsertJson() => {
    'user_id': userId,
    'lifecycle_status': lifecycleStatus.value,
    if (continuationCertainty != null)
      'continuation_certainty': continuationCertainty!.value,
    'start_date': _dateOnly(startDate),
    'start_precision': startPrecision.value,
    'start_source': startSource.value,
    if (endDate != null) 'end_date': _dateOnly(endDate!),
    if (endPrecision != null) 'end_precision': endPrecision!.value,
    if (endSource != null) 'end_source': endSource!.value,
    if (clientOperationId != null) 'client_operation_id': clientOperationId,
    if (endClientOperationId != null)
      'end_client_operation_id': endClientOperationId,
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
      lifecycleStatus: LifecycleStatus.parse(
        json['lifecycle_status'] as String?,
      ),
      continuationCertainty: json['continuation_certainty'] == null
          ? null
          : ContinuationCertainty.parse(
              json['continuation_certainty'] as String?,
            ),
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
      clientOperationId: json['client_operation_id'] as String?,
      endClientOperationId: json['end_client_operation_id'] as String?,
    );
  }

  @override
  List<Object?> get props => [
    id,
    userId,
    lifecycleStatus,
    continuationCertainty,
    startDate,
    startPrecision,
    startSource,
    endDate,
    endPrecision,
    endSource,
    clientOperationId,
    endClientOperationId,
  ];
}

/// A user's stated USUAL bleeding duration / cycle length — data taxonomy
/// class 3 (USER_REPORTED_ESTIMATE, Section 3). Never itself an
/// observation.
///
/// PR #4 hardening, Blocker 9: previously one mutable row per user, which
/// meant changing her answer made the *old* one unrecoverable — breaking
/// reproducibility for anything that may have used it (a prediction
/// computed under the old estimate could no longer be explained). Each
/// [CycleBaseline] is now its own immutable row in an append-only
/// history; "the current baseline" is simply the most recently
/// [reportedAt] one for that user. Still never versioned as *observed*
/// history — a history of estimates is a fundamentally different taxonomy
/// class from a history of facts.
class CycleBaseline extends Equatable {
  const CycleBaseline({
    this.id,
    required this.userId,
    this.usualBleedingDurationDays,
    this.usualCycleLengthDays,
    this.reportedAt,
  });

  /// Null before insert — the database assigns it.
  final String? id;
  final String userId;
  final int? usualBleedingDurationDays;
  final int? usualCycleLengthDays;

  /// Null lets the database's own `default now()` stamp the real insert
  /// time.
  final DateTime? reportedAt;

  Map<String, dynamic> toInsertJson() => {
    'user_id': userId,
    'usual_bleeding_duration_days': usualBleedingDurationDays,
    'usual_cycle_length_days': usualCycleLengthDays,
  };

  factory CycleBaseline.fromJson(Map<String, dynamic> json) => CycleBaseline(
    id: json['id'] as String?,
    userId: json['user_id'] as String? ?? '',
    usualBleedingDurationDays: json['usual_bleeding_duration_days'] as int?,
    usualCycleLengthDays: json['usual_cycle_length_days'] as int?,
    reportedAt: json['reported_at'] == null
        ? null
        : DateTime.tryParse(json['reported_at'] as String),
  );

  @override
  List<Object?> get props => [
    id,
    userId,
    usualBleedingDurationDays,
    usualCycleLengthDays,
    reportedAt,
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
    this.timezone,
    required this.utcOffsetMinutes,
    this.symptoms,
    this.notes,
    this.supersedesId,
    this.clientOperationId,
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

  /// Best-effort metadata only (an IANA identifier when the platform
  /// genuinely provides one, otherwise a bare abbreviation, otherwise
  /// null) — PR #4 hardening, Blocker 7: never used in a computation,
  /// since a name like "AST"/"GMT+3" is ambiguous and would make a
  /// database-side `AT TIME ZONE` lookup outright error rather than
  /// degrade gracefully. [utcOffsetMinutes] is the reliable field.
  final String? timezone;

  /// The exact UTC offset, in minutes, in effect when this was reported —
  /// always obtainable from the platform (`DateTime.timeZoneOffset`),
  /// unlike a true IANA identifier. The only field local-date-boundary
  /// math (future-date rejection, "today" for the daily check-in) is
  /// ever based on.
  final int utcOffsetMinutes;
  final List<String>? symptoms;
  final String? notes;
  final String? supersedesId;

  /// The idempotency key the write that created this row was performed
  /// under, if any — see `start_bleeding_episode`/`end_bleeding_episode`.
  final String? clientOperationId;

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
    if (timezone != null) 'timezone': timezone,
    'utc_offset_minutes': utcOffsetMinutes,
    if (symptoms != null) 'symptoms': symptoms,
    if (notes != null) 'notes': notes,
    if (supersedesId != null) 'supersedes_id': supersedesId,
    if (clientOperationId != null) 'client_operation_id': clientOperationId,
  };

  factory BleedingObservation.fromJson(Map<String, dynamic> json) {
    final rawObservedDate = json['observed_date'] as String?;
    final observedDate = rawObservedDate == null
        ? null
        : DateTime.tryParse(rawObservedDate);
    if (observedDate == null) {
      throw BleedingEpisodeParseException('observed_date', rawObservedDate);
    }

    final rawOffset = json['utc_offset_minutes'];
    final utcOffsetMinutes = rawOffset is int
        ? rawOffset
        : (rawOffset is String ? int.tryParse(rawOffset) : null);
    if (utcOffsetMinutes == null) {
      throw BleedingEpisodeParseException('utc_offset_minutes', rawOffset);
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
      timezone: json['timezone'] as String?,
      utcOffsetMinutes: utcOffsetMinutes,
      symptoms: (json['symptoms'] as List<dynamic>?)
          ?.map((item) => item.toString())
          .toList(),
      notes: json['notes'] as String?,
      supersedesId: json['supersedes_id'] as String?,
      clientOperationId: json['client_operation_id'] as String?,
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
    utcOffsetMinutes,
    symptoms,
    notes,
    supersedesId,
    clientOperationId,
  ];
}
