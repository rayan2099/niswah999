import 'report_source_status.dart';

/// Whether Doctor's Report, as a whole, can honestly be presented as
/// finished — separate from whether it *rendered* successfully. A report
/// can render a perfectly valid PDF while still being [partial] or
/// [insufficient]; this value is what the UI and the PDF itself use to
/// say so, rather than presenting every successfully-rendered report as
/// equally trustworthy. Doctor's Report Data Completeness + Truthfulness
/// wave, 2026-09-06 (PJ-006).
enum ReportCompleteness {
  /// Every source resolved without error, and there is enough real data
  /// to make the report meaningful.
  complete,

  /// At least one optional source failed to load, but enough of the
  /// required data resolved to still produce a useful report. The failed
  /// section(s) must be explicitly disclosed, never silently dropped.
  partial,

  /// Everything resolved without error, but there simply isn't enough
  /// real data anywhere to make the report meaningful (e.g. a brand-new
  /// account with no logged history at all). Not a failure — an honest
  /// "nothing to show yet."
  insufficient,

  /// The required source (cycle/haid history — the data this report is
  /// fundamentally built around) failed to load. Generating a cycle/fiqh
  /// report without it would actively misrepresent the user's status, not
  /// just omit a supplementary detail.
  loadFailure,
}

/// Computes the report-level state from each source's individually
/// observed outcome. Cycle/haid history is the only required source (see
/// the wave's Phase D classification) — everything else is optional and
/// degrades the report to [ReportCompleteness.partial], never blocks it.
ReportCompleteness computeReportCompleteness({
  required ReportSourceStatus cycleStatus,
  required ReportSourceStatus pregnancyStatus,
  required ReportSourceStatus wellbeingStatus,
  required ReportSourceStatus flagsStatus,
  required bool hasAnyMeaningfulData,
}) {
  if (cycleStatus == ReportSourceStatus.failed) {
    return ReportCompleteness.loadFailure;
  }

  final anyOptionalFailed = [
    pregnancyStatus,
    wellbeingStatus,
    flagsStatus,
  ].contains(ReportSourceStatus.failed);
  if (anyOptionalFailed) {
    return ReportCompleteness.partial;
  }

  if (!hasAnyMeaningfulData) {
    return ReportCompleteness.insufficient;
  }

  return ReportCompleteness.complete;
}
