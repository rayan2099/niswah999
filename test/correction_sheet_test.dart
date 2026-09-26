import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/features/cycle_tracking/presentation/widgets/correction_sheet.dart';

import 'support/device_timezone_test_support.dart';
import 'support/secure_storage_test_support.dart';

/// Menstrual Data Integrity charter, Commits D5/D6/D7 — mirrors
/// start_bleeding_sheet_test.dart's own established scope: a real
/// Supabase session (and therefore the real correct_observation RPC,
/// including its D7 conflict detection) cannot be exercised in a plain
/// widget test — that was verified directly against a real local
/// Postgres reconstruction (see the migration's own commit message).
/// What a widget test legitimately covers: the sheet renders the current
/// value pre-selected, offers every flow option, and reports an honest
/// failure with no session rather than a false success or a crash.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSecureLocalStoreForTest();
    mockDeviceTimezoneForTest();
    AppLocaleController.instance.setArabic(false);
  });

  final target = BleedingObservation(
    id: 'obs-1',
    userId: 'user-1',
    episodeId: 'episode-1',
    observedDate: DateTime(2026, 9, 10),
    precision: ObservationPrecision.dateOnly,
    flow: ObservationFlow.medium,
    source: ObservationSource.userObserved,
    utcOffsetMinutes: 180,
  );

  Future<void> pumpCorrectionSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () =>
                showCorrectObservationSheet(context, target: target),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'renders with the current flow pre-selected and every option offered',
    (tester) async {
      await pumpCorrectionSheet(tester);

      expect(find.text('Correct this entry'), findsOneWidget);
      expect(find.text('Spotting'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Medium'), findsOneWidget);
      expect(find.text('Heavy'), findsOneWidget);
      expect(find.text("I'm not sure"), findsOneWidget);

      final selectedChip = tester.widget<ChoiceChip>(
        find.ancestor(
          of: find.text('Medium'),
          matching: find.byType(ChoiceChip),
        ),
      );
      expect(
        selectedChip.selected,
        isTrue,
        reason:
            'the observation being corrected already has a flow — the '
            'sheet must show it as the honest starting point, never blank',
      );
    },
  );

  testWidgets('Closure Blocker 12: with no Supabase session, Save reports the '
      'honest "saved on device, syncing" state rather than a false '
      '"could not save" (the correction was already persisted to the '
      'pending outbox before the RPC was ever attempted) or a crash', (
    tester,
  ) async {
    await pumpCorrectionSheet(tester);

    await tester.tap(find.text('Light'));
    await tester.pump();
    await tester.tap(find.text('Save correction'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    expect(find.text('Saved on device — syncing.'), findsOneWidget);
    // The sheet must still be open (not popped as if fully synced).
    expect(find.text('Correct this entry'), findsOneWidget);
  });

  testWidgets('Arabic: the sheet renders RTL with the Arabic labels', (
    tester,
  ) async {
    AppLocaleController.instance.setArabic(true);
    await pumpCorrectionSheet(tester);

    expect(find.text('تصحيح هذا الإدخال'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Directionality &&
            widget.textDirection == TextDirection.rtl,
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
    AppLocaleController.instance.setArabic(false);
  });
}
