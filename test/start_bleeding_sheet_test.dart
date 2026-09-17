import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/features/cycle_tracking/presentation/widgets/start_bleeding_sheet.dart';

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

  testWidgets(
    'with no Supabase session, Save reports an honest failure rather than '
    'a false success or a crash',
    (tester) async {
      await pumpStartSheet(tester);

      await tester.tap(find.text('Today'));
      await tester.tap(find.text('Medium'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
      expect(
        find.text('Could not save. Please try again.'),
        findsOneWidget,
        reason:
            'a failed save must say so honestly, never silently succeed '
            'or throw an unhandled exception',
      );
      // The sheet must still be open (not popped as if it had succeeded).
      expect(find.text('Bleeding started'), findsOneWidget);
    },
  );

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

  testWidgets('showEndBleedingSheet: with no Supabase session, Save reports an '
      'honest failure', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () =>
                showEndBleedingSheet(context, episodeId: 'episode-1'),
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
    expect(find.text('Could not save. Please try again.'), findsOneWidget);
  });
}
