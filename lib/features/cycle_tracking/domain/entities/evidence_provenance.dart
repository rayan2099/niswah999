import 'package:flutter/material.dart';

import 'bleeding_episode.dart';
import 'cycle_log.dart';

/// F7 (menstrual-data-integrity charter) — the single, shared taxonomy
/// every provenance-aware surface (dashboard, canonical calendar,
/// observation detail, prediction surfaces) renders from. Six classes,
/// never fewer: collapsing any two of these into one visual/semantic
/// treatment is exactly the failure mode this enum exists to prevent
/// (e.g. showing a prediction the same way as a confirmed observation,
/// or silently upgrading [legacyUnverified] to [userObserved]).
///
/// Each value carries its own icon and short/long label pair so every
/// consumer distinguishes classes by more than color alone (a
/// color-only distinction fails for color-blind users and is invisible
/// to a screen reader) — see [icon]/[shortLabel]/[longLabel].
enum EvidenceProvenance {
  /// Reported live, at/near the same real time as the event.
  userObserved,

  /// Reported after the fact (backfill, onboarding, a correction).
  userReportedHistorical,

  /// A stated USUAL bleeding duration / cycle length ([CycleBaseline]) —
  /// never itself an observation of a specific day.
  userReportedEstimate,

  /// A statistical projection (e.g. an "Expected Haid" calendar day, a
  /// ring segment) — never a fact, always subject to change as real
  /// data arrives.
  predicted,

  /// A pre-canonical-migration `cycle_entries` row with no recorded
  /// source — never assumed to be [userObserved].
  legacyUnverified,

  /// An explicit "I'm not sure" answer ([ObservationFlow.uncertain]) —
  /// itself a first-class response, not merely an absence of data.
  missingUncertain;

  IconData get icon => switch (this) {
    EvidenceProvenance.userObserved => Icons.check_circle_rounded,
    EvidenceProvenance.userReportedHistorical => Icons.history_edu_rounded,
    EvidenceProvenance.userReportedEstimate => Icons.calculate_rounded,
    EvidenceProvenance.predicted => Icons.auto_graph_rounded,
    EvidenceProvenance.legacyUnverified => Icons.help_outline_rounded,
    EvidenceProvenance.missingUncertain => Icons.question_mark_rounded,
  };

  /// A visual pattern distinct from color — used for border/fill style
  /// so a color-blind reader (and print/greyscale contexts) can still
  /// tell provenance classes apart. See [ProvenanceBadge] and the
  /// canonical calendar's day cells for where this is applied.
  BorderStyle get borderStyle => switch (this) {
    EvidenceProvenance.userObserved => BorderStyle.solid,
    EvidenceProvenance.userReportedHistorical => BorderStyle.solid,
    EvidenceProvenance.userReportedEstimate => BorderStyle.solid,
    EvidenceProvenance.predicted => BorderStyle.none, // dashed, drawn manually
    EvidenceProvenance.legacyUnverified => BorderStyle.solid,
    EvidenceProvenance.missingUncertain => BorderStyle.solid,
  };

  /// True for classes that must never be rendered with the same solid,
  /// confident fill a real observed fact gets — [predicted] most of
  /// all: this charter explicitly requires a predicted date never share
  /// confirmed bleeding's own visual style.
  bool get isTentative => switch (this) {
    EvidenceProvenance.predicted => true,
    EvidenceProvenance.legacyUnverified => true,
    EvidenceProvenance.missingUncertain => true,
    EvidenceProvenance.userObserved => false,
    EvidenceProvenance.userReportedHistorical => false,
    EvidenceProvenance.userReportedEstimate => false,
  };

  String shortLabel(bool arabic) => switch (this) {
    EvidenceProvenance.userObserved => arabic ? 'مُلاحَظ' : 'Observed',
    EvidenceProvenance.userReportedHistorical =>
      arabic ? 'مُدخَل لاحقاً' : 'Backfilled',
    EvidenceProvenance.userReportedEstimate => arabic ? 'تقدير' : 'Estimate',
    EvidenceProvenance.predicted => arabic ? 'متوقع' : 'Predicted',
    EvidenceProvenance.legacyUnverified => arabic ? 'غير مؤكد' : 'Unverified',
    EvidenceProvenance.missingUncertain => arabic ? 'غير معروف' : 'Unknown',
  };

  String longLabel(bool arabic) => switch (this) {
    EvidenceProvenance.userObserved =>
      arabic
          ? 'أبلغتِ عن هذا وقت حدوثه فعلياً'
          : 'You reported this at the time it happened',
    EvidenceProvenance.userReportedHistorical =>
      arabic
          ? 'أُضيف لاحقاً كإدخال لتاريخ سابق'
          : 'Added later as a record of a past date',
    EvidenceProvenance.userReportedEstimate =>
      arabic
          ? 'تقديركِ العام لمدة أو تكرار الدورة، وليس ملاحظة ليوم بعينه'
          : "Your general estimate of duration or cycle length, not an "
                'observation of a specific day',
    EvidenceProvenance.predicted =>
      arabic
          ? 'تقدير إحصائي مبني على نمط دوراتكِ السابقة — وليس حقيقة مؤكدة'
          : "A statistical projection from your past cycles — not a "
                'confirmed fact',
    EvidenceProvenance.legacyUnverified =>
      arabic
          ? 'بيانات قديمة قبل التتبع الحالي، لم تُسجَّل مصادرها الأصلية'
          : "Older data from before this tracking model — its original "
                'source was not recorded',
    EvidenceProvenance.missingUncertain =>
      arabic
          ? 'أجبتِ بأنكِ غير متأكدة — إجابة صريحة، وليست غيابا للبيانات'
          : 'You answered "I\'m not sure" — an explicit answer, not an '
                'absence of data',
  };
}

/// Derives the provenance class for a canonical `bleeding_observations`
/// row. [ObservationFlow.uncertain] always wins over the row's own
/// [ObservationSource] — an explicit "I'm not sure" is its own class
/// regardless of when it was reported (see [EvidenceProvenance.missingUncertain]'s
/// own doc comment).
EvidenceProvenance provenanceForObservation(BleedingObservation observation) {
  if (observation.flow == ObservationFlow.uncertain) {
    return EvidenceProvenance.missingUncertain;
  }
  return switch (observation.source) {
    ObservationSource.userObserved => EvidenceProvenance.userObserved,
    ObservationSource.userReportedHistorical =>
      EvidenceProvenance.userReportedHistorical,
  };
}

/// Derives the provenance class for a legacy `cycle_entries`-backed
/// [CycleLog] row (dashboard/ring surfaces that still read [CycleLog]
/// directly, e.g. the pre-canonical calendar) — never assumes
/// [EvidenceProvenance.userObserved] for a row with no recorded
/// provenance.
EvidenceProvenance provenanceForCycleLog(CycleLog log) =>
    switch (log.dataProvenance) {
      CycleEntryProvenance.userObserved => EvidenceProvenance.userObserved,
      CycleEntryProvenance.userReportedHistorical =>
        EvidenceProvenance.userReportedHistorical,
      CycleEntryProvenance.legacyUnverified =>
        EvidenceProvenance.legacyUnverified,
    };
