# Report cycle-history ownership — 2026-10-30

Stacked on PR #75 at `afad4f361e5782dc3646e0a423090157fc3e3c36`. This addresses the report-specific read path; ordinary list/single-entry guards have separate evidence.

## Finding and correction

[getCycleLogsForReport](../lib/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart) read local data before capturing its remote account. An account change during that await could combine A's local records with B's remote records. A later account change during the remote request could also return A's records, including through the catch/fallback path.

Capture local identity and remote session before the first await. Reject an observed identity change after local or remote reads. Pin the initiating JWT on the remote query. A stale report-source load returns `failed` with an empty list; another account's cache is not a safe fallback. A stable-account remote failure still returns its own local records with `failed`, preserving the report completeness contract.

[Four regressions](../test/report_cycle_history_owner_test.dart) exercise delayed local reads (no new-account fetch), delayed remote success, delayed remote failure, and normal same-account error fallback. The remote tests assert original token and ownership filters. Synthetic records only.

## Verification and limits

Dart formatting/parser, whitespace, four vault tests and generated-navigation checks pass locally. Behavioral CI is pending. Local Flutter setup remains unavailable; no workaround for the earlier metadata-access block is attempted.

This is not a complete report-generation gate, an A→B→A generation/deletion fence, signed-device acceptance, or overall NJ/PT pass. Other report datasets and stale report widgets still require their own boundaries. No production mutation, migration, merge or release.

Related evidence: PR #75 CI 40999840409 at afad4f3 passes all jobs with 1,601 tests passed, 7 skipped; all three local-save ownership tests explicitly pass. That does not verify the report guard in this branch.

Navigation: [tracking](../project-hub/generated/feature-cycle_tracking.md), [doctor report](../project-hub/generated/feature-doctor_report.md), [quality](../project-hub/generated/Quality-and-Release.md).
