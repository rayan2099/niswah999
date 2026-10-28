// Launch review case pack (2026-10-27): runs each reviewer case through the
// same pure engines the app uses (Today dashboard, Fiqh report, AI advisor
// context, next-period prediction) for "no madhhab" and all four madhahib,
// and writes what Niswah would say to a JSON file a medical or scholarly
// reviewer can approve or reject. Synthetic histories only.
//
// REVIEW_CASES_OUT=<path> writes the file; without it the test only checks
// that the three surfaces agree and that no case without a madhhab ever
// gets a haid/tahara/needsAdvisory ruling while bleeding.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/controllers/cycle_tracking_controller.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';

import '../round2_properties/support/fiqh_surfaces.dart';
import '../round2_properties/support/synthetic_history.dart';

const _m = ObservationFlow.medium;
const _s = ObservationFlow.spotting;
const _u = ObservationFlow.uncertain;

List<ObservationFlow> _days(int n, [ObservationFlow f = _m]) =>
    List.filled(n, f);

SynthEpisode _ep(
  int start,
  int days, {
  bool ended = true,
  bool onboarding = false,
  Set<int> skipped = const {},
  List<ObservationFlow>? flows,
}) => SynthEpisode(
  start: start,
  flows: flows ?? _days(days),
  ended: ended,
  onboarding: onboarding,
  skipped: skipped,
);

class ReviewCase {
  const ReviewCase(
    this.id,
    this.category,
    this.description,
    this.episodes,
    this.today, {
    this.statedCycle,
    this.statedPeriod,
  });
  final String id;
  final String category;
  final String description;
  final List<SynthEpisode> episodes;
  final int today;
  final int? statedCycle;
  final int? statedPeriod;
}

// Day 0 = 2026-01-01. "today" is a day offset.
final cases = <ReviewCase>[
  // Regular baseline.
  ReviewCase(
    'RC-01',
    'regular',
    'Three regular 28-day cycles, 5-day periods; today is day 3 of a new period.',
    [_ep(0, 5), _ep(28, 5), _ep(56, 5), _ep(84, 3, ended: false)],
    86,
  ),
  ReviewCase(
    'RC-02',
    'regular',
    'Same regular history; today is cycle day 12, not bleeding.',
    [_ep(0, 5), _ep(28, 5), _ep(56, 5), _ep(84, 5)],
    95,
  ),
  ReviewCase(
    'RC-03',
    'regular',
    'Same regular history; period is 4 days late, nothing logged.',
    [_ep(0, 5), _ep(28, 5), _ep(56, 5), _ep(84, 5)],
    116,
  ),
  // Irregular cycles.
  ReviewCase(
    'IR-01',
    'irregular',
    'Cycles of 24, 35 and 29 days; today is day 4 of a new period.',
    [_ep(0, 5), _ep(24, 5), _ep(59, 6), _ep(88, 4, ended: false)],
    91,
  ),
  ReviewCase(
    'IR-02',
    'irregular',
    'Cycles of 21, 45 and 30 days; today is cycle day 10, not bleeding.',
    [_ep(0, 5), _ep(21, 5), _ep(66, 5), _ep(96, 5)],
    105,
  ),
  ReviewCase(
    'IR-03',
    'irregular',
    'A 70-day gap that is probably a missed log, then two 28-day cycles.',
    [_ep(0, 5), _ep(70, 5), _ep(98, 5), _ep(126, 5)],
    135,
  ),
  // Duration limits.
  ReviewCase(
    'DL-01',
    'duration',
    'Regular history; current bleeding has lasted 12 days (above the Hanafi 10-day maximum, within 15).',
    [_ep(0, 5), _ep(28, 5), _ep(56, 5), _ep(84, 12, ended: false)],
    95,
  ),
  ReviewCase(
    'DL-02',
    'duration',
    'Regular history; current bleeding has lasted 16 days (above every school\'s maximum).',
    [_ep(0, 5), _ep(28, 5), _ep(56, 5), _ep(84, 16, ended: false)],
    99,
  ),
  ReviewCase(
    'DL-03',
    'duration',
    'Regular history; bleeding started this morning (day 1, below the Hanafi 3-day and Shafi\'i/Hanbali 24-hour minimum).',
    [_ep(0, 5), _ep(28, 5), _ep(56, 5), _ep(84, 1, ended: false)],
    84,
  ),
  ReviewCase(
    'DL-04',
    'duration',
    'Regular history; the latest bleeding stopped after 2 days (closed episode).',
    [_ep(0, 5), _ep(28, 5), _ep(56, 5), _ep(84, 2)],
    88,
  ),
  // Purity between periods.
  ReviewCase(
    'PU-01',
    'purity',
    'Bleeding returns 10 clean days after a 5-day period (below every school\'s minimum purity).',
    [_ep(0, 5), _ep(28, 5), _ep(56, 5), _ep(71, 3, ended: false)],
    73,
  ),
  ReviewCase(
    'PU-02',
    'purity',
    'Bleeding returns 14 clean days after a period (Hanbali minimum 13 met; Hanafi/Maliki/Shafi\'i 15 not met).',
    [_ep(0, 5), _ep(28, 5), _ep(56, 5), _ep(75, 3, ended: false)],
    77,
  ),
  // Interrupted bleeding.
  ReviewCase(
    'IN-01',
    'interrupted',
    'Period with a one-day clean gap (bleeding 5 days, clean 1, bleeding 2 more), now ended.',
    [_ep(0, 5), _ep(28, 5), _ep(56, 5), _ep(62, 2)],
    66,
  ),
  ReviewCase(
    'IN-02',
    'interrupted',
    'Period with a one-day clean gap; bleeding has resumed and is ongoing today.',
    [_ep(0, 5), _ep(28, 5), _ep(56, 5), _ep(62, 2, ended: false)],
    63,
  ),
  ReviewCase(
    'IN-03',
    'interrupted',
    'Bleeding resumes 5 days after the period ended and is ongoing today.',
    [_ep(0, 5), _ep(28, 5), _ep(56, 5), _ep(66, 2, ended: false)],
    67,
  ),
  // Uncertain dates and evidence.
  ReviewCase(
    'UN-01',
    'uncertain',
    'Brand-new user, first bleeding ever logged, day 2.',
    [_ep(0, 2, ended: false)],
    1,
  ),
  ReviewCase(
    'UN-02',
    'uncertain',
    'Only onboarding answers (one approximate past period, usual cycle 28, usual period 6); not bleeding today.',
    [_ep(0, 6, onboarding: true)],
    20,
    statedCycle: 28,
    statedPeriod: 6,
  ),
  ReviewCase(
    'UN-03',
    'uncertain',
    'Onboarding period plus one logged period; bleeding today, day 2.',
    [_ep(0, 6, onboarding: true), _ep(28, 2, ended: false)],
    29,
    statedCycle: 28,
    statedPeriod: 6,
  ),
  ReviewCase(
    'UN-04',
    'uncertain',
    'Regular history; the current period has an "I\'m not sure" day in it.',
    [
      _ep(0, 5),
      _ep(28, 5),
      _ep(56, 5),
      _ep(84, 4, ended: false, flows: [_m, _u, _m, _m]),
    ],
    87,
  ),
  ReviewCase(
    'UN-05',
    'uncertain',
    'Regular history; she skipped two daily check-ins during the current period.',
    [
      _ep(0, 5),
      _ep(28, 5),
      _ep(56, 5),
      _ep(84, 5, ended: false, skipped: {1, 2}),
    ],
    88,
  ),
  ReviewCase(
    'UN-06',
    'uncertain',
    'Regular history; current period is only spotting so far, day 2.',
    [
      _ep(0, 5),
      _ep(28, 5),
      _ep(56, 5),
      _ep(84, 2, ended: false, flows: [_s, _s]),
    ],
    85,
  ),
];

