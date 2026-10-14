import '../../features/cycle_tracking/domain/entities/bleeding_episode.dart';
import '../../features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import '../network/supabase_client.dart';
import 'madhhab_controller.dart';

/// One row of `public.madhhab_history`, parsed read-side. See
/// `supabase/migrations/20261007090000_madhhab_change_history.sql` for the
/// base schema -- effective interval resolution needs no new columns for
/// Madhhab/selection-state ("this row's [changedAt] until the next row's
/// [changedAt] for the same user"). [previousRulesetVersion] mirrors the
/// one additive column from `20261014220000_madhhab_history_ruleset_
/// version_future_safety.sql` (governance item 2: future ruleset-version
/// safety) -- null for any row written before that column existed, or
/// for a user's genuine first-ever transition.
class MadhhabHistoryEntry {
  const MadhhabHistoryEntry({
    required this.changedAt,
    required this.previousSelectionState,
    required this.previousMadhhab,
    required this.newSelectionState,
    required this.newMadhhab,
    required this.rulesetVersion,
    this.previousRulesetVersion,
    required this.source,
  });

  final DateTime changedAt;
  final MadhhabSelectionState previousSelectionState;
  final Madhhab? previousMadhhab;
  final MadhhabSelectionState newSelectionState;
  final Madhhab? newMadhhab;
  final String rulesetVersion;

  /// The ruleset version that governed the PREVIOUS interval (i.e. what
  /// was in effect immediately before [changedAt]), as recorded at the
  /// time of this transition from the user's own prior row -- never
  /// inferred after the fact. Null when unknown (no column value, or no
  /// prior row existed to read it from).
  final String? previousRulesetVersion;
  final String? source;

  static MadhhabSelectionState _parseState(String? raw) =>
      switch (raw) {
        'selected' => MadhhabSelectionState.selected,
        'unknown' => MadhhabSelectionState.unknown,
        _ => MadhhabSelectionState.unset,
      };

  static Madhhab? _parseMadhhab(String? raw) {
    if (raw == null) return null;
    for (final value in Madhhab.values) {
      if (value.name == raw.toLowerCase()) return value;
    }
    return null;
  }

  factory MadhhabHistoryEntry.fromJson(Map<String, dynamic> json) =>
      MadhhabHistoryEntry(
        changedAt: DateTime.parse(json['changed_at'] as String).toUtc(),
        previousSelectionState: _parseState(
          json['previous_selection_state'] as String?,
        ),
        previousMadhhab: _parseMadhhab(json['previous_madhhab'] as String?),
        newSelectionState: _parseState(json['new_selection_state'] as String?),
        newMadhhab: _parseMadhhab(json['new_madhhab'] as String?),
        rulesetVersion:
            json['ruleset_version'] as String? ??
            MadhhabRuleEvaluator.rulesetVersion,
        previousRulesetVersion: json['previous_ruleset_version'] as String?,
        source: json['source'] as String?,
      );
}

/// Why [ResolvedMadhhab] resolved the way it did -- lets a caller or test
/// distinguish a real historical boundary from a disclosed fallback,
/// never silently treating the two the same way.
enum MadhhabResolutionBasis {
  /// The requested date falls inside a real `madhhab_history` interval:
  /// [MadhhabHistoryEntry.changedAt] <= date < the next entry's
  /// [MadhhabHistoryEntry.changedAt] (or unbounded if this is the latest).
  historicalRecord,

  /// The requested date is before the user's EARLIEST known
  /// `madhhab_history` row. Resolved from that row's own
  /// `previous_selection_state`/`previous_madhhab` -- the honestly-recorded
  /// state she was in right before her first captured change -- never a
  /// fabricated date. If that row's previous state was itself `unset`,
  /// this correctly resolves to unset (she genuinely hadn't chosen yet).
  earliestRecordPreviousState,

  /// No `madhhab_history` row exists for this user at all (predates the
  /// table, or every transition's audit insert has so far failed/never
  /// happened). Falls back to her CURRENT `users.madhhab`/
  /// `madhhab_selection_state`, applied to every date for lack of any
  /// better information. A disclosed limitation, not an invented boundary.
  noHistoryFallback,
}

/// The result of resolving "what Madhhab/ruleset applied on this date" --
/// never a bare [Madhhab]/[MadhhabSelectionState] pair, so a caller can
/// always see which interval (if any) it came from and why.
class ResolvedMadhhab {
  const ResolvedMadhhab({
    required this.selectionState,
    required this.madhhab,
    required this.rulesetVersion,
    required this.effectiveFrom,
    required this.effectiveTo,
    required this.resolution,
  });

  final MadhhabSelectionState selectionState;

  /// Non-null only when [selectionState] is
  /// [MadhhabSelectionState.selected] -- same invariant [MadhhabController]
  /// itself holds.
  final Madhhab? madhhab;

