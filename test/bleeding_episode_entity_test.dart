import 'package:flutter_test/flutter_test.dart';

import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';

/// Menstrual Data Integrity charter, Commit A: round-trips a
/// [BleedingEpisode] through its wire representation and confirms strict
/// parsing rejects invalid/missing required fields instead of substituting
/// a plausible default (the same policy already enforced for `CycleLog`).
void main() {
  group('BleedingEpisode', () {
    test('an active episode serializes without any end fields', () {
      final episode = BleedingEpisode(
        userId: 'user-1',
        status: EpisodeStatus.active,
        startDate: DateTime(2026, 9, 10),
        startPrecision: ObservationPrecision.dateOnly,
        startSource: ObservationSource.userReportedHistorical,
      );

      final json = episode.toInsertJson();
      expect(json['status'], 'active');
      expect(json['start_date'], '2026-09-10');
      expect(json.containsKey('end_date'), isFalse);
    });

    test('an ended episode round-trips through JSON exactly', () {
      final episode = BleedingEpisode(
        userId: 'user-1',
        status: EpisodeStatus.ended,
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

      expect(parsed.status, EpisodeStatus.ended);
      expect(parsed.startDate, DateTime(2026, 9, 1));
      expect(parsed.endDate, DateTime(2026, 9, 6));
    });

    test(
      'constructing an ended episode without an end date is a programmer error',
      () {
        expect(
          () => BleedingEpisode(
            userId: 'user-1',
            status: EpisodeStatus.ended,
            startDate: DateTime(2026, 9, 1),
            startPrecision: ObservationPrecision.dateOnly,
            startSource: ObservationSource.userReportedHistorical,
          ),
          throwsA(isA<AssertionError>()),
        );
      },
    );

    test('fromJson throws on a missing start_date rather than defaulting', () {
      expect(
        () => BleedingEpisode.fromJson({
          'user_id': 'user-1',
          'status': 'uncertain',
          'start_precision': 'date_only',
          'start_source': 'user_reported_historical',
        }),
        throwsA(isA<BleedingEpisodeParseException>()),
      );
    });

    test('fromJson throws on an unrecognized status', () {
      expect(
        () => BleedingEpisode.fromJson({
          'user_id': 'user-1',
          'status': 'definitely_haid',
          'start_date': '2026-09-01',
          'start_precision': 'date_only',
          'start_source': 'user_reported_historical',
        }),
        throwsA(isA<BleedingEpisodeParseException>()),
      );
    });
  });

  group('CycleBaseline', () {
    test('round-trips with both fields set', () {
      const baseline = CycleBaseline(
        userId: 'user-1',
        usualBleedingDurationDays: 6,
        usualCycleLengthDays: 29,
      );
      final parsed = CycleBaseline.fromJson(baseline.toUpsertJson());
      expect(parsed, baseline);
    });

    test('an unanswered estimate stays null — never coerced to a fabricated '
        'value', () {
      const baseline = CycleBaseline(userId: 'user-1');
      final json = baseline.toUpsertJson();
      expect(json['usual_bleeding_duration_days'], isNull);
      expect(json['usual_cycle_length_days'], isNull);
    });
  });
}
