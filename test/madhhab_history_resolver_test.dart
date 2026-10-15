// Effective-dated Madhhab history (2026-10-14): MadhhabHistoryResolver is
// the one canonical resolver for "what Madhhab/ruleset governed a given
// date" -- every historical-period Fiqh calculation must go through it
// rather than reading MadhhabController.instance's current value, which
// only ever reflects today's selection. These tests exercise the PURE
// `resolveFromEntries` function (no network, no MadhhabController
// involved at all) against the boundary matrix the task specified.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:niswah/core/preferences/madhhab_controller.dart';
import 'package:niswah/core/preferences/madhhab_history_resolver.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';

MadhhabHistoryEntry _entry({
  required DateTime changedAt,
  required MadhhabSelectionState previousState,
  Madhhab? previousMadhhab,
  required MadhhabSelectionState newState,
  Madhhab? newMadhhab,
  String rulesetVersion = MadhhabRuleEvaluator.rulesetVersion,
  String? previousRulesetVersion,
  String source = 'test',
}) => MadhhabHistoryEntry(
  changedAt: changedAt,
  previousSelectionState: previousState,
  previousMadhhab: previousMadhhab,
  newSelectionState: newState,
  newMadhhab: newMadhhab,
  previousRulesetVersion: previousRulesetVersion,
  rulesetVersion: rulesetVersion,
  source: source,
);

