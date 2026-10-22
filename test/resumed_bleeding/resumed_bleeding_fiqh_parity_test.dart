// Resumed bleeding (2026-10-22, proposed): the prediction-only change must
// leave the fiqh engine byte-for-byte unchanged. Every expected fingerprint
// below was recorded by running this same file against the pre-change
// code (origin/perf/prediction-efficiency, bfb47f2), so a difference here
// means fiqh output moved. Synthetic histories only.
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/utils/calendar_days.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/canonical_fiqh_assessment.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';

var _id = 0;

final _origin = DateTime(2026, 1, 1);
DateTime _d(int offset) => addCalendarDays(_origin, offset);

CycleLog _log(int offset, FlowLevel flow) => CycleLog(
  id: 'p${_id++}',
  userId: 'local-user',
  date: _d(offset),
  flow: flow,
  cycleDay: 2,
);

/// Bleeding on [from]..[to] (inclusive day offsets).
List<CycleLog> _bleed(int from, int to) => [
  for (var i = from; i <= to; i++) _log(i, FlowLevel.medium),
];

List<CycleLog> _clean(int day) => [_log(day, FlowLevel.none)];

String _ymd(DateTime? d) => d == null
    ? '-'
    : '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';

/// Everything the fiqh engine reads from or returns for this evidence.
String _fingerprint(
  List<CycleLog> logs,
  List<CanonicalEpisodeTiming> timing,
  int nowOffset,
) {
  final now = _d(nowOffset).add(const Duration(hours: 10));
  final latestFlow = logs.isEmpty
      ? null
      : logs.reduce((a, b) => b.date.isBefore(a.date) ? a : b).flow;
  final open = latestFlow != null && latestFlow != FlowLevel.none;
  final parts = <String>[];
  for (final madhhab in <Madhhab?>[null, ...Madhhab.values]) {
    final a = CanonicalFiqhAssessment.assess(
      effectiveLogs: logs,
      hasOpenEpisode: open,
      evidenceUnresolved: false,
      madhhab: madhhab,
      now: now,
      canonicalEpisodes: timing,
    );
    final c = a.calculation;
    final s = a.snapshot;
    parts.add(
      '${madhhab?.name ?? 'none'}:${a.verdict.name}/${a.state?.name}'
      ' snap=${s.state.name},${s.confirmAt?.toIso8601String()},'
      '${s.daysIntoCurrentEpisode},${s.cycleDayEstimate},'
      '${s.averageCycleLength},${s.averagePeriodLength}'
      ' calc=${c.haidStarts.map(_ymd).join('|')},${c.currentCycleDay},'
      '${c.averageCycleLength},${c.cycleLengths.join('|')},'
      '${c.averagePeriodLength},${c.hasSufficientHistory},'
      '${_ymd(c.lastHaidStart)},${c.regularity.name}',
    );
  }
  return parts.join(' || ');
}

/// Regular 28-day periods of 5 days at offsets 0, 28, 56; the third one
/// resumes after a one-day gap (bleeding 56-60, clean 61, bleeding 62-63).
List<CycleLog> _oneDayGap({bool closed = true}) => [
  ..._bleed(0, 4),
  ..._clean(5),
  ..._bleed(28, 32),
  ..._clean(33),
  ..._bleed(56, 60),
  ..._clean(61),
  ..._bleed(62, 63),
  if (closed) ..._clean(64),
];

/// A resumption inside an earlier cycle, then a later normal period.
List<CycleLog> _midHistoryGap() => [
  ..._bleed(0, 4),
  ..._clean(5),
  ..._bleed(28, 31),
  ..._clean(32),
  ..._bleed(33, 34),
  ..._clean(35),
  ..._bleed(58, 62),
  ..._clean(63),
  ..._bleed(86, 90),
  ..._clean(91),
];

/// Repeated on/off bleeding after one period (several short gaps).
List<CycleLog> _repeatedGaps() => [
  ..._bleed(0, 5),
  ..._clean(6),
  ..._bleed(30, 33),
  ..._clean(34),
  ..._bleed(35, 35),
  ..._clean(36),
  ..._clean(37),
  ..._bleed(38, 40),
  ..._clean(41),
  ..._bleed(50, 51),
];

final _canonicalTiming = [
  CanonicalEpisodeTiming(startDate: _d(0), endDate: _d(5)),
  CanonicalEpisodeTiming(startDate: _d(28), endDate: _d(33)),
  CanonicalEpisodeTiming(startDate: _d(35), endDate: _d(38)),
];

