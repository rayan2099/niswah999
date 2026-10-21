// Round-2 property tests — CycleSegmentPlanner and month grids, plus a
// time-zone digest of every engine's output (compare the printed
// R2_DIGEST lines across zones with run_all_timezones.sh).
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/utils/calendar_days.dart';
import 'package:niswah/features/cycle_tracking/domain/controllers/cycle_tracking_controller.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_segment_planner.dart';

import 'support/fiqh_surfaces.dart';
import 'support/property_runner.dart';
import 'support/synthetic_history.dart';

const _controller = CycleTrackingController();

CycleSegmentPlan? _plan(
  CycleTrackingSummary s,
  DateTime today, {
  bool bleeding = false,
}) {
  if (!s.hasPlausibleAverage || s.lastCycleStart == null) return null;
  final cycleLength = s.predictedCycleLength ?? s.averageCycleLength!;
  final periodLength = s.averagePeriodLength ?? 0;
  return const CycleSegmentPlanner().plan(
    cycleLength: cycleLength,
    periodLength: periodLength,
    fertileWindow: s.fertileWindow,
    cycleStart: s.lastCycleStart!,
    isBleedingNow: bleeding,
    cycleDayEstimate: calendarDaysBetween(s.lastCycleStart!, today) + 1,
  );
}

String _segments(CycleSegmentPlan p) =>
    p.segments.map((s) => '${s.id.name}:${s.durationDays}').join(' ');

void main() {
  property(
    'S1 segment plan is contiguous, non-negative and sums to the cycle length',
    seedBase: 400000,
    kindFor: (seed) =>
        const ['shortLong', 'irregular', 'longBleed', 'regular'][seed % 4],
    check: (h) {
      final r = Random(h.seed);
      for (final t in evaluationDays(h, r)) {
        final ev = evidenceAsOf(h, t);
        final today = h.day(t);
        final s = _controller.summarizeHistory(
          ev.flatLogs,
          now: today,
          canonicalEpisodes: ev.timing,
          statedBaseline: h.baseline,
        );
        final p = _plan(s, today);
        if (p == null) continue;
        evaluationCounter++;
        final cycleLength = s.predictedCycleLength!;
        if (p.segments.any((seg) => seg.durationDays < 0)) {
          return 'negative segment: ${_segments(p)}';
        }
        if (p.totalDays != cycleLength) {
          return 'segments sum to ${p.totalDays}, cycle is $cycleLength '
              '(period ${s.averagePeriodLength}, fertile '
              '${ymd(s.fertileWindow.start)}..${ymd(s.fertileWindow.end)}, '
              'start ${ymd(s.lastCycleStart)}): ${_segments(p)}';
        }
        // The fertile segment sits where the fertile window really is
        // when the window fits after the period and before pre-period.
        final fw = s.fertileWindow;
        final period = s.averagePeriodLength ?? 0;
        if (fw.start != null) {
          final startOff =
              calendarDaysBetween(s.lastCycleStart!, fw.start!) + 1;
          final endOff = calendarDaysBetween(s.lastCycleStart!, fw.end!) + 1;
          if (startOff > period && endOff <= cycleLength - 4) {
            var offset = 0;
            for (final seg in p.segments) {
              if (seg.id == CycleSegmentId.fertile) {
                if (offset + 1 != startOff ||
                    seg.durationDays != endOff - startOff + 1) {
                  return 'fertile segment at day ${offset + 1} for '
                      '${seg.durationDays}d, window is day $startOff..$endOff';
                }
              }
              offset += seg.durationDays;
            }
          }
        }
        if (p.activeIndex == null) return 'no active segment: ${_segments(p)}';
      }
      return null;
    },
  );

  test(
    'S2 month grids are strictly consecutive local midnights (2020-2030)',
    () {
      var cases = 0;
      for (var year = 2020; year <= 2030; year++) {
        for (var month = 1; month <= 12; month++) {
          // Same formula as canonical_calendar_screen.dart:394/450 and
          // cycle_calendar.dart:37/139.
          final monthStart = DateTime(year, month);
          final gridStart = addCalendarDays(
            monthStart,
            -(monthStart.weekday % 7),
          );
          final cells = [
            for (var i = 0; i < 42; i++) addCalendarDays(gridStart, i),
          ];
          for (var i = 0; i < cells.length; i++) {
            cases++;
            final c = cells[i];
            expect(
              c.hour == 0 && c.minute == 0,
              isTrue,
              reason: '$c not midnight',
            );
            if (i > 0) {
              expect(
                calendarDaysBetween(cells[i - 1], c),
                1,
                reason: '${cells[i - 1]} -> $c',
              );
              expect(c.isAfter(cells[i - 1]), isTrue);
            }
          }
          final daysInMonth = DateTime(year, month + 1, 0).day;
          final inMonth = cells.where(
            (c) => c.month == month && c.year == year,
          );
          expect(inMonth.map((c) => c.day).toList(), [
            for (var d = 1; d <= daysInMonth; d++) d,
          ], reason: '$year-$month');
        }
      }
      // ignore: avoid_print
      print('PROPERTY [S2 grids] evaluations=$cases');
    },
  );

  // Not an assertion: prints one digest per engine for this zone. Equal
  // digests across zones = identical outputs (run_all_timezones.sh).
  test('TZ digest of prediction, fiqh (noon) and segment outputs', () {
    final pred = StringBuffer();
    final fiqh = StringBuffer();
    final seg = StringBuffer();
    var cases = 0;
    for (var seed = 500000; seed < 500150; seed++) {
      final h = generateHistory(seed);
      final r = Random(seed);
      for (final t in evaluationDays(h, r)) {
        final ev = evidenceAsOf(h, t);
        final today = h.day(t);
        final noon = today.add(const Duration(hours: 12));
        final s = _controller.summarizeHistory(
          ev.flatLogs,
          now: noon,
          canonicalEpisodes: ev.timing,
          statedBaseline: h.baseline,
        );
        cases++;
        pred.writeln(
          '$seed/$t ${ymd(s.lastCycleStart)} ${s.predictedCycleLength} '
          '${ymd(s.nextPeriodStart)} ${s.daysLate} '
          '${ymd(s.nextPeriodRange?.earliest)} ${ymd(s.nextPeriodRange?.latest)} '
          '${ymd(s.fertileWindow.start)} ${ymd(s.fertileWindow.end)} '
          '${s.currentPhase.name} ${s.averagePeriodLength}',
        );
        final p = _plan(s, today);
        if (p != null) seg.writeln('$seed/$t ${_segments(p)} ${p.activeIndex}');
        final c = canonicalInputs(ev.episodes, ev.observations, noon);
        fiqh.writeln(
          '$seed/$t ${[for (final m in madhhabs) dashboardLabel(c, m, noon)].join(',')}',
        );
      }
    }
    String digest(StringBuffer b) {
      // FNV-1a 64-bit over UTF-8.
      var hash = 0xcbf29ce484222325;
      for (final byte in utf8.encode(b.toString())) {
        hash ^= byte;
        hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
      }
      return hash.toUnsigned(64).toRadixString(16);
    }

    // ignore: avoid_print
    print(
      'R2_DIGEST cases=$cases prediction=${digest(pred)} '
      'fiqh_noon=${digest(fiqh)} segments=${digest(seg)}',
    );
  });
}
