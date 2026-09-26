/// Menstrual Data Integrity charter, Closure Blocker 1 — a read failure
/// must never be silently conflated with "verified no data." Every
/// canonical read this app treats as load-bearing for a factual claim
/// ("no history," "no open episode," "nothing missed") returns one of
/// these three, explicitly, rather than degrading a
/// `PostgrestException`/parse failure into an empty list or null that
/// looks identical to a genuinely empty, successfully-verified result.
sealed class LoadResult<T> {
  const LoadResult();

  /// True only for a query that genuinely ran and returned rows (however
  /// many, including zero) with no unreadable rows quarantined along the
  /// way.
  bool get isCleanSuccess => this is LoadSuccess<T>;

  /// The data if this read produced any at all (`LoadSuccess`/
  /// `LoadDegraded`), or null if the read never completed
  /// (`LoadUnavailable`). Convenience for call sites that only need a
  /// best-effort value and already treat "nothing found" and "couldn't
  /// check" the same way (e.g. an opportunistic projection mirror
  /// look-up) — never use this where the distinction actually matters to
  /// the user (that is exactly what this type exists to prevent).
  T? get dataOrNull => switch (this) {
    LoadSuccess<T>(:final data) => data,
    LoadDegraded<T>(:final data) => data,
    LoadUnavailable<T>() => null,
  };
}

/// A clean, fully-verified result — every row that came back parsed
/// successfully. An empty [data] here is a genuine, positive fact ("this
/// user has zero episodes"), not an absence-of-evidence default.
final class LoadSuccess<T> extends LoadResult<T> {
  const LoadSuccess(this.data);
  final T data;
}

/// The read could not be completed at all — a network/backend failure,
/// an RLS/auth rejection, or (for a single-row read) a parse failure on
/// the one row that exists. Callers MUST treat this as "unknown," never
/// as "confirmed absent."
final class LoadUnavailable<T> extends LoadResult<T> {
  const LoadUnavailable(this.category, [this.message]);
  final LoadErrorCategory category;
  final String? message;
}

/// A list read that substantively succeeded but quarantined one or more
/// individually-unparseable rows along the way (mirroring
/// `PendingBleedingOperation.tryFromJson`'s own "quarantine, don't crash"
/// policy). [data] is real and safe to use, but [quarantinedCount] > 0
/// means the true picture may be incomplete — a caller computing
/// something with real user-facing consequences (a prediction, a Fiqh
/// conclusion) must not claim full confidence from it.
final class LoadDegraded<T> extends LoadResult<T> {
  const LoadDegraded(this.data, this.quarantinedCount);
  final T data;
  final int quarantinedCount;
}

enum LoadErrorCategory { network, backend, unauthorized, parseFailure, unknown }
