// Round-2 property tests: seeded, deterministic SYNTHETIC menstrual
// histories (no real user data) and the adapters that feed one history to
// every engine exactly the way the app does:
//
//   * canonical `bleeding_episodes` + effective `bleeding_observations`
//     (what CanonicalFiqhEvidenceAdapter / CanonicalBleedingStatusResolver /
//     ReportCanonicalEvidence read);
//   * the flat `cycle_entries` projection of those observations (what
//     CycleTrackingViewModel.logs holds) — built with the projection's own
//     `computeCycleDayForNewEntry`, uncertain days never projected;
//   * `CanonicalEpisodeTiming` dates (start/end only).
//
// A history is a list of episodes laid out in calendar days from an
// [anchor] (local midnight). Evidence "as of" a day T is every fact dated
// on or before T, so one history can be evaluated at many "today" values.
import 'dart:math';

import 'package:niswah/core/utils/calendar_days.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/load_result.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';

/// One bleeding episode of a synthetic history.
class SynthEpisode {
  const SynthEpisode({
    required this.start,
    required this.flows,
    this.ended = true,
    this.skipped = const {},
    this.onboarding = false,
    this.startHour,
  });

  /// Day offset from [SynthHistory.anchor].
  final int start;

  /// Flow on each bleeding day, index 0 = start day. Length = bleeding days.
  /// The closing `none` observation (if [ended]) lands on day
  /// `start + flows.length` — the canonical `end_date`.
  final List<ObservationFlow> flows;

  /// Whether a closing `none` / end date is ever recorded.
  final bool ended;

  /// Indices (never 0) of days with no observation at all (missed check-in).
  final Set<int> skipped;

  /// Recorded in onboarding: only an `uncertain` start observation (and the
  /// closing `none`), like `record_onboarding_menstrual_history`.
  final bool onboarding;

  /// Exact local start hour on day 0; null = date-only.
  final int? startHour;

  int get endOffset => start + flows.length;

  SynthEpisode copyWith({
    int? start,
    List<ObservationFlow>? flows,
    bool? ended,
    Set<int>? skipped,
    bool? onboarding,
    int? Function()? startHour,
  }) => SynthEpisode(
    start: start ?? this.start,
    flows: flows ?? this.flows,
    ended: ended ?? this.ended,
    skipped: skipped ?? this.skipped,
    onboarding: onboarding ?? this.onboarding,
    startHour: startHour == null ? this.startHour : startHour(),
  );
}

class SynthHistory {
  const SynthHistory({
    required this.kind,
    required this.seed,
    required this.anchor,
    required this.episodes,
    this.statedCycle,
    this.statedPeriod,
  });

  final String kind;
  final int seed;
  final DateTime anchor;
  final List<SynthEpisode> episodes;
  final int? statedCycle;
  final int? statedPeriod;

  DateTime day(int offset) => addCalendarDays(anchor, offset);

  int get lastStart => episodes.isEmpty ? 0 : episodes.last.start;

  SynthHistory copyWith({
    List<SynthEpisode>? episodes,
    int? Function()? statedCycle,
    int? Function()? statedPeriod,
    DateTime? anchor,
  }) => SynthHistory(
    kind: kind,
    seed: seed,
    anchor: anchor ?? this.anchor,
    episodes: episodes ?? this.episodes,
    statedCycle: statedCycle == null ? this.statedCycle : statedCycle(),
    statedPeriod: statedPeriod == null ? this.statedPeriod : statedPeriod(),
  );

  CycleBaseline? get baseline => statedCycle == null && statedPeriod == null
      ? null
      : CycleBaseline(
          userId: 'u',
          usualCycleLengthDays: statedCycle,
          usualBleedingDurationDays: statedPeriod,
        );

