import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/preferences/madhhab_controller.dart';
import 'package:niswah/core/storage/secure_local_store.dart';
import 'package:niswah/features/cycle_tracking/data/local/cycle_log_draft_store.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart'
    show Madhhab;
import 'package:niswah/features/cycle_tracking/presentation/viewmodels/cycle_tracking_view_model.dart';
import 'package:niswah/features/cycle_tracking/presentation/widgets/cycle_log_form_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secure_storage_test_support.dart';

/// NJ-013: when the session ends while the day-log sheet is open, what she
/// typed is kept for her account only and offered back on the same day's
/// entry. Synthetic account ids only.
void main() {
  final day = DateTime(2026, 10, 20);
  final otherDay = DateTime(2026, 10, 21);
  final navigatorKey = GlobalKey<NavigatorState>();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    resetSecureLocalStoreForTest();
    AppLocaleController.instance.setArabic(false);
    SecureLocalStore.debugUserIdOverride = 'account-a';
    await MadhhabController.instance.selectMadhhab(Madhhab.hanafi);
  });

  tearDown(() => SecureLocalStore.debugUserIdOverride = null);

  Future<void> openSheet(WidgetTester tester, DateTime date) async {
    final viewModel = CycleTrackingViewModel(
      repository: CycleTrackingRepositoryImpl(),
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showCycleLogSheet(
                context,
                viewModel: viewModel,
                mode: CycleLogSheetMode.symptomsOnly,
                date: date,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> typeNotes(WidgetTester tester, String text) async {
    await tester.scrollUntilVisible(
      find.text('Notes'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, text);
    await tester.pump();
  }

  Future<void> closeSheet(WidgetTester tester) async {
    navigatorKey.currentState!.popUntil((route) => route.isFirst);
    await tester.pumpAndSettle();
  }

  testWidgets('session ends: kept for her account, offered back, restored', (
    tester,
  ) async {
    await openSheet(tester, day);
    await typeNotes(tester, 'cramps after lunch');

    // The session ends and another account signs in; the sheet closes.
    SecureLocalStore.debugUserIdOverride = 'account-b';
    await closeSheet(tester);

    expect(
      (await CycleLogDraftStore.read('account-a'))?.values['notes'],
      'cramps after lunch',
    );
    expect(
      await CycleLogDraftStore.read('account-b'),
      isNull,
      reason: 'never stored under the next account',
    );

    // Account B opens the same day: nothing is offered.
    await openSheet(tester, day);
    expect(find.byKey(const Key('cycle_log_draft_banner')), findsNothing);
    await closeSheet(tester);

    // Account A signs back in and opens the same day.
    SecureLocalStore.debugUserIdOverride = 'account-a';
    await openSheet(tester, day);
    expect(find.byKey(const Key('cycle_log_draft_banner')), findsOneWidget);
    expect(
      find.text('cramps after lunch'),
      findsNothing,
      reason: 'nothing is filled in until she restores it',
    );
    await tester.tap(find.byKey(const Key('cycle_log_draft_restore')));
    await tester.pump();
    expect(find.byKey(const Key('cycle_log_draft_banner')), findsNothing);
    await tester.scrollUntilVisible(
      find.text('cramps after lunch'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('cramps after lunch'), findsOneWidget);
  });

  testWidgets('a draft is offered only for the same day', (tester) async {
    await openSheet(tester, day);
    await typeNotes(tester, 'headache');
    SecureLocalStore.debugUserIdOverride = null;
    await closeSheet(tester);

    SecureLocalStore.debugUserIdOverride = 'account-a';
    await openSheet(tester, otherDay);
    expect(find.byKey(const Key('cycle_log_draft_banner')), findsNothing);
  });

  testWidgets('closing the sheet herself keeps no draft', (tester) async {
    await openSheet(tester, day);
    await typeNotes(tester, 'not this one');
    await closeSheet(tester);
    expect(await CycleLogDraftStore.read('account-a'), isNull);
  });

  testWidgets('Discard removes the draft', (tester) async {
    await CycleLogDraftStore.write(
      'account-a',
      CycleLogDraft(
        formKey: 'symptomsOnly|2026-10-20|new',
        values: const {'notes': 'old'},
        savedAt: DateTime(2026, 10, 20),
      ),
    );
    await openSheet(tester, day);
    await tester.tap(find.byKey(const Key('cycle_log_draft_discard')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cycle_log_draft_banner')), findsNothing);
    expect(await CycleLogDraftStore.read('account-a'), isNull);
  });
}