  /// The ruleset version in force for this interval. For
  /// [MadhhabResolutionBasis.historicalRecord] and
  /// [MadhhabResolutionBasis.earliestRecordPreviousState] when the
  /// relevant row has a recorded `previous_ruleset_version` (every
  /// transition written on or after migration 20261014220000), this is a
  /// real, resolved value — never guessed. It only falls back to the
  /// CURRENT global ruleset version ([MadhhabRuleEvaluator.rulesetVersion])
  /// for [MadhhabResolutionBasis.noHistoryFallback], or for
  /// [MadhhabResolutionBasis.earliestRecordPreviousState] against a row
  /// written before that column existed (or a user's true first-ever
  /// transition, which has no prior ruleset to record) — harmless today,
  /// since only one ruleset value has ever existed. See
  /// `madhhab_history_resolver_test.dart`'s "a second Fiqh ruleset
  /// version must not be released until..." test, which is the literal
  /// release gate for whenever a second value is introduced.
  final String rulesetVersion;

  /// Null only for [MadhhabResolutionBasis.noHistoryFallback] (no known
  /// boundary at all, not even an unbounded-past one) and for the
  /// unbounded-past side of [MadhhabResolutionBasis.earliestRecordPreviousState].
  final DateTime? effectiveFrom;

  /// Null means "still in effect" (the latest known interval, or the
  /// no-history fallback, which is never superseded by a later interval
  /// since none exists).
  final DateTime? effectiveTo;

  final MadhhabResolutionBasis resolution;

  bool get isSelected =>
      selectionState == MadhhabSelectionState.selected && madhhab != null;
}

/// The one canonical resolver for "what Madhhab governed a given date" --
/// every historical-period Fiqh calculation must go through this, rather
/// than reading `MadhhabController.instance`'s current value (which only
/// ever reflects *today's* selection, never history). Current-context UI
/// (today's dashboard ring, the AI advisor's live context, Profile) may
/// keep reading `MadhhabController.instance` directly -- see the
/// geographic-Madhhab-era call-site audit, which confirmed every existing
/// Fiqh-evaluation call site is current-context only; none currently do
/// historical-period evaluation, so none needed updating for this.
///
/// Pure resolution logic ([resolveFromEntries]) is factored out from I/O
/// ([resolveMadhhabForDate]) specifically so the boundary matrix (section
/// 5/11 of the effective-dated-history task) can be tested exhaustively
/// without a live backend.
class MadhhabHistoryResolver {
  const MadhhabHistoryResolver();

  /// Pure: given a user's full `madhhab_history` (any order) and her
  /// current server state (the fallback for a user with no history at
  /// all), resolves which Madhhab/ruleset governed [date].
  ///
  /// ## The canonical same-calendar-day rule (governance decision,
  /// confirmed 2026-10-14; see `madhhab_history_resolver_test.dart`'s
  /// "same-calendar-day semantics are explicit" group for the dedicated
  /// test)
  ///
  /// **A Madhhab change becomes effective for Fiqh interpretation from the
  /// calendar date of the change. If a bleeding episode starts on that
  /// same calendar date, the newly selected Madhhab governs the entire
  /// episode** -- regardless of what time of day, on that date, the
  /// change was actually recorded. An entry's effective interval is
  /// `[changedAt, nextChangedAt)` at CALENDAR-DAY granularity: both sides
  /// are truncated to UTC midnight before comparing.
  ///
  /// This is an APPLICATION METHODOLOGY decision forced by this app's own
  /// data shape, not a universal Fiqh claim: a bleeding episode's start is
  /// currently recorded as date-only (`BleedingEpisode.startDate` has no
  /// time component — see its own doc comment), and Niswah has no
  /// reliable start-TIME granularity to rely on. Because of that, sub-day
  /// ordering between "when she changed her Madhhab" and "when her
  /// episode actually started that same day" cannot be honestly
  /// reconstructed — there is no trustworthy finer-grained fact to
  /// resolve it from. Treating the whole calendar day as governed by the
  /// day's final Madhhab choice is the one deterministic, honest
  /// resolution available given that limitation; it is not a position on
  /// which moment within a day a Fiqh ruling would, in principle, take
  /// effect.
  static ResolvedMadhhab resolveFromEntries({
    required List<MadhhabHistoryEntry> entries,
    required DateTime date,
    required MadhhabSelectionState currentState,
    required Madhhab? currentMadhhab,
    String currentRulesetVersion = MadhhabRuleEvaluator.rulesetVersion,
  }) {
    if (entries.isEmpty) {
      return ResolvedMadhhab(
        selectionState: currentState,
        madhhab: currentState == MadhhabSelectionState.selected
            ? currentMadhhab
            : null,
        rulesetVersion: currentRulesetVersion,
        effectiveFrom: null,
        effectiveTo: null,
        resolution: MadhhabResolutionBasis.noHistoryFallback,
      );
    }

    final targetDay = _dayOnlyUtc(date);
    final sorted = [...entries]..sort(
      (a, b) => a.changedAt.compareTo(b.changedAt),
    );

    MadhhabHistoryEntry? applicable;
    var applicableIndex = -1;
    for (var i = 0; i < sorted.length; i++) {
      if (!_dayOnlyUtc(sorted[i].changedAt).isAfter(targetDay)) {
        applicable = sorted[i];
        applicableIndex = i;
      } else {
        break;
      }
    }

    if (applicable == null) {
      final earliest = sorted.first;
      return ResolvedMadhhab(
        selectionState: earliest.previousSelectionState,
        madhhab: earliest.previousSelectionState == MadhhabSelectionState.selected
            ? earliest.previousMadhhab
            : null,
        // Governance item 2 (future ruleset-version safety): use the
        // earliest row's own recorded previousRulesetVersion when
        // present (populated for every transition written on or after
        // migration 20261014220000) -- only fall back to the current
        // global constant when that field is genuinely unknown (a row
        // written before the column existed, or her true first-ever
        // transition, which has no prior ruleset to record).
        rulesetVersion: earliest.previousRulesetVersion ?? currentRulesetVersion,
        effectiveFrom: null,
        effectiveTo: earliest.changedAt,
        resolution: MadhhabResolutionBasis.earliestRecordPreviousState,
      );
    }

    final next = applicableIndex + 1 < sorted.length
        ? sorted[applicableIndex + 1]
        : null;

    return ResolvedMadhhab(
      selectionState: applicable.newSelectionState,
      madhhab: applicable.newSelectionState == MadhhabSelectionState.selected
          ? applicable.newMadhhab
          : null,
      rulesetVersion: applicable.rulesetVersion,
      effectiveFrom: applicable.changedAt,
      effectiveTo: next?.changedAt,
      resolution: MadhhabResolutionBasis.historicalRecord,
    );
  }