  String describe() {
    String f(ObservationFlow flow) => switch (flow) {
      ObservationFlow.uncertain => '?',
      ObservationFlow.none => '0',
      ObservationFlow.spotting => 's',
      ObservationFlow.light => 'l',
      ObservationFlow.medium => 'm',
      ObservationFlow.heavy => 'h',
    };
    final b = StringBuffer(
      'kind=$kind seed=$seed anchor=${ymd(anchor)} '
      'stated(cycle=$statedCycle, period=$statedPeriod)\n',
    );
    for (final e in episodes) {
      final flows = [
        for (var i = 0; i < e.flows.length; i++)
          e.skipped.contains(i) ? '_' : f(e.flows[i]),
      ].join();
      b.writeln(
        '  ${e.onboarding ? 'onboarding ' : ''}start=${ymd(day(e.start))}'
        '${e.startHour == null ? '' : ' at ${e.startHour}h'} '
        'flows=[$flows] '
        '${e.ended ? 'end=${ymd(day(e.endOffset))}' : 'open'}',
      );
    }
    return b.toString();
  }
}

String ymd(DateTime? d) => d == null
    ? 'null'
    : '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';

String ymdhm(DateTime d) =>
    '${ymd(d)}T${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}:'
    '${d.second.toString().padLeft(2, '0')}';

/// Canonical evidence for [h] as of the end of day [t] (offset).
class Evidence {
  Evidence({
    required this.episodes,
    required this.observations,
    required this.flatLogs,
    required this.timing,
  });

  final List<BleedingEpisode> episodes;
  final List<BleedingObservation> observations;

  /// `cycle_entries` as `CycleEntriesProjection` would hold them.
  final List<CycleLog> flatLogs;
  final List<CanonicalEpisodeTiming> timing;
}

Evidence evidenceAsOf(SynthHistory h, int t, {bool reverseIds = false}) {
  final episodes = <BleedingEpisode>[];
  final observations = <BleedingObservation>[];
  var seq = 0;
  for (var k = 0; k < h.episodes.length; k++) {
    final e = h.episodes[k];
    if (e.start > t) continue;
    final id = 'e$k';
    final isEnded = e.ended && e.endOffset <= t;
    final startPrecision = e.startHour == null || e.onboarding
        ? ObservationPrecision.dateOnly
        : ObservationPrecision.exactTime;
    final startSource = e.onboarding
        ? ObservationSource.userReportedHistorical
        : ObservationSource.userObserved;
    episodes.add(
      BleedingEpisode(
        id: id,
        userId: 'u',
        lifecycleStatus: isEnded ? LifecycleStatus.ended : LifecycleStatus.open,
        continuationCertainty: isEnded ? null : ContinuationCertainty.confirmed,
        startDate: h.day(e.start),
        startPrecision: startPrecision,
        startSource: startSource,
        endDate: isEnded ? h.day(e.endOffset) : null,
        endPrecision: isEnded ? ObservationPrecision.dateOnly : null,
        endSource: isEnded ? startSource : null,
      ),
    );
    BleedingObservation obs(int offset, ObservationFlow flow, {int? hour}) {
      final date = h.day(offset);
      return BleedingObservation(
        id: 'o${seq++}',
        userId: 'u',
        episodeId: id,
        observedDate: date,
        observedTime: hour == null
            ? null
            : DateTime(date.year, date.month, date.day, hour),
        precision: hour == null
            ? ObservationPrecision.dateOnly
            : ObservationPrecision.exactTime,
        flow: flow,
        source: startSource,
        reportedAt: DateTime(date.year, date.month, date.day, 20),
        utcOffsetMinutes: 0,
      );
    }

    if (e.onboarding) {
      observations.add(obs(e.start, ObservationFlow.uncertain));
    } else {
      for (var i = 0; i < e.flows.length; i++) {
        if (e.start + i > t) break;
        if (i != 0 && e.skipped.contains(i)) continue;
        observations.add(
          obs(e.start + i, e.flows[i], hour: i == 0 ? e.startHour : null),
        );
      }
    }
    if (isEnded) observations.add(obs(e.endOffset, ObservationFlow.none));
  }
  return Evidence(
    episodes: episodes,
    observations: reverseIds ? observations.reversed.toList() : observations,
    flatLogs: t >= _fullHorizon
        ? projectFlat(observations)
        : [
            for (final log in _fullProjection(h))
              if (!log.date.isAfter(h.day(t))) log,
          ],
    timing: [
      for (final e in episodes)
        CanonicalEpisodeTiming(startDate: e.startDate, endDate: e.endDate),
    ],
  );
}

