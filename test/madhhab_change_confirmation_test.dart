// Requirement 2: a Madhhab change must warn before replacing an existing
// interpretation, must never silently mix Madhhabs, and must never touch
// raw observations. Covers setMadhhabWithConfirmation's own decision of
// when the warning dialog fires, and that Cancel truly leaves the
// previous selection untouched.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/preferences/madhhab_controller.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart'
    show Madhhab;
import 'package:niswah/features/madhhab/presentation/widgets/madhhab_change_confirmation.dart';

Widget _harness(Widget Function(BuildContext) builder) => MaterialApp(
  home: Scaffold(body: Builder(builder: builder)),
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppLocaleController.instance.setArabic(false);
    await MadhhabController.instance.load();
  });

  testWidgets('a first-ever selection (from unset) shows no warning dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        (context) => ElevatedButton(
          onPressed: () => setMadhhabWithConfirmation(
            context,
            newMadhhab: Madhhab.hanafi,
            source: 'test',
          ),
          child: const Text('select'),
        ),
      ),
    );
    await tester.tap(find.text('select'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm change'), findsNothing);
    expect(MadhhabController.instance.state, MadhhabSelectionState.selected);
    expect(MadhhabController.instance.selectedOrNull, Madhhab.hanafi);
  });

  testWidgets(
    'replacing an existing selection with a different madhhab shows the '
    'warning dialog with the literal task copy',
    (tester) async {
      await MadhhabController.instance.selectMadhhab(Madhhab.hanafi);

      await tester.pumpWidget(
        _harness(
          (context) => ElevatedButton(
            onPressed: () => setMadhhabWithConfirmation(
              context,
              newMadhhab: Madhhab.shafii,
              source: 'test',
            ),
            child: const Text('select'),
          ),
        ),
      );
      await tester.tap(find.text('select'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Changing your Madhhab may change the Fiqh interpretation of '
          'some previously recorded days. Your original records will '
          'not be changed. Niswah will recalculate the relevant Fiqh '
          'results according to your new Madhhab.',
        ),
        findsOneWidget,
      );
      expect(find.text('Confirm change'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      // Not persisted yet — only an explicit Confirm does that.
      expect(MadhhabController.instance.selectedOrNull, Madhhab.hanafi);
    },
  );

  testWidgets(
    'Cancel on the warning dialog leaves the previous madhhab completely '
    'unchanged',
    (tester) async {
      await MadhhabController.instance.selectMadhhab(Madhhab.hanafi);

      await tester.pumpWidget(
        _harness(
          (context) => ElevatedButton(
            onPressed: () => setMadhhabWithConfirmation(
              context,
              newMadhhab: Madhhab.shafii,
              source: 'test',
            ),
            child: const Text('select'),
          ),
        ),
      );
      await tester.tap(find.text('select'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(MadhhabController.instance.selectedOrNull, Madhhab.hanafi);
      expect(MadhhabController.instance.state, MadhhabSelectionState.selected);
    },
  );

  testWidgets(
    'Confirm on the warning dialog persists the new madhhab, never mixing '
    'the old and new values',
    (tester) async {
      await MadhhabController.instance.selectMadhhab(Madhhab.hanafi);

      await tester.pumpWidget(
        _harness(
          (context) => ElevatedButton(
            onPressed: () => setMadhhabWithConfirmation(
              context,
              newMadhhab: Madhhab.shafii,
              source: 'test',
            ),
            child: const Text('select'),
          ),
        ),
      );
      await tester.tap(find.text('select'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm change'));
      await tester.pumpAndSettle();

      expect(MadhhabController.instance.selectedOrNull, Madhhab.shafii);
      expect(MadhhabController.instance.state, MadhhabSelectionState.selected);
    },
  );

  testWidgets(
    'selected -> "I don\'t know" shows the warning dialog too (withdrawing '
    'an existing interpretation)',
    (tester) async {
      await MadhhabController.instance.selectMadhhab(Madhhab.hanbali);

      await tester.pumpWidget(
        _harness(
          (context) => ElevatedButton(
            onPressed: () => setMadhhabWithConfirmation(
              context,
              newMadhhab: null,
              source: 'test',
            ),
            child: const Text('select'),
          ),
        ),
      );
      await tester.tap(find.text('select'));
      await tester.pumpAndSettle();

      expect(find.text('Confirm change'), findsOneWidget);
      await tester.tap(find.text('Confirm change'));
      await tester.pumpAndSettle();

      expect(MadhhabController.instance.state, MadhhabSelectionState.unknown);
      expect(MadhhabController.instance.selectedOrNull, isNull);
    },
  );

  testWidgets(
    '"I don\'t know" -> a real madhhab shows the LIGHT notice (not the '
    'full warning) — no prior interpretation existed to "change," but '
    'her historical observations are about to be interpreted for the '
    'first time, which still deserves a heads-up',
    (tester) async {
      await MadhhabController.instance.selectUnknown();

      await tester.pumpWidget(
        _harness(
          (context) => ElevatedButton(
            onPressed: () => setMadhhabWithConfirmation(
              context,
              newMadhhab: Madhhab.maliki,
              source: 'test',
            ),
            child: const Text('select'),
          ),
        ),
      );
      await tester.tap(find.text('select'));
      await tester.pumpAndSettle();

      // The light notice, not the full warning.
      expect(find.text('Confirm change'), findsNothing);
      expect(
        find.text(
          'Niswah will now interpret your previous records according to '
          'the Madhhab you selected. Your original entries will not be '
          'changed.',
        ),
        findsOneWidget,
      );
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(
        MadhhabController.instance.selectedOrNull,
        isNull,
        reason: 'not persisted until Continue is explicitly tapped',
      );

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(MadhhabController.instance.selectedOrNull, Madhhab.maliki);
    },
  );

  testWidgets('Cancel on the light notice leaves the UNKNOWN state completely '
      'unchanged', (tester) async {
    await MadhhabController.instance.selectUnknown();

    await tester.pumpWidget(
      _harness(
        (context) => ElevatedButton(
          onPressed: () => setMadhhabWithConfirmation(
            context,
            newMadhhab: Madhhab.maliki,
            source: 'test',
          ),
          child: const Text('select'),
        ),
      ),
    );
    await tester.tap(find.text('select'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(MadhhabController.instance.state, MadhhabSelectionState.unknown);
    expect(MadhhabController.instance.selectedOrNull, isNull);
  });

  testWidgets(
    'selected A -> selected A (same value) is a true no-op: no dialog of '
    'either kind, no history write, no notifyListeners-triggered rebuild '
    'signal beyond what was already there',
    (tester) async {
      await MadhhabController.instance.selectMadhhab(Madhhab.hanafi);
      var notifyCount = 0;
      void listener() => notifyCount++;
      MadhhabController.instance.addListener(listener);

      await tester.pumpWidget(
        _harness(
          (context) => ElevatedButton(
            onPressed: () => setMadhhabWithConfirmation(
              context,
              newMadhhab: Madhhab.hanafi,
              source: 'test',
            ),
            child: const Text('select'),
          ),
        ),
      );
      await tester.tap(find.text('select'));
      await tester.pumpAndSettle();

      expect(find.text('Confirm change'), findsNothing);
      expect(find.text('Continue'), findsNothing);
      expect(
        notifyCount,
        0,
        reason: 'a true no-op never calls notifyListeners',
      );
      expect(MadhhabController.instance.selectedOrNull, Madhhab.hanafi);

      MadhhabController.instance.removeListener(listener);
    },
  );
}
