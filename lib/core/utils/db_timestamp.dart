/// Serializes an instant for a Postgres `timestamptz` column.
///
/// A local [DateTime]'s `toIso8601String()` has NO zone designator, and the
/// database reads a zone-less string as UTC — so a device at UTC+3 wrote every
/// timestamp 3 hours into the future (found live: a pregnancy `manual_week_set_at`
/// and `wellbeing_logs.created_at` were ahead of the server clock by exactly
/// the device's UTC offset). Always send an explicit UTC instant.
///
/// Do NOT use this for `date` columns (a calendar day, no instant).
String dbTimestamp(DateTime instant) => instant.toUtc().toIso8601String();