final _madhahib = <Madhhab?>[null, ...Madhhab.values];

Map<String, Object?> _run(ReviewCase c) {
  final h = SynthHistory(
    kind: c.id,
    seed: 0,
    anchor: DateTime(2026, 1, 1),
    episodes: c.episodes,
    statedCycle: c.statedCycle,
    statedPeriod: c.statedPeriod,
  );
  final ev = evidenceAsOf(h, c.today);
  final now = h.day(c.today).add(const Duration(hours: 10));
  final inputs = canonicalInputs(ev.episodes, ev.observations, now);
  final summary = const CycleTrackingController().summarizeHistory(
    ev.flatLogs,
    now: now,
    canonicalEpisodes: ev.timing,
    statedBaseline: h.baseline,
  );
  final byMadhhab = <String, Object?>{};
  for (final m in _madhahib) {
    final a = dashboardAssessment(inputs, m, now);
    byMadhhab[m?.name ?? 'none'] = {
      'today': dashboardLabel(inputs, m, now),
      'report': reportLabel(inputs, m, now),
      'ai_context': aiLabel(inputs, m, now),
      'confirm_at': a.snapshot.confirmAt == null
          ? null
          : ymdhm(a.snapshot.confirmAt!),
      'days_into_episode': a.snapshot.daysIntoCurrentEpisode,
    };
  }
  return {
    'id': c.id,
    'category': c.category,
    'description': c.description,
    'today': ymd(h.day(c.today)),
    'history': h.describe().trim(),
    'prediction': {
      'next_period': ymd(summary.nextPeriodStart),
      'range': summary.nextPeriodRange == null
          ? null
          : '${ymd(summary.nextPeriodRange!.earliest)}..${ymd(summary.nextPeriodRange!.latest)}',
      'days_late': summary.daysLate,
      'basis': summary.predictionBasis?.name,
      'average_cycle': summary.averageCycleLength,
      'average_period': summary.averagePeriodLength,
    },
    'by_madhhab': byMadhhab,
  };
}

void main() {
  test('review case pack: surfaces agree, no ruling without a madhhab', () {
    final out = [for (final c in cases) _run(c)];
    for (final r in out) {
      final none = (r['by_madhhab']! as Map)['none']! as Map;
      expect(
        ['haid', 'needsAdvisory'].contains(none['today']),
        isFalse,
        reason: '${r['id']}: a ruling was shown with no madhhab',
      );
      for (final entry in (r['by_madhhab']! as Map).entries) {
        final v = entry.value as Map;
        expect(
          dashboardInReportVocabulary(v['today'] as String),
          v['report'],
          reason: '${r['id']}/${entry.key}: Today and the report disagree',
        );
      }
    }
    final path = Platform.environment['REVIEW_CASES_OUT'];
    if (path != null) {
      File(path)
          .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
    }
  });
}
