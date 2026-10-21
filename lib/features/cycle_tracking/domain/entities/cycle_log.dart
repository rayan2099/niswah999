import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import '../../../../core/utils/db_timestamp.dart';

/// Thrown by [CycleLog.fromJson] when a record's required health fields
/// (`date`, `flow`) cannot be honestly parsed — an unparseable date or an
/// unrecognized flow value is never coerced to a plausible-looking default
/// (menstrual-data-integrity charter, Section 6: "invalid required health
/// data must produce ... an honest failure, never a silently-manufactured
/// valid observation"). Callers must catch this and quarantine the single
/// record rather than let it corrupt the rest of a batch — see
/// [SecureLocalStore.decodeJsonListSafely]'s per-item handling.
class CycleLogParseException implements Exception {
  const CycleLogParseException(this.field, this.rawValue);

  final String field;
  final Object? rawValue;

  @override
  String toString() =>
      'CycleLogParseException: invalid or missing "$field" ($rawValue)';
}

enum CyclePhase { menstrual, follicular, ovulation, luteal }

enum FlowLevel { none, spotting, light, medium, heavy }

/// `cycle_entries.data_provenance` (menstrual-data-integrity charter,
/// Commit A migration). [legacyUnverified] is reserved for rows that
/// existed before this column did — provenance genuinely cannot be
/// reconstructed for them (Section 33), so it is never assigned by new
/// application code. Every [CycleLog] built by live application code
/// (the manual Log-Haidh sheet, the bleeding_observations->cycle_entries
/// compatibility projection, Section 35) is a real, live, user-driven
/// action, so [userObserved] is the correct default going forward —
/// [legacyUnverified] only ever reaches a real row via this column's own
/// DB-level default on rows that predate it.
enum CycleEntryProvenance {
  legacyUnverified,
  userObserved,
  userReportedHistorical;

  String get value => switch (this) {
    CycleEntryProvenance.legacyUnverified => 'legacy_unverified',
    CycleEntryProvenance.userObserved => 'user_observed',
    CycleEntryProvenance.userReportedHistorical => 'user_reported_historical',
  };

  // Metadata about the record, not health data itself — Section 6's
  // strict-parsing mandate targets health facts (date/flow); an
  // unrecognized or missing provenance value here is treated the same
  // conservative way the column's own DB default already treats a
  // pre-existing row: legacyUnverified, never assumed otherwise.
  static CycleEntryProvenance parse(String? raw) => switch (raw) {
    'user_observed' => CycleEntryProvenance.userObserved,
    'user_reported_historical' => CycleEntryProvenance.userReportedHistorical,
    _ => CycleEntryProvenance.legacyUnverified,
  };
}

class CycleLog extends Equatable {
  const CycleLog({
    required this.id,
    required this.userId,
    required this.date,
    required this.flow,
    this.notes,
    this.cycleDay = 1,
    this.symptoms = const <String>[],
    this.syncStatus = SyncStatus.pending,
    this.createdAt,
    this.updatedAt,
    this.dataProvenance = CycleEntryProvenance.userObserved,
    this.observedTime,
  });

  final String id;
  final String userId;
  final DateTime date;
  final FlowLevel flow;
  final String? notes;
  final int cycleDay;
  final List<String> symptoms;
  final SyncStatus syncStatus;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final CycleEntryProvenance dataProvenance;

  /// The exact moment bleeding was observed on this day, when the
  /// canonical evidence states one (every bleeding observation for the
  /// day was recorded with an exact time; the earliest is kept). Null for
  /// a date-only (or approximate-time) day — the Fiqh engine then must
  /// not assume bleeding began at local midnight. Set only by
  /// `CanonicalFiqhEvidenceAdapter`; never persisted to `cycle_entries`.
  final DateTime? observedTime;