const _expected = <String, String>{
  // Recorded from the pre-change code; see the file header.
  'oneDayGap-during-resumption': r'''none:evaluated/madhhabUnresolved snap=madhhabUnresolved,null,2,2,21,5 calc=2026-01-01|2026-01-29|2026-02-26|2026-03-04,2,21,28|28|6,5,true,2026-03-04,irregular || hanafi:evaluated/needsAdvisory snap=needsAdvisory,null,2,2,21,5 calc=2026-01-01|2026-01-29|2026-02-26|2026-03-04,2,21,28|28|6,5,true,2026-03-04,irregular || maliki:evaluated/needsAdvisory snap=needsAdvisory,null,2,2,21,5 calc=2026-01-01|2026-01-29|2026-02-26|2026-03-04,2,21,28|28|6,5,true,2026-03-04,irregular || shafii:evaluated/needsAdvisory snap=needsAdvisory,null,2,2,21,5 calc=2026-01-01|2026-01-29|2026-02-26|2026-03-04,2,21,28|28|6,5,true,2026-03-04,irregular || hanbali:evaluated/needsAdvisory snap=needsAdvisory,null,2,2,21,5 calc=2026-01-01|2026-01-29|2026-02-26|2026-03-04,2,21,28|28|6,5,true,2026-03-04,irregular''',
  'oneDayGap-after': r'''none:evaluated/tahara snap=tahara,null,null,9,21,4 calc=2026-01-01|2026-01-29|2026-02-26|2026-03-04,9,21,28|28|6,4,true,2026-03-04,irregular || hanafi:evaluated/tahara snap=tahara,null,null,9,21,4 calc=2026-01-01|2026-01-29|2026-02-26|2026-03-04,9,21,28|28|6,4,true,2026-03-04,irregular || maliki:evaluated/tahara snap=tahara,null,null,9,21,4 calc=2026-01-01|2026-01-29|2026-02-26|2026-03-04,9,21,28|28|6,4,true,2026-03-04,irregular || shafii:evaluated/tahara snap=tahara,null,null,9,21,4 calc=2026-01-01|2026-01-29|2026-02-26|2026-03-04,9,21,28|28|6,4,true,2026-03-04,irregular || hanbali:evaluated/tahara snap=tahara,null,null,9,21,4 calc=2026-01-01|2026-01-29|2026-02-26|2026-03-04,9,21,28|28|6,4,true,2026-03-04,irregular''',
  'oneDayGap-in-gap': r'''none:evaluated/tahara snap=tahara,null,null,6,28,5 calc=2026-01-01|2026-01-29,6,28,28,5,true,2026-01-29,insufficientData || hanafi:evaluated/tahara snap=tahara,null,null,6,28,5 calc=2026-01-01|2026-01-29,6,28,28,5,true,2026-01-29,insufficientData || maliki:evaluated/tahara snap=tahara,null,null,6,28,5 calc=2026-01-01|2026-01-29,6,28,28,5,true,2026-01-29,insufficientData || shafii:evaluated/tahara snap=tahara,null,null,6,28,5 calc=2026-01-01|2026-01-29,6,28,28,5,true,2026-01-29,insufficientData || hanbali:evaluated/tahara snap=tahara,null,null,6,28,5 calc=2026-01-01|2026-01-29,6,28,28,5,true,2026-01-29,insufficientData''',
  'midHistoryGap': r'''none:evaluated/tahara snap=tahara,null,null,10,22,4 calc=2026-01-01|2026-01-29|2026-02-03|2026-02-28|2026-03-28,10,22,28|5|25|28,4,true,2026-03-28,irregular || hanafi:evaluated/tahara snap=tahara,null,null,10,22,4 calc=2026-01-01|2026-01-29|2026-02-03|2026-02-28|2026-03-28,10,22,28|5|25|28,4,true,2026-03-28,irregular || maliki:evaluated/tahara snap=tahara,null,null,10,22,4 calc=2026-01-01|2026-01-29|2026-02-03|2026-02-28|2026-03-28,10,22,28|5|25|28,4,true,2026-03-28,irregular || shafii:evaluated/tahara snap=tahara,null,null,10,22,4 calc=2026-01-01|2026-01-29|2026-02-03|2026-02-28|2026-03-28,10,22,28|5|25|28,4,true,2026-03-28,irregular || hanbali:evaluated/tahara snap=tahara,null,null,10,22,4 calc=2026-01-01|2026-01-29|2026-02-03|2026-02-28|2026-03-28,10,22,28|5|25|28,4,true,2026-03-28,irregular''',
  'repeatedGaps-bleeding': r'''none:evaluated/madhhabUnresolved snap=madhhabUnresolved,null,2,2,13,4 calc=2026-01-01|2026-01-31|2026-02-05|2026-02-08|2026-02-20,2,13,30|5|3|12,4,true,2026-02-20,irregular || hanafi:evaluated/needsAdvisory snap=needsAdvisory,null,2,2,13,4 calc=2026-01-01|2026-01-31|2026-02-05|2026-02-08|2026-02-20,2,13,30|5|3|12,4,true,2026-02-20,irregular || maliki:evaluated/needsAdvisory snap=needsAdvisory,null,2,2,13,4 calc=2026-01-01|2026-01-31|2026-02-05|2026-02-08|2026-02-20,2,13,30|5|3|12,4,true,2026-02-20,irregular || shafii:evaluated/needsAdvisory snap=needsAdvisory,null,2,2,13,4 calc=2026-01-01|2026-01-31|2026-02-05|2026-02-08|2026-02-20,2,13,30|5|3|12,4,true,2026-02-20,irregular || hanbali:evaluated/needsAdvisory snap=needsAdvisory,null,2,2,13,4 calc=2026-01-01|2026-01-31|2026-02-05|2026-02-08|2026-02-20,2,13,30|5|3|12,4,true,2026-02-20,irregular''',
  'canonicalResumption': r'''none:evaluated/tahara snap=tahara,null,null,11,18,4 calc=2026-01-01|2026-01-29|2026-02-05,11,18,28|7,4,true,2026-02-05,irregular || hanafi:evaluated/tahara snap=tahara,null,null,11,18,4 calc=2026-01-01|2026-01-29|2026-02-05,11,18,28|7,4,true,2026-02-05,irregular || maliki:evaluated/tahara snap=tahara,null,null,11,18,4 calc=2026-01-01|2026-01-29|2026-02-05,11,18,28|7,4,true,2026-02-05,irregular || shafii:evaluated/tahara snap=tahara,null,null,11,18,4 calc=2026-01-01|2026-01-29|2026-02-05,11,18,28|7,4,true,2026-02-05,irregular || hanbali:evaluated/tahara snap=tahara,null,null,11,18,4 calc=2026-01-01|2026-01-29|2026-02-05,11,18,28|7,4,true,2026-02-05,irregular''',
  'canonicalResumption-mixed': r'''none:evaluated/tahara snap=tahara,null,null,6,18,4 calc=2026-01-01|2026-01-29|2026-02-05,6,18,28|7,4,true,2026-02-05,irregular || hanafi:evaluated/tahara snap=tahara,null,null,6,18,4 calc=2026-01-01|2026-01-29|2026-02-05,6,18,28|7,4,true,2026-02-05,irregular || maliki:evaluated/tahara snap=tahara,null,null,6,18,4 calc=2026-01-01|2026-01-29|2026-02-05,6,18,28|7,4,true,2026-02-05,irregular || shafii:evaluated/tahara snap=tahara,null,null,6,18,4 calc=2026-01-01|2026-01-29|2026-02-05,6,18,28|7,4,true,2026-02-05,irregular || hanbali:evaluated/tahara snap=tahara,null,null,6,18,4 calc=2026-01-01|2026-01-29|2026-02-05,6,18,28|7,4,true,2026-02-05,irregular''',
};

