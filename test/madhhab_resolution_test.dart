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
import 'package:niswah/features/madhhab_resolution/presentation/widgets/madhhab_resolution_flow.dart';
import 'package:niswah/features/onboarding/domain/services/madhhab_suggestion_service.dart';

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

/// Walks "I don't know — help me" through the shared flow's country
/// question, opens the modal picker, searches, and taps the match.
Future<void> pickUpbringingCountry(
  WidgetTester tester,
  String query,
  String matchText,
) async {
  await tester.tap(find.text("I don't know — help me"));
  await tester.pumpAndSettle();
  expect(
    find.text(
      'Which country did you grow up in for most of your childhood?',
    ),
    findsOneWidget,
    reason:
        'the old "Where did you learn most of your religious '
        'practice?" / two-question chip flow must be gone — this is '
        'the exact same upbringing-country question onboarding asks',
  );
  await tester.tap(find.text('Select country'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), query);
  await tester.pump();
  await tester.tap(find.widgetWithText(ListTile, matchText));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Continue'));
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

  group(
    'Canonical confirmation routing (final-review fix, 2026-10-15)',
    () {
      // Prior defect: _confirmSelection/_stillNotSure called
      // MadhhabController directly, bypassing setMadhhabWithConfirmation
      // entirely, so the light first-Fiqh-interpretation notice never
      // fired on a genuine unknown -> selected pick reached through this
      // screen. Both now route through setMadhhabWithConfirmation, which
      // is the only place that decides which dialog (if any) applies.
      testWidgets(
        'genuine UNKNOWN -> selected via the known-picker shows the light '
        'notice (not just this screen\'s own "use this school?" step), '
        'and Continue persists the selection and closes the screen',
        (tester) async {
          await MadhhabController.instance.selectUnknown();
          await _openResolver(tester);

          await tester.tap(find.text('I know my Madhhab'));
          await tester.pumpAndSettle();
          await tester.tap(find.text("Shafi'i"));
          await tester.pumpAndSettle();

          // This screen's own existing confirm step still appears first —
          // unrelated to, and not a substitute for, the canonical dialog.
          expect(
            find.text("Use the Shafi'i school in Niswah's rulings?"),
            findsOneWidget,
          );
          await tester.tap(find.text("Yes, use Shafi'i"));
          await tester.pumpAndSettle();

          // The canonical light notice now fires, because
          // setMadhhabWithConfirmation (not MadhhabController directly)
          // is what _confirmSelection calls.
          expect(
            find.textContaining('Niswah will now interpret your previous'),
            findsOneWidget,
          );
          expect(find.text('Continue'), findsOneWidget);

          await tester.tap(find.text('Continue'));
          await tester.pumpAndSettle();

          expect(
            MadhhabController.instance.state,
            MadhhabSelectionState.selected,
          );
          expect(MadhhabController.instance.selectedOrNull, Madhhab.shafii);
          expect(
            MadhhabResolutionScreen.lastConfirmedSelectionSource,
            'direct',
          );
          // The screen itself closed (popped) only after the canonical
          // operation actually succeeded.
          expect(find.byType(MadhhabResolutionScreen), findsNothing);
        },
      );

      testWidgets(
        'genuine UNKNOWN -> selected: cancelling the light notice persists '
        'nothing and leaves the resolution screen open',
        (tester) async {
          await MadhhabController.instance.selectUnknown();
          await _openResolver(tester);

          await tester.tap(find.text('I know my Madhhab'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Hanbali'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Yes, use Hanbali'));
          await tester.pumpAndSettle();

          expect(
            find.textContaining('Niswah will now interpret your previous'),
            findsOneWidget,
          );
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();

          // Nothing was persisted — state is exactly as it was before
          // this flow started.
          expect(
            MadhhabController.instance.state,
            MadhhabSelectionState.unknown,
          );
          expect(MadhhabController.instance.selectedOrNull, isNull);
          expect(MadhhabResolutionScreen.lastConfirmedSelectionSource, isNull);
          // The screen was never popped as though the selection succeeded —
          // cancelling a dialog must not be indistinguishable from success.
          // It also leaves her exactly where she was (this screen's own
          // confirm step for the school she tapped), to reconsider rather
          // than losing her place.
          expect(find.byType(MadhhabResolutionScreen), findsOneWidget);
          expect(
            find.text("Use the Hanbali school in Niswah's rulings?"),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'UNSET -> selected (via load(), no prior interpretation to '
        'reinterpret) still shows no canonical dialog beyond this '
        'screen\'s own confirm step — no regression from the fix',
        (tester) async {
          await MadhhabController.instance.load();
          await _openResolver(tester);

          await tester.tap(find.text('I know my Madhhab'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Maliki'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Yes, use Maliki'));
          await tester.pumpAndSettle();

          // No light notice, no full warning — setMadhhabWithConfirmation
          // applies the change immediately for unset -> selected.
          expect(
            find.textContaining('Niswah will now interpret your previous'),
            findsNothing,
          );
          expect(
            find.text('Changing your Madhhab may change the Fiqh'),
            findsNothing,
          );
          expect(
            MadhhabController.instance.state,
            MadhhabSelectionState.selected,
          );
          expect(MadhhabController.instance.selectedOrNull, Madhhab.maliki);
        },
      );

      testWidgets(
        '"still not sure" from a genuine UNKNOWN start remains a correct '
        'no-op (unset/unknown -> unknown never dialogs either)',
        (tester) async {
          await MadhhabController.instance.selectUnknown();
          await _openResolver(tester);

          await pickUpbringingCountry(tester, 'Japan', 'Japan');
          // Japan is unmapped, so this lands on the manual grid (Resolution-
          // flow unification wave, 2026-10-12) — its own "I don't know" tile
          // is this UI's equivalent of the old screen's "Still not sure".
          expect(find.text('Choose the Madhhab you follow'), findsOneWidget);
          await tester.tap(find.text("I don't know"));
          await tester.pumpAndSettle();

          expect(
            MadhhabController.instance.state,
            MadhhabSelectionState.unknown,
          );
          expect(MadhhabController.instance.selectedOrNull, isNull);
          expect(find.byType(MadhhabResolutionScreen), findsNothing);
        },
      );
    },
  );

  group('Guided selection — now the shared MadhhabResolutionFlow (manual '
      'QA wave, 2026-10-12)', () {
    testWidgets(
      // Knowledge-Base Source-Verification wave (2026-10-14): Saudi
      // Arabia's entry is now genuinely SOURCE_VERIFIED (a real,
      // directly-fetched US State Dept report explicitly ties Saudi
      // Arabia's legal system to the Hanbali school) — this replaces the
      // old "every country lands on manual selection because nothing is
      // reviewed" test, since that premise is no longer true for this
      // specific country. The old dead-end "المعلومات الحالية لا
      // تكفي..." message and its "Choose manually" button remain gone
      // either way.
      'Saudi Arabia: SOURCE_VERIFIED -> the real suggestion step, not '
      'manual selection',
      (tester) async {
        await MadhhabController.instance.load();
        await _openResolver(tester);
        await pickUpbringingCountry(tester, 'Saudi Arabia', 'Saudi Arabia');

        expect(
          find.text(
            'Based on the country where you grew up, Hanbali may be '
            'the closest fit.',
          ),
          findsOneWidget,
        );
        expect(find.text('Choose the Madhhab you follow'), findsNothing);
        expect(
          MadhhabController.instance.state,
          isNot(MadhhabSelectionState.selected),
          reason: 'a suggestion is shown, but nothing is persisted until '
              'she explicitly confirms it',
        );

        await tester.tap(find.widgetWithText(OutlinedButton, 'Use Hanbali'));
        await tester.pumpAndSettle();

        expect(
          MadhhabController.instance.state,
          MadhhabSelectionState.selected,
        );
        expect(MadhhabController.instance.selectedOrNull, Madhhab.hanbali);
        expect(
          MadhhabResolutionScreen.lastConfirmedSelectionSource,
          'suggested_confirmed',
          reason: 'confirming a shown suggestion is "suggested_confirmed", '
              'distinct from a manual pick ("direct")',
        );
      },
    );

    testWidgets(
      // Madhhab unification (2026-10-12): the in-app Profile/Settings
      // change screen's guided step must literally render the same
      // MadhhabResolutionFlow widget onboarding renders — not a
      // lookalike reimplementation. This is the structural half of
      // acceptance item 2 ("Profile/Settings change uses same flow");
      // the behavioral half is covered by the Saudi Arabia/Afghanistan/
      // Egypt/Japan tests in this group.
      '"I don\'t know — help me" renders the shared MadhhabResolutionFlow '
      'widget, not a separate resolution-screen-only implementation',
      (tester) async {
        await MadhhabController.instance.load();
        await _openResolver(tester);

        await tester.tap(find.text("I don't know — help me"));
        await tester.pumpAndSettle();

        expect(
          find.byType(MadhhabResolutionFlow),
          findsOneWidget,
          reason:
              'the in-app resolution screen must delegate to the shared '
              'MadhhabResolutionFlow component rather than maintaining '
              'its own duplicate inference/UX path',
        );
      },
    );

    testWidgets('Afghanistan: SOURCE_VERIFIED -> the real Hanafi '
        'suggestion, no crash, no blocked flow', (tester) async {
      await MadhhabController.instance.load();
      await _openResolver(tester);
      await pickUpbringingCountry(tester, 'Afghanistan', 'Afghanistan');

      expect(tester.takeException(), isNull);
      expect(
        find.text(
          'Based on the country where you grew up, Hanafi may be '
          'the closest fit.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Use Hanafi'));
      await tester.pumpAndSettle();

      expect(MadhhabController.instance.selectedOrNull, Madhhab.hanafi);
      expect(
        MadhhabResolutionScreen.lastConfirmedSelectionSource,
        'suggested_confirmed',
      );
    });

    testWidgets(
      // Syria stays UNVERIFIED after real research (see its review_notes
      // in geographic_madhhab_mapping.json) despite being a multi-madhhab
      // country_level entry — a deliberate choice for this specific test,
      // which exists to prove multi-candidate countries aren't somehow
      // pre-filtered down to one option when they DO land on manual
      // selection, not to prove Syria itself is unresolved (that's
      // covered at the service level).
      'a multi-candidate country that stays UNVERIFIED (Syria) lands on '
      'the full manual grid, not a pre-filtered options list',
      (tester) async {
        await MadhhabController.instance.load();
        await _openResolver(tester);
        await pickUpbringingCountry(tester, 'Syria', 'Syria');

        expect(find.text('Choose the Madhhab you follow'), findsOneWidget);
        await tester.tap(find.text('Maliki'));
        await tester.pumpAndSettle();

        expect(MadhhabController.instance.selectedOrNull, Madhhab.maliki);
        expect(MadhhabResolutionScreen.lastConfirmedSelectionSource, 'direct');
      },
    );

    testWidgets('an unsupported/unmapped country (Japan) also lands on manual '
        'selection, no arbitrary Madhhab assigned', (tester) async {
      await MadhhabController.instance.load();
      await _openResolver(tester);
      await pickUpbringingCountry(tester, 'Japan', 'Japan');

      expect(find.text('Choose the Madhhab you follow'), findsOneWidget);
      expect(MadhhabController.instance.selectedOrNull, isNull);
    });

    testWidgets("choosing \"I don't know\" from the manual selector persists "
        'UNKNOWN correctly, never a guessed Madhhab', (tester) async {
      await MadhhabController.instance.load();
      await _openResolver(tester);
      await pickUpbringingCountry(tester, 'Japan', 'Japan');

      await tester.tap(find.text("I don't know"));
      await tester.pumpAndSettle();

      expect(MadhhabController.instance.state, MadhhabSelectionState.unknown);
      expect(MadhhabController.instance.selectedOrNull, isNull);
    });

    testWidgets(
      'going back from the first (country) step exits the whole flow, '
      'returning to the explanation step — never a crash or dead end',
      (tester) async {
        await MadhhabController.instance.load();
        await _openResolver(tester);

        await tester.tap(find.text("I don't know — help me"));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();

        expect(find.text('Before logging your Haidh'), findsOneWidget);
      },
    );

    testWidgets(
      // Knowledge-Base Source-Verification wave (2026-10-14): previously
      // this test used the debugApprovedMappingIdsForTesting seam to
      // simulate a future approval, since no real entry was verified yet.
      // That future is now real (see the Saudi Arabia/Afghanistan tests
      // above, which cover this exact ground with actual data and no
      // override) — this test is kept only to prove the override
      // mechanism itself still works correctly for an entry that is
      // genuinely still UNVERIFIED (Tunisia), so it would fail without
      // the override, unlike if it used an already-verified country.
      'the test-only debug override still correctly makes an UNVERIFIED '
      'entry (Tunisia) surface a suggestion through the real widget tree',
      (tester) async {
        expect(
          MadhhabSuggestionService.debugApprovedMappingIdsForTesting,
          isEmpty,
        );
        MadhhabSuggestionService.debugApprovedMappingIdsForTesting = {
          'GEO-007', // Tunisia — still UNVERIFIED in the real dataset
        };
        try {
          await MadhhabController.instance.load();
          await _openResolver(tester);
          await pickUpbringingCountry(tester, 'Tunisia', 'Tunisia');

          expect(
            find.text(
              'Based on the country where you grew up, Maliki may be '
              'the closest fit.',
            ),
            findsOneWidget,
          );
          expect(find.text('Choose the Madhhab you follow'), findsNothing);

          await tester.tap(find.widgetWithText(OutlinedButton, 'Use Maliki'));
          await tester.pumpAndSettle();

          expect(MadhhabController.instance.selectedOrNull, Madhhab.maliki);
          expect(
            MadhhabResolutionScreen.lastConfirmedSelectionSource,
            'suggested_confirmed',
          );
        } finally {
          MadhhabSuggestionService.debugApprovedMappingIdsForTesting = {};
        }
      },
    );
  });

  group(
    'Resolution-flow unification defect fix (2026-10-14): '
    '_confirmSelection/_stillNotSure now route through '
    'setMadhhabWithConfirmation instead of calling MadhhabController '
    'directly -- one canonical transition/confirmation path for every '
    'post-onboarding entry point, not a duplicated decision table',
    () {
      testWidgets(
        'post-onboarding UNKNOWN -> Hanafi via the manual grid (an '
        'unmapped country, "Help me choose") shows the LIGHT first-'
        'interpretation notice, not the full warning',
        (tester) async {
          await MadhhabController.instance.selectUnknown();
          await _openResolver(tester);
          await pickUpbringingCountry(tester, 'Japan', 'Japan');

          expect(find.text('Choose the Madhhab you follow'), findsOneWidget);
          await tester.tap(find.text('Hanafi'));
          await tester.pumpAndSettle();

          expect(
            find.text(
              'Niswah will now interpret your previous records according '
              'to the Madhhab you selected. Your original entries will '
              'not be changed.',
            ),
            findsOneWidget,
            reason: 'unknown -> selected deserves a light heads-up, even '
                'via the manual grid, not the full "replacing a selection" '
                'warning',
          );
          expect(find.text('Change your Fiqh Madhhab?'), findsNothing);
          expect(
            MadhhabController.instance.selectedOrNull,
            isNull,
            reason: 'not persisted until Continue is explicitly tapped',
          );

          await tester.tap(find.text('Continue'));
          await tester.pumpAndSettle();

          expect(
            MadhhabController.instance.state,
            MadhhabSelectionState.selected,
          );
          expect(MadhhabController.instance.selectedOrNull, Madhhab.hanafi);
          expect(
            MadhhabResolutionScreen.lastConfirmedSelectionSource,
            'direct',
            reason: 'a manual pick from the fallback grid is still tagged '
                'direct after the fix, same as before it',
          );
        },
      );

      testWidgets(
        'post-onboarding UNKNOWN -> an accepted geographic suggestion '
        '(Saudi Arabia) shows the LIGHT first-interpretation notice, and '
        'source attribution stays suggested_confirmed',
        (tester) async {
          await MadhhabController.instance.selectUnknown();
          await _openResolver(tester);
          await pickUpbringingCountry(tester, 'Saudi Arabia', 'Saudi Arabia');

          expect(
            find.text(
              'Based on the country where you grew up, Hanbali may be '
              'the closest fit.',
            ),
            findsOneWidget,
          );
          await tester.tap(find.widgetWithText(OutlinedButton, 'Use Hanbali'));
          await tester.pumpAndSettle();

          expect(
            find.text(
              'Niswah will now interpret your previous records according '
              'to the Madhhab you selected. Your original entries will '
              'not be changed.',
            ),
            findsOneWidget,
          );
          expect(
            MadhhabController.instance.selectedOrNull,
            isNull,
            reason: 'not persisted until Continue is explicitly tapped',
          );

          await tester.tap(find.text('Continue'));
          await tester.pumpAndSettle();

          expect(MadhhabController.instance.selectedOrNull, Madhhab.hanbali);
          expect(
            MadhhabResolutionScreen.lastConfirmedSelectionSource,
            'suggested_confirmed',
            reason: 'provenance must survive routing through the canonical '
                'confirmation function, same as before the fix',
          );
        },
      );

      testWidgets(
        'an existing selected Madhhab -> a different Madhhab via the '
        'known-picker shows the FULL warning, and Cancel leaves it '
        'completely unchanged',
        (tester) async {
          await MadhhabController.instance.selectMadhhab(Madhhab.hanafi);
          await _openResolver(tester, start: MadhhabResolutionStart.knownPicker);

          await tester.tap(find.text("Shafi'i"));
          await tester.pumpAndSettle();
          expect(
            find.text("Use the Shafi'i school in Niswah's rulings?"),
            findsOneWidget,
          );
          await tester.tap(find.text("Yes, use Shafi'i"));
          await tester.pumpAndSettle();

          expect(find.text('Change your Fiqh Madhhab?'), findsOneWidget);
          expect(
            find.text(
              'Niswah will now interpret your previous records according '
              'to the Madhhab you selected. Your original entries will '
              'not be changed.',
            ),
            findsNothing,
            reason: 'replacing an existing selection is the full warning, '
                'never the light notice',
          );
          expect(
            MadhhabController.instance.selectedOrNull,
            Madhhab.hanafi,
            reason: 'nothing persisted until Confirm change is tapped',
          );

          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();

          expect(MadhhabController.instance.selectedOrNull, Madhhab.hanafi);
          expect(
            MadhhabResolutionScreen.lastConfirmedSelectionSource,
            isNull,
            reason: 'a cancelled dialog must never mark a selection as '
                'confirmed',
          );
        },
      );

      testWidgets(
        'confirming the full warning actually persists the new Madhhab, '
        'with provenance still tagged direct',
        (tester) async {
          await MadhhabController.instance.selectMadhhab(Madhhab.hanafi);
          await _openResolver(tester, start: MadhhabResolutionStart.knownPicker);

          await tester.tap(find.text("Shafi'i"));
          await tester.pumpAndSettle();
          await tester.tap(find.text("Yes, use Shafi'i"));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Confirm change'));
          await tester.pumpAndSettle();

          expect(MadhhabController.instance.selectedOrNull, Madhhab.shafii);
          expect(
            MadhhabResolutionScreen.lastConfirmedSelectionSource,
            'direct',
          );
        },
      );

      testWidgets(
        'selected A -> selected A (same value) via the known-picker is a '
        'true no-op -- no dialog of either kind, and the flow still '
        'closes normally',
        (tester) async {
          await MadhhabController.instance.selectMadhhab(Madhhab.hanafi);
          var notifyCount = 0;
          void listener() => notifyCount++;
          MadhhabController.instance.addListener(listener);

          await _openResolver(tester, start: MadhhabResolutionStart.knownPicker);
          await tester.tap(find.text('Hanafi'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Yes, use Hanafi'));
          await tester.pumpAndSettle();

          expect(find.text('Change your Fiqh Madhhab?'), findsNothing);
          expect(
            find.text(
              'Niswah will now interpret your previous records according '
              'to the Madhhab you selected. Your original entries will '
              'not be changed.',
            ),
            findsNothing,
          );
          expect(
            notifyCount,
            0,
            reason: 'a true no-op never calls notifyListeners',
          );
          expect(MadhhabController.instance.selectedOrNull, Madhhab.hanafi);
          expect(
            MadhhabResolutionScreen.lastConfirmedSelectionSource,
            'direct',
            reason: 'a no-op still counts as a confirmed selection for the '
                'screen\'s own pop-with-result/provenance bookkeeping',
          );

          MadhhabController.instance.removeListener(listener);
        },
      );
    },
  );

  group('Settings reuses the same canonical resolver (Section 16)', () {
    testWidgets('"help me choose" starts directly at the guided question', (
      tester,
    ) async {
      await MadhhabController.instance.load();
      await _openResolver(tester, start: MadhhabResolutionStart.guided);

      expect(find.text('Before logging your Haidh'), findsNothing);
      expect(
        find.text(
          'Which country did you grow up in for most of your childhood?',
        ),
        findsOneWidget,
        reason:
            'onboarding and this screen share one flow — this is the '
            'exact same first question onboarding asks',
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

      // The country question's own field is a tappable summary — open
      // its modal picker before interacting with its search TextField.
      await tester.tap(find.text('Select country'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.enterText(find.byType(TextField), 'a');
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the searchable country field filters as you type', (
      tester,
    ) async {
      await MadhhabController.instance.load();
      await _openResolver(tester, start: MadhhabResolutionStart.guided);
      await tester.tap(find.text('Select country'));
      await tester.pumpAndSettle();

      // The unfiltered list has ~195 entries — ListView.builder only
      // actually builds what's near the visible viewport, so this checks
      // the filtered-down result (the real point of this test) rather
      // than asserting on the huge unfiltered list's lazy-build state.
      await tester.enterText(find.byType(TextField), 'egy');
      await tester.pump();
      expect(find.text('Egypt'), findsOneWidget);
      expect(find.text('Jordan'), findsNothing);
    });
  });
}
