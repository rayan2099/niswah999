# 00_05 — Unknown & Assumption Register

Consolidated from all specialist audits. Per master §3.3, none of these are converted to PASS.

## Unknown Register

| Unknown ID | Area | Why unknown | Criticality | Blocks GO? | Owner |
|---|---|---|---|---|---|
| `UNK-001` | Whether `GeminiService`'s endpoint (`v1beta/interactions`) / `dr-niswah-chat`'s identical shape is a real Gemini API surface (`ROOT-001`) | No live network access authorized in this audit | Critical — if broken, 3 of 4 AI features are dead on arrival | **YES** | Backend engineer — resolve with one authenticated smoke-test call |
| `UNK-002` | Whether migrations in `supabase/migrations/` have actually been applied, in order, to the live Supabase project | No dashboard/CLI access | Critical | **YES** | Release owner — `supabase db diff` or dashboard review |
| `UNK-003` | Live Supabase dashboard config: Auth rate limits, leaked-password protection, email-confirmation requirement, redirect-URL allow-list, Realtime RLS toggle | No dashboard access | High | Contributes to Security gate | Release owner |
| `UNK-004` | Live deprecation/advisory status of several pinned dependency versions | No network access for pub.dev lookups | Low | NO | Engineer, pre-launch housekeeping |
| `UNK-005` | ~~Whether `flutter test` passes~~ | **RESOLVED**: 254/262 pass; 8 golden-image failures need visual triage (`FQ-000`) | — | Closed | — |
| `UNK-006` | Whether `public.users` is populated for real accounts — FK target for 14+ tables | No live DB access; **`PJ-001` now identifies the specific mechanism and tables affected** | Critical | **YES** | Backend engineer — one read-only query resolves this |
| `UNK-007` | Whether the live Supabase schema matches either `schema.sql` or the tracked migrations in full | No live `information_schema` access | Critical | **YES** | Backend engineer |
| `UNK-008` | Whether historical silent-failure incidents (`DI-002`) caused unrecoverable data loss for real users beyond the documented incident window | No access to production logs/data | High | Contributes to severity, not independently blocking | Release owner |
| `UNK-009` | Supabase billing/plan tier and backup/PITR configuration for the live project (`BR-001`) | No dashboard/billing access | **Critical — top priority** | **YES** | Release owner — could mean zero backups exist at all |
| `UNK-010` | Whether any restore has ever been demonstrated for any backup or migration (`BR-008`, Golden Rule) | No restore-test evidence exists anywhere | High | Compounds `UNK-009` | Release owner |
| `UNK-011` | Whether the informal `dr-niswah-chat` kill-switch (`RD-009`) generalizes to other Supabase-backed features | Would require testing every repository's error path individually | Medium | NO independently | Engineer |

## Assumption Register

| Assumption ID | Description | Evidence | Risk if false | Must verify before GO? |
|---|---|---|---|---|
| `ASM-001` | The Flutter app (`lib/`) + Supabase backend (`supabase/`) is the release candidate under audit; `src/` (React/Vite web app) is a design-reference-only artifact, not a separate shipping product | Prior project guidance (persisted instruction); corroborated by `FLUTTER_UI_PARITY_GUIDE.md`, `MANIFEST.md`, golden-test parity suite, and `src/`'s Firebase/`@google/genai` dependencies matching the orphaned root-level Firebase config files (`CQ-001`/`DC-008`) rather than the Flutter app | If `src/` is actually also shipping (e.g., as a companion web app), this audit's scope is incomplete for that surface | YES, if incorrect — confirm with release owner |
| `ASM-002` | The live Supabase project referenced by the shipped `.env`/`SUPABASE_URL` is the same project all 15 migrations were intended for, in the order presented | Migration filenames are sequentially timestamped and internally reference each other's prior states | If multiple Supabase projects/environments exist with divergent history, `DI-001`/`BR-002`'s exact failure point could differ | Recommend confirming, not independently blocking beyond `UNK-002`/`UNK-007` |
| `ASM-003` | The two-commit git history (`6d59bfe`, `13a9387`) genuinely reflects a squashed/reset history rather than a deliberately obscured one | `RD-008` — the commit message itself uses "clean," consistent with intentional history removal for repository hygiene, not concealment; no evidence either way | Low — does not change the audited code's actual defects, only the confidence in provenance | NO, but should be acknowledged by the release owner |
| `ASM-004` | The audited commit (`13a9387e`) has not changed since the audit began | No RC-CHG-001+ entries recorded in `00_01_RELEASE_CANDIDATE_BASELINE.md`'s change log | If the working tree changed mid-audit, some evidence could be stale | Re-verify commit SHA at final sign-off |
