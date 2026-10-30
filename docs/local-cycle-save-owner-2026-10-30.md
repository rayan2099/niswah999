# Local cycle-save ownership — 2026-10-30

Reviewed main: `5a88cd7753914c4dfa5260d0e1950bd622a7ea04`. A focused port of a still-applicable safeguard from draft PR #26.

## Finding and fix

[saveCycleLog](../lib/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart) persisted the supplied record before checking its owner in `upsertCycleLog`. A stale account-A form or callback invoked after B signed in could put A's private record into B's local cache. Rejecting the later server write did not remove that local copy, and local-first reads could return it.

Check both the active local-store identity and the injected client's signed-in session identity before the first local mutation. A mismatch throws without writing or uploading. The local datasource already captures its owner synchronously before its first await, so an account switch during the later write remains covered by the existing capture behavior. Same-owner local saves continue to work when server sync is unavailable.

This is an entry guard, not a blanket closure of account transitions: signed-out cache routing, sync acknowledgements after switching accounts, A→B→A generation fences, deletion races and direct datasource consumers remain separate review concerns. No record is relabeled, migrated or deleted by this patch.

## Verification

[Three regressions](../test/cycle_save_owner_boundary_test.dart) assert that a foreign record enters neither account cache, that an injected signed-in client refuses the foreign save before any network request even without a global store session, and that same-owner offline content remains persisted/pending and absent from the other account. Fixtures are synthetic.

Dart parser/formatting, whitespace, four vault tests and generated navigation checks pass locally. Behavioral CI is pending; no overall PT/NJ acceptance is claimed. No local Flutter setup workaround is attempted after the earlier metadata-access review block. No production writes, migrations, merges, releases, signed-device or specialist claims.

Related verified evidence: PR #74 at 503e089, CI 40997050590: 1,605 passed, 7 skipped, all jobs green; both completed-authority regressions pass. PR #73 at fc222a6, CI 40988753827: all nine combined SQL security files pass and all CI jobs are green. These results do not verify this new save guard.

Navigation: [tracking](../project-hub/generated/feature-cycle_tracking.md), [quality](../project-hub/generated/Quality-and-Release.md).
