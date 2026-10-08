import 'dart:io';

/// Commit H — adversarial review follow-up (2026-10-08). The concurrent
/// account-switch fix only protects a `savePending`/`clearPending` pair if
/// the CALLER actually threads its own captured `userId` through — the
/// store's own test suite proves the mechanism works when a userId is
/// passed, but can never prove every real call site actually passes one.
/// This is a source-inspection regression tripwire (same technique as
/// `app_localization_delegates_test.dart`): for every file known to run a
/// savePending -> await RPC -> clearPending sequence, every such call must
/// carry an explicit `userId:` argument *inside that same call's own
/// parentheses* — found via balanced-paren scanning, not a fixed line
/// window, since `onboarding_screen.dart`'s savePending call has a large
/// nested params map between its opening paren and its `userId:` argument.
/// A future call site added without this parameter — or one of these four
/// files' existing calls losing it in a refactor — fails this test
/// immediately, rather than silently reintroducing the exact race
/// `pending_bleeding_operation_store_test.dart` already proves is real.
///
/// Deliberately NOT covered here (by design, confirmed ambient-correct
/// during the Commit H adversarial review): `loadPending()`/
/// `getPendingByType(...)` calls that only ask "what's pending for
/// whoever is signed in right now" (`start_bleeding_sheet.dart`'s/
/// `onboarding_screen.dart`'s own `_resolveOnboardingOperationId`-style
/// pending-id lookups, `_SyncStatusBanner._load` in dashboard_screen.dart),
/// and `reconcilePendingOperations` itself (`bleeding_episode_repository_
/// impl.dart`), which intentionally always acts on the currently
/// signed-in user.
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Every `PendingBleedingOperationStore.savePending(`/`.clearPending(`
  /// call in [path] must have a `userId:` argument inside its own
  /// matching parentheses. Found by scanning forward from each call's
  /// opening `(` and tracking paren depth until it returns to zero —
  /// robust to however much nested content (a multi-line map literal,
  /// say) sits between the call and its own `userId:` argument.
  void expectEveryCallThreadsUserId(String path) {
    final source = File(path).readAsStringSync();
    final callPattern = RegExp(
      r'PendingBleedingOperationStore\.(savePending|clearPending)\(',
    );
    var callsFound = 0;
    for (final match in callPattern.allMatches(source)) {
      callsFound++;
      // match.end is the index right after the call's own opening '('.
      var depth = 1;
      var i = match.end;
      while (i < source.length && depth > 0) {
        if (source[i] == '(') depth++;
        if (source[i] == ')') depth--;
        i++;
      }
      final callBody = source.substring(match.end, i);
      expect(
        callBody,
        contains('userId:'),
        reason:
            'a PendingBleedingOperationStore.${match.group(1)} call at '
            '$path (starting at character offset ${match.start}) has no '
            'userId: argument anywhere inside its own parentheses — this '
            'is exactly the shape of the Commit H account-switch race (an '
            'account switch between save and clear would silently '
            "redirect the clear to the new user's bucket)",
      );
    }
    expect(
      callsFound,
      greaterThan(0),
      reason:
          'expected to find at least one savePending/clearPending call '
          'in $path — if this file no longer calls either, update this '
          'test rather than leave it vacuously passing',
    );
  }

  test(
    'start_bleeding_sheet.dart: every savePending/clearPending call '
    'threads an explicit userId',
    () => expectEveryCallThreadsUserId(
      'lib/features/cycle_tracking/presentation/widgets/start_bleeding_sheet.dart',
    ),
  );

  test(
    'daily_checkin_sheet.dart: every savePending/clearPending call '
    'threads an explicit userId',
    () => expectEveryCallThreadsUserId(
      'lib/features/cycle_tracking/presentation/widgets/daily_checkin_sheet.dart',
    ),
  );

  test(
    'correction_sheet.dart: every savePending/clearPending call threads '
    'an explicit userId',
    () => expectEveryCallThreadsUserId(
      'lib/features/cycle_tracking/presentation/widgets/correction_sheet.dart',
    ),
  );

  test(
    'onboarding_screen.dart: every savePending/clearPending call threads '
    'an explicit userId (found missing this entirely during the Commit H '
    'adversarial review — fixed alongside this test)',
    () => expectEveryCallThreadsUserId(
      'lib/features/onboarding/presentation/screens/onboarding_screen.dart',
    ),
  );
}
