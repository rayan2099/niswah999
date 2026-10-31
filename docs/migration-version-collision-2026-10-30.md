# Migration version collision — 2026-10-30

## Finding

Two concurrent draft features use the same Supabase migration version:

| PR | Migration |
|---|---|
| #70, community safety | `20261030090000_community_ugc_safety.sql` |
| #71, episode split/merge | `20261030090000_bleeding_episode_split_merge.sql` |

The timestamp prefix identifies a migration independently of its descriptive suffix. Both files must not ship with the same version. Their individual branch CI cannot establish that the combined version set is valid.

## Correction

This branch is stacked on #71 at `8c444e3dd220e475afb5d9ff7eb8e14680b7160e`. Supabase CLI `migration new` generated the replacement `20261030012106_bleeding_episode_split_merge.sql`. The split/merge SQL is byte-identical to the original (SHA-256 `e338967f6115327ed7e092569ecb381c5b1428072374af7cfb6dc553315d8de3`). Only its version/path and tracked references change. Its required previous-day unknown-end migration still sorts before it; community safety has no dependency on split/merge.

Read-only checks of staging and production found neither version in `supabase_migrations.schema_migrations`, and neither feature's checked RPC (`split_episode`, `report_community_content`) is installed. This does not authorize installing them. Existing external staging kits referencing the old split/merge version must be regenerated before use; they are not updated by this repository patch.

[CI](../.github/workflows/ci.yml) now runs a [version identity check](../scripts/check_migration_versions.py) before schema rebuild. Its [two tests](../scripts/test_migration_versions.py) reproduce the exact conflicting filename pair and verify that the replacement plus community migration and prior unknown-end migration have distinct versions. This check protects the final combined tree; it does not discover collisions on branches absent from that tree.

## Verification and limits

The two Python tests pass; the active migration set passes the checker; period and journey register checks pass. SQL content parity is verified by SHA-256. Project navigation is regenerated from staged additions/removal. Remote schema/bootstrap and app CI remain required after the rename. No database migration or production mutation is performed.

The combined account/tracking candidate PR #69 independently passes CI 40978597053: 1,622 behavioral tests passed, 7 skipped, all jobs green, including real route-boundary/deletion interaction. That candidate excludes #70/#71; it does not prove their combined schema or a full release artifact.

Launch remains NO-GO. Community moderation operations, environment rollout, signed-device acceptance and specialist evidence remain separate gates. No prediction accuracy or clinical/scholarly approval is claimed.

Navigation: [engineering](../project-hub/generated/Engineering.md), [quality](../project-hub/generated/Quality-and-Release.md).