  static DateTime _dayOnlyUtc(DateTime d) {
    final utc = d.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }

  /// I/O: fetches [userId]'s full `madhhab_history` plus her current
  /// server state, then resolves [date] via [resolveFromEntries]. Does its
  /// own Supabase queries directly, the same established pattern
  /// `MadhhabController` itself already uses for this table -- no
  /// repository abstraction exists for Madhhab data in this codebase.
  ///
  /// Never reads `MadhhabController.instance`'s in-memory state -- that
  /// reflects only *today's* selection, and would make this resolver's
  /// result depend on which account happens to be signed in on this
  /// device right now rather than purely on [userId]'s own server history,
  /// breaking the "restart/reload preserves the same historical
  /// interpretation" guarantee this resolver exists to provide.
  Future<ResolvedMadhhab> resolveMadhhabForDate(
    String userId,
    DateTime date,
  ) async {
    final client = NiswahSupabase.clientOrNull;
    if (client == null) {
      throw StateError(
        'MadhhabHistoryResolver.resolveMadhhabForDate requires a live '
        'Supabase client.',
      );
    }

    const baseColumns =
        'changed_at, previous_selection_state, previous_madhhab, '
        'new_selection_state, new_madhhab, ruleset_version, source';
    List<dynamic> historyRows;
    try {
      // previous_ruleset_version: migration 20261014220000, applied on
      // the team's own schedule. Select it when present; fall back to
      // the base columns when the environment doesn't have it yet, so
      // this resolver keeps working (without that one future-safety
      // field) rather than failing outright before the migration lands.
      historyRows = await client
          .from('madhhab_history')
          .select('$baseColumns, previous_ruleset_version')
          .eq('user_id', userId) as List;
    } catch (_) {
      historyRows = await client
          .from('madhhab_history')
          .select(baseColumns)
          .eq('user_id', userId) as List;
    }
    final entries = historyRows
        .map((row) => MadhhabHistoryEntry.fromJson(row as Map<String, dynamic>))
        .toList();

    final userRow = await client
        .from('users')
        .select('madhhab, madhhab_selection_state')
        .eq('id', userId)
        .maybeSingle();
    final currentState = MadhhabHistoryEntry._parseState(
      userRow?['madhhab_selection_state'] as String?,
    );
    final currentMadhhab = MadhhabHistoryEntry._parseMadhhab(
      userRow?['madhhab'] as String?,
    );

    return resolveFromEntries(
      entries: entries,
      date: date,
      currentState: currentState,
      currentMadhhab: currentMadhhab,
    );
  }

  /// Convenience wrapper implementing the agreed spanning-episode rule
  /// (decided 2026-10-14, not guessed): the Madhhab in effect at the
  /// episode's START date governs the WHOLE episode, even if she changed
  /// Madhhab again before it ended. This matches the existing engine's own
  /// architecture -- [MadhhabRuleEvaluator.evaluate] already classifies an
  /// episode's entire bleeding duration against ONE ruleset, with no
  /// mechanism to split a duration-threshold calculation partway through
  /// under two different rule sets. Splitting at the boundary was
  /// considered and rejected for this reason -- see the audit report.
  Future<ResolvedMadhhab> resolveMadhhabForEpisode(
    String userId,
    BleedingEpisode episode,
  ) => resolveMadhhabForDate(userId, episode.startDate);
}
