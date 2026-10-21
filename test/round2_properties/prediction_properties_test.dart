// Round-2 property tests — prediction (CycleCalculationService,
// CycleTrackingController.summarizeHistory) over seeded synthetic
// histories. Invariants come from docs/cycle-prediction-model.md.
//
// Run under several zones (see run_all_timezones.sh); every check here must
// hold in each.
import 'dart:math';

import 'package:niswah/core/utils/calendar_days.dart';
import 'package:niswah/features/cycle_tracking/domain/controllers/cycle_tracking_controller.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';

import 'support/property_runner.dart';
import 'support/synthetic_history.dart';

const _controller = CycleTrackingController();
const _service = CycleCalculationService();

enum Source { flat, canonical, both }

CycleTrackingSummary summarize(
  SynthHistory h,
  Evidence ev,
  DateTime now, {
  Source source = Source.both,
  bool withBaseline = true,
}) => _controller.summarizeHistory(
  source == Source.canonical ? const [] : ev.flatLogs,
  now: now,
  canonicalEpisodes: source == Source.flat ? const [] : ev.timing,
  statedBaseline: withBaseline ? h.baseline : null,
);

CycleCalculationResult calculate(
  SynthHistory h,
  Evidence ev,
  DateTime now, {
  Source source = Source.both,
  bool withBaseline = true,
}) => _service.calculate(
  source == Source.canonical ? const [] : ev.flatLogs,
  asOf: calendarDay(now),
  canonicalEpisodes: source == Source.flat ? const [] : ev.timing,
  statedBaseline: withBaseline ? h.baseline : null,
);

String describeSummary(CycleTrackingSummary s) =>
    'last=${ymd(s.lastCycleStart)} avg=${s.averageCycleLength} '
    'pred=${s.predictedCycleLength} basis=${s.predictionBasis?.name} '
    'next=${ymd(s.nextPeriodStart)} late=${s.daysLate} '
    'range=${ymd(s.nextPeriodRange?.earliest)}..${ymd(s.nextPeriodRange?.latest)} '
    'fertile=${ymd(s.fertileWindow.start)}..${ymd(s.fertileWindow.end)} '
    'peak=${ymd(s.fertileWindow.peakDay)} avgPeriod=${s.averagePeriodLength}';

/// Runs [check] for every (today, time-of-day) of [h]; first failure wins.
String? forEachNow(
  SynthHistory h,
  String? Function(Evidence ev, DateTime now, DateTime today) check, {
  bool allTimes = true,
}) {
  final r = Random(h.seed * 31 + 7);
  for (final t in evaluationDays(h, r)) {
    final ev = evidenceAsOf(h, t);
    final today = h.day(t);
    for (final now
        in allTimes ? timesOn(today) : [today.add(const Duration(hours: 12))]) {
      evaluationCounter++;
      final message = check(ev, now, today);
      if (message != null) return 'today=${ymdhm(now)}: $message';
    }
  }
  return null;
}

double _median(List<int> values) {
  final sorted = [...values]..sort();
  final m = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[m].toDouble()
      : (sorted[m - 1] + sorted[m]) / 2;
}

bool _onlyCleanFlatEquivalent(SynthHistory h) => h.episodes.every(
  (e) => !e.onboarding && !e.flows.contains(ObservationFlow.uncertain),
);