const int _fullHorizon = 1 << 20;
final Expando<List<CycleLog>> _projectionCache = Expando();

/// The projection is incremental (each row depends only on rows already
/// projected, in date order), so the projection as of day t is exactly the
/// full projection's prefix — computed once per history.
List<CycleLog> _fullProjection(SynthHistory h) =>
    _projectionCache[h] ??= evidenceAsOf(h, _fullHorizon).flatLogs;

/// The `cycle_entries` projection: each non-uncertain effective observation
/// in the order it was recorded (chronological here), its `cycleDay` from
/// `computeCycleDayForNewEntry` over the rows already projected. One row
/// per day (a later same-day report replaces the row).
List<CycleLog> projectFlat(List<BleedingObservation> observations) {
  const service = CycleCalculationService();
  final sorted = [...observations]
    ..sort((a, b) => a.observedDate.compareTo(b.observedDate));
  final byDay = <DateTime, CycleLog>{};
  for (final o in sorted) {
    final flow = switch (o.flow) {
      ObservationFlow.uncertain => null,
      ObservationFlow.none => FlowLevel.none,
      ObservationFlow.spotting => FlowLevel.spotting,
      ObservationFlow.light => FlowLevel.light,
      ObservationFlow.medium => FlowLevel.medium,
      ObservationFlow.heavy => FlowLevel.heavy,
    };
    if (flow == null) continue;
    final day = calendarDay(o.observedDate);
    final existing = byDay.values.where((l) => l.date != day).toList();
    byDay[day] = CycleLog(
      id: 'c-${o.id}',
      userId: 'u',
      date: day,
      flow: flow,
      cycleDay: service.computeCycleDayForNewEntry(
        existingLogs: existing,
        date: day,
        flow: flow,
      ),
    );
  }
  return byDay.values.toList()..sort((a, b) => a.date.compareTo(b.date));
}

/// Legacy "only day 1 is ever logged" flat history (manual Log-Haidh users).
List<CycleLog> day1OnlyLogs(SynthHistory h, int t) => [
  for (final e in h.episodes)
    if (e.start <= t)
      CycleLog(
        id: 'd1-${e.start}',
        userId: 'u',
        date: h.day(e.start),
        flow: FlowLevel.medium,
        cycleDay: 1,
      ),
];

// ---------------------------------------------------------------------------
// Generators
// ---------------------------------------------------------------------------

/// Days around which evaluation is most likely to break: DST changes in
/// the five test zones, year boundaries, a leap day.
final interestingDates = <DateTime>[
  DateTime(2025, 3, 9), DateTime(2025, 11, 2), // US
  DateTime(2026, 3, 8), DateTime(2026, 11, 1),
  DateTime(2025, 3, 30), DateTime(2025, 10, 26), // EU
  DateTime(2026, 3, 29), DateTime(2026, 10, 25),
  DateTime(2025, 4, 6), DateTime(2025, 9, 28), // NZ
  DateTime(2026, 4, 5), DateTime(2026, 9, 27),
  DateTime(2025, 1, 1), DateTime(2026, 1, 1), DateTime(2027, 1, 1),
  DateTime(2028, 2, 29),
];

const generatorKinds = <String>[
  'regular',
  'irregular',
  'missedLogs',
  'spottingUncertain',
  'shortLong',
  'yearBoundary',
  'dst',
  'onboardingOnly',
  'mixedOnboarding',
  'exactTime',
  'longBleed',
  'shortRuns',
  'closeRuns',
];

double _gauss(Random r) {
  // Box-Muller.
  final u1 = 1 - r.nextDouble();
  final u2 = r.nextDouble();
  return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
}

List<ObservationFlow> _flows(Random r, int n, {bool spotty = false}) => [
  for (var i = 0; i < n; i++)
    spotty && (i == 0 || i == n - 1 || r.nextInt(4) == 0)
        ? ObservationFlow.spotting
        : spotty && r.nextInt(5) == 0
        ? ObservationFlow.uncertain
        : const [
            ObservationFlow.light,
            ObservationFlow.medium,
            ObservationFlow.heavy,
          ][r.nextInt(3)],
];

