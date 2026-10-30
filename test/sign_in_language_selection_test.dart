import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/features/auth/presentation/screens/sign_in_screen.dart';

void main() {
  testWidgets('language highlight follows English and Arabic selection', (
    tester,
  ) async {
    final locale = AppLocaleController.instance;
    locale.setArabic(true);
    addTearDown(() => locale.setArabic(false));
    await tester.pumpWidget(
      AnimatedBuilder(
        animation: locale,
        builder: (_, _) => MaterialApp(
          builder: (_, child) => Directionality(
            textDirection: locale.textDirection,
            child: child!,
          ),
          home: const SignInScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Color? segmentColor(String label) {
      final segment = find
          .ancestor(
            of: find.text(label),
            matching: find.byType(AnimatedContainer),
          )
          .first;
      return (tester.widget<AnimatedContainer>(segment).decoration
              as BoxDecoration)
          .color;
    }

    expect(segmentColor('ع'), const Color(0xFFE11D48));
    await tester.tap(find.text('EN'));
    await tester.pumpAndSettle();
    expect(locale.isArabic, isFalse);
    expect(segmentColor('EN'), const Color(0xFFE11D48));
    expect(segmentColor('ع'), Colors.transparent);
    await tester.tap(find.text('ع'));
    await tester.pumpAndSettle();
    expect(locale.isArabic, isTrue);
    expect(segmentColor('ع'), const Color(0xFFE11D48));
    expect(segmentColor('EN'), Colors.transparent);
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('feature labels remain complete at 390px and ${scale}x text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AppLocaleController.instance.setArabic(false);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const SignInScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in [
        'Pregnancy prediction',
        'Women community',
        'Dream interpretation',
      ]) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        expect(paragraph.didExceedMaxLines, isFalse, reason: label);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
