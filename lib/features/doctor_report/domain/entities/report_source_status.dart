/// The real, observed outcome of loading one Doctor's Report data source —
/// deliberately distinct from the source's *content*, so a genuinely empty
/// result (nothing to report) can never be confused with a failed one
/// (couldn't tell whether there was anything to report). This is the exact
/// architectural gap PJ-006 identified: an empty `flagged_conversations`
/// read and a silently-failed write into that same table produce the
/// identical zero-row result, with nothing anywhere recording which
/// happened. Doctor's Report Data Completeness + Truthfulness wave,
/// 2026-09-06.
enum ReportSourceStatus {
  /// Successfully loaded, and there is real data to show.
  available,

  /// Successfully loaded — the query/read genuinely succeeded — and there
  /// is nothing there. Not a failure; a true, positive "nothing to report."
  empty,

  /// Not applicable to this report run at all (e.g. no signed-in session
  /// to check pregnancy status for) — different from [empty]: this source
  /// was never meaningfully checked, so its absence proves nothing either
  /// way.
  unavailable,

  /// A load was attempted and did not succeed — the content of [empty]
  /// cannot be trusted to mean "nothing exists," because this path never
  /// actually confirmed that.
  failed,
}

/// Wraps one source's loaded value together with the true outcome of
/// loading it. [data] is always a safe, usable value (an empty list, a
/// null profile, or a local-only fallback) so downstream code never needs
/// null-checks — but [status] must always be consulted before treating
/// [data] as proof of anything. Never substitute a fabricated/default
/// value here to mask a failure — [data] on a [ReportSourceStatus.failed]
/// result must be the best *honest* fallback available (e.g. locally
/// cached data), never an invented one.
class ReportSourceResult<T> {
  const ReportSourceResult({required this.status, required this.data});

  final ReportSourceStatus status;
  final T data;

  bool get isUsable =>
      status == ReportSourceStatus.available ||
      status == ReportSourceStatus.empty;
}