SynthHistory generateHistory(int seed, {String? forcedKind}) {
  final r = Random(seed);
  final kind = forcedKind ?? generatorKinds[r.nextInt(generatorKinds.length)];
  final cycles = 1 + r.nextInt(9);

  int base;
  double sd;
  switch (kind) {
    case 'irregular':
      base = 22 + r.nextInt(18);
      sd = 2 + r.nextDouble() * 8;
    case 'shortLong':
      base = r.nextBool() ? 15 + r.nextInt(6) : 45 + r.nextInt(46);
      sd = r.nextDouble() * 2;
    default:
      base = 24 + r.nextInt(12);
      sd = 0.7;
  }

  final episodes = <SynthEpisode>[];
  var start = 0;
  for (var c = 0; c <= cycles; c++) {
    final bleed = switch (kind) {
      'longBleed' => 9 + r.nextInt(10),
      'shortRuns' => 1 + r.nextInt(3),
      _ => 3 + r.nextInt(6),
    };
    final spotty = kind == 'spottingUncertain';
    var flows = _flows(r, bleed, spotty: spotty);
    final skipped = <int>{
      if (kind == 'missedLogs' || spotty)
        for (var i = 1; i < bleed - 1; i++)
          if (r.nextInt(4) == 0) i,
    };
    final onboarding =
        kind == 'onboardingOnly' ||
        (kind == 'mixedOnboarding' && c < 1 + r.nextInt(3));
    final startHour = kind == 'exactTime' && r.nextBool()
        ? const [3, 7, 18, 21][r.nextInt(4)]
        : null;
    if (spotty && r.nextInt(3) == 0) {
      flows = [ObservationFlow.uncertain, ...flows.skip(1)];
    }
    episodes.add(
      SynthEpisode(
        start: start,
        flows: flows,
        skipped: skipped,
        onboarding: onboarding,
        startHour: startHour,
      ),
    );
    if (kind == 'closeRuns' && r.nextInt(2) == 0) {
      // A second run 2-16 days after this one stopped (purity question).
      final gap = 2 + r.nextInt(15);
      final runStart = start + bleed + gap;
      final runLen = 1 + r.nextInt(6);
      episodes.add(SynthEpisode(start: runStart, flows: _flows(r, runLen)));
      start = runStart + runLen + 1;
    }
    var len = (base + sd * _gauss(r)).round().clamp(15, 90);
    final minLen = episodes.last.endOffset - start + 2;
    if (len < minLen) len = minLen;
    start += len;
  }

  // Missed logs: drop one or two whole middle episodes from every source.
  if (kind == 'missedLogs' && episodes.length > 3) {
    episodes.removeAt(1 + r.nextInt(episodes.length - 2));
  }

  // The last episode: sometimes still open (ongoing), sometimes ended.
  if (r.nextInt(3) == 0) {
    episodes[episodes.length - 1] = episodes.last.copyWith(ended: false);
  }

  // Place the history so its final cycle runs across an interesting date.
  final DateTime target;
  if (kind == 'dst' || kind == 'yearBoundary' || r.nextInt(3) > 0) {
    final pool = kind == 'yearBoundary'
        ? interestingDates.where((d) => d.month == 1 && d.day == 1).toList()
        : interestingDates;
    target = pool[r.nextInt(pool.length)];
  } else {
    target = DateTime(
      2024 + r.nextInt(5),
      1 + r.nextInt(12),
      1 + r.nextInt(28),
    );
  }
  final lastStart = episodes.last.start;
  final anchor = addCalendarDays(target, -lastStart - r.nextInt(40) + 10);

  int? statedCycle;
  int? statedPeriod;
  if (r.nextBool()) {
    statedCycle = r.nextInt(8) == 0 ? 10 + r.nextInt(100) : base;
    statedPeriod = r.nextInt(8) == 0 ? r.nextInt(20) : 5;
  }

  return SynthHistory(
    kind: kind,
    seed: seed,
    anchor: anchor,
    episodes: episodes,
    statedCycle: statedCycle,
    statedPeriod: statedPeriod,
  );
}

