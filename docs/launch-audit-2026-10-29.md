# Launch audit — 2026-10-29

Reviewed main: `5a88cd7753914c4dfa5260d0e1950bd622a7ea04`.

## Decision

Public-launch GO is not established. This note records engineering and catalog checks only. It does not establish signed-device acceptance, clinical accuracy, scholarly approval, or deployment of a new build.

## Current evidence

- PRs #40, #41, #44 and #45 are merged. Their descriptions contain historical pre-merge environment states; those are not current installation evidence.
- Historical CI 40548587989 failed two owner-switch tests in `period_tracking_concurrency_test.dart` (pending operation save and local log save). Main subsequently includes owner-pinning commit `71a1489` and repository ownership commit `b2c709c`; do not reapply the old branch wholesale.
- Current main CI 40942040211: analyzer, bootstrap/schema contract, DB reproducibility, and secret-redaction checks passed when inspected; behavioral tests and native builds were not yet complete.
- Staging `ovgvevzrcefloitgcsia`: the supplied `06_confirm_installed_read_only.sql` returned 12/12 `ok`. This checks function body hashes, search paths, revision action constraint and grants. Thus the PR #60 search-path and observation-removal follow-ups are already installed. This run did not apply migrations or claim fresh behavior-script execution.
- Production `jkmjobvxfrmuwafczvtw`: catalog checks deny anon EXECUTE on `check_and_increment_ai_rate_limit`, `delete_my_account`, `get_active_kb_snapshot`, and `retrieve_knowledge_v1`; `notification-cleanup-hourly` is active at minute 17. This verifies selected grants and scheduling, not every policy or successful cleanup execution.
- Production has none of `correct_episode_start`, `remove_observation`, `restore_observation`. PR #60 UI must not ship against that backend without the required separately authorized deployment and integration evidence.
- Password recovery is merged; email delivery, allowed redirect and warm/cold signed-device recovery still require evidence. See [password recovery](password-recovery.md).

## Focused remediation

`getCycleLogById` lacked the list-read ownership guard. A request begun as A could return A's health row after B signed in; an empty/malformed remote response could also fall back to whichever account was then active.

The proposed patch captures the initiating session, pins its token to the remote query, rejects observed identity changes before returning remote data, and checks identity before and after local fallback reads. Three regression cases exercise delayed remote response, signed-in fallback, and signed-out fallback followed by sign-in. Existing list/read/save tests remain.

Source: [repository](../lib/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart).
Tests: [account-switch regressions](../test/cycle_repository_account_switch_regression_test.dart).
Feature: [tracking map](../project-hub/generated/feature-cycle_tracking.md).

Dart format parsing and whitespace checks passed. Local Flutter dependency resolution did not complete in this environment; no local behavioral pass is claimed. CI is required. Identity equality checks do not prove A→B→A safety or deletion-generation fencing.

## PR #26 reconciliation — remaining scope

| Concern | Current evidence / remaining work |
|---|---|
| Concurrent local writers and owner capture | Later main commits address the two original failures; fresh suite evidence is required, not a trial merge with 40 conflicts. |
| Synced snapshot acknowledgment | Main has `setSyncStatusIfUnchanged`; compare timestamps/provenance and account transitions separately. |
| Single-entry delayed read | Focused patch in this branch; distinct from list-read fix already on main. |
| Retry/deletion, stale remote reads and newer edits | Not closed by this audit. PR #26 has relevant variants; port only demonstrated missing behavior with targeted tests. |
| Civil-day, canonical authority, reminders and prediction changes | Several later fixes exist; not reconciled comprehensively by this run. No wholesale merge recommendation. |

Next: validate the focused patch in CI, then continue targeted retry/deletion and snapshot reconciliation against current main. Keep outstanding device, environment and specialist gates separate.
