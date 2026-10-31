# Combined schema security candidate — 2026-10-30

This is a schema-verification candidate, not a deployable app or a complete release tree. It is stacked on PR #72 at `72a8af6bee05a5550fec31a5f855dd21c64f14e3` (which includes #60/#71). It adds only the community-safety migration and SQL checks from PR #70 at `a2ae377fb644685bf8097ffa1742089456711229`; the community app UI is deliberately absent. The community terms-enforcement schema must never be deployed ahead of its compatible app.

## Why another check is necessary

Normal CI currently proves schema reconstruction and runs the notification-specific backend tests, but does not run `test/security/run_sql_checks.sh`. Individual feature authors report local passes; these are different evidence from repository CI against the combined tree. Renaming the colliding migration fixes identity, not possible policy/trigger interactions.

The [CI SQL security job](../.github/workflows/ci.yml) uses a disposable PostgreSQL 16 service with synthetic test credentials, no secrets or live backend access. The [existing harness](../test/security/run_sql_checks.sh) creates an independent scratch database for each SQL check from the Supabase stub, canonical baseline and complete active migration chain. It checks permissions, own/cross-user behavior, corrections/removals, unknown ends, split/merge, and community block/report/terms/moderation.

Exact community inputs are `supabase/migrations/20261030090000_community_ugc_safety.sql`, `test/security/community_ugc_safety.sql`, and its terms-aware revision of `test/security/app_rls_initplan_and_notification_cleanup_cron.sql`. Feature SQL is unchanged. Split/merge retains the unique `20261030012106` version from #72.

## Evidence

PR #72 CI 40985564815 is green at 72a8af6: 1,653 app tests passed, 7 skipped, migration identity check, schema/bootstrap and native compilation passed. It did not include community safety.

This combined candidate passes local version-uniqueness, both acceptance-register checks, vault checks and Python tests. Local PostgreSQL/Docker binaries are unavailable, so combined schema behavior requires the new CI job. This is not staging evidence, signed-device acceptance, specialist approval or a full PT/NJ journey pass. No live migration, deployment, merge or release is performed.

Navigation: [engineering](../project-hub/generated/Engineering.md), [quality](../project-hub/generated/Quality-and-Release.md).
