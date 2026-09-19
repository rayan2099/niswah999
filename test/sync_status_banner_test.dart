import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/features/cycle_tracking/data/local/pending_bleeding_operation_store.dart';
import 'package:niswah/features/dashboard/presentation/screens/dashboard_screen.dart';

import 'support/secure_storage_test_support.dart';

/// New critical finding — three honest sync states. Genuine widget-level
/// coverage (not only pure-logic tests on [PendingBleedingOperation]
/// itself): the dashboard must actually surface a "Sync needs attention"
/// banner once a pending operation reaches that state, and stay silent
/// otherwise — an ordinary, still-syncing pending item must never look
/// alarming.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSecureLocalStoreForTest();
    // AppLocaleController defaults to Arabic until .load() overrides it
    // from a real preference — pinned to English here so the English
    // assertions below are unambiguous.
    AppLocaleController.instance.setArabic(false);
  });

  testWidgets('nothing pending: no sync banner appears at all', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DashboardScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Sync needs attention'), findsNothing);
  });

  testWidgets('a pending operation that is still ordinary savedSyncing (never '
      'failed yet) does not show the needs-attention banner — only a '
      'genuine SyncState.needsAttention does', (tester) async {
    await PendingBleedingOperationStore.savePending(
      PendingBleedingOperation(
        operationId: 'op-1',
        type: PendingBleedingOperationType.startEpisode,
        params: const {},
        createdAt: DateTime.now(),
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: DashboardScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Sync needs attention'), findsNothing);
  });

  testWidgets('a validation-categorized pending operation shows the needs-'
      'attention banner with an honest "needs your review" message and '
      'no false retry affordance for it', (tester) async {
    final operation =
        PendingBleedingOperation(
          operationId: 'op-1',
          type: PendingBleedingOperationType.startEpisode,
          params: const {},
          createdAt: DateTime.now(),
        ).withFailure(
          PendingOperationFailureCategory.validation,
          attemptedAt: DateTime.now(),
        );
    await PendingBleedingOperationStore.savePending(operation);

    await tester.pumpWidget(const MaterialApp(home: DashboardScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Sync needs attention'), findsOneWidget);
    expect(
      find.textContaining('need your review'),
      findsOneWidget,
      reason:
          'a validation failure cannot be fixed by retrying with the '
          'same data — the banner must say so honestly',
    );
    expect(
      find.text('Retry now'),
      findsNothing,
      reason: 'no retry button for a category retrying cannot possibly fix',
    );
  });

  testWidgets(
    'a network-categorized pending operation past the retry threshold '
    'shows the needs-attention banner WITH a real "Retry now" action',
    (tester) async {
      var operation = PendingBleedingOperation(
        operationId: 'op-1',
        type: PendingBleedingOperationType.startEpisode,
        params: const {},
        createdAt: DateTime.now(),
      );
      for (var i = 0; i < 3; i++) {
        operation = operation.withFailure(
          PendingOperationFailureCategory.network,
          attemptedAt: DateTime.now(),
        );
      }
      await PendingBleedingOperationStore.savePending(operation);

      await tester.pumpWidget(const MaterialApp(home: DashboardScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Sync needs attention'), findsOneWidget);
      expect(find.text('Retry now'), findsOneWidget);
    },
  );
}
