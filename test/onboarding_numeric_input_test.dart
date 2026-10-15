import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Onboarding fixes wave (2026-10-11), Part 6/7: the small numeric text
/// field (and its earlier Arabic-Indic normalization fix) was replaced
/// entirely by a discrete number wheel — no keyboard, no typed numeral
/// system to get wrong. These tests exercise the wheel end to end:
/// unselected-by-default state, Continue's gating, "I'm not sure",
/// back-navigation persistence, and — critically — Part 5's confirmed
/// cross-question value-leakage bug (duration's answer visibly carrying
/// into the cycle-length wheel), now fixed via a distinct Key per
/// question (see `_predictionsStep` in onboarding_screen.dart).
void main() {
  Future<void> pumpToDurationQuestion(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    AppLocaleController.instance.setArabic(false);
    await tester.pumpWidget(
      MaterialApp(home: OnboardingScreen(onFinished: () {}, initialStep: 6)),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Would you like to add some information to improve predictions?',
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Yes, help me improve predictions'));
    await tester.tap(find.text('Yes, help me improve predictions'));
    await tester.pumpAndSettle();
    expect(
      find.text('How many days does your bleeding usually last?'),
      findsOneWidget,
    );
  }

  bool continueEnabled(WidgetTester tester) {
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Continue'),
        matching: find.byType(FilledButton),
      ),
    );
    return button.onPressed != null;
  }

  /// The wheel's current value, as exposed via its own Semantics node —
  /// null while untouched (the "unselected" state Part 6 requires), a
  /// digit string once she's actually scrolled it. Reading this (rather
  /// than guessing a drag-distance-to-value mapping) keeps these tests
  /// independent of CupertinoPicker's own scroll-physics internals.
  String? wheelSemanticsValue(WidgetTester tester) {
    final finder = find.ancestor(
      of: find.byType(CupertinoPicker),
      matching: find.byType(Semantics),
    );
    for (final element in finder.evaluate()) {
      final widget = element.widget as Semantics;
      if (widget.properties.value != null) return widget.properties.value;
      if (widget.properties.label != null &&
          widget.properties.label!.startsWith('No value selected')) {
        return null;
      }
    }
    return null;
  }

  Future<void> dragWheel(WidgetTester tester, double dy) async {
    await tester.drag(find.byType(CupertinoPicker), Offset(0, dy));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'the wheel starts unselected — Continue disabled, a "scroll to '
    'choose" hint shown, no value implied',
    (tester) async {
      await pumpToDurationQuestion(tester);

      expect(continueEnabled(tester), isFalse);
      expect(find.textContaining('Swipe to'), findsOneWidget);
      expect(wheelSemanticsValue(tester), isNull);
    },
  );

  testWidgets(
    // Manual QA round 2 (2026-10-11), Part 1: the wheel must visibly
    // center on a real, readable number from the very first frame (never
    // render as an empty/missing slot) — but that centered number is
    // display-only until she actually interacts with the wheel. This is
    // the "visible value != confirmed answer until interaction"
    // requirement, verified directly rather than just inferred from
    // Continue's enabled state.
    'a real, non-blank number is visibly centered from the first frame, '
    'but it is not treated as her answer until she actually interacts',
    (tester) async {
      await pumpToDurationQuestion(tester);

      // A real digit is on screen immediately — never a blank/empty
      // center slot.
      final digitFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data != null &&
            RegExp(r'^\d+$').hasMatch(widget.data!),
      );
      expect(
        digitFinder,
        findsWidgets,
        reason: 'the wheel must show real numbers on screen immediately, '
            'never an empty center slot',
      );

      // But nothing has been "answered" yet: Continue disabled, no value
      // reported via onChanged, and the semantics layer explicitly
      // reports no value selected (not the midpoint number).
      expect(continueEnabled(tester), isFalse);
      expect(wheelSemanticsValue(tester), isNull);

      // Now she actually interacts — only now does a value become real.
      await dragWheel(tester, -48);
      await tester.pump();
      expect(continueEnabled(tester), isTrue);
      expect(wheelSemanticsValue(tester), isNotNull);
    },
  );

  testWidgets(
    'scrolling the wheel selects an exact value, enables Continue, and '
    'clears the unselected hint',
    (tester) async {
      await pumpToDurationQuestion(tester);

      await dragWheel(tester, -96); // two rows
      await tester.pump();

      expect(continueEnabled(tester), isTrue);
      expect(find.textContaining('Swipe to'), findsNothing);
      expect(wheelSemanticsValue(tester), isNotNull);
    },
  );

  testWidgets(
    '"I\'m not sure" always advances, regardless of whether the wheel '
    'was ever touched',
    (tester) async {
      await pumpToDurationQuestion(tester);

      await tester.ensureVisible(find.text('I’m not sure'));
      await tester.tap(find.text('I’m not sure'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'How many days between the start of one period and the start '
              'of the next?',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a selected value survives stepping back from cycle length to '
    'duration (Part 8: back-navigation preserves entered answers)',
    (tester) async {
      await pumpToDurationQuestion(tester);

      await dragWheel(tester, -96);
      await tester.pump();
      final valueA = wheelSemanticsValue(tester);
      expect(valueA, isNotNull);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'How many days between the start of one period and the start '
              'of the next?',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(
        find.text('How many days does your bleeding usually last?'),
        findsOneWidget,
      );
      expect(
        wheelSemanticsValue(tester),
        valueA,
        reason: 'duration\'s own previously-selected value must still be '
            'shown, unchanged, after navigating back to it',
      );
    },
  );

  group('Part 5 — cross-question value-leakage bug (confirmed manual QA, '
      '2026-10-11)', () {
    testWidgets(
      'answering the duration question leaves the cycle-length question '
      'unselected — it must never start pre-filled with duration\'s value',
      (tester) async {
        await pumpToDurationQuestion(tester);

        await dragWheel(tester, -96);
        await tester.pump();
        expect(wheelSemanticsValue(tester), isNotNull);

        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'How many days between the start of one period and the start '
                'of the next?',
          ),
          findsOneWidget,
        );
        expect(
          continueEnabled(tester),
          isFalse,
          reason: 'cycle length must start unanswered, not inherit '
              'duration\'s Continue-enabled state',
        );
        expect(find.textContaining('Swipe to'), findsOneWidget);
        expect(
          wheelSemanticsValue(tester),
          isNull,
          reason: 'the exact bug reported: the second question must not '
              'start already showing the first question\'s value',
        );
      },
    );

    testWidgets(
      'full round trip: A=valueA, B initially unset, answer B=valueB, '
      'back to A still shows valueA, forward to B still shows valueB',
      (tester) async {
        await pumpToDurationQuestion(tester);

        // Answer A.
        await dragWheel(tester, -96);
        await tester.pump();
        final valueA = wheelSemanticsValue(tester);
        expect(valueA, isNotNull);
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        // B must start unset.
        expect(wheelSemanticsValue(tester), isNull);

        // Answer B, with a different drag distance so it's very unlikely
        // to coincidentally land on the same value as A.
        await dragWheel(tester, -192);
        await tester.pump();
        final valueB = wheelSemanticsValue(tester);
        expect(valueB, isNotNull);

        // Back to A — must still be exactly valueA, not valueB and not
        // unset.
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(
          find.text('How many days does your bleeding usually last?'),
          findsOneWidget,
        );
        expect(wheelSemanticsValue(tester), valueA);

        // Forward to B again — must still be exactly valueB.
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'How many days between the start of one period and the start '
                'of the next?',
          ),
          findsOneWidget,
        );
        expect(wheelSemanticsValue(tester), valueB);
      },
    );

    testWidgets(
      '"I\'m not sure" on duration never leaves a hidden number behind '
      'for cycle length to inherit',
      (tester) async {
        await pumpToDurationQuestion(tester);

        await dragWheel(tester, -96);
        await tester.pump();
        expect(wheelSemanticsValue(tester), isNotNull);

        // Switching to "I'm not sure" after having scrolled must clear
        // the answer, not just hide it.
        await tester.ensureVisible(find.text('I’m not sure'));
        await tester.tap(find.text('I’m not sure'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'How many days between the start of one period and the start '
                'of the next?',
          ),
          findsOneWidget,
        );
        expect(wheelSemanticsValue(tester), isNull);
        expect(continueEnabled(tester), isFalse);
      },
    );
  });

  testWidgets(
    'the predictions gate and duration question render with no layout '
    'exception on a small viewport (Part 12: never hardcode for one '
    'simulator size)',
    (tester) async {
      final originalSize = tester.view.physicalSize;
      final originalRatio = tester.view.devicePixelRatio;
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.physicalSize = originalSize;
        tester.view.devicePixelRatio = originalRatio;
      });

      await pumpToDurationQuestion(tester);
      expect(tester.takeException(), isNull);

      await dragWheel(tester, -48);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the predictions gate and duration question render with no layout '
    'exception at 200% text scale',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      AppLocaleController.instance.setArabic(false);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2.0)),
            child: child!,
          ),
          home: OnboardingScreen(onFinished: () {}, initialStep: 6),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Yes, help me improve predictions'));
      await tester.tap(find.text('Yes, help me improve predictions'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.text('How many days does your bleeding usually last?'),
        findsOneWidget,
      );
    },
  );

  group('Manual QA round 3 (2026-10-11) — the selection highlight can '
      'never obscure the centered digit', () {
    testWidgets(
      'CupertinoPicker.selectionOverlay is disabled entirely, and the '
      'picker is the topmost (last) child in its Stack — the highlight '
      'box is structurally behind it, not merely low-opacity',
      (tester) async {
        await pumpToDurationQuestion(tester);

        final picker = tester.widget<CupertinoPicker>(
          find.byType(CupertinoPicker),
        );
        expect(
          picker.selectionOverlay,
          isNull,
          reason:
              'CupertinoPicker paints its own selectionOverlay as the '
              'last (topmost) child of its internal Stack, by SDK '
              'construction — no alpha value on it can guarantee the '
              'centered digit stays legible. It must be disabled '
              'entirely and replaced with a highlight drawn behind the '
              'picker in our own Stack instead.',
        );

        // `find.ancestor` yields ancestors nearest-first, so `.first` is
        // the innermost Stack directly containing the highlight box and
        // the picker — not an unrelated outer Stack elsewhere in the
        // onboarding screen's own layout.
        final stack = tester
            .widgetList<Stack>(
              find.ancestor(
                of: find.byType(CupertinoPicker),
                matching: find.byType(Stack),
              ),
            )
            .first;
        final pickerIndex = stack.children.indexWhere(
          (w) => w is AnimatedBuilder,
        );
        expect(
          pickerIndex,
          stack.children.length - 1,
          reason:
              'the picker (wrapped in the AnimatedBuilder that drives '
              'the live fade effect) must be the LAST child of the '
              'Stack, so it paints on top of every other child '
              '(the highlight box) — this is what actually guarantees '
              'the digit is never obscured, not a color choice.',
        );
      },
    );

    testWidgets(
      'the centered digit is a real, visible Text widget before and '
      'after interaction — minimum, middle, and after scrolling toward '
      'the maximum',
      (tester) async {
        await pumpToDurationQuestion(tester);

        // Untouched (midpoint) state: some real digit text exists.
        expect(
          find.byWidgetPredicate(
            (w) => w is Text && w.data != null && RegExp(r'^\d+$').hasMatch(w.data!),
          ),
          findsWidgets,
        );

        // Scroll toward the minimum end.
        await dragWheel(tester, 400);
        await tester.pump();
        expect(wheelSemanticsValue(tester), isNotNull);
        expect(
          find.byWidgetPredicate(
            (w) => w is Text && w.data != null && RegExp(r'^\d+$').hasMatch(w.data!),
          ),
          findsWidgets,
        );

        // Scroll toward the maximum end.
        await dragWheel(tester, -800);
        await tester.pump();
        expect(wheelSemanticsValue(tester), isNotNull);
        expect(
          find.byWidgetPredicate(
            (w) => w is Text && w.data != null && RegExp(r'^\d+$').hasMatch(w.data!),
          ),
          findsWidgets,
        );
      },
    );
  });
}
