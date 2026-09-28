import 'package:flutter_test/flutter_test.dart';

import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';

/// Menstrual Data Integrity charter: round-trips a [BleedingEpisode]
/// through its wire representation and confirms strict parsing rejects
/// invalid/missing required fields instead of substituting a plausible
/// default (the same policy already enforced for `CycleLog`).
///
/// PR #4 hardening, Blocker 5: the lifecycle is now split into
/// [LifecycleStatus] (open/ended) and [ContinuationCertainty]
/// (confirmed/uncertain, meaningful only while open) — replacing the
/// original three-way active/ended/uncertain, which let "I'm not sure"
/// silently vacate the one-active-episode slot.
void main() {
  group('BleedingEpisode', () {
    test('an open, confirmed episode serializes without any end fields', () {
      final episode = BleedingEpisode(
        userId: 'user-1',
        lifecycleStatus: LifecycleStatus.open,
        continuationCertainty: ContinuationCertainty.confirmed,
        startDate: DateTime(2026, 9, 10),
        startPrecision: ObservationPrecision.dateOnly,
        startSource: ObservationSource.userReportedHistorical,
      );

      final json = episode.toInsertJson();
      expect(json['lifecycle_status'], 'open');
      expect(json['continuation_certainty'], 'confirmed');
      expect(json['start_date'], '2026-09-10');
      expect(json.containsKey('end_date'), isFalse);
    });

    test('an ended episode round-trips through JSON exactly', () {
      final episode = BleedingEpisode(
        userId: 'user-1',
        lifecycleStatus: LifecycleStatus.ended,
        startDate: DateTime(2026, 9, 1),
        startPrecision: ObservationPrecision.dateOnly,
        startSource: ObservationSource.userReportedHistorical,
        endDate: DateTime(2026, 9, 6),
        endPrecision: ObservationPrecision.dateOnly,
        endSource: ObservationSource.userReportedHistorical,
      );

      final json = episode.toInsertJson()
        ..['id'] = 'episode-1'
        ..['user_id'] = 'user-1';
      final parsed = BleedingEpisode.fromJson(json);

      expect(parsed.lifecycleStatus, LifecycleStatus.ended);
      expect(parsed.continuationCertainty, isNull);
      expect(parsed.startDate, DateTime(2026, 9, 1));
      expect(parsed.endDate, DateTime(2026, 9, 6));
    });

    test(
      'constructing an ended episode without an end date is a programmer error',
      () {
        expect(
          () => BleedingEpisode(
            userId: 'user-1',
            lifecycleStatus: LifecycleStatus.ended,
            startDate: DateTime(2026, 9, 1),
            startPrecision: ObservationPrecision.dateOnly,
            startSource: ObservationSource.userReportedHistorical,
          ),
          throwsA(isA<AssertionError>()),
        );
      },
    );

    test('constructing an open episode without continuationCertainty is a '
        'programmer error', () {
      expect(
        () => BleedingEpisode(
          userId: 'user-1',
          lifecycleStatus: LifecycleStatus.open,
          startDate: DateTime(2026, 9, 1),
          startPrecision: ObservationPrecision.dateOnly,
          startSource: ObservationSource.userReportedHistorical,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('marking continuation uncertain never itself ends the episode', () {
      final episode = BleedingEpisode(
        userId: 'user-1',
        lifecycleStatus: LifecycleStatus.open,
        continuationCertainty: ContinuationCertainty.uncertain,
        startDate: DateTime(2026, 9, 1),
        startPrecision: ObservationPrecision.dateOnly,
        startSource: ObservationSource.userReportedHistorical,
      );
      expect(episode.lifecycleStatus, LifecycleStatus.open);
      expect(episode.endDate, isNull);
    });

    test('fromJson throws on a missing start_date rather than defaulting', () {
      expect(
        () => BleedingEpisode.fromJson({
          'user_id': 'user-1',
          'lifecycle_status': 'open',
          'continuation_certainty': 'uncertain',
          'start_precision': 'date_only',
          'start_source': 'user_reported_historical',
        }),
        throwsA(isA<BleedingEpisodeParseException>()),
      );
    });

    test('fromJson throws on an unrecognized lifecycle_status', () {
      expect(
        () => BleedingEpisode.fromJson({
          'user_id': 'user-1',
          'lifecycle_status': 'definitely_haid',
          'start_date': '2026-09-01',
          'start_precision': 'date_only',
          'start_source': 'user_reported_historical',
        }),
        throwsA(isA<BleedingEpisodeParseException>()),
      );
    });
  });

  group('ObservationSource.classify (PR #4 hardening, Blocker 4)', () {
    test('reporting today is userObserved', () {
      final today = DateTime(2026, 9, 18);
      expect(
        ObservationSource.classify(reportedDate: today, localToday: today),
        ObservationSource.userObserved,
      );
    });

    test('reporting yesterday is userReportedHistorical, not userObserved', () {
      final today = DateTime(2026, 9, 18);
      final yesterday = DateTime(2026, 9, 17);
      expect(
        ObservationSource.classify(reportedDate: yesterday, localToday: today),
        ObservationSource.userReportedHistorical,
      );
    });

    test('reporting a date far in the past is userReportedHistorical', () {
      final today = DateTime(2026, 9, 18);
      final longAgo = DateTime(2020, 1, 1);
      expect(
        ObservationSource.classify(reportedDate: longAgo, localToday: today),
        ObservationSource.userReportedHistorical,
      );
    });

    test('classification ignores time-of-day, only the calendar date', () {
      final today = DateTime(2026, 9, 18, 23, 59);
      final reportedThisMorning = DateTime(2026, 9, 18, 6, 0);
      expect(
        ObservationSource.classify(
          reportedDate: reportedThisMorning,
          localToday: today,
        ),
        ObservationSource.userObserved,
      );
    });
  });

  group('CycleBaseline (PR #4 hardening, Blocker 9 — append-only history)', () {
    test('round-trips with both fields set', () {
      const baseline = CycleBaseline(
        userId: 'user-1',
        usualBleedingDurationDays: 6,
        usualCycleLengthDays: 29,
      );
      final json = baseline.toInsertJson()..['user_id'] = 'user-1';
      final parsed = CycleBaseline.fromJson(json);
      expect(parsed.usualBleedingDurationDays, 6);
      expect(parsed.usualCycleLengthDays, 29);
    });

    test('an unanswered estimate stays null — never coerced to a fabricated '
        'value', () {
      const baseline = CycleBaseline(userId: 'user-1');
      final json = baseline.toInsertJson();
      expect(json['usual_bleeding_duration_days'], isNull);
      expect(json['usual_cycle_length_days'], isNull);
    });

    test('toInsertJson never includes an id — the database assigns it', () {
      const baseline = CycleBaseline(userId: 'user-1');
      expect(baseline.toInsertJson().containsKey('id'), isFalse);
    });
  });
}
