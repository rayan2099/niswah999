import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/preferences/pregnancy_status_controller.dart';
import 'package:niswah/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Found live (Batch 3): the English pregnancy overview showed the Arabic
/// stage/size line ("مرحلة المضغة · بحجم حبة الليمون"). English mode must
/// contain no Arabic script in the overview card, at every stage boundary.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final arabic = RegExp(r'[؀-ۿ]');

  for (final week in [3, 7, 12, 15, 20, 30]) {
    testWidgets('English pregnancy overview at week $week has no Arabic', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      AppLocaleController.instance.setArabic(false);
      await PregnancyStatusController.instance.activate(startWeek: week);
      await tester.pumpWidget(const MaterialApp(home: DashboardScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final overview = find.byKey(const Key('pregnancy-overview'));
      expect(overview, findsOneWidget);
      final texts = find
          .descendant(of: overview, matching: find.byType(Text))
          .evaluate()
          .map((e) => (e.widget as Text).data ?? '')
          .join(' | ');
      expect(
        arabic.hasMatch(texts),
        isFalse,
        reason: 'Arabic script in the English overview: $texts',
      );
    });
  }
}
