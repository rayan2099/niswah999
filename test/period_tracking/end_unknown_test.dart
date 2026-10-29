import 'package:flutter_test/flutter_test.dart';

import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/services/canonical_fiqh_assessment.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:niswah/features/wellbeing/domain/entities/wellbeing_log.dart';
import 'package:niswah/features/wellbeing/domain/services/wellbeing_period_split.dart';

/// PT-002: a period she says has stopped, without knowing when. The app
/// side of supabase/migrations/20261029130000_bleeding_episode_end_unknown.sql;
/// the server rules are proven in test/security/bleeding_episode_end_unknown.sql.

Map<String, dynamic> _row({String? endDate, String? endPrecision}) => {
  'id': 'e1',
  'user_id': 'u1',
  'lifecycle_status': 'ended',
  'continuation_certainty': null,
  'start_date': '2026-09-01',
  'start_precision': 'date_only',
  'start_source': 'user_reported_historical',
  'end_date': endDate,
  'end_precision': endPrecision,
  'end_source': 'user_reported_historical',
  'updated_at': '2026-10-20T10:00:00Z',
};

void main() {
  group('BleedingEpisode', () {
    test('reads an unknown end as ended with no end date and no precision', () {
      final e = BleedingEpisode.fromJson(_row(endPrecision: 'unknown'));
      expect(e.lifecycleStatus, LifecycleStatus.ended);
      expect(e.endUnknown, isTrue);
      expect(e.endDate, isNull);
      expect(e.endPrecision, isNull);
      expect(e.toInsertJson()['end_precision'], 'unknown');
      expect(e.toInsertJson().containsKey('end_date'), isFalse);
    });

    test('a row claiming both an end date and an unknown end is refused', () {
      expect(
        () => BleedingEpisode.fromJson(
          _row(endDate: '2026-09-05', endPrecision: 'unknown'),
        ),
        throwsA(isA<BleedingEpisodeParseException>()),
      );
    });

    test('a known end is unchanged', () {
      final e = BleedingEpisode.fromJson(
        _row(endDate: '2026-09-05', endPrecision: 'date_only'),
      );
      expect(e.endUnknown, isFalse);
      expect(e.endDate, DateTime(2026, 9, 5));
    });
  });

  group('predictions', () {
    test('its start counts as a cycle start, but it gives no period length '
        'and is never treated as still going', () {
      final result = const CycleCalculationService().calculate(
        const [],
        asOf: DateTime(2026, 10, 25),
        canonicalEpisodes: [
          CanonicalEpisodeTiming(
            startDate: DateTime(2026, 8, 30),
            endUnknown: true,
          ),
          CanonicalEpisodeTiming(
            startDate: DateTime(2026, 9, 28),
            endDate: DateTime(2026, 10, 3),
          ),
        ],
      );
      expect(result.haidStarts, [DateTime(2026, 8, 30), DateTime(2026, 9, 28)]);
      expect(result.cycleLengths, [29]);
      expect(
        result.averagePeriodLength,
        5,
        reason: 'only the period with a known end has a length',
      );
    });
  });

  group('fiqh', () {
    CanonicalFiqhAssessment assess(List<CanonicalEpisodeTiming> episodes) =>
        CanonicalFiqhAssessment.assess(
          effectiveLogs: const [],
          hasOpenEpisode: false,
          evidenceUnresolved: false,
          madhhab: Madhhab.hanafi,
          now: DateTime(2026, 10, 25),
          canonicalEpisodes: episodes,
        );

    test('no ruling while her most recent period has an unknown end', () {
      final a = assess([
        CanonicalEpisodeTiming(
          startDate: DateTime(2026, 8, 1),
          endDate: DateTime(2026, 8, 6),
        ),
        CanonicalEpisodeTiming(
          startDate: DateTime(2026, 9, 1),
          endDate: DateTime(2026, 9, 6),
        ),
        CanonicalEpisodeTiming(
          startDate: DateTime(2026, 10, 1),
          endUnknown: true,
        ),
      ]);
      expect(a.verdict, CanonicalFiqhVerdict.lastEndUnknown);
      expect(a.state, isNull, reason: 'no state may be presented');
    });

    test('an older unknown end followed by a known period does not block', () {
      final a = assess([
        CanonicalEpisodeTiming(
          startDate: DateTime(2026, 8, 1),
          endUnknown: true,
        ),
        CanonicalEpisodeTiming(
          startDate: DateTime(2026, 9, 1),
          endDate: DateTime(2026, 9, 6),
        ),
        CanonicalEpisodeTiming(
          startDate: DateTime(2026, 10, 1),
          endDate: DateTime(2026, 10, 6),
        ),
      ]);
      expect(a.verdict, isNot(CanonicalFiqhVerdict.lastEndUnknown));
    });
  });

  test('wellbeing counts only the known start day as a period day', () {
    WellbeingLog mood(int day) => WellbeingLog(
      id: 'w$day',
      userId: 'u',
      logDate: DateTime(2026, 10, day),
      mood: 3,
      energy: 3,
      sleep: 3,
    );
    final split = WellbeingPeriodSplit.compute(
      logs: [mood(1), mood(2), mood(20)],
      episodes: [
        CanonicalEpisodeTiming(
          startDate: DateTime(2026, 10, 1),
          endUnknown: true,
        ),
      ],
      today: DateTime(2026, 10, 25),
    );
    expect(split.onPeriodDays.count, 1);
    expect(split.onOtherDays.count, 2);
  });
}
