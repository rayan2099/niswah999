import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/presentation/widgets/start_bleeding_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/device_timezone_test_support.dart';
import 'support/secure_storage_test_support.dart';

/// Regression for Persona F's reconnect finding: after an offline save was
/// replayed by the background reconcile, a still-open "Saved on device —
/// syncing." sheet stayed stale and Today never refreshed. The reconcile
/// now announces completion; a sheet that was queued offline closes as a
/// success once its own operation is no longer pending, and a sheet that
/// never queued anything ignores the signal.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSecureLocalStoreForTest();
    mockDeviceTimezoneForTest();
    AppLocaleController.instance.setArabic(false);
  });

  final results = <bool?>[];

  Future<void> pumpAndOpen(WidgetTester tester) async {
    results.clear();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              results.add(await showStartBleedingSheet(context));
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a sheet queued offline closes as a success when the '
      'background reconcile finishes', (tester) async {
    await pumpAndOpen(tester);

    await tester.tap(find.text('Today'));
    await tester.tap(find.text('Medium'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    // No session here: the save cannot reach a server, so it is queued.
    expect(find.text('Saved on device — syncing.'), findsOneWidget);

    BleedingEpisodeRepositoryImpl.reconcileCompletions.value++;
    await tester.pumpAndSettle();

    expect(find.text('When did it start?'), findsNothing);
    expect(results, [true]);
  });

  testWidgets('a sheet that has queued nothing ignores the signal', (
    tester,
  ) async {
    await pumpAndOpen(tester);
    expect(find.text('When did it start?'), findsOneWidget);

    BleedingEpisodeRepositoryImpl.reconcileCompletions.value++;
    await tester.pumpAndSettle();

    expect(find.text('When did it start?'), findsOneWidget);
  });
}
