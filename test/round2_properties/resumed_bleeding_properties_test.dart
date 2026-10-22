// Resumed-bleeding property tests (2026-10-22, proposed). Seeded synthetic
// histories only. Bleeding that resumes after a short clean gap is
// uncertain for predictions (CycleCalculationService
// .resumedBleedingPredictionWindowDays): it never moves the prediction anchor
// and no interval it bounds is learned from, while every logged date stays
// a detected start for the fiqh engine. Must hold in every zone (see
// run_all_timezones.sh).
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/utils/calendar_days.dart';
import 'package:niswah/features/cycle_tracking/domain/controllers/cycle_tracking_controller.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/notifications/domain/services/notification_scheduler.dart';

const _service = CycleCalculationService();
const _controller = CycleTrackingController();
var _id = 0;

/// One period: bleeding on [bleedDays] days from [start], then a clean day.
/// [resumeAfter] clean days later bleeding resumes for [resumeDays] days
/// (0 = no resumption), followed by a clean day.
class _Period {
  _Period(
    this.start,
    this.bleedDays, {
    this.resumeAfter = 0,
    this.resumeDays = 0,
  });
  final int start;
  final int bleedDays;
  final int resumeAfter;
  final int resumeDays;

  int get resumeStart => start + bleedDays + resumeAfter;
  int get lastDay =>
      resumeDays == 0 ? start + bleedDays : resumeStart + resumeDays;

  _Period withResumption(int after, int days) =>
      _Period(start, bleedDays, resumeAfter: after, resumeDays: days);
}

class _Case {
  _Case(this.origin, this.periods, this.hour);
  final DateTime origin;
  final List<_Period> periods;
  final int hour;

  DateTime day(int offset) => addCalendarDays(origin, offset);

  List<CycleLog> logs() {
    CycleLog log(int offset, FlowLevel flow) => CycleLog(
      id: 'rb${_id++}',
      userId: 'local-user',
      // Logged at a random time of day; only the calendar day matters.
      date: day(offset).add(Duration(hours: hour)),
      flow: flow,
      cycleDay: 2,
    );
    return [
      for (final p in periods) ...[
        for (var i = 0; i < p.bleedDays; i++)
          log(p.start + i, FlowLevel.medium),
        if (p.resumeDays == 0)
          log(p.start + p.bleedDays, FlowLevel.none)
        else ...[
          for (var i = 0; i < p.resumeAfter; i++)
            log(p.start + p.bleedDays + i, FlowLevel.none),
          for (var i = 0; i < p.resumeDays; i++)
            log(p.resumeStart + i, FlowLevel.light),
          log(p.resumeStart + p.resumeDays, FlowLevel.none),
        ],
      ],
    ];
  }

  _Case replacing(int index, _Period period) =>
      _Case(origin, [...periods]..[index] = period, hour);
}

/// 3–8 cycles of 26–38 days with 3–7 bleeding days, so every genuine
/// start is at least 19 days after the last bleeding day.
_Case _generate(Random r) {
  final origin = DateTime(
    2023 + r.nextInt(3),
    1 + r.nextInt(12),
    1 + r.nextInt(28),
  );
  final count = 3 + r.nextInt(6);
  final periods = <_Period>[];
  var start = 0;
  for (var i = 0; i < count; i++) {
    periods.add(_Period(start, 3 + r.nextInt(5)));
    start += 26 + r.nextInt(13);
  }
  return _Case(origin, periods, r.nextInt(24));
}

String _ymd(DateTime? d) => d == null ? '-' : '${d.year}-${d.month}-${d.day}';

String _predictionFingerprint(CycleCalculationResult c, DateTime today) {
  final s = _controller.summarizeCalculation(c, today: today);
  final reminder = NotificationScheduler.planCycleReminder(
    calculation: c,
    now: today.add(const Duration(hours: 9)),
  );
  return 'next=${_ymd(s.nextPeriodStart)} '
      'range=${_ymd(s.nextPeriodRange?.earliest)}..${_ymd(s.nextPeriodRange?.latest)} '
      'fertile=${_ymd(s.fertileWindow.start)}..${_ymd(s.fertileWindow.end)} '
      'peak=${_ymd(s.fertileWindow.peakDay)} last=${_ymd(s.lastCycleStart)} '
      'pred=${s.predictedCycleLength} late=${s.daysLate} '
      'basis=${s.predictionBasis?.name} canPredict=${c.canPredictFromHistory} '
      'cycleDay=${c.predictionCycleDay} reminder=${reminder?.fireAt}';
}

