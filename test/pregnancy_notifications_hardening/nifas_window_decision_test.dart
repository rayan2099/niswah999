// Nifas window decision (2026-10-21, team at the owner's request; fiqh
// basis pending scholar confirmation): 40 days is the window shown for
// every madhhab. A Shafi'i or Maliki user bleeding on day 41..60 after the
// logged birth gets no ruling (neither "nifas continues" nor "tahara,
// pray") — only a "please consult a scholar" advisory, on Today, in the
// fiqh report and in the AI advisor's client state.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:niswah/core/preferences/madhhab_controller.dart';
import 'package:niswah/features/ai_advisor/client_fiqh_state_provider.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/load_result.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:niswah/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:niswah/features/fiqh_report/domain/services/fiqh_report_insights_engine.dart';
import 'package:niswah/features/pregnancy_profile/domain/entities/pregnancy_profile.dart';
import 'package:niswah/features/pregnancy_profile/domain/services/pregnancy_status_engine.dart';

import '../support/parity_test_harness.dart';

CycleLog _log(DateTime date, FlowLevel flow, int cycleDay) => CycleLog(
  id: 'log-${date.toIso8601String()}',
  userId: 'user-1',
  date: date,
  flow: flow,
  cycleDay: cycleDay,
);

PregnancyProfile _postpartum(DateTime birth) => PregnancyProfile(
  id: 'p',
  userId: 'user-1',
  isPostpartum: true,
  postpartumStartDate: birth,
);

