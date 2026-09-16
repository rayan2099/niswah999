// Madhhab Resolution Gate wave (2026-09-16), completing AUTH-010's original
// "I don't know my Madhhab" assistance behavior. Covers: the canonical
// Log-my-Haidh entry gate (SELECTED/UNSET/UNKNOWN), direct selection,
// guided selection (single/multiple/insufficient-evidence candidates, the
// upbringing-outranks-family signal hierarchy, residence never sufficient
// alone), "still not sure," Settings' reuse of the same resolver, and
// account-switch isolation.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/preferences/madhhab_controller.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart'
    show Madhhab;
import 'package:niswah/features/cycle_tracking/presentation/viewmodels/cycle_tracking_view_model.dart';
import 'package:niswah/features/cycle_tracking/presentation/widgets/cycle_log_form_sheet.dart';
import 'package:niswah/features/madhhab_resolution/presentation/madhhab_resolution_screen.dart';

Widget _harness(Widget Function(BuildContext) builder) => MaterialApp(
  home: Scaffold(body: Builder(builder: builder)),
);

Future<void> _openResolver(
  WidgetTester tester, {
  MadhhabResolutionStart start = MadhhabResolutionStart.intro,
}) async {
  await tester.pumpWidget(
    _harness(
      (context) => ElevatedButton(
        onPressed: () => showMadhhabResolutionFlow(
          context,
          entryContext: MadhhabResolutionContext.haidhLogging,
          start: start,
        ),
        child: const Text('open'),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLocaleController.instance.setArabic(false);
    MadhhabResolutionScreen.lastConfirmedSelectionSource = null;
  });

  tearDown(() async {
    await MadhhabController.instance.selectMadhhab(Madhhab.hanafi);
  });

  group('Log-my-Haidh entry gate (Section 1/14)', () {
    testWidgets('SELECTED user: tap Log my Haidh opens the logger directly', (
      tester,
    ) async {
      await MadhhabController.instance.selectMadhhab(Madhhab.shafii);
      final viewModel = CycleTrackingViewModel(
        repository: CycleTrackingRepositoryImpl(),
      );
      await tester.pumpWidget(
        _harness(
          (context) => ElevatedButton(
            onPressed: () => showCycleLogSheet(context, viewModel: viewModel),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('What is your Fiqh Madhhab?'), findsNothing);
      expect(find.text('Flow intensity'), findsOneWidget);
    });

    testWidgets('UNSET user: tap Log my Haidh opens the resolver first', (
      tester,
    ) async {
      await MadhhabController.instance
          .load(); // fresh SharedPreferences -> unset
      final viewModel = CycleTrackingViewModel(
        repository: CycleTrackingRepositoryImpl(),
      );
      await tester.pumpWidget(
        _harness(
          (context) => ElevatedButton(
            onPressed: () => showCycleLogSheet(context, viewModel: viewModel),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Before logging your Haidh'), findsOneWidget);
      expect(find.text('Flow intensity'), findsNothing);
    });

    testWidgets('UNKNOWN user: tap Log my Haidh opens the resolver first', (
      tester,
    ) async {
      await MadhhabController.instance.selectUnknown();
      final viewModel = CycleTrackingViewModel(
        repository: CycleTrackingRepositoryImpl(),
      );
      await tester.pumpWidget(
        _harness(
          (context) => ElevatedButton(
            onPressed: () => showCycleLogSheet(context, viewModel: viewModel),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Before logging your Haidh'), findsOneWidget);
      expect(find.text('Flow intensity'), findsNothing);
    });

    testWidgets(
      'symptomsOnly mode is never gated — raw wellbeing logging stays reachable while UNKNOWN',
      (tester) async {
        await MadhhabController.instance.selectUnknown();
        final viewModel = CycleTrackingViewModel(
          repository: CycleTrackingRepositoryImpl(),
        );
        await tester.pumpWidget(
          _harness(
            (context) => ElevatedButton(
              onPressed: () => showCycleLogSheet(
                context,
                viewModel: viewModel,
                mode: CycleLogSheetMode.symptomsOnly,
              ),
              child: const Text('open'),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(find.text('Before logging your Haidh'), findsNothing);
      },
    );
  });

  group('Direct selection (Section 3)', () {
    testWidgets(
      'choose Shafi\'i -> confirm -> server state becomes SELECTED/Shafi\'i',
      (tester) async {
        await MadhhabController.instance.load();
        await _openResolver(tester);

        await tester.tap(find.text('I know my Madhhab'));
        await tester.pumpAndSettle();
        await tester.tap(find.text("Shafi'i"));
        await tester.pumpAndSettle();

        expect(
          find.text("Use the Shafi'i school in Niswah's rulings?"),
          findsOneWidget,
        );
        await tester.tap(find.text("Yes, use Shafi'i"));
        await tester.pumpAndSettle();

        expect(
          MadhhabController.instance.state,
          MadhhabSelectionState.selected,
        );
        expect(MadhhabController.instance.selectedOrNull, Madhhab.shafii);
        expect(
          MadhhabResolutionScreen.lastConfirmedSelectionSource,
          'direct',
          reason: 'a manual pick from the 4-school list must be tagged direct',
        );
      },
    );
  });

  group('Guided selection (Sections 4-13)', () {
    testWidgets(
      'single-candidate country (Saudi Arabia -> Hanbali): suggestion alone '
      'does not persist; explicit confirmation does',
      (tester) async {
        await MadhhabController.instance.load();
        await _openResolver(tester);

        await tester.tap(find.text("I don't know — help me"));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Saudi Arabia');
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ListTile, 'Saudi Arabia'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Hanbali school may be closest'),
          findsOneWidget,
        );
        expect(
          MadhhabController.instance.state,
          isNot(MadhhabSelectionState.selected),
          reason: 'a displayed suggestion must never itself persist',
        );

        await tester.tap(find.text('Yes, use Hanbali'));
        await tester.pumpAndSettle();

        expect(
          MadhhabController.instance.state,
          MadhhabSelectionState.selected,
        );
        expect(MadhhabController.instance.selectedOrNull, Madhhab.hanbali);
        expect(
          MadhhabResolutionScreen.lastConfirmedSelectionSource,
          'suggested_confirmed',
          reason: 'an explicitly-confirmed suggestion must be tagged suggested_confirmed, never direct',
        );
      },
    );

    testWidgets(
      'multi-candidate country (Egypt): shown as options, none auto-selected',
      (tester) async {
        await MadhhabController.instance.load();
        await _openResolver(tester);

        await tester.tap(find.text("I don't know — help me"));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Egypt');
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ListTile, 'Egypt'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'More than one school is common in the environment you described.',
          ),
          findsOneWidget,
        );
        expect(
          MadhhabController.instance.state,
          isNot(MadhhabSelectionState.selected),
          reason: 'multiple candidates must never auto-select a winner',
        );

        await tester.tap(find.text('Maliki'));
        await tester.pumpAndSettle();

        expect(MadhhabController.instance.selectedOrNull, Madhhab.maliki);
        expect(
          MadhhabResolutionScreen.lastConfirmedSelectionSource,
          'suggested_confirmed',
        );
      },
    );

    testWidgets(
      'unsupported country: insufficient evidence, no arbitrary Madhhab assigned',
      (tester) async {
        await MadhhabController.instance.load();
        await _openResolver(tester);

        await tester.tap(find.text("I don't know — help me"));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Japan');
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ListTile, 'Japan'));
        await tester.pumpAndSettle();
        // Q2 (family/community) — also answer with an unsupported country.
        await tester.enterText(find.byType(TextField), 'Japan');
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ListTile, 'Japan'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining("isn't enough for a confident"),
          findsOneWidget,
        );
        expect(MadhhabController.instance.selectedOrNull, isNull);
      },
    );

    testWidgets('Canada case: residence alone never assigns a Madhhab', (
      tester,
    ) async {
      await MadhhabController.instance.load();
      await _openResolver(tester);

      await tester.tap(find.text("I don't know — help me"));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Canada');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Canada'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Canada');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Canada'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining("isn't enough for a confident"),
        findsOneWidget,
        reason:
            'Canada is not in the reviewed mapping — must never '
            'produce a guessed suggestion',
      );
      expect(MadhhabController.instance.selectedOrNull, isNull);
    });

    testWidgets(
      'conflicting signals: upbringing (unresolved) then family (Egypt) — '
      'family signal used only because upbringing did not resolve',
      (tester) async {
        await MadhhabController.instance.load();
        await _openResolver(tester);

        await tester.tap(find.text("I don't know — help me"));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Canada');
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ListTile, 'Canada'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Egypt');
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ListTile, 'Egypt'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'More than one school is common in the environment you described.',
          ),
          findsOneWidget,
          reason:
              "Egypt's own multi-candidate result must surface once "
              'Canada (upbringing) failed to resolve',
        );
      },
    );

    testWidgets('still not sure: retains UNKNOWN, never persists a Madhhab', (
      tester,
    ) async {
      await MadhhabController.instance.load();
      await _openResolver(tester);

      await tester.tap(find.text("I don't know — help me"));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Japan');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Japan'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Japan');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Japan'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose manually'));
      await tester.pumpAndSettle();
      // Back out of the manual picker to reach "Still not sure" instead.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Still not sure'));
      await tester.pumpAndSettle();

      expect(MadhhabController.instance.state, MadhhabSelectionState.unknown);
      expect(MadhhabController.instance.selectedOrNull, isNull);
    });
  });

  group('Settings reuses the same canonical resolver (Section 16)', () {
    testWidgets('"help me choose" starts directly at the guided question', (
      tester,
    ) async {
      await MadhhabController.instance.load();
      await _openResolver(tester, start: MadhhabResolutionStart.guided);

      expect(find.text('Before logging your Haidh'), findsNothing);
      expect(
        find.text('Where did you learn most of your religious practice?'),
        findsOneWidget,
      );
    });

    testWidgets('"choose Madhhab" starts directly at the school list', (
      tester,
    ) async {
      await MadhhabController.instance.load();
      await _openResolver(tester, start: MadhhabResolutionStart.knownPicker);

      expect(find.text('What is your Fiqh Madhhab?'), findsOneWidget);
    });
  });

  group('Account isolation (Section 21: account-switch)', () {
    testWidgets("User A's selection cannot affect User B's UNKNOWN state", (
      tester,
    ) async {
      await MadhhabController.instance.selectMadhhab(Madhhab.hanafi);
      expect(MadhhabController.instance.isSelected, isTrue);

      // Simulates AuthController's own sign-out handling (resetInMemory).
      MadhhabController.instance.resetInMemory();
      expect(MadhhabController.instance.isSelected, isFalse);
      expect(MadhhabController.instance.state, MadhhabSelectionState.unset);
    });
  });

  group('Arabic / RTL (Section 22)', () {
    testWidgets('intro screen renders Arabic copy', (tester) async {
      AppLocaleController.instance.setArabic(true);
      await MadhhabController.instance.load();
      await _openResolver(tester);

      expect(find.text('قبل تسجيل حيضك'), findsOneWidget);
      expect(find.text('أعرف مذهبي'), findsOneWidget);
      expect(find.text('لا أعرف مذهبي — ساعديني'), findsOneWidget);
      AppLocaleController.instance.setArabic(false);
    });

    testWidgets('known-picker and confirm screens render Arabic copy', (
      tester,
    ) async {
      AppLocaleController.instance.setArabic(true);
      await MadhhabController.instance.load();
      await _openResolver(tester);

      await tester.tap(find.text('أعرف مذهبي'));
      await tester.pumpAndSettle();
      for (final label in ['حنفي', 'مالكي', 'شافعي', 'حنبلي']) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('حنبلي'));
      await tester.pumpAndSettle();
      expect(
        find.text('هل تريدين استخدام المذهب الحنبلي في أحكام نسوة؟'),
        findsOneWidget,
      );
      AppLocaleController.instance.setArabic(false);
    });
  });

  group('Accessibility (Section 22)', () {
    testWidgets('no overflow at 200% text scale', (tester) async {
      await MadhhabController.instance.load();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2.0)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showMadhhabResolutionFlow(
                  context,
                  entryContext: MadhhabResolutionContext.settings,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('I know my Madhhab'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('usable at a small viewport (320x568)', (tester) async {
      await MadhhabController.instance.load();
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _openResolver(tester, start: MadhhabResolutionStart.guided);
      expect(tester.takeException(), isNull);

      await tester.enterText(find.byType(TextField), 'a');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the searchable country field filters as you type', (
      tester,
    ) async {
      await MadhhabController.instance.load();
      await _openResolver(tester, start: MadhhabResolutionStart.guided);

      // The unfiltered list has ~195 entries — ListView.builder only
      // actually builds what's near the visible viewport, so this checks
      // the filtered-down result (the real point of this test) rather
      // than asserting on the huge unfiltered list's lazy-build state.
      await tester.enterText(find.byType(TextField), 'egy');
      await tester.pumpAndSettle();
      expect(find.text('Egypt'), findsOneWidget);
      expect(find.text('Jordan'), findsNothing);
    });
  });
}