Map<String, String> _cases() => {
  'oneDayGap-during-resumption': _fingerprint(
    _oneDayGap(closed: false),
    const [],
    63,
  ),
  'oneDayGap-after': _fingerprint(_oneDayGap(), const [], 70),
  'oneDayGap-in-gap': _fingerprint(
    [..._bleed(0, 4), ..._clean(5), ..._bleed(28, 32), ..._clean(33)],
    const [],
    33,
  ),
  'midHistoryGap': _fingerprint(_midHistoryGap(), const [], 95),
  'repeatedGaps-bleeding': _fingerprint(_repeatedGaps(), const [], 51),
  'canonicalResumption': _fingerprint(const [], _canonicalTiming, 45),
  'canonicalResumption-mixed': _fingerprint(
    [..._bleed(35, 37), ..._clean(38)],
    _canonicalTiming,
    40,
  ),
};

void main() {
  test('fiqh assessment for resumed-bleeding histories is unchanged by the '
      'prediction-only view', () {
    final actual = _cases();
    if (_expected.isEmpty) {
      // Recording mode (only used to capture the pre-change fingerprints).
      for (final entry in actual.entries) {
        // ignore: avoid_print
        print("  '${entry.key}': r'''${entry.value}''',");
      }
      fail('no recorded fingerprints');
    }
    expect(actual.keys, unorderedEquals(_expected.keys));
    for (final key in _expected.keys) {
      expect(actual[key], _expected[key], reason: key);
    }
  });
}
