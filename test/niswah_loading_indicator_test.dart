// Global Loading/Spinner Remediation wave (UI-001) — Section J required
// automated tests for the canonical loading component.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/widgets/niswah_loading_indicator.dart';

void main() {
  group('NiswahLoadingIndicator — explicit, non-collapsing dimensions', () {
    for (final entry in {
      NiswahLoadingSize.small: 15.0,
      NiswahLoadingSize.medium: 22.0,
      NiswahLoadingSize.large: 40.0,
    }.entries) {
      testWidgets(
        '${entry.key.name} renders at exactly ${entry.value}x${entry.value}, '
        'never collapsed to a dot',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Center(child: NiswahLoadingIndicator(size: entry.key)),
            ),
          );
          await tester.pump();

          final finder = find.byType(CircularProgressIndicator);
          expect(finder, findsOneWidget);
          final size = tester.getSize(finder);
          expect(size.width, entry.value);
          expect(size.height, entry.value);
          expect(
            size.width,
            greaterThan(8),
            reason:
                'a spinner rendered at 8px or less is exactly the '
                '"collapsed to a tiny dot" defect this wave exists to prevent',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'the medium (button) size is unaffected by a tight parent — parent '
      'layout is never trusted to determine visible size',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Center(
              child: SizedBox(
                // A parent far larger than the spinner still yields the
                // spinner's own fixed, explicit size — not a collapse and
                // not an unbounded stretch either.
                width: 300,
                height: 300,
                child: Center(child: NiswahLoadingIndicator()),
              ),
            ),
          ),
        );
        await tester.pump();

        final size = tester.getSize(find.byType(CircularProgressIndicator));
        expect(size, const Size(22, 22));
      },
    );
  });

  group('NiswahLoadingButton — Section D canonical button behavior', () {
    testWidgets(
      'button dimensions are identical between the normal and loading '
      'states — no shrink, no height change, no layout jump',
      (tester) async {
        Widget buildButton(bool loading) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: NiswahLoadingButton(
                loading: loading,
                onPressed: () {},
                label: 'Create Account',
              ),
            ),
          ),
        );

        await tester.pumpWidget(buildButton(false));
        await tester.pump();
        final normalSize = tester.getSize(find.byType(NiswahLoadingButton));

        await tester.pumpWidget(buildButton(true));
        await tester.pump();
        final loadingSize = tester.getSize(find.byType(NiswahLoadingButton));

        expect(loadingSize, normalSize);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'the button cannot be double-submitted while loading — onPressed is '
      'null and the label is replaced by the spinner, never both shown',
      (tester) async {
        var tapCount = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: NiswahLoadingButton(
                  loading: true,
                  onPressed: () => tapCount++,
                  label: 'Create Account',
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Create Account'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        await tester.tap(find.byType(FilledButton), warnIfMissed: false);
        await tester.pump();
        expect(
          tapCount,
          0,
          reason: 'a disabled (loading) button must never invoke onPressed',
        );
      },
    );

    testWidgets('no overflow at 200% text scale, English and Arabic', (
      tester,
    ) async {
      for (final arabic in [false, true]) {
        AppLocaleController.instance.setArabic(arabic);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => Directionality(
              textDirection: AppLocaleController.instance.textDirection,
              child: MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2.0)),
                child: child!,
              ),
            ),
            home: Scaffold(
              body: Center(
                child: NiswahLoadingButton(
                  loading: false,
                  onPressed: () {},
                  label: arabic ? 'إنشاء حساب' : 'Create Account',
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => Directionality(
              textDirection: AppLocaleController.instance.textDirection,
              child: MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2.0)),
                child: child!,
              ),
            ),
            home: Scaffold(
              body: Center(
                child: NiswahLoadingButton(
                  loading: true,
                  onPressed: () {},
                  label: arabic ? 'إنشاء حساب' : 'Create Account',
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      AppLocaleController.instance.setArabic(false);
    });

    testWidgets('usable at a small viewport (320x568)', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: NiswahLoadingButton(
                loading: true,
                onPressed: () {},
                label: 'Create Account',
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      final size = tester.getSize(find.byType(CircularProgressIndicator));
      expect(size.width, greaterThan(8));
    });
  });

  group('Page-level loader (large size)', () {
    testWidgets('renders visible, centered, and with non-zero dimensions', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: NiswahLoadingIndicator(size: NiswahLoadingSize.large),
            ),
          ),
        ),
      );
      await tester.pump();

      final finder = find.byType(CircularProgressIndicator);
      expect(finder, findsOneWidget);
      final size = tester.getSize(finder);
      expect(size, const Size(40, 40));
      expect(tester.takeException(), isNull);
    });
  });
}
