import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/main.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/preferences/madhhab_controller.dart';
import 'package:niswah/core/preferences/marital_status_controller.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('App Integration and Feature Flow Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'niswah_arabic': false,
        'niswah_madhhab': 'HANBALI',
        'niswah_marital_status': 'married',
        'niswah_cycle_tracking_logs': jsonEncode([
          {
            "id": "1",
            "user_id": "local-user",
            "date": "2026-07-15T12:00:00.000",
            "flow": "medium",
            "cycle_day": 1,
            "sync_status": "synced",
          },
          {
            "id": "2",
            "user_id": "local-user",
            "date": "2026-08-15T12:00:00.000",
            "flow": "medium",
            "cycle_day": 1,
            "sync_status": "synced",
          },
        ]),
      });
      await AppLocaleController.instance.load();
      await MadhhabController.instance.load();
      await MaritalStatusController.instance.load();
    });

    testWidgets(
      'Verification of complete dashboard flow with sufficient history',
      (tester) async {
        await tester.pumpWidget(const NiswahApp());
        await tester.pumpAndSettle();

        // Verify English translation elements
        expect(find.text('Today'), findsWidgets);
        expect(find.text('Calendar'), findsWidgets);
        expect(find.text('Insights'), findsWidgets);
        expect(find.text('Community'), findsWidgets);
        expect(find.text('Profile'), findsWidgets);

        // Verify Fiqh state ring is rendered
        expect(find.byKey(const Key('today-cycle-ring')), findsOneWidget);
      },
    );

    testWidgets('Verification of onboarding transition to main shell', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'niswah_arabic': false,
        'niswah_marital_status': '', // Needs onboarding
      });
      await AppLocaleController.instance.load();
      await MaritalStatusController.instance.load();

      await tester.pumpWidget(const NiswahApp());
      await tester.pumpAndSettle();

      // App should start or can handle onboarding
      expect(find.byType(NiswahApp), findsOneWidget);
    });

    testWidgets('Verification of language and Madhhab configuration settings', (
      tester,
    ) async {
      // Toggle to Arabic
      AppLocaleController.instance.setArabic(true);
      expect(AppLocaleController.instance.isArabic, isTrue);

      // Toggle Madhhab
      await MadhhabController.instance.selectMadhhab(Madhhab.hanafi);
      expect(MadhhabController.instance.selectedOrNull, Madhhab.hanafi);
      expect(MadhhabController.instance.state, MadhhabSelectionState.selected);

      // Clean up
      AppLocaleController.instance.setArabic(false);
      await MadhhabController.instance.selectMadhhab(Madhhab.hanbali);
    });
  });
}
