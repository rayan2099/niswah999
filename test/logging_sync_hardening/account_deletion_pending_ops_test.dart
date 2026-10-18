import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/storage/local_sensitive_data_cleanup.dart';
import 'package:niswah/features/cycle_tracking/data/local/pending_bleeding_operation_store.dart';

import '../support/secure_storage_test_support.dart';

/// Logging/sync hardening — account-deletion local cleanup also removes the
/// encrypted queue of not-yet-synced bleeding operations (dates, flows,
/// episode ids, baseline answers) of the deleted account.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSecureLocalStoreForTest();
  });

  test('deleting an account removes its queued bleeding operations', () async {
    await PendingBleedingOperationStore.savePending(
      PendingBleedingOperation(
        operationId: 'op-1',
        type: PendingBleedingOperationType.dailyOrBackfillObservation,
        params: {
          'episodeId': 'e-1',
          'observedDate': DateTime(2026, 10, 17).toIso8601String(),
          'precision': 'date_only',
          'flow': 'heavy',
          'utcOffsetMinutes': 180,
        },
        createdAt: DateTime(2026, 10, 17),
      ),
      userId: 'deleted-user',
    );

    await cleanUpLocalSensitiveDataForDeletedAccount('deleted-user');

    expect(
      await PendingBleedingOperationStore.loadPending(userId: 'deleted-user'),
      isEmpty,
    );
  });
}