  /// Round-2 hardening (proposed) — marks a `cycle_entries` row saved from
  /// the "Symptoms & notes" sheet for a day that had no row yet. Such a
  /// row records symptoms/notes ONLY: its `flow` column holds the
  /// table's required placeholder (`none`), which is NOT an observation
  /// that she was not bleeding (contract: unknown is valid data, never an
  /// invented fact). Stored in the existing `symptoms` array as a
  /// `key:value` pair whose value is not a number, so every symptom
  /// decoder already ignores it. See [recordsFlow].
  static const String symptomsOnlyMarker = 'flow:unrecorded';

  /// False for a symptoms/notes-only row ([symptomsOnlyMarker]). Episode
  /// detection, the Fiqh engine, the reports and the calendar's
  /// Haid/Tahara markers read only rows where this is true.
  bool get recordsFlow => !symptoms.contains(symptomsOnlyMarker);

  CycleLog copyWith({
    String? id,
    String? userId,
    DateTime? date,
    FlowLevel? flow,
    String? notes,
    int? cycleDay,
    List<String>? symptoms,
    SyncStatus? syncStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
    CycleEntryProvenance? dataProvenance,
    DateTime? observedTime,
  }) {
    return CycleLog(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      date: date ?? this.date,
      flow: flow ?? this.flow,
      notes: notes ?? this.notes,
      cycleDay: cycleDay ?? this.cycleDay,
      symptoms: symptoms ?? this.symptoms,
      syncStatus: syncStatus ?? this.syncStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      dataProvenance: dataProvenance ?? this.dataProvenance,
      observedTime: observedTime ?? this.observedTime,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'date': date.toIso8601String(),
      'time_logged': dbTimestamp(updatedAt ?? createdAt ?? DateTime.now()),
      'flow': flow.name,
      'notes': notes,
      'cycle_day': cycleDay,
      'symptoms': symptoms,
      'sync_status': syncStatus.name,
      'created_at': dbTimestamp(createdAt ?? DateTime.now()),
      'updated_at': dbTimestamp(updatedAt ?? DateTime.now()),
      'data_provenance': dataProvenance.value,
    };
  }

