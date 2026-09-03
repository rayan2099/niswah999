import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/presentation/screens/cycle_tracking_screen.dart';
import 'package:niswah/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:niswah/features/insights/presentation/screens/insights_screen.dart';

import 'support/parity_test_harness.dart';

void main() {
  testWidgets(
    'Today, Calendar, and Insights share one CycleTrackingViewModel '
    'instance, so a log saved on one tab is reflected on the others '
    'without needing an app restart',
    (tester) async {
      await ParityTestHarness.pump(tester, arabic: false);

      // The other four tabs stay mounted inside an IndexedStack even while
      // only "Today" is showing, but IndexedStack only *paints* the active
      // child — the rest read as "offstage" to the default finder, so it
      // has to be told to look anyway.
      final dashboardViewModel = tester
          .widget<DashboardScreen>(
            find.byType(DashboardScreen, skipOffstage: false),
          )
          .viewModel;
      final calendarViewModel = tester
          .widget<CycleTrackingScreen>(
            find.byType(CycleTrackingScreen, skipOffstage: false),
          )
          .viewModel;
      final insightsViewModel = tester
          .widget<InsightsScreen>(
            find.byType(InsightsScreen, skipOffstage: false),
          )
          .viewModel;

      expect(dashboardViewModel, isNotNull);
      expect(identical(dashboardViewModel, calendarViewModel), isTrue);
      expect(identical(dashboardViewModel, insightsViewModel), isTrue);
    },
  );
}