class _Repo extends BleedingEpisodeRepositoryImpl {
  _Repo(this.episodes, this.observations) : super(client: null);
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

/// Harness clock 2026-08-18 12:00; birth logged 45 days earlier
/// (2026-07-04); bleeding open since 2026-08-15 (day 42).
_Repo _bleedingAfterDay40() {
  var n = 0;
  return _Repo(
    [
      BleedingEpisode(
        id: 'open',
        userId: 'user-1',
        lifecycleStatus: LifecycleStatus.open,
        continuationCertainty: ContinuationCertainty.confirmed,
        startDate: DateTime(2026, 8, 15),
        startPrecision: ObservationPrecision.dateOnly,
        startSource: ObservationSource.userObserved,
      ),
    ],
    [
      for (var d = 15; d <= 18; d++)
        BleedingObservation(
          id: 'o${n++}',
          userId: 'user-1',
          episodeId: 'open',
          observedDate: DateTime(2026, 8, d),
          precision: ObservationPrecision.dateOnly,
          flow: ObservationFlow.medium,
          source: ObservationSource.userObserved,
          utcOffsetMinutes: 0,
        ),
    ],
  );
}

Future<void> _pumpDashboard(WidgetTester tester, Madhhab madhhab) async {
  const prefs = {'niswah_nifas_started_at': '2026-07-04T00:00:00.000'};
  await ParityTestHarness.pump(tester, arabic: false, extraPrefs: prefs);
  await MadhhabController.instance.selectMadhhab(madhhab);
  await ParityTestHarness.pump(
    tester,
    arabic: false,
    extraPrefs: prefs,
    homeOverride: DashboardScreen(
      canonicalRepositoryOverride: _bleedingAfterDay40(),
      canonicalUserIdOverride: 'user-1',
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('engine', () {
    test('40 days is the window for every madhhab; 60 is never a window', () {
      expect(PregnancyStatusEngine.nifasWindowDays, 40);
      expect(PregnancyStatusEngine.extendedNifasMaxDays, 60);
      expect(PregnancyStatusEngine.isWithinNifasWindow(40), isTrue);
      expect(PregnancyStatusEngine.isWithinNifasWindow(41), isFalse);
    });

    test('advisory only for Shafi\'i/Maliki, bleeding, days 41..60', () {
      bool advisory(int day, Madhhab? m, bool? bleeding) =>
          PregnancyStatusEngine.needsPostNifasScholarAdvisory(
            daysPostpartum: day,
            madhhab: m,
            isBleeding: bleeding,
          );
      for (final m in [Madhhab.shafii, Madhhab.maliki]) {
        expect(advisory(40, m, true), isFalse, reason: '$m day 40 is nifas');
        expect(advisory(41, m, true), isTrue, reason: '$m day 41');
        expect(advisory(60, m, true), isTrue, reason: '$m day 60');
        expect(advisory(61, m, true), isFalse, reason: '$m day 61');
        expect(advisory(45, m, false), isFalse, reason: '$m not bleeding');
        expect(advisory(45, m, null), isFalse, reason: '$m unverifiable');
      }
      for (final m in [Madhhab.hanafi, Madhhab.hanbali, null]) {
        expect(advisory(45, m, true), isFalse, reason: '$m');
      }
    });

    test('calendar-day based: birth logged with a time of day', () {
      expect(
        PregnancyStatusEngine.needsPostNifasScholarAdvisoryOn(
          birthDate: DateTime(2026, 7, 4, 23, 30),
          today: DateTime(2026, 8, 14, 0, 5), // day 41
          madhhab: Madhhab.shafii,
          isBleeding: true,
        ),
        isTrue,
      );
      expect(
        PregnancyStatusEngine.needsPostNifasScholarAdvisoryOn(
          birthDate: null,
          today: DateTime(2026, 8, 14),
          madhhab: Madhhab.shafii,
          isBleeding: true,
        ),
        isFalse,
      );
    });

    test('the advisory copy states no ruling, in EN and AR', () {
      const en = PregnancyStatusEngine.postNifasAdvisoryEn;
      const ar = PregnancyStatusEngine.postNifasAdvisoryAr;
      expect(en, contains('please consult a scholar'));
      expect(ar, contains('يُرجى استشارة أهل العلم'));
      for (final claim in ['is lifted', 'is obligatory', 'nifas continues']) {
        expect(en.toLowerCase(), isNot(contains(claim)));
      }
    });
  });

  group('fiqh report', () {
    final birth = DateTime(2026, 1, 1);
    // Bleeding logged from day 38 (2026-02-08) through day 45 (2026-02-15).
    final bleeding = [
      for (var d = 8; d <= 15; d++)
        _log(DateTime(2026, 2, d), FlowLevel.medium, d - 7),
    ];

    for (final m in [Madhhab.shafii, Madhhab.maliki]) {
      test('$m bleeding on day 45: needs advisory, no ruling', () {
        final insights = FiqhReportInsightsEngine.analyze(
          cycleLogs: bleeding,
          madhhab: m,
          pregnancyProfile: _postpartum(birth),
          now: DateTime(2026, 2, 15),
        );
        expect(insights.mode, FiqhReportMode.cycle);
        expect(insights.cycleState, FiqhCycleState.needsAdvisory);
        expect(
          insights.evidenceNote,
          ReportEvidenceNote.postNifasScholarAdvisory,
        );
      });
    }

    test('Hanafi bleeding on day 45: no post-nifas advisory (40 max)', () {
      final insights = FiqhReportInsightsEngine.analyze(
        cycleLogs: bleeding,
        madhhab: Madhhab.hanafi,
        pregnancyProfile: _postpartum(birth),
        now: DateTime(2026, 2, 15),
      );
      expect(insights.mode, FiqhReportMode.cycle);
      expect(
        insights.evidenceNote,
        isNot(ReportEvidenceNote.postNifasScholarAdvisory),
      );
    });

    test('Shafi\'i on day 61: the advisory has ended', () {
      final logs = [
        for (var d = 1; d <= 3; d++)
          _log(DateTime(2026, 3, d), FlowLevel.medium, d),
      ];
      final insights = FiqhReportInsightsEngine.analyze(
        cycleLogs: logs,
        madhhab: Madhhab.shafii,
        pregnancyProfile: _postpartum(birth),
        now: DateTime(2026, 3, 3), // day 61
      );
      expect(
        insights.evidenceNote,
        isNot(ReportEvidenceNote.postNifasScholarAdvisory),
      );
    });

    test('Shafi\'i not bleeding on day 45: no advisory', () {
      final logs = [
        ...bleeding.take(3),
        _log(DateTime(2026, 2, 11), FlowLevel.none, 4),
      ];
      final insights = FiqhReportInsightsEngine.analyze(
        cycleLogs: logs,
        madhhab: Madhhab.shafii,
        pregnancyProfile: _postpartum(birth),
        now: DateTime(2026, 2, 15),
      );
      expect(
        insights.evidenceNote,
        isNot(ReportEvidenceNote.postNifasScholarAdvisory),
      );
    });

    test('Shafi\'i inside day 0..40 stays in the nifas branch', () {
      final insights = FiqhReportInsightsEngine.analyze(
        cycleLogs: bleeding,
        madhhab: Madhhab.shafii,
        pregnancyProfile: _postpartum(birth),
        now: DateTime(2026, 2, 10), // day 40
      );
      expect(insights.mode, FiqhReportMode.nifas);
      expect(insights.daysPostpartum, 40);
    });
  });

  group('AI advisor client state', () {
    ClientFiqhStateProvider provider(DateTime? birth) =>
        ClientFiqhStateProvider(
          repository: _bleedingAfterDay40(),
          currentUserId: () => 'user-1',
          clock: () => DateTime(2026, 8, 18, 12),
          birthDate: () => birth,
        );

    test('Shafi\'i bleeding on day 45 is sent as needsAdvisory', () async {
      expect(
        await provider(DateTime(2026, 7, 4))
            .currentClassification(Madhhab.shafii),
        FiqhCycleState.needsAdvisory.name,
      );
    });

    test('without a logged birth the classification is unchanged', () async {
      final withBirth = await provider(DateTime(2026, 7, 4))
          .currentClassification(Madhhab.hanafi);
      final without = await provider(null)
          .currentClassification(Madhhab.hanafi);
      expect(withBirth, without);
    });
  });

  group('dashboard', () {
    testWidgets('Shafi\'i bleeding on day 45: advisory card, no ruling', (
      tester,
    ) async {
      await _pumpDashboard(tester, Madhhab.shafii);
      expect(find.byKey(const Key('nifas-status')), findsNothing);
      expect(find.byKey(const Key('post-nifas-advisory')), findsOneWidget);
      expect(find.text('Please consult a scholar'), findsOneWidget);
      final s = tester.state<ScrollableState>(find.byType(Scrollable).first);
      s.position.jumpTo(s.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('Salah is obligatory'), findsNothing);
      expect(find.text('Salah is lifted'), findsNothing);
      expect(find.text('Please consult a trusted source'), findsOneWidget);
    });

    testWidgets('Maliki bleeding on day 45 shows the advisory too', (
      tester,
    ) async {
      await _pumpDashboard(tester, Madhhab.maliki);
      expect(find.byKey(const Key('post-nifas-advisory')), findsOneWidget);
    });

    testWidgets('Hanafi bleeding on day 45: no post-nifas advisory', (
      tester,
    ) async {
      await _pumpDashboard(tester, Madhhab.hanafi);
      expect(find.byKey(const Key('post-nifas-advisory')), findsNothing);
    });

    testWidgets('the advisory card in Arabic', (tester) async {
      await ParityTestHarness.pump(
        tester,
        arabic: true,
        homeOverride: const Scaffold(body: PostNifasAdvisoryCard()),
      );
      expect(find.text('يُرجى استشارة أهل العلم'), findsOneWidget);
      expect(
        find.text(PregnancyStatusEngine.postNifasAdvisoryAr),
        findsOneWidget,
      );
    });
  });
}
