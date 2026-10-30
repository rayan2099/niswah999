# Cycle delete request ownership — 2026-10-30

Stacked on PR #80 head `8aa2f6f9129fc34e3ced05ecca99554baaa9e06f`. This ports the applicable session/token capture from PR #26 without changing the current datasource API or serialized local mutations.

## Finding and correction

[deleteCycleLog](../lib/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart) awaited local deletion before reading the server account. A deletion begun under A could therefore use B's filter and default token after an account switch, leaving the intended A server row untouched. A deletion begun signed out could adopt an account that signed in during local storage.

Capture the original client session before the first await. After local deletion completes, use its user ID and pinned token for the server request; when no session existed initially, remain local-only. This continues an already authorized deletion for its initiating account rather than redirecting it. If that token is revoked, the request may fail and the existing error path reports the refusal; it must not retry under the next account. The local datasource already captures its starting storage owner before awaits, with separate concurrency tests.

Three [synthetic HTTP regressions](../test/cycle_delete_request_owner_test.dart) hold local deletion before releasing the network phase: stable signed-in deletion, A→B with the same requested ID, and signed-out→B without any server deletion. They assert the exact table, ID/owner filter and captured Authorization header. Local storage is deliberately held by a test double; this is request ownership evidence, not a claim that the whole deletion journey passed.

## Verification and limits

Dart parsing/formatting, whitespace, navigation and six Python vault/migration tests pass locally. Behavioral CI is pending for this branch.

PR #79's extended head `4477d1b` passed [CI 41043088016](https://github.com/rayan2099/niswah999/actions/runs/41043088016): 1,734 tests passed, 7 skipped, all jobs green. PR #80's exact head above passed [CI 41044399767](https://github.com/rayan2099/niswah999/actions/runs/41044399767): 1,738 tests passed, 7 skipped, including all four new revision regressions and nine prior snapshot cases; SQL, schema, bootstrap and both native compilation checks passed. These passes do not establish this branch's behavior before its CI runs, or signed-device acceptance.

This does not add a durable remote-delete retry queue, change delete-by-ID callers to supply an expected owner, protect a stale callback invoked only after the account already changed, prove A→B→A/deletion generation fencing, or prevent all later writes. Offline deletion followed by a later remote read remains a separate reconciliation concern. No server/migration changes are included.

Fresh read-only staging/production checks confirm the rollout gaps recorded in the launch source candidate remain. Public launch stays NO-GO; remaining engineering, scope, email, operational, device and specialist evidence is independent. No main merge, live mutation, deployment, prediction accuracy or clinical/scholarly approval is performed or claimed.

Navigation: [tracking](../project-hub/generated/feature-cycle_tracking.md), [quality](../project-hub/generated/Quality-and-Release.md), [candidate](launch-source-candidate-2026-10-30.md).