void main() {
  property(
    'P1 nextPeriodStart is never before today',
    seedBase: 100000,
    check: (h) => forEachNow(h, (ev, now, today) {
      final s = summarize(h, ev, now);
      final next = s.nextPeriodStart;
      if (next != null && next.isBefore(today)) {
        return 'nextPeriodStart ${ymd(next)} < today | ${describeSummary(s)}';
      }
      return null;
    }),
  );

  property(
    'P2 nextPeriodRange: earliest >= today, earliest <= expected <= latest',
    seedBase: 110000,
    check: (h) => forEachNow(h, (ev, now, today) {
      final s = summarize(h, ev, now);
      final range = s.nextPeriodRange;
      if (range == null) return null;
      if (range.earliest.isBefore(today)) {
        return 'earliest < today | ${describeSummary(s)}';
      }
      if (range.latest.isBefore(range.earliest)) {
        return 'latest < earliest | ${describeSummary(s)}';
      }
      final next = s.nextPeriodStart;
      if (s.daysLate == 0 && next != null) {
        if (next.isBefore(range.earliest) || next.isAfter(range.latest)) {
          return 'expected outside range | ${describeSummary(s)}';
        }
      }
      return null;
    }),
  );

  // Doc: "Past the window: no date at all ... nothing further is predicted
  // until she logs" and the range is "gone once she is clearly late".
  property(
    'P2b once clearly late (no next date) no range is offered either',
    seedBase: 120000,
    kindFor: (seed) => seed.isEven ? 'irregular' : null,
    check: (h) => forEachNow(h, (ev, now, today) {
      final s = summarize(h, ev, now);
      if (s.hasPlausibleAverage &&
          s.nextPeriodStart == null &&
          s.nextPeriodRange != null) {
        final calc = calculate(h, ev, now);
        return 'late ${s.daysLate}d, tolerance '
            '${CycleTrackingController.lateToleranceDays(calc.predictionSpreadDays!)}d, '
            'spread ${calc.predictionSpreadDays!.toStringAsFixed(2)} but range '
            'still offered | ${describeSummary(s)}';
      }
      return null;
    }),
  );

  property(
    'P3 fertile window lies inside the cycle and before the next period',
    seedBase: 130000,
    kindFor: (seed) =>
        seed % 3 == 0 ? 'irregular' : (seed % 3 == 1 ? 'shortLong' : null),
    check: (h) => forEachNow(h, (ev, now, today) {
      final s = summarize(h, ev, now);
      final fw = s.fertileWindow;
      if (fw.start == null) return null;
      final cycleStart = s.lastCycleStart!;
      final expected = addCalendarDays(cycleStart, s.predictedCycleLength!);
      if (fw.start!.isBefore(cycleStart)) {
        return 'fertile start ${ymd(fw.start)} before cycle start '
            '${ymd(cycleStart)} | ${describeSummary(s)}';
      }
      if (!fw.end!.isBefore(expected)) {
        return 'fertile end not before next period | ${describeSummary(s)}';
      }
      if (fw.peakDay!.isBefore(fw.start!) || fw.peakDay!.isAfter(fw.end!)) {
        return 'peak outside window | ${describeSummary(s)}';
      }
      return null;
    }, allTimes: false),
  );

  property(
    'P4 no fertile window/ovulation when late, outside 21-60 days, or '
    'from the stated estimate alone',
    seedBase: 140000,
    kindFor: (seed) => seed.isEven ? 'shortLong' : null,
    check: (h) => forEachNow(h, (ev, now, today) {
      final s = summarize(h, ev, now);
      final fw = s.fertileWindow;
      final hasWindow =
          fw.start != null || fw.end != null || fw.peakDay != null;
      if (!hasWindow) {
        if (s.predictionBasis == PredictionBasis.statedEstimate &&
            s.nextPeriodStart != null) {
          return 'estimate-only prediction produced a single date | '
              '${describeSummary(s)}';
        }
        return null;
      }
      if (s.daysLate > 0) {
        return 'fertile window while late | ${describeSummary(s)}';
      }
      final p = s.predictedCycleLength;
      if (p == null || p < 21 || p > 60) {
        return 'fertile window for predicted length $p | ${describeSummary(s)}';
      }
      if (s.predictionBasis == PredictionBasis.statedEstimate) {
        return 'fertile window from estimate alone | ${describeSummary(s)}';
      }
      return null;
    }),
  );

  property(
    'P5 summary depends only on the calendar day (00:00:01 == 23:59:59)',
    seedBase: 150000,
    check: (h) => forEachNow(h, (ev, now, today) {
      if (now.hour != 0) return null;
      final early = summarize(h, ev, now);
      final late = summarize(
        h,
        ev,
        DateTime(today.year, today.month, today.day, 23, 59, 59, 999),
      );
      if (early != late) {
        return 'differs within a day:\n  ${describeSummary(early)}\n  '
            '${describeSummary(late)}';
      }
      return null;
    }),
  );

  property(
    'P6 same episodes via flat logs AND canonical timing == canonical only',
    seedBase: 160000,
    check: (h) => forEachNow(h, (ev, now, today) {
      final both = summarize(h, ev, now);
      final canonical = summarize(h, ev, now, source: Source.canonical);
      if (both != canonical) {
        return 'both != canonical-only\n  both:      ${describeSummary(both)}'
            '\n  canonical: ${describeSummary(canonical)}';
      }
      return null;
    }, allTimes: false),
  );

  property(
    'P6b fully projected episodes: flat only == canonical only == both',
    seedBase: 170000,
    adapt: (h) => h.copyWith(
      episodes: [
        for (final e in h.episodes)
          e.copyWith(
            onboarding: false,
            flows: [
              for (final f in e.flows)
                f == ObservationFlow.uncertain ? ObservationFlow.medium : f,
            ],
          ),
      ],
    ),
    check: (h) {
      assert(_onlyCleanFlatEquivalent(h));
      return forEachNow(h, (ev, now, today) {
        final flat = summarize(h, ev, now, source: Source.flat);
        final both = summarize(h, ev, now);
        final canonical = summarize(h, ev, now, source: Source.canonical);
        if (flat != both || both != canonical) {
          return 'sources disagree\n  flat:      ${describeSummary(flat)}'
              '\n  both:      ${describeSummary(both)}'
              '\n  canonical: ${describeSummary(canonical)}';
        }
        return null;
      }, allTimes: false);
    },
  );

  property(
    'P7 predictedCycleLength within [min,max] of qualifying intervals '
    '(blended with the stated baseline)',
    seedBase: 180000,
    kindFor: (seed) => seed.isEven ? 'irregular' : null,
    check: (h) => forEachNow(h, (ev, now, today) {
      final calc = calculate(h, ev, now);
      final p = calc.predictedCycleLength;
      if (p == null) return null;
      final plausible = calc.cycleLengths
          .where((d) => d >= 15 && d <= 90)
          .toList();
      final stated = CycleCalculationService.statedCycleLength(h.baseline);
      if (plausible.isEmpty) {
        if (p != stated ||
            calc.predictionBasis != PredictionBasis.statedEstimate) {
          return 'no qualifying interval yet pred=$p basis=${calc.predictionBasis}';
        }
        return null;
      }
      // Leave-one-out missed-log rule (docs/cycle-prediction-model.md).
      final valid = [
        for (var i = 0; i < plausible.length; i++)
          if (plausible.length == 1 ||
              plausible[i] < 2 * _median([...plausible]..removeAt(i)))
            plausible[i],
      ];
      final pool = [
        ...valid.reversed.take(6),
        if (calc.predictionBasis == PredictionBasis.historyAndEstimate) stated!,
      ];
      final lo = pool.reduce(min);
      final hi = pool.reduce(max);
      if (p < lo || p > hi) {
        return 'pred=$p outside [$lo,$hi] intervals=${calc.cycleLengths} '
            'stated=$stated basis=${calc.predictionBasis}';
      }
      if (valid.length >= 6 &&
          calc.predictionBasis != PredictionBasis.history) {
        return 'estimate still used with ${valid.length} logged cycles';
      }
      return null;
    }, allTimes: false),
  );

  property(
    'P8 the stated baseline never changes logged statistics',
    seedBase: 190000,
    check: (h) => forEachNow(h, (ev, now, today) {
      final a = calculate(h, ev, now);
      final b = calculate(h, ev, now, withBaseline: false);
      if (a.averageCycleLength != b.averageCycleLength ||
          a.averagePeriodLength != b.averagePeriodLength ||
          a.cycleLengths.toString() != b.cycleLengths.toString() ||
          a.haidStarts.toString() != b.haidStarts.toString()) {
        return 'baseline changed logged facts';
      }
      return null;
    }, allTimes: false),
  );

  property(
    'P9 haidStarts are prefix-stable (later evidence never moves or adds '
    'an earlier start)',
    seedBase: 200000,
    check: (h) {
      final fullDay = h.lastStart + 40;
      final full = calculate(h, evidenceAsOf(h, fullDay), h.day(fullDay));
      for (var t = 0; t <= fullDay; t += 3) {
        evaluationCounter++;
        final prefix = calculate(h, evidenceAsOf(h, t), h.day(t));
        // A start can only be confirmed by later facts; drop the newest
        // start of the prefix if it lies within a day of t (a start the
        // next day's log may legitimately replace, see _mergeCanonical).
        final expected = full.haidStarts
            .where((d) => !d.isAfter(h.day(t)))
            .map(ymd)
            .toList();
        final got = prefix.haidStarts.map(ymd).toList();
        if (expected.toString() != got.toString()) {
          return 'as of ${ymd(h.day(t))}: starts $got, but with later '
              'evidence the same period has $expected';
        }
      }
      return null;
    },
  );

  // "adding an obviously-missed-log interval moves the prediction by at
  // most a small amount" — one whole period is dropped from every source.
  // "Obviously missed" is the documented rule: the merged gap is at least
  // twice the median of the other qualifying intervals. A gap just under
  // that (e.g. 69 days among 35-day cycles, since two real cycles sum to
  // 2x the median +/- noise) is NOT covered by the rule and is not checked
  // here; see docs/cycle-prediction-model.md (open question).
  property(
    'P10 one obviously-missed period moves the predicted length by <= 3 days',
    seedBase: 210000,
    kindFor: (seed) => seed.isEven ? 'regular' : 'irregular',
    check: (h) {
      if (h.episodes.length < 4) return null;
      final t = h.lastStart;
      final now = h.day(t);
      final complete = calculate(
        h,
        evidenceAsOf(h, t),
        now,
        withBaseline: false,
      );
      for (var drop = 1; drop < h.episodes.length - 1; drop++) {
        final missed = h.copyWith(episodes: [...h.episodes]..removeAt(drop));
        final withGap = calculate(
          missed,
          evidenceAsOf(missed, t),
          now,
          withBaseline: false,
        );
        final gap = calendarDaysBetween(
          missed.day(missed.episodes[drop - 1].start),
          missed.day(missed.episodes[drop].start),
        );
        final others = [
          for (final d in complete.cycleLengths)
            if (d >= 15 && d <= 90) d,
        ];
        // The two intervals the gap replaced are not "other" intervals.
        others
          ..remove(
            calendarDaysBetween(
              h.day(h.episodes[drop - 1].start),
              h.day(h.episodes[drop].start),
            ),
          )
          ..remove(
            calendarDaysBetween(
              h.day(h.episodes[drop].start),
              h.day(h.episodes[drop + 1].start),
            ),
          );
        if (others.isEmpty || gap < 2 * _median(others)) continue;
        evaluationCounter++;
        final a = complete.predictedCycleLength;
        final b = withGap.predictedCycleLength;
        if (a == null || b == null) continue;
        // For regular cycles, losing one period barely matters. (For
        // irregular cycles, losing two real intervals legitimately moves the
        // mean by more than 3 days, so only regular histories are bounded.)
        if (h.kind == 'regular' && (a - b).abs() > 3) {
          return 'pred $a -> $b after dropping period #$drop; intervals '
              '${complete.cycleLengths} -> ${withGap.cycleLengths}';
        }
      }
      return null;
    },
  );
}
