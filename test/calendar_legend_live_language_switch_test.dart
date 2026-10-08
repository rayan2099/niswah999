import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/utils/app_clock.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/presentation/widgets/cycle_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Found live in the Arabic persona: after switching the language from
/// Profile, the calendar legend chips (Haid / Expected Haid / Tahara) stayed
/// English until an app restart, because they were `const` widgets that a
/// parent rebuild skips. A live switch must update them.
void main() {
  const summary = CycleTrackingSummary(
    averageCycleLength: null,
    averagePeriodLength: null,
    lastCycleStart: null,
    currentPhase: CyclePhase.follicular,
    fertileWindow: FertileWindow(start: null, end: null, peakDay: null),
  );

  Widget tree() => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: CycleCalendar(
          logs: const [],
          month: DateTime(2026, 8),
          summary: summary,
          onDateSelected: (_) {},
          showHijri: false,
          onCalendarModeChanged: (_) {},
        ),
      ),
    ),
  );

  testWidgets('legend follows a live language switch', (tester) async {
    SharedPreferences.setMockInitialValues({});
    AppClock.now = () => DateTime(2026, 8, 18, 12);
    AppLocaleController.instance.setArabic(false);
    await tester.pumpWidget(tree());
    await tester.pumpAndSettle();
    expect(find.text('Haid'), findsWidgets);
    expect(find.text('Tahara'), findsOneWidget);

    AppLocaleController.instance.setArabic(true);
    await tester.pumpWidget(tree()); // the parent rebuilds after the switch
    await tester.pumpAndSettle();
    expect(find.text('Tahara'), findsNothing);
    expect(find.text('Expected Haid'), findsNothing);
    expect(find.text('طهارة'), findsWidgets);
    expect(find.text('حيض متوقع'), findsOneWidget);
    AppLocaleController.instance.setArabic(false);
  });
}
