// Round-2 property tests — Fiqh (CanonicalFiqhAssessment, CycleStatusEngine,
// MadhhabRuleEvaluator) over seeded synthetic histories, all four madhahib
// plus unset. Only rules the repo documents are checked (madhhab min/max
// haid and min purity values from MadhhabRuleEvaluator / FD-7; the purity
// anchor and date-only bounds from docs/menstrual-data-integrity-contract.md
// §16 items 2, 3 and 5). Talfiq is not modelled by the product (§16
// "Known and not changed") and is not checked.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/utils/calendar_days.dart';
import 'package:niswah/features/ai_advisor/client_fiqh_state_provider.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:niswah/features/cycle_tracking/domain/services/report_canonical_evidence.dart';
import 'package:niswah/features/fiqh_report/domain/services/fiqh_report_insights_engine.dart';

import 'support/fiqh_surfaces.dart';
import 'support/property_runner.dart';
import 'support/synthetic_history.dart';

const _fiqhKinds = [
  'closeRuns',
  'shortRuns',
  'longBleed',
  'exactTime',
  'dst',
  'mixedOnboarding',
  'onboardingOnly',
  'spottingUncertain',
  'regular',
  'irregular',
];

String _kind(int seed) => _fiqhKinds[seed % _fiqhKinds.length];

/// Every 7th history: the last episode is still open and its latest
/// effective observation was corrected to `none` (correct_observation
/// allows `none` on any non-start, non-closing day — §18 #10).
SynthHistory _fiqhAdapt(SynthHistory h) {
  if (h.seed % 7 != 0) return h;
  final last = h.episodes.last;
  if (last.flows.length < 3 || last.onboarding) return h;
  final flows = [...last.flows]..[last.flows.length - 1] = ObservationFlow.none;
  return h.copyWith(
    episodes: [
      ...h.episodes.sublist(0, h.episodes.length - 1),
      last.copyWith(flows: flows, ended: false),
    ],
  );
}

List<int> _fiqhDays(SynthHistory h) {
  final r = Random(h.seed * 17 + 3);
  final last = h.lastStart;
  return {
    for (var k = -18; k <= 22; k += 1 + r.nextInt(2)) last + k,
    r.nextInt(last + 1),
  }.where((t) => t >= 0).toList()..sort();
}

String? _forEachFiqh(
  SynthHistory h,
  String? Function(Evidence ev, CanonicalInputs c, Madhhab? m, DateTime now)
  check, {
  bool noonOnly = false,
}) {
  for (final t in _fiqhDays(h)) {
    final ev = evidenceAsOf(h, t);
    final day = h.day(t);
    for (final now
        in noonOnly ? [day.add(const Duration(hours: 12))] : timesOn(day)) {
      final c = canonicalInputs(ev.episodes, ev.observations, now);
      for (final m in madhhabs) {
        evaluationCounter++;
        final msg = check(ev, c, m, now);
        if (msg != null) {
          return 'now=${ymdhm(now)} madhhab=${m?.name ?? 'unset'}: $msg';
        }
      }
    }
  }
  return null;
}

class _Run {
  _Run(this.first, this.noneDate);
  final CycleLog first;
  final DateTime? noneDate;
}

List<_Run> _runs(List<CycleLog> logs) {
  final sorted = [...logs]..sort((a, b) => a.date.compareTo(b.date));
  final runs = <_Run>[];
  CycleLog? first;
  for (final l in sorted) {
    if (l.flow == FlowLevel.none) {
      if (first != null) runs.add(_Run(first, l.date));
      first = null;
    } else {
      first ??= l;
    }
  }
  if (first != null) runs.add(_Run(first, null));
  return runs;
}

/// Doc-defined most generous length of a completed run: from its start
/// day's midnight (or exact start time) to the day of its closing `none`
/// log — counted in calendar days, never in DST-dependent wall hours.
Duration _generousLength(_Run run) {
  final days = calendarDaysBetween(run.first.date, run.noneDate!);
  final t = run.first.observedTime;
  final offset = t == null
      ? Duration.zero
      : Duration(hours: t.hour, minutes: t.minute, seconds: t.second);
  return Duration(days: days) - offset;
}