/// "Today" values to evaluate at: one per day across the last cycle and
/// into lateness, plus a handful earlier in the history.
List<int> evaluationDays(SynthHistory h, Random r) {
  final last = h.lastStart;
  return {
    for (var k = 0; k <= 70; k += 1 + r.nextInt(3)) last + k,
    for (var i = 0; i < 4; i++) r.nextInt(last + 1),
  }.toList()..sort();
}

/// Local times on day [d] — including just after and just before midnight.
List<DateTime> timesOn(DateTime d) => [
  DateTime(d.year, d.month, d.day, 0, 0, 1),
  DateTime(d.year, d.month, d.day, 12),
  DateTime(d.year, d.month, d.day, 23, 59, 59, 999),
];

const madhhabs = <Madhhab?>[
  null,
  Madhhab.hanafi,
  Madhhab.maliki,
  Madhhab.shafii,
  Madhhab.hanbali,
];

// ---------------------------------------------------------------------------
// Shrinking
// ---------------------------------------------------------------------------

Iterable<SynthHistory> shrinkCandidates(SynthHistory h) sync* {
  final eps = h.episodes;
  // Drop whole episodes (front first — keeps the "current" one).
  for (var i = 0; i < eps.length; i++) {
    if (eps.length == 1) break;
    yield h.copyWith(episodes: [...eps]..removeAt(i));
  }
  if (h.statedCycle != null || h.statedPeriod != null) {
    yield h.copyWith(statedCycle: () => null, statedPeriod: () => null);
  }
  for (var i = 0; i < eps.length; i++) {
    final e = eps[i];
    SynthHistory withEp(SynthEpisode n) =>
        h.copyWith(episodes: [...eps]..[i] = n);
    if (e.skipped.isNotEmpty) yield withEp(e.copyWith(skipped: {}));
    if (e.startHour != null) yield withEp(e.copyWith(startHour: () => null));
    if (e.flows.length > 1) {
      yield withEp(e.copyWith(flows: e.flows.sublist(0, e.flows.length - 1)));
    }
    if (e.flows.any((f) => f != ObservationFlow.medium) && !e.onboarding) {
      final simplified = [
        for (final f in e.flows)
          f == ObservationFlow.uncertain ? f : ObservationFlow.medium,
      ];
      if (simplified.toString() != e.flows.toString()) {
        yield withEp(e.copyWith(flows: simplified));
      }
    }
  }
}

/// Greedy shrink: keeps applying the first candidate that still fails.
SynthHistory shrink(SynthHistory h, bool Function(SynthHistory) fails) {
  var current = h;
  var progress = true;
  var steps = 0;
  while (progress && steps < 150) {
    progress = false;
    for (final candidate in shrinkCandidates(current)) {
      steps++;
      bool failed;
      try {
        failed = fails(candidate);
      } catch (_) {
        failed = false;
      }
      if (failed) {
        current = candidate;
        progress = true;
        break;
      }
    }
  }
  return current;
}

// ---------------------------------------------------------------------------
// Fakes for the async surfaces (report / AI advisor) — no network.
// ---------------------------------------------------------------------------

class FakeEpisodeRepo extends BleedingEpisodeRepositoryImpl {
  FakeEpisodeRepo(this.episodes, this.observations) : super(client: null);
  final List<BleedingEpisode> episodes;
  final List<BleedingObservation> observations;
  @override
  Future<LoadResult<List<BleedingEpisode>>> getEpisodesForUser(
    String u,
  ) async => LoadSuccess(episodes);
  @override
  Future<LoadResult<List<BleedingObservation>>> getAllObservationsForUser(
    String u,
  ) async => LoadSuccess(observations);
}

class FakeBaselineRepo extends CycleBaselineRepositoryImpl {
  FakeBaselineRepo(this.baseline) : super(client: null);
  final CycleBaseline? baseline;
  @override
  Future<CycleBaseline?> getBaseline(String userId) async => baseline;
}

/// Collects violations; the test fails at the end with the first few,
/// each shrunk to a minimal history.
class ViolationLog {
  ViolationLog(this.invariant);
  final String invariant;
  final List<String> messages = [];
  int cases = 0;

  void add(String message) {
    messages.add(message);
    // ignore: avoid_print
    print('VIOLATION [$invariant] $message');
  }

  String summary() =>
      '$invariant: ${messages.length} violation(s) in $cases cases';
}
