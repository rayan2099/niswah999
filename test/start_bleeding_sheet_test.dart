import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/features/cycle_tracking/presentation/widgets/start_bleeding_sheet.dart';

import 'support/device_timezone_test_support.dart';
import 'support/secure_storage_test_support.dart';

/// Menstrual Data Integrity charter, Commit D: the "Start Bleeding" /
/// "Bleeding stopped" sheets ask only the two factual questions Section 6
/// requires — never a Fiqh conclusion, never a forced/assumed flow. A real
/// Supabase session cannot be simulated in a plain widget test, so this
/// covers what a widget test legitimately can: the sheet's own gating
/// (Save disabled until both questions are answered) and its honest
/// failure path when there is no session to save against — the
/// `start_bleeding_episode` RPC's own atomicity/idempotency was verified
/// directly against a real local Postgres reconstruction (see the
/// migration's commit message), which a widget test cannot exercise.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // PR #4 completion wave, Fix D: the sheets now persist a pending
    // operation via SecureLocalStore before every RPC attempt — without
    // this, that call hits a real platform channel that doesn't exist
    // under flutter_test, and every test below hangs indefinitely rather
    // than failing fast.
    resetSecureLocalStoreForTest();
    // Fix B: DeviceTimezone.currentId() call — same reasoning, a
    // different channel (flutter_timezone has no test double of its own).
    mockDeviceTimezoneForTest();
    AppLocaleController.instance.setArabic(false);
  });

  Future<void> pumpStartSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showStartBleedingSheet(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Save stays disabled until both a start date and a flow are chosen',
    (tester) async {
      await pumpStartSheet(tester);

      expect(find.text('When did it start?'), findsOneWidget);
      expect(find.text('How is the bleeding right now?'), findsOneWidget);

      final saveButtonFinder = find.ancestor(
        of: find.text('Save'),
        matching: find.byType(FilledButton),
      );
      expect(
        tester.widget<FilledButton>(saveButtonFinder).onPressed,
        isNull,
        reason: 'nothing has been answered yet — Save must not be assumed',
      );

      await tester.tap(find.text('Today'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(saveButtonFinder).onPressed,
        isNull,
        reason: 'a start date alone is not enough — flow is still unanswered',
      );

      await tester.tap(find.text('Medium'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(saveButtonFinder).onPressed,
        isNotNull,
        reason: 'both factual questions are now answered',
      );
    },
  );

  testWidgets(
    "\"I'm not sure\" is a real, selectable answer for the flow question",
    (tester) async {
      await pumpStartSheet(tester);

      await tester.tap(find.text('Today'));
      await tester.tap(find.text("I'm not sure"));
      await tester.pump();

      final saveButtonFinder = find.ancestor(
        of: find.text('Save'),
        matching: find.byType(FilledButton),
      );
      expect(
        tester.widget<FilledButton>(saveButtonFinder).onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('Closure Blocker 12: with no Supabase session, Save reports the '
      'honest "saved on device, syncing" state rather than a false '
      '"could not save" or a crash', (tester) async {
    await pumpStartSheet(tester);

    await tester.tap(find.text('Today'));
    await tester.tap(find.text('Medium'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    expect(
      find.text('Saved on device — syncing.'),
      findsOneWidget,
      reason:
          'the operation was already persisted to the pending outbox '
          'before the RPC was ever attempted — a failed RPC here must '
          'say so honestly, never claim data was lost nor throw an '
          'unhandled exception',
    );
    // The sheet must still be open (not popped as if fully synced).
    expect(find.text('Bleeding started'), findsOneWidget);
  });

  testWidgets('Arabic: the sheet renders RTL with the Arabic questions', (
    tester,
  ) async {
    AppLocaleController.instance.setArabic(true);
    await pumpStartSheet(tester);

    expect(find.text('متى بدأ؟'), findsOneWidget);
    expect(find.text('كيف حال النزيف الآن؟'), findsOneWidget);
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

  testWidgets(
    'showEndBleedingSheet: the "Yesterday" chip is disabled (not merely '
    'hidden) when yesterday precedes the episode\'s own start date '
    '(PR #4 hardening, Blocker 11)',
    (tester) async {
      final episodeStart = DateTime.now();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showEndBleedingSheet(
                context,
                episodeId: 'episode-1',
                episodeStartDate: episodeStart,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final yesterdayChipFinder = find.ancestor(
        of: find.text('Yesterday'),
        matching: find.byType(ChoiceChip),
      );
      final chip = tester.widget<ChoiceChip>(yesterdayChipFinder);
      expect(
        chip.onSelected,
        isNull,
        reason:
            'the episode started today, so "yesterday" is not a reachable '
            'end date — the picker must not offer it as tappable',
      );
    },
  );

  testWidgets(
    'Closure Blocker 12: showEndBleedingSheet with no Supabase session, '
    'Save reports the honest "saved on device, syncing" state',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showEndBleedingSheet(
                context,
                episodeId: 'episode-1',
                episodeStartDate: DateTime.now().subtract(
                  const Duration(days: 3),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('When did it stop?'), findsOneWidget);
      await tester.tap(find.text('Today'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
      expect(find.text('Saved on device — syncing.'), findsOneWidget);
    },
  );
}
