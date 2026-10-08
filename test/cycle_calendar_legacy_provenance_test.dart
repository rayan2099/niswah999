import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/utils/app_clock.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/presentation/widgets/cycle_calendar.dart';

/// Fix 5 (prove actual F7 category coverage) — [CycleCalendar] is the
/// one real surface in the app where a genuine
/// [CycleEntryProvenance.legacyUnverified] record can actually appear
/// (the new canonical calendar deliberately never reads `cycle_entries`
/// at all). Previously, [EvidenceProvenance.legacyUnverified] was
/// declared in the shared taxonomy and shown only in a legend — no code
/// path ever attached it to a real rendered day. This file proves the
/// fix: a legacy, provenance-less row is now visibly and audibly
/// distinguished from a real observed/historical one, without ever
/// being treated as a canonical observation (the day's own haid/tahara
/// marker logic is untouched — this is purely an honest, additional
/// visibility flag).
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLocaleController.instance.setArabic(false);
    AppClock.now = () => DateTime(2026, 8, 18, 12);
  });

  const summary = CycleTrackingSummary(
    averageCycleLength: null,
    averagePeriodLength: null,
    lastCycleStart: null,
    currentPhase: CyclePhase.follicular,
    fertileWindow: FertileWindow(start: null, end: null, peakDay: null),
  );

  Future<void> pumpCalendar(
    WidgetTester tester, {
    required List<CycleLog> logs,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CycleCalendar(
              logs: logs,
              month: DateTime(2026, 8),
              summary: summary,
              onDateSelected: (_) {},
              showHijri: false,
              onCalendarModeChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  CycleLog log({
    required String date,
    required FlowLevel flow,
    CycleEntryProvenance provenance = CycleEntryProvenance.userObserved,
  }) => CycleLog(
    id: 'log-$date',
    userId: 'user-1',
    date: DateTime.parse(date),
    flow: flow,
    dataProvenance: provenance,
  );

  testWidgets(
    'a legacy, provenance-less day is announced distinctly from a real '
    'observed day, via the same shared taxonomy every other surface uses',
    (tester) async {
      await pumpCalendar(
        tester,
        logs: [
          log(date: '2026-08-20', flow: FlowLevel.medium),
          log(
            date: '2026-08-25',
            flow: FlowLevel.medium,
            provenance: CycleEntryProvenance.legacyUnverified,
          ),
        ],
      );

      final observedSemantics = tester.getSemantics(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.label != null &&
              w.properties.label!.startsWith('20,'),
        ),
      );
      expect(observedSemantics.label, isNot(contains('legacy')));
      expect(observedSemantics.label, isNot(contains('قديمة')));

      final legacySemantics = tester.getSemantics(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.label != null &&
              w.properties.label!.startsWith('25,'),
        ),
      );
      expect(
        legacySemantics.label,
        contains('source was not recorded'),
        reason:
            'a legacy row with no recorded provenance must be honestly '
            'disclosed as such, never silently indistinguishable from a '
            'real observed day',
      );
    },
  );

  testWidgets('no legacy rows at all: no day is ever flagged as legacy', (
    tester,
  ) async {
    await pumpCalendar(
      tester,
      logs: [log(date: '2026-08-20', flow: FlowLevel.medium)],
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Arabic: the legacy disclosure is announced in Arabic, not English, '
    'matching this same fix\'s own localization requirement',
    (tester) async {
      AppLocaleController.instance.setArabic(true);
      await pumpCalendar(
        tester,
        logs: [
          log(
            date: '2026-08-25',
            flow: FlowLevel.medium,
            provenance: CycleEntryProvenance.legacyUnverified,
          ),
        ],
      );

      final legacySemantics = tester.getSemantics(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.label != null &&
              w.properties.label!.startsWith('25,'),
        ),
      );
      expect(legacySemantics.label, contains('لم تُسجَّل مصادرها'));
      AppLocaleController.instance.setArabic(false);
    },
  );
}