void main() {
  property(
    'F1 madhhab unset while bleeding/open episode: never a confident haid '
    'or tahara',
    seedBase: 300000,
    kindFor: _kind,
    adapt: _fiqhAdapt,
    check: (h) => _forEachFiqh(h, (ev, c, m, now) {
      if (m != null) return null;
      final sorted = [...c.logs]..sort((a, b) => a.date.compareTo(b.date));
      final latestBleeding =
          sorted.isNotEmpty && sorted.last.flow != FlowLevel.none;
      if (!latestBleeding && !c.hasOpenEpisode) return null;
      final label = dashboardLabel(c, m, now);
      if (label == 'haid' || label == 'tahara') {
        return 'Today shows "$label" (openEpisode=${c.hasOpenEpisode}, '
            'latestEffectiveBleeding=$latestBleeding)';
      }
      return null;
    }),
  );

  property(
    'F2/F3 a confident haid run is within [min, max] for the madhhab under '
    'both date-only bounds',
    seedBase: 310000,
    kindFor: _kind,
    adapt: _fiqhAdapt,
    check: (h) => _forEachFiqh(h, (ev, c, m, now) {
      if (m == null || dashboardLabel(c, m, now) != 'haid') return null;
      final run = _runs(c.logs).last;
      final first = run.first;
      final earliest = first.observedTime ?? first.date;
      final latest = first.observedTime ?? addCalendarDays(first.date, 1);
      final longest = now.difference(earliest);
      final shortest = now.difference(latest);
      final max = MadhhabRuleEvaluator.maximumHaidFor(m);
      final minimum = MadhhabRuleEvaluator.minimumHaidFor(m);
      if (longest > max) return 'haid but run is $longest > max $max';
      if (minimum != null && shortest < minimum) {
        return 'haid but shortest reading $shortest < min $minimum';
      }
      return null;
    }),
  );

  property(
    'F4 purity below the madhhab minimum after a run that could have been '
    'haid is never a confident new haid',
    seedBase: 320000,
    kindFor: (seed) => seed.isEven ? 'closeRuns' : _kind(seed),
    adapt: _fiqhAdapt,
    check: (h) => _forEachFiqh(h, (ev, c, m, now) {
      if (m == null || dashboardLabel(c, m, now) != 'haid') return null;
      final runs = _runs(c.logs);
      final current = runs.last;
      final minimum = MadhhabRuleEvaluator.minimumHaidFor(m);
      for (final run in runs.reversed.skip(1)) {
        final length = _generousLength(run);
        if (minimum != null && length < minimum) continue;
        final purity = calendarDaysBetween(run.noneDate!, current.first.date);
        final needed = MadhhabRuleEvaluator.minimumPurityFor(m).inDays;
        if (purity < needed) {
          return 'haid after only $purity clean days (< $needed) following a '
              'run of ${length.inHours}h starting ${ymd(run.first.date)} '
              '(calendar-day length; min ${minimum?.inHours}h)';
        }
        break;
      }
      return null;
    }),
  );

  property(
    'F5 dashboard == fiqh report == AI advisor for the same evidence',
    seedBase: 330000,
    kindFor: _kind,
    adapt: _fiqhAdapt,
    check: (h) => _forEachFiqh(h, (ev, c, m, now) {
      final d = dashboardLabel(c, m, now);
      final ai = aiInDashboardVocabulary(aiLabel(c, m, now));
      final report = reportLabel(c, m, now);
      if (d != ai || dashboardInReportVocabulary(d) != report) {
        return 'Today=$d AI=$ai report=$report';
      }
      return null;
    }, noonOnly: true),
    count: 400,
  );

  property(
    'F6 invariant to observation order and duplicate same-day reports',
    seedBase: 340000,
    kindFor: _kind,
    adapt: _fiqhAdapt,
    check: (h) => _forEachFiqh(h, (ev, c, m, now) {
      if (m != Madhhab.shafii && m != null) return null; // keep cost down
      final r = Random(h.seed ^ now.millisecondsSinceEpoch);
      final shuffled = [...ev.observations]..shuffle(r);
      final dup = shuffled.isEmpty
          ? null
          : shuffled[r.nextInt(shuffled.length)];
      final withDup = [
        ...shuffled,
        if (dup != null)
          BleedingObservation(
            id: '${dup.id}-dup',
            userId: dup.userId,
            episodeId: dup.episodeId,
            observedDate: dup.observedDate,
            observedTime: dup.observedTime,
            precision: dup.precision,
            flow: dup.flow,
            source: dup.source,
            reportedAt: dup.reportedAt?.add(const Duration(minutes: 1)),
            utcOffsetMinutes: dup.utcOffsetMinutes,
          ),
      ];
      final base = dashboardLabel(c, m, now);
      final other = dashboardLabel(
        canonicalInputs(ev.episodes.reversed.toList(), withDup, now),
        m,
        now,
      );
      if (base != other) return 'in order: $base, shuffled+duplicate: $other';
      return null;
    }),
  );

  property(
    'F7 monotonic: an extra later clean ("No") day after an ended episode '
    'never changes any ruling',
    seedBase: 350000,
    kindFor: _kind,
    check: (h) {
      for (final t in _fiqhDays(h)) {
        final ev = evidenceAsOf(h, t);
        final now = h.day(t).add(const Duration(hours: 12));
        final extra = <BleedingObservation>[
          ...ev.observations,
          for (final e in ev.episodes)
            if (e.endDate != null &&
                !addCalendarDays(e.endDate!, 1).isAfter(h.day(t)) &&
                !ev.episodes.any(
                  (o) => o.startDate == addCalendarDays(e.endDate!, 1),
                ))
              BleedingObservation(
                id: 'extra-${e.id}',
                userId: 'u',
                episodeId: e.id!,
                observedDate: addCalendarDays(e.endDate!, 1),
                precision: ObservationPrecision.dateOnly,
                flow: ObservationFlow.none,
                source: ObservationSource.userReportedHistorical,
                reportedAt: addCalendarDays(
                  e.endDate!,
                  1,
                ).add(const Duration(hours: 21)),
                utcOffsetMinutes: 0,
              ),
        ];
        final a = canonicalInputs(ev.episodes, ev.observations, now);
        final b = canonicalInputs(ev.episodes, extra, now);
        for (final m in madhhabs) {
          evaluationCounter++;
          final x = dashboardLabel(a, m, now);
          final y = dashboardLabel(b, m, now);
          if (x != y) {
            return 'now=${ymdhm(now)} madhhab=${m?.name}: $x -> $y after an '
                'extra clean day';
          }
        }
      }
      return null;
    },
  );

  // Same history, same local times of day, shifted by whole weeks across
  // DST changes. "now" is at local noon, so a date-only start's wall-clock
  // bounds stay ±1h away from every whole-day threshold and the ruling
  // must not change. Meaningful only under a DST zone (run_all_timezones.sh).
  property(
    'F8 fiqh ruling is invariant to shifting the history across DST',
    seedBase: 360000,
    kindFor: (seed) => seed.isEven ? 'shortRuns' : 'closeRuns',
    check: (h) {
      for (final weeks in const [-26, -13, -4, 4, 13, 26]) {
        final shifted = h.copyWith(
          anchor: addCalendarDays(h.anchor, 7 * weeks),
        );
        final msg = _forEachFiqh(h, (ev, c, m, now) {
          if (m == null) return null;
          final t = calendarDaysBetween(h.anchor, now);
          final sev = evidenceAsOf(shifted, t);
          final sday = shifted.day(t);
          final snow = DateTime(sday.year, sday.month, sday.day, now.hour);
          final sc = canonicalInputs(sev.episodes, sev.observations, snow);
          final a = dashboardLabel(c, m, now);
          final b = dashboardLabel(sc, m, snow);
          if (a != b) {
            return '$a at ${ymdhm(now)} but $b when shifted ${weeks}w to '
                '${ymdhm(snow)}';
          }
          return null;
        }, noonOnly: true);
        if (msg != null) return msg;
      }
      return null;
    },
    count: 80,
  );

  // Exhaustive sweep (deterministic generation): a short completed run
  // placed on every day around each DST/year boundary, followed by a new
  // run after a short clean gap, evaluated at noon. Checks F4 with the
  // doc's calendar-day run length, so a wall-clock (23h/25h day) length
  // shows up under a DST zone.
  test('F9 sweep: purity anchor decided by calendar days around DST', () {
    final failures = <String>[];
    var cases = 0;
    for (final pivot in interestingDates) {
      for (var shift = -4; shift <= 1; shift++) {
        for (var runLen = 1; runLen <= 4; runLen++) {
          for (final gap in const [5, 9, 12]) {
            final firstStart = addCalendarDays(pivot, shift);
            final h = SynthHistory(
              kind: 'dstSweep',
              seed: 0,
              anchor: addCalendarDays(firstStart, -60),
              episodes: [
                SynthEpisode(
                  start: 0,
                  flows: List.filled(5, ObservationFlow.medium),
                ),
                SynthEpisode(
                  start: 30,
                  flows: List.filled(5, ObservationFlow.medium),
                ),
                SynthEpisode(
                  start: 60,
                  flows: List.filled(runLen, ObservationFlow.medium),
                ),
                SynthEpisode(
                  start: 60 + runLen + gap,
                  flows: List.filled(8, ObservationFlow.medium),
                  ended: false,
                ),
              ],
            );
            for (var k = 0; k < 8; k++) {
              final t = 60 + runLen + gap + k;
              final ev = evidenceAsOf(h, t);
              final now = h.day(t).add(const Duration(hours: 12));
              final c = canonicalInputs(ev.episodes, ev.observations, now);
              for (final m in madhhabs.whereType<Madhhab>()) {
                cases++;
                if (dashboardLabel(c, m, now) != 'haid') continue;
                final minimum = MadhhabRuleEvaluator.minimumHaidFor(m);
                final calendarLength = Duration(days: runLen);
                if (minimum != null && calendarLength < minimum) continue;
                failures.add(
                  '${m.name}: run ${ymd(h.day(60))}..${ymd(h.day(60 + runLen))} '
                  '(${runLen}d = min) then bleeding ${ymd(h.day(60 + runLen + gap))} '
                  'after $gap clean days -> confident haid at ${ymdhm(now)}',
                );
              }
            }
          }
        }
      }
    }
    // ignore: avoid_print
    print('PROPERTY [F9 sweep] evaluations=$cases failures=${failures.length}');
    for (final f in failures.take(5)) {
      // ignore: avoid_print
      print('VIOLATION [F9] $f');
    }
    expect(failures, isEmpty);
  });

  // The pure replicas in support/fiqh_surfaces.dart must match the real
  // async loaders, otherwise F5 proves nothing.
  test('F5-sanity replicas == ReportCanonicalEvidence.load / '
      'ClientFiqhStateProvider', () async {
    var cases = 0;
    for (var seed = 370000; seed < 370060; seed++) {
      final h = _fiqhAdapt(generateHistory(seed, forcedKind: _kind(seed)));
      for (final t in _fiqhDays(h).take(12)) {
        final ev = evidenceAsOf(h, t);
        final now = h.day(t).add(const Duration(hours: 12));
        final c = canonicalInputs(ev.episodes, ev.observations, now);
        final repo = FakeEpisodeRepo(ev.episodes, ev.observations);
        final loaded = await ReportCanonicalEvidence.load(
          userId: 'u',
          now: now,
          repository: repo,
          baselineRepository: FakeBaselineRepo(null),
        );
        for (final m in madhhabs) {
          cases++;
          final provider = ClientFiqhStateProvider(
            repository: repo,
            currentUserId: () => 'u',
            clock: () => now,
          );
          expect(
            await provider.currentClassification(m),
            aiLabel(c, m, now),
            reason: 'seed=$seed t=$t m=$m',
          );
          final real = FiqhReportInsightsEngine.analyze(
            cycleLogs: const [],
            madhhab: m,
            now: now,
            canonical: loaded,
          );
          expect(
            real.cycleState,
            reportInsights(c, m, now).cycleState,
            reason: 'seed=$seed t=$t m=$m',
          );
        }
      }
    }
    // ignore: avoid_print
    print('PROPERTY [F5-sanity] evaluations=$cases');
  });
}