  /// Throws [CycleLogParseException] if `date` is missing/unparseable or
  /// `flow` is missing/unrecognized — never invents `DateTime.now()` or
  /// `FlowLevel.light` in their place. See [CycleLogParseException].
  factory CycleLog.fromJson(Map<String, dynamic> json) {
    final rawDate = json['date'] as String?;
    final parsedDate = rawDate == null ? null : DateTime.tryParse(rawDate);
    if (parsedDate == null) {
      throw CycleLogParseException('date', rawDate);
    }

    final rawFlow = json['flow'] as String?;
    final parsedFlow = rawFlow == null
        ? null
        : FlowLevel.values.firstWhereOrNull((value) => value.name == rawFlow);
    if (parsedFlow == null) {
      throw CycleLogParseException('flow', rawFlow);
    }

    return CycleLog(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      date: parsedDate,
      flow: parsedFlow,
      notes: json['notes'] as String?,
      cycleDay: json['cycle_day'] as int? ?? 1,
      symptoms: (json['symptoms'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      syncStatus: SyncStatus.values.firstWhere(
        (value) => value.name == (json['sync_status'] as String? ?? 'pending'),
        orElse: () => SyncStatus.pending,
      ),
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'] as String),
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.tryParse(json['updated_at'] as String),
      // A row read back from the database keeps whatever provenance it
      // actually has — including legacyUnverified for a genuinely old
      // row — never the constructor's userObserved default, which is
      // only correct for a *newly constructed* instance representing a
      // fresh live action, not for reading one back.
      dataProvenance: CycleEntryProvenance.parse(
        json['data_provenance'] as String?,
      ),
    );
  }

  @override
  List<Object?> get props => [
    id,
    userId,
    date,
    flow,
    notes,
    cycleDay,
    symptoms,
    syncStatus,
    createdAt,
    updatedAt,
    dataProvenance,
    observedTime,
  ];
}

enum SyncStatus { pending, synced, failed }

class CycleTrackingSummary extends Equatable {
  const CycleTrackingSummary({
    required this.averageCycleLength,
    required this.averagePeriodLength,
    required this.lastCycleStart,
    required this.currentPhase,
    required this.fertileWindow,
    this.nextPeriodStart,
    this.hasPlausibleAverage = false,
    this.predictedCycleLength,
    this.daysLate = 0,
    this.nextPeriodRange,
    this.predictionBasis,
  });

  final int? averageCycleLength;
  final int? averagePeriodLength;
  final DateTime? lastCycleStart;
  final CyclePhase currentPhase;
  final FertileWindow fertileWindow;

  /// Predicted start of the next period — never a date in the past
  /// relative to the `now` given to
  /// [CycleTrackingController.summarizeHistory]. When the period is late
  /// this is "today" while still inside the expected window, then null
  /// once she is clearly late (see [daysLate]); it is never silently
  /// replaced by the following month's date.
  final DateTime? nextPeriodStart;

  /// Cycle length every forward prediction here was built from (see
  /// `CycleCalculationResult.predictedCycleLength`). Null when nothing is
  /// predicted.
  final int? predictedCycleLength;

  /// Days past the expected period start with no new start logged; 0 when
  /// not late. While > 0 the fertile window is withheld.
  final int daysLate;

  /// Days the next period is most likely to start on. Set whenever a next
  /// period is predicted, including from her stated estimate alone (then
  /// [predictionBasis] is [PredictionBasis.statedEstimate] and
  /// [nextPeriodStart] stays null, so nothing presents an estimate as her
  /// logged pattern without saying so). Null when she is clearly late.
  final PredictedDateRange? nextPeriodRange;

  /// What the prediction was built from; null when nothing is predicted.
  final PredictionBasis? predictionBasis;

  /// Whether forward predictions exist, i.e. [predictedCycleLength] is
  /// set. [averageCycleLength] is deliberately left ungated above
  /// (Haid/Tahara day-tallies and fiqh classification stay valid even on a
  /// degenerate average), but any *forward projection* (an "Expected Haid"
  /// pattern drawn on a calendar, say) must check this first and build
  /// from [predictedCycleLength], or a tiny average (e.g. 2 days, from two
  /// Haid starts logged close together) repeats every couple of days
  /// instead of producing one real block per cycle.
  final bool hasPlausibleAverage;

  @override
  List<Object?> get props => [
    averageCycleLength,
    averagePeriodLength,
    lastCycleStart,
    currentPhase,
    fertileWindow,
    nextPeriodStart,
    hasPlausibleAverage,
    predictedCycleLength,
    daysLate,
    nextPeriodRange,
    predictionBasis,
  ];
}

/// What a forward prediction was built from. The charter's evidence
/// taxonomy keeps a woman's own stated estimate (`USER_REPORTED_ESTIMATE`,
/// the onboarding `cycle_baselines` row) distinct from cycles she actually
/// logged, so every screen can say which one it is showing.
enum PredictionBasis {
  /// Logged cycles only.
  history,

  /// Logged cycles, pulled toward her stated usual cycle length while
  /// there are still few of them.
  historyAndEstimate,

  /// No usable logged cycle yet: her stated usual cycle length alone,
  /// counted from her one logged start.
  statedEstimate,
}

/// The days the next period is most likely to start on, both inclusive —
/// shown instead of a single date, which promises more precision than any
/// cycle prediction has.
class PredictedDateRange extends Equatable {
  const PredictedDateRange({required this.earliest, required this.latest});

  final DateTime earliest;
  final DateTime latest;

  @override
  List<Object?> get props => [earliest, latest];
}

class FertileWindow extends Equatable {
  const FertileWindow({
    required this.start,
    required this.end,
    required this.peakDay,
  });

  final DateTime? start;
  final DateTime? end;
  final DateTime? peakDay;

  @override
  List<Object?> get props => [start, end, peakDay];
}