void main() {
  group('Three-month switching (the task\'s own literal example)', () {
    // Jan 1: unknown -> Hanafi. Feb 15: Hanafi -> Shafi'i. Mar 21:
    // Shafi'i -> Hanafi again.
    final entries = [
      _entry(
        changedAt: DateTime.utc(2026, 1, 1),
        previousState: MadhhabSelectionState.unknown,
        newState: MadhhabSelectionState.selected,
        newMadhhab: Madhhab.hanafi,
      ),
      _entry(
        changedAt: DateTime.utc(2026, 2, 15),
        previousState: MadhhabSelectionState.selected,
        previousMadhhab: Madhhab.hanafi,
        newState: MadhhabSelectionState.selected,
        newMadhhab: Madhhab.shafii,
      ),
      _entry(
        changedAt: DateTime.utc(2026, 3, 21),
        previousState: MadhhabSelectionState.selected,
        previousMadhhab: Madhhab.shafii,
        newState: MadhhabSelectionState.selected,
        newMadhhab: Madhhab.hanafi,
      ),
    ];

    test('a January episode resolves to Hanafi', () {
      final result = MadhhabHistoryResolver.resolveFromEntries(
        entries: entries,
        date: DateTime.utc(2026, 1, 20),
        currentState: MadhhabSelectionState.selected,
        currentMadhhab: Madhhab.hanafi,
      );
      expect(result.madhhab, Madhhab.hanafi);
      expect(result.resolution, MadhhabResolutionBasis.historicalRecord);
      expect(result.effectiveFrom, DateTime.utc(2026, 1, 1));
      expect(result.effectiveTo, DateTime.utc(2026, 2, 15));
    });

    test('a February episode (after the 15th) resolves to Shafi\'i', () {
      final result = MadhhabHistoryResolver.resolveFromEntries(
        entries: entries,
        date: DateTime.utc(2026, 2, 20),
        currentState: MadhhabSelectionState.selected,
        currentMadhhab: Madhhab.hanafi,
      );
      expect(result.madhhab, Madhhab.shafii);
      expect(result.effectiveFrom, DateTime.utc(2026, 2, 15));
      expect(result.effectiveTo, DateTime.utc(2026, 3, 21));
    });

    test('a March episode (on or after the 21st) resolves to Hanafi again', () {
      final result = MadhhabHistoryResolver.resolveFromEntries(
        entries: entries,
        date: DateTime.utc(2026, 3, 25),
        currentState: MadhhabSelectionState.selected,
        currentMadhhab: Madhhab.hanafi,
      );
      expect(result.madhhab, Madhhab.hanafi);
      expect(result.effectiveFrom, DateTime.utc(2026, 3, 21));
      expect(
        result.effectiveTo,
        isNull,
        reason: 'the latest interval is still in effect',
      );
    });

    test('a pre-January date (before any history existed) falls back to '
        'the earliest row\'s own previous state (unknown)', () {
      final result = MadhhabHistoryResolver.resolveFromEntries(
        entries: entries,
        date: DateTime.utc(2025, 12, 1),
        currentState: MadhhabSelectionState.selected,
        currentMadhhab: Madhhab.hanafi,
      );
      expect(result.selectionState, MadhhabSelectionState.unknown);
      expect(result.madhhab, isNull);
      expect(
        result.resolution,
        MadhhabResolutionBasis.earliestRecordPreviousState,
      );
    });
  });

  group('Boundary scenarios', () {
    final switchEntries = [
      _entry(
        changedAt: DateTime.utc(2026, 2, 15),
        previousState: MadhhabSelectionState.selected,
        previousMadhhab: Madhhab.hanafi,
        newState: MadhhabSelectionState.selected,
        newMadhhab: Madhhab.shafii,
      ),
    ];

    test('episode entirely before the change resolves to the old Madhhab', () {
      final result = MadhhabHistoryResolver.resolveFromEntries(
        entries: switchEntries,
        date: DateTime.utc(2026, 2, 10),
        currentState: MadhhabSelectionState.selected,
        currentMadhhab: Madhhab.shafii,
      );
      expect(result.madhhab, Madhhab.hanafi);
    });

    test('episode entirely after the change resolves to the new Madhhab', () {
      final result = MadhhabHistoryResolver.resolveFromEntries(
        entries: switchEntries,
        date: DateTime.utc(2026, 2, 20),
        currentState: MadhhabSelectionState.selected,
        currentMadhhab: Madhhab.shafii,
      );
      expect(result.madhhab, Madhhab.shafii);
    });

    test('episode start date exactly equal to the change date resolves to '
        'the NEW Madhhab -- the change is effective for that whole '
        'calendar day', () {
      final result = MadhhabHistoryResolver.resolveFromEntries(
        entries: switchEntries,
        date: DateTime.utc(2026, 2, 15),
        currentState: MadhhabSelectionState.selected,
        currentMadhhab: Madhhab.shafii,
      );
      expect(result.madhhab, Madhhab.shafii);
    });

    group('Same-calendar-day semantics are explicit (governance item 1)', () {
      // The canonical rule, verbatim: "A Madhhab change becomes effective
      // for Fiqh interpretation from the calendar date of the change. If
      // a bleeding episode starts on that same calendar date, the newly
      // selected Madhhab governs the entire episode." This is an
      // application-methodology decision forced by date-only episode
      // data (BleedingEpisode.startDate has no time component, and
      // Niswah has no reliable start-TIME granularity), not a universal
      // Fiqh claim -- see MadhhabHistoryResolver.resolveFromEntries' own
      // doc comment for the full reasoning.
      for (final changeTime in [
        const Duration(hours: 0, minutes: 0), // midnight
        const Duration(hours: 9, minutes: 15), // morning
        const Duration(hours: 14, minutes: 30), // afternoon
        const Duration(hours: 23, minutes: 59), // last minute of the day
      ]) {
        test(
          'history change recorded at Feb 15 $changeTime, episode starts '
          'Feb 15 (date-only, no time) -> the NEW Madhhab governs, '
          'regardless of what time the change itself happened to land at',
          () {
            final entries = [
              _entry(
                changedAt: DateTime.utc(2026, 2, 15).add(changeTime),
                previousState: MadhhabSelectionState.selected,
                previousMadhhab: Madhhab.hanafi,
                newState: MadhhabSelectionState.selected,
                newMadhhab: Madhhab.shafii,
              ),
            ];
            final episodeStart = DateTime.utc(2026, 2, 15); // date-only
            final result = MadhhabHistoryResolver.resolveFromEntries(
              entries: entries,
              date: episodeStart,
              currentState: MadhhabSelectionState.selected,
              currentMadhhab: Madhhab.shafii,
            );
            expect(result.madhhab, Madhhab.shafii);
          },
        );
      }
    });

    test(
      'a day BEFORE the change, even at 23:59, still resolves to the OLD '
      'Madhhab -- calendar-day truncation never leaks a later day\'s '
      'change backward',
      () {
        final result = MadhhabHistoryResolver.resolveFromEntries(
          entries: switchEntries,
          date: DateTime.utc(2026, 2, 14, 23, 59),
          currentState: MadhhabSelectionState.selected,
          currentMadhhab: Madhhab.shafii,
        );
        expect(result.madhhab, Madhhab.hanafi);
      },
    );

    test(
      'a spanning episode (started before the change, ended after) is '
      'governed end-to-end by the Madhhab in effect at its START date -- '
      'the agreed decision, confirmed by using the episode\'s startDate as '
      'the resolver\'s reference date (MadhhabHistoryResolver.resolveMadhhabForEpisode '
      'is a one-line wrapper that does exactly this)',
      () {
        final episode = BleedingEpisode(
          userId: 'user-1',
          lifecycleStatus: LifecycleStatus.ended,
          startDate: DateTime.utc(2026, 2, 13),
          startPrecision: ObservationPrecision.dateOnly,
          startSource: ObservationSource.userReportedHistorical,
          endDate: DateTime.utc(2026, 2, 17),
          endPrecision: ObservationPrecision.dateOnly,
          endSource: ObservationSource.userReportedHistorical,
        );
        // The episode's end date (Feb 17) is after the Feb 15 change --
        // if end date governed, this would resolve to Shafi'i.
        final byEndDate = MadhhabHistoryResolver.resolveFromEntries(
          entries: switchEntries,
          date: episode.endDate!,
          currentState: MadhhabSelectionState.selected,
          currentMadhhab: Madhhab.shafii,
        );
        expect(byEndDate.madhhab, Madhhab.shafii);

        // The agreed rule uses the START date instead.
        final byStartDate = MadhhabHistoryResolver.resolveFromEntries(
          entries: switchEntries,
          date: episode.startDate,
          currentState: MadhhabSelectionState.selected,
          currentMadhhab: Madhhab.shafii,
        );
        expect(
          byStartDate.madhhab,
          Madhhab.hanafi,
          reason: 'she was Hanafi when this episode began -- the whole '
              'episode is classified under Hanafi end to end',
        );
      },
    );

    test('multiple rapid switches within the same week resolve correctly '
        'at each point', () {
      final rapid = [
        _entry(
          changedAt: DateTime.utc(2026, 5, 1, 9),
          previousState: MadhhabSelectionState.selected,
          previousMadhhab: Madhhab.hanafi,
          newState: MadhhabSelectionState.selected,
          newMadhhab: Madhhab.maliki,
        ),
        _entry(
          changedAt: DateTime.utc(2026, 5, 1, 15),
          previousState: MadhhabSelectionState.selected,
          previousMadhhab: Madhhab.maliki,
          newState: MadhhabSelectionState.selected,
          newMadhhab: Madhhab.hanbali,
        ),
        _entry(
          changedAt: DateTime.utc(2026, 5, 3),
          previousState: MadhhabSelectionState.selected,
          previousMadhhab: Madhhab.hanbali,
          newState: MadhhabSelectionState.selected,
          newMadhhab: Madhhab.shafii,
        ),
      ];
      // All three same-day changes collapse to the same calendar day
      // (May 1) under day-granularity truncation -- the LAST one that
      // day (Hanbali) governs the whole day, matching "a change is
      // effective for that whole calendar day" from the equal-date test
      // above.
      final onMay1 = MadhhabHistoryResolver.resolveFromEntries(
        entries: rapid,
        date: DateTime.utc(2026, 5, 1),
        currentState: MadhhabSelectionState.selected,
        currentMadhhab: Madhhab.shafii,
      );
      expect(onMay1.madhhab, Madhhab.hanbali);

      final onMay2 = MadhhabHistoryResolver.resolveFromEntries(
        entries: rapid,
        date: DateTime.utc(2026, 5, 2),
        currentState: MadhhabSelectionState.selected,
        currentMadhhab: Madhhab.shafii,
      );
      expect(onMay2.madhhab, Madhhab.hanbali);

      final onMay3 = MadhhabHistoryResolver.resolveFromEntries(
        entries: rapid,
        date: DateTime.utc(2026, 5, 3),
        currentState: MadhhabSelectionState.selected,
        currentMadhhab: Madhhab.shafii,
      );
      expect(onMay3.madhhab, Madhhab.shafii);
    });
  });

  group('Selection-state transitions (Section 5)', () {
    test('unknown -> selected: a date after the change resolves to the '
        'newly-selected Madhhab', () {
      final entries = [
        _entry(
          changedAt: DateTime.utc(2026, 6, 1),
          previousState: MadhhabSelectionState.unknown,
          newState: MadhhabSelectionState.selected,
          newMadhhab: Madhhab.maliki,
        ),
      ];
      final result = MadhhabHistoryResolver.resolveFromEntries(
        entries: entries,
        date: DateTime.utc(2026, 6, 5),
        currentState: MadhhabSelectionState.selected,
        currentMadhhab: Madhhab.maliki,
      );
      expect(result.selectionState, MadhhabSelectionState.selected);
      expect(result.madhhab, Madhhab.maliki);
    });

    test('selected -> unknown: a date after the change resolves to '
        'unknown, with a null madhhab even though one is technically still '
        'cached as "previous"', () {
      final entries = [
        _entry(
          changedAt: DateTime.utc(2026, 6, 1),
          previousState: MadhhabSelectionState.selected,
          previousMadhhab: Madhhab.hanafi,
          newState: MadhhabSelectionState.unknown,
        ),
      ];
      final result = MadhhabHistoryResolver.resolveFromEntries(
        entries: entries,
        date: DateTime.utc(2026, 6, 5),
        currentState: MadhhabSelectionState.unknown,
        currentMadhhab: null,
      );
      expect(result.selectionState, MadhhabSelectionState.unknown);
      expect(result.madhhab, isNull);
    });

    test('selected A -> selected B: resolves distinctly on either side', () {
      final entries = [
        _entry(
          changedAt: DateTime.utc(2026, 6, 1),
          previousState: MadhhabSelectionState.selected,
          previousMadhhab: Madhhab.hanafi,
          newState: MadhhabSelectionState.selected,
          newMadhhab: Madhhab.hanbali,
        ),
      ];
      final before = MadhhabHistoryResolver.resolveFromEntries(
        entries: entries,
        date: DateTime.utc(2026, 5, 20),
        currentState: MadhhabSelectionState.selected,
        currentMadhhab: Madhhab.hanbali,
      );
      final after = MadhhabHistoryResolver.resolveFromEntries(
        entries: entries,
        date: DateTime.utc(2026, 6, 10),
        currentState: MadhhabSelectionState.selected,
        currentMadhhab: Madhhab.hanbali,
      );
      expect(before.madhhab, Madhhab.hanafi);
      expect(after.madhhab, Madhhab.hanbali);
    });

    test('selected A -> A (a true no-op): MadhhabController.selectMadhhab\'s '
        'own no-op guard means no history row is ever written for this '
        'case in real use (see madhhab_controller.dart), so the resolver '
        'is never even asked to resolve across a no-op boundary. The '
        'resolver itself needs no special no-op handling either way: even '
        'if two consecutive rows happened to repeat the same value, each '
        'interval still resolves correctly on its own terms.', () {
      final repeatedValue = [
        _entry(
          changedAt: DateTime.utc(2026, 6, 1),
          previousState: MadhhabSelectionState.unknown,
          newState: MadhhabSelectionState.selected,
          newMadhhab: Madhhab.hanafi,
        ),
        _entry(
          changedAt: DateTime.utc(2026, 6, 10),
          previousState: MadhhabSelectionState.selected,
          previousMadhhab: Madhhab.hanafi,
          newState: MadhhabSelectionState.selected,
          newMadhhab: Madhhab.hanafi,
        ),
      ];
      final result = MadhhabHistoryResolver.resolveFromEntries(
        entries: repeatedValue,
        date: DateTime.utc(2026, 6, 15),
        currentState: MadhhabSelectionState.selected,
        currentMadhhab: Madhhab.hanafi,
      );
      expect(result.madhhab, Madhhab.hanafi);
      expect(result.effectiveFrom, DateTime.utc(2026, 6, 10));
    });
  });

  group('No-history / unknown-interval fallback (Section 8)', () {
    test('zero history rows: falls back to the current server state for '
        'any date, with resolution == noHistoryFallback', () {
      final result = MadhhabHistoryResolver.resolveFromEntries(
        entries: const [],
        date: DateTime.utc(2020, 1, 1),
        currentState: MadhhabSelectionState.selected,
        currentMadhhab: Madhhab.hanafi,
      );
      expect(result.selectionState, MadhhabSelectionState.selected);
      expect(result.madhhab, Madhhab.hanafi);
      expect(result.resolution, MadhhabResolutionBasis.noHistoryFallback);
      expect(result.effectiveFrom, isNull);
      expect(result.effectiveTo, isNull);
    });

    test('zero history rows, current state unknown: falls back to '
        'unknown, never a guessed madhhab', () {
      final result = MadhhabHistoryResolver.resolveFromEntries(
        entries: const [],
        date: DateTime.utc(2020, 1, 1),
        currentState: MadhhabSelectionState.unknown,
        currentMadhhab: null,
      );
      expect(result.selectionState, MadhhabSelectionState.unknown);
      expect(result.madhhab, isNull);
    });

    test('a date before the earliest row, where that row\'s own previous '
        'state was already "selected" (she chose a Madhhab before this '
        'table ever existed): resolves to that previously-selected '
        'Madhhab, never unset, and never fabricates a start date for it', () {
      final entries = [
        _entry(
          changedAt: DateTime.utc(2026, 3, 1),
          previousState: MadhhabSelectionState.selected,
          previousMadhhab: Madhhab.hanafi,
          newState: MadhhabSelectionState.selected,
          newMadhhab: Madhhab.shafii,
        ),
      ];
      final result = MadhhabHistoryResolver.resolveFromEntries(
        entries: entries,
        date: DateTime.utc(2026, 1, 1),
        currentState: MadhhabSelectionState.selected,
        currentMadhhab: Madhhab.shafii,
      );
      expect(result.selectionState, MadhhabSelectionState.selected);
      expect(result.madhhab, Madhhab.hanafi);
      expect(
        result.resolution,
        MadhhabResolutionBasis.earliestRecordPreviousState,
      );
      expect(
        result.effectiveFrom,
        isNull,
        reason: 'genuinely unbounded into the past -- no fabricated date',
      );
      expect(result.effectiveTo, DateTime.utc(2026, 3, 1));
    });
  });

  group('Ruleset version resolution (Section 6)', () {
    test('each interval resolves to its OWN recorded ruleset_version, not '
        'whatever the current code constant happens to be', () {
      final entries = [
        _entry(
          changedAt: DateTime.utc(2026, 1, 1),
          previousState: MadhhabSelectionState.unknown,
          newState: MadhhabSelectionState.selected,
          newMadhhab: Madhhab.hanafi,
          rulesetVersion: 'v1-2026-09-09',
        ),
        _entry(
          changedAt: DateTime.utc(2026, 7, 1),
          previousState: MadhhabSelectionState.selected,
          previousMadhhab: Madhhab.hanafi,
          newState: MadhhabSelectionState.selected,
          newMadhhab: Madhhab.hanafi,
          rulesetVersion: 'v2-2026-12-01-hypothetical',
        ),
      ];
      final beforeRulesetChange = MadhhabHistoryResolver.resolveFromEntries(
        entries: entries,
        date: DateTime.utc(2026, 3, 1),
        currentState: MadhhabSelectionState.selected,
        currentMadhhab: Madhhab.hanafi,
        currentRulesetVersion: 'v2-2026-12-01-hypothetical',
      );
      final afterRulesetChange = MadhhabHistoryResolver.resolveFromEntries(
        entries: entries,
        date: DateTime.utc(2026, 8, 1),
        currentState: MadhhabSelectionState.selected,
        currentMadhhab: Madhhab.hanafi,
        currentRulesetVersion: 'v2-2026-12-01-hypothetical',
      );
      expect(beforeRulesetChange.rulesetVersion, 'v1-2026-09-09');
      expect(afterRulesetChange.rulesetVersion, 'v2-2026-12-01-hypothetical');
    });

    test('a date before the earliest row uses that row\'s own recorded '
        'previousRulesetVersion when present (migration 20261014220000), '
        'never the current global constant, once that field is known', () {
      final entries = [
        _entry(
          changedAt: DateTime.utc(2026, 7, 1),
          previousState: MadhhabSelectionState.selected,
          previousMadhhab: Madhhab.hanafi,
          newState: MadhhabSelectionState.selected,
          newMadhhab: Madhhab.hanafi,
          rulesetVersion: 'v2-2026-12-01-hypothetical',
          previousRulesetVersion: 'v1-2026-09-09',
        ),
      ];
      final result = MadhhabHistoryResolver.resolveFromEntries(
        entries: entries,
        date: DateTime.utc(2026, 3, 1),
        currentState: MadhhabSelectionState.selected,
        currentMadhhab: Madhhab.hanafi,
        currentRulesetVersion: 'v2-2026-12-01-hypothetical',
      );
      expect(
        result.rulesetVersion,
        'v1-2026-09-09',
        reason: 'the real recorded previous ruleset, not the current '
            'global constant (which this test deliberately sets to a '
            'DIFFERENT value to prove it is not what\'s being read)',
      );
    });

    test(
      'RELEASE GATE: a second Fiqh ruleset version must not be released '
      'until historical intervals can deterministically resolve the '
      'applicable ruleset version -- proven here by a realistic '
      'multi-transition chain spanning a hypothetical v1 -> v2 switch, '
      'where EVERY interval resolves its true recorded ruleset version '
      'with zero reliance on the currentRulesetVersion fallback '
      'parameter (which is deliberately set to a THIRD, wrong value '
      'below -- if any interval leaked through to it, this test would '
      'catch it)',
      () {
        final entries = [
          _entry(
            changedAt: DateTime.utc(2026, 1, 1),
            previousState: MadhhabSelectionState.unknown,
            newState: MadhhabSelectionState.selected,
            newMadhhab: Madhhab.hanafi,
            rulesetVersion: 'v1',
            // Her first-ever transition: genuinely no prior ruleset to
            // record -- left null, honestly, never fabricated.
          ),
          _entry(
            changedAt: DateTime.utc(2026, 2, 15),
            previousState: MadhhabSelectionState.selected,
            previousMadhhab: Madhhab.hanafi,
            newState: MadhhabSelectionState.selected,
            newMadhhab: Madhhab.shafii,
            rulesetVersion: 'v1',
            previousRulesetVersion: 'v1',
          ),
          _entry(
            // The hypothetical ruleset switch happens to land on a day
            // she also changed Madhhab -- the harder case.
            changedAt: DateTime.utc(2026, 7, 1),
            previousState: MadhhabSelectionState.selected,
            previousMadhhab: Madhhab.shafii,
            newState: MadhhabSelectionState.selected,
            newMadhhab: Madhhab.hanbali,
            rulesetVersion: 'v2',
            previousRulesetVersion: 'v1',
          ),
          _entry(
            changedAt: DateTime.utc(2026, 9, 1),
            previousState: MadhhabSelectionState.selected,
            previousMadhhab: Madhhab.hanbali,
            newState: MadhhabSelectionState.selected,
            newMadhhab: Madhhab.maliki,
            rulesetVersion: 'v2',
            previousRulesetVersion: 'v2',
          ),
        ];
        const wrongFallback = 'THIS-VALUE-MUST-NEVER-LEAK-THROUGH';

        ResolvedMadhhab at(DateTime date) =>
            MadhhabHistoryResolver.resolveFromEntries(
              entries: entries,
              date: date,
              currentState: MadhhabSelectionState.selected,
              currentMadhhab: Madhhab.maliki,
              currentRulesetVersion: wrongFallback,
            );

        // The ONE legitimate exception: before her true first-ever
        // transition, there is genuinely no prior ruleset recorded
        // anywhere to resolve -- this is the disclosed fallback case the
        // gate does not cover, and it correctly falls through to the
        // current constant (proving the fallback parameter IS reachable
        // when truly nothing better exists, rather than being silently
        // unused dead code).
        expect(
          at(DateTime.utc(2025, 12, 1)).rulesetVersion,
          wrongFallback,
        );
        // Every real interval from here on, including the earliest-row
        // fallback for a date between the table's start and the first
        // row with a recorded previousRulesetVersion, resolves its own
        // true version -- zero further reliance on the fallback.
        expect(at(DateTime.utc(2026, 1, 10)).rulesetVersion, 'v1');
        expect(at(DateTime.utc(2026, 3, 1)).rulesetVersion, 'v1');
        expect(at(DateTime.utc(2026, 7, 15)).rulesetVersion, 'v2');
        expect(at(DateTime.utc(2026, 10, 1)).rulesetVersion, 'v2');
      },
    );
  });

  group('Determinism / "restart preserves the same historical '
      'interpretation" (Section 11)', () {
    final entries = [
      _entry(
        changedAt: DateTime.utc(2026, 2, 15),
        previousState: MadhhabSelectionState.selected,
        previousMadhhab: Madhhab.hanafi,
        newState: MadhhabSelectionState.selected,
        newMadhhab: Madhhab.shafii,
      ),
    ];

    test('resolving the same date twice always returns the same result -- '
        'the pure function has no cache/mutable state to go stale across '
        'an app restart', () {
      final first = MadhhabHistoryResolver.resolveFromEntries(
        entries: entries,
        date: DateTime.utc(2026, 2, 10),
        currentState: MadhhabSelectionState.selected,
        currentMadhhab: Madhhab.shafii,
      );
      final second = MadhhabHistoryResolver.resolveFromEntries(
        entries: entries,
        date: DateTime.utc(2026, 2, 10),
        currentState: MadhhabSelectionState.selected,
        currentMadhhab: Madhhab.shafii,
      );
      expect(first.madhhab, second.madhhab);
      expect(first.effectiveFrom, second.effectiveFrom);
      expect(first.effectiveTo, second.effectiveTo);
      expect(first.resolution, second.resolution);
    });

    test('the result never depends on MadhhabController.instance\'s '
        'current in-memory state -- only on the entries/currentState/'
        'currentMadhhab explicitly passed in', () async {
      // Deliberately set the live singleton to something that CONTRADICTS
      // what's passed to resolveFromEntries below -- if the resolver ever
      // started reading MadhhabController.instance internally, this test
      // would catch it.
      MadhhabController.instance.resetInMemory();

      final result = MadhhabHistoryResolver.resolveFromEntries(
        entries: entries,
        date: DateTime.utc(2026, 2, 10),
        currentState: MadhhabSelectionState.selected,
        currentMadhhab: Madhhab.shafii,
      );
      expect(result.madhhab, Madhhab.hanafi);
      expect(
        MadhhabController.instance.state,
        MadhhabSelectionState.unset,
        reason: 'confirms the controller itself was in a totally '
            'different state than what the resolver was given -- and the '
            'resolver still answered correctly from its own parameters',
      );
    });
  });

  group('Raw-data integrity (Section 10)', () {
    test('MadhhabController imports no cycle-tracking/bleeding-episode '
        'repository at all -- selectMadhhab/selectUnknown are structurally '
        'incapable of touching cycle_entries, bleeding_episodes, or '
        'bleeding_observations, not merely "don\'t currently call" them. '
        'Guards against a future edit silently wiring one in.', () {
      final source = File(
        'lib/core/preferences/madhhab_controller.dart',
      ).readAsStringSync();
      for (final forbidden in [
        'cycle_tracking_repository',
        'bleeding_episode_repository',
        'CycleTrackingRepository',
        'BleedingEpisodeRepositoryImpl',
      ]) {
        expect(
          source.contains(forbidden),
          isFalse,
          reason:
              '$forbidden must never be imported/referenced by '
              'MadhhabController -- a Madhhab selection change must only '
              'ever write users.madhhab/madhhab_selection_state and an '
              'audit row to madhhab_history, never raw observation data',
        );
      }
    });

    test('MadhhabHistoryResolver itself is also read-only -- it imports no '
        'write-capable repository and its resolution logic never mutates '
        'any input it is given', () {
      final source = File(
        'lib/core/preferences/madhhab_history_resolver.dart',
      ).readAsStringSync();
      for (final forbidden in [
        'cycle_tracking_repository',
        'bleeding_episode_repository',
        '.insert(',
        '.update(',
        '.delete(',
      ]) {
        expect(
          source.contains(forbidden),
          isFalse,
          reason:
              '$forbidden must never appear in the resolver -- resolving '
              '"what Madhhab applied on this date" must never write '
              'anything, to any table',
        );
      }
    });
  });
}