void _property(String name, int seedBase, String? Function(Random r) check) {
  test(name, () {
    final failures = <String>[];
    const count = 200;
    for (var i = 0; i < count; i++) {
      final message = check(Random(seedBase + i));
      if (message != null) failures.add('seed=${seedBase + i} $message');
    }
    // ignore: avoid_print
    print(
      'PROPERTY [$name] histories=$count failingHistories=${failures.length}',
    );
    expect(failures, isEmpty, reason: failures.take(3).join('\n'));
  });
}

void main() {
  _property(
    'RB1 resumption in the current period never moves a prediction',
    9100,
    (r) {
      final base = _generate(r);
      final last = base.periods.length - 1;
      final gapped = base.replacing(
        last,
        base.periods[last].withResumption(1 + r.nextInt(5), 1 + r.nextInt(3)),
      );
      final resumption = gapped.day(gapped.periods[last].resumeStart);
      for (var t = 0; t < 12; t++) {
        final today = gapped.day(gapped.periods[last].lastDay + t);
        final a = _service.calculate(base.logs(), asOf: today);
        final b = _service.calculate(gapped.logs(), asOf: today);
        if (!b.haidStarts.contains(resumption)) {
          return 'resumption ${_ymd(resumption)} dropped from haidStarts';
        }
        if (!b.uncertainCycleStarts.contains(resumption)) {
          return 'resumption ${_ymd(resumption)} not uncertain';
        }
        final fa = _predictionFingerprint(a, today);
        final fb = _predictionFingerprint(b, today);
        if (fa != fb) return 'today=${_ymd(today)}\n  base: $fa\n  gap:  $fb';
      }
      return null;
    },
  );

  _property(
    'RB2 a resumption mid-history removes exactly that cycle from '
    'learning and keeps the anchor',
    9400,
    (r) {
      final base = _generate(r);
      if (base.periods.length < 3) return null;
      final index = r.nextInt(base.periods.length - 1);
      final gapped = base.replacing(
        index,
        base.periods[index].withResumption(1 + r.nextInt(4), 1 + r.nextInt(3)),
      );
      final today = gapped.day(gapped.periods.last.lastDay + 3);
      final a = _service.calculate(base.logs(), asOf: today);
      final b = _service.calculate(gapped.logs(), asOf: today);
      final expected = [...a.cycleLengths]..removeAt(index);
      if (b.predictionCycleLengths.join(',') != expected.join(',')) {
        return 'learned ${b.predictionCycleLengths} expected $expected '
            '(factual ${b.cycleLengths})';
      }
      if (b.predictionCycleStarts.join(',') != a.haidStarts.join(',')) {
        return 'confirmed starts differ from the history without the gap';
      }
      if (b.haidStarts.length != a.haidStarts.length + 1) {
        return 'the resumption is not kept as a detected start';
      }
      if (b.predictionAnchor != a.lastHaidStart) return 'anchor moved';
      return null;
    },
  );

  _property(
    'RB3 without a short gap the prediction view is the factual view',
    9700,
    (r) {
      final h = _generate(r);
      final today = h.day(h.periods.last.lastDay + r.nextInt(30));
      final c = _service.calculate(h.logs(), asOf: today);
      if (c.hasUncertainCycleStart ||
          c.predictionCycleStarts.join(',') != c.haidStarts.join(',') ||
          c.predictionCycleLengths.join(',') != c.cycleLengths.join(',') ||
          c.predictionCycleDay != c.currentCycleDay ||
          c.predictionAverageCycleLength != c.averageCycleLength) {
        return 'prediction view differs: ${c.predictionCycleStarts} vs '
            '${c.haidStarts}';
      }
      return null;
    },
  );
}
