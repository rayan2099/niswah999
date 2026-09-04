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

## Phase 0 Resolution — Remediation Session (2026-09-04)

Performed by the remediation engineer (not the original audit) prior to any code changes, per the remediation charter's Phase 0. Evidence and verdicts below; native finding IDs preserved throughout.

### `UNK-001` — RESOLVED (favorably)

- **Evidence required:** one authenticated live smoke-test call against the exact endpoint/request/response shape hardcoded in `gemini_service.dart` and `dr-niswah-chat/index.ts`.
- **Verification performed:** Live `curl` calls reproducing the app's exact call shape (`POST https://generativelanguage.googleapis.com/v1beta/interactions`, header `x-goog-api-key`, body `{model, input, system_instruction}`), using the real `GEMINI_API_KEY` from `.env`:
  1. `model: gemini-3.5-flash-lite` (the client's primary model) → HTTP 500, structured JSON error `"gemini-3.5-flash-lite is currently experiencing high demand"` — i.e., a genuine upstream API error, not a routing/404 failure.
  2. `model: gemini-3.6-flash` (the client's own configured fallback) → **HTTP 200**, full valid response: `"object":"interaction"`, `"status":"completed"`, a `steps[]` array containing a `{"type":"model_output","content":[{"type":"text","text":"Hello."}]}` block — this is exactly the shape `GeminiService._modelOutputBlocks()` parses. The two-call sequence also happens to exercise the app's real primary→fallback retry logic end-to-end, live.
  3. Control A: a certainly-nonexistent path (`/v1beta/garbagepath123`) on the same host returned a fast 404 in 0.4s — proving Google's frontend responds quickly to bad paths, and that `/v1beta/interactions` is not that.
  4. Control B: `ListModels` (`/v1beta/models`) confirmed the API key is valid/active and that every model name referenced in the app's code (`gemini-3.5-flash-lite`, `gemini-3.6-flash`, `gemini-3.5-flash`) is a real, currently-served model — ruling out the "hallucinated model name" half of the concern as well.
- **Verdict:** **RESOLVED.** The endpoint, request shape, and response parsing are real and functional today. This is evidently a genuine, newer Gemini "Interactions" API surface that postdates both this remediation engineer's and the original audit's training/knowledge cutoff — not a hallucinated integration.
- **Findings affected:**
  - `ROOT-001` — **not confirmed; disproven.** Close as N/A.
  - `AB-001` (BLOCKER, pending live validation) — **downgrade to CLOSED/VERIFIED.** The "3 of 4 AI features silently non-functional" risk did not materialize.
  - `CQ-010` (same root cause, independently derived) — **downgrade to CLOSED/VERIFIED**, same evidence.
  - Does **not** affect `OB-003`/`OB-004` (the edge function still swallows failures with no logging *if* a failure occurs — unrelated to whether the endpoint itself works) or `SEC-001`/`DC-001`/`AB-002` (client-embedded key exposure — an orthogonal defect regardless of endpoint correctness). Both remain OPEN.

### `UNK-002` — RESOLVED (CONFIRMED FINDING): migrations have NOT been applied to the live project

- **Evidence required:** `supabase db diff` (or `information_schema` query) against the linked live project; or dashboard schema review.
- **Verification performed (2026-09-04, addendum):** The user authenticated the Supabase CLI (`supabase login`) and authorized read-only verification. Confirmed via `supabase projects list` that exactly one project matches this repo's `.env` (`SUPABASE_URL=https://jkmjobvxfrmuwafczvtw.supabase.co`) — project `Niswah`, ref `jkmjobvxfrmuwafczvtw`, region `ap-southeast-1`, Postgres 17.6.1, status `ACTIVE_HEALTHY`. Linked to it (`supabase link --project-ref jkmjobvxfrmuwafczvtw`, no DB password required). Ran `supabase migration list --linked` (read-only): **all 12 tracked local migrations show a populated `local` timestamp but an empty `remote` field** — none are recorded in Supabase's own migration-tracking ledger as ever having been applied to the live project via the CLI/standard migration mechanism.
- **Verdict:** **RESOLVED — CONFIRMED FINDING.** The tracked migration history was not used to build or evolve the live database (at least not through the CLI's tracked mechanism). This is corroborated end-to-end by the `UNK-007` schema dump below (see next section), which shows the live schema as a third, independently-drifted variant matching neither `schema.sql` nor the tracked migrations in full.
- **Findings affected:** `DI-001`/`BR-002` — further confirmed (see `UNK-007`). `SEC-010`(migration-application unknown) — resolved unfavorably.

### `UNK-007` — RESOLVED (CONFIRMED FINDING): live schema matches neither `schema.sql` nor tracked migrations

- **Evidence required:** live schema export compared against `schema.sql` and the tracked migrations.
- **Verification performed:**
  1. First attempted `supabase db diff --linked -s public` (the CLI's own recommended comparison tool, called for by name in the `DI`/`BR`/`SEC` remediation plans). This tool must first replay the local tracked migrations into a disposable shadow database before it can diff against the live project. **It failed outright**: `ERROR: relation "public.prayer_log" does not exist (SQLSTATE 42P01)` at migration 2/12 (`20260822014500_niswah_schema_sync_and_indexes.sql`, a `DROP POLICY ... ON public.prayer_log` statement), producing `{"code":"LegacyDeclarativeShadowDbError","message":"failed to provision the shadow database: exit 1"}`. This independently reproduces `BR-002`/`DI-001` a second, distinct way (this time via Supabase's own official tooling, not a manual replica), and pinpoints a second concrete missing-table name (`prayer_log`) in addition to the two found earlier this session (`prayer_entries`, `cycle_entries`).
  2. Since the diff tool itself cannot run, pivoted to `supabase db dump --linked -s public` — a direct, schema-only (`pg_dump --schema-only`, confirmed via `--dry-run` before executing) export of the **actual live production schema**, independent of the broken local-migration-replay path. This is read-only and pulls no row data. Result saved to a local scratch file (not committed, not distributed).
  3. **The live schema is a third, distinct variant, matching neither document:**
     - Contains `prayer_log` (not `prayer_entries`, `schema.sql`'s name) — the tracked "rename prayer_log → prayer_entries" migration was evidently never applied live, consistent with `UNK-002`.
     - Contains `pregnancy_records` (not `pregnancy_milestones`) — same pattern, another un-applied rename.
     - Contains `secret_vault` (not `secret_vault_entries`).
     - Contains `chat_history` — a table that exists **live only**; zero mentions anywhere in `schema.sql`, any tracked migration, or `lib/`.
     - Contains two live-only functions absent from every tracked source — `create_user_profile()` and `delete_my_account()` — see `UNK-006` below.
     - 16 tables' FKs (`cycle_entries`, `chat_threads`, `chat_messages`, `flagged_conversations`, `community_posts`, and 12 others) target `public.users(id)` live — matching `schema.sql`'s pattern, **not** the tracked migration for `chat_threads`/`chat_messages` (which specifies the identical `users(id)` text but that migration itself was never applied per `UNK-002`, so this convergence is coincidental, not causal).
  4. Additionally attempted a schema-only dump of the `auth` schema (`supabase db dump --linked -s auth`) — succeeded, read-only, and is what resolved `UNK-006` below.
- **Verdict:** **RESOLVED — CONFIRMED FINDING.** The live production schema was built and evolved through direct, out-of-band SQL execution (almost certainly the Supabase Studio SQL editor), essentially bypassing the tracked migration system entirely. `schema.sql` is a stale, hand-maintained approximation; `supabase/migrations/` is an incomplete, never-actually-applied parallel history. Neither is the real source of truth — the *live database itself* is the only current source of truth, and it exists nowhere in version control.
- **Findings affected:** `DI-001` — **CONFIRMED FINDING**, materially deepened (live-schema-drift now proven directly, not inferred; `chat_history`/`secret_vault` naming/existence drift newly discovered). `BR-002` — **CONFIRMED FINDING**, reproduced twice over (manual Docker replay + official CLI shadow-db provisioning), both independently. `ROOT-007` — escalated: this is not just "hard to rebuild," it is proven that a live-only, business-critical mechanism (see `UNK-006`) is completely unrecoverable from this repository as it stands today.

### `UNK-006` — RESOLVED (favorably): `public.users` IS populated live

- **Evidence required:** live query confirming every `auth.users` row has a matching `public.users` row.
- **Verification performed:** The `auth` schema dump (schema-only, read-only, see `UNK-007` step 4) revealed the actual trigger wiring on `auth.users`, which is invisible from a `public`-only dump since the trigger objects belong to the (platform-managed, excluded-by-default) `auth` schema:
  ```
  CREATE OR REPLACE TRIGGER "auth_users_create_profile" AFTER INSERT ON "auth"."users" FOR EACH ROW EXECUTE FUNCTION "public"."create_user_profile"();
  CREATE OR REPLACE TRIGGER "on_auth_user_created" AFTER INSERT ON "auth"."users" FOR EACH ROW EXECUTE FUNCTION "public"."handle_new_user"();
  ```
  **Both triggers are live and active.** `create_user_profile()` — a live-only function, absent from every tracked migration and from `schema.sql` — inserts into `public.users(id, email_hash, display_name, madhhab, language, onboarding_completed, premium_status, created_at, updated_at)` with `ON CONFLICT (id) DO NOTHING`, firing on every new signup alongside the already-known `handle_new_user()` → `profiles` trigger.
- **Verdict:** **RESOLVED, favorably.** `public.users` is in fact populated for every real account today — the original code-only concern (no *tracked* code path populates it) was correct as written, but the live system is safe because of an out-of-band trigger that was never committed to version control. `DI-004`/`PJ-001`'s worst-case scenario (100% write failure across 16 dependent tables) is **not occurring in production**.
- **However — this is not fully good news.** It is simultaneously the single clearest proof this session found of `DI-001`'s core claim: business-critical logic (the entire `public.users` provisioning path, plus a working `delete_my_account()` account-deletion RPC — see below) exists **only** in the live database and **nowhere** in this repository. If the database were ever lost and rebuilt from `supabase/migrations/` alone (per `BR-002`), new signups would populate `profiles` but never `public.users`, and all 16 dependent tables would begin hard-failing every write for every new user — a *worse*, silently-triggered version of the exact incident `DI-002`/`PJ-002` already describes, and one the current tracked migrations would not prevent or even reveal.
- **Bonus discovery, material to `PC-002`:** the same live-only, untracked surface includes a working `delete_my_account()` RPC (`SECURITY DEFINER`, deletes the `auth.users` row for the calling session, relying on existing `ON DELETE CASCADE` FKs to cascade everywhere) — confirmed via `grep` that the Flutter client **never calls it** (zero references to `delete_my_account`/`deleteAccount` anywhere in `lib/`). `PC-002`'s account-deletion gap is real, but the remediation is smaller than originally scoped: wiring an existing, already-deployed, already-correct server-side RPC into a client screen — not building new deletion logic from scratch. (This RPC, like `create_user_profile()`, still needs to be captured in a tracked migration — it does not currently exist in version control at all.)
- **Findings affected:** `DI-004` — **RESOLVED, favorably** (live query equivalent obtained via direct trigger inspection). `PJ-001` — **RESOLVED, favorably** for present-day write correctness, but the *mechanism* PJ-001 worried about (undocumented, unrecoverable live provisioning) is now proven to literally exist, just via a different table (`public.users` via an untracked trigger, not "no path exists at all"). `PC-002` — remediation scope narrowed (wire existing RPC, not build new one); still OPEN.

### `UNK-009` — RESOLVED (CONFIRMED FINDING, worst case): zero backups exist, PITR disabled

- **Evidence required:** Supabase dashboard/billing review (Project Settings → Database → Backups).
- **Verification performed:** `supabase backups list --project-ref jkmjobvxfrmuwafczvtw` (read-only, no dashboard/billing access needed once CLI-authenticated) returned:
  ```json
  {"region":"ap-southeast-1","walg_enabled":true,"pitr_enabled":false,"backups":[],"physical_backup_data":{}}
  ```
- **Verdict:** **RESOLVED — CONFIRMED FINDING, the worst case the audit flagged.** `pitr_enabled: false` and an empty `backups: []` list mean there are, right now, **zero restorable backups of any kind** for the live Niswah database, and point-in-time recovery is off. (`walg_enabled: true` indicates the underlying backup engine is present at the infrastructure level, but has produced no actual restorable backups — consistent with a plan tier where physical backups are not yet provisioned/retained.)
- **Findings affected:** `BR-001` — **CONFIRMED FINDING** (was "critical unknown," now a confirmed, current-state gap). Combined with `BR-002`'s confirmed migration-rebuild failure (`UNK-007` above), **the live database currently has no recovery path of any kind** — not from a platform backup, and not from this repository's migrations. `BR-004` (no DR runbook/RPO/RTO) and `BR-008` (no restore ever demonstrated) are both moot-but-urgent until this is remediated — there is nothing to restore yet.

### Net effect on launch risk (final, Phase 0 complete)

- **Two BLOCKER findings close favorably** (`AB-001`, `CQ-010`) and one root cause is disproven (`ROOT-001`) — the AI integration works end-to-end; genuinely good news.
- **`DI-004`/`PJ-001` (the `users`-table population question) also close favorably** — production is not currently broken. But the *way* it's not broken (a live-only, untracked trigger) is itself now the clearest, most concrete instance of `DI-001`'s central claim found anywhere in this audit.
- **`BR-002`/`DI-001` (schema recoverability) are confirmed twice over, independently**, and materially deepened: the live schema is proven (via direct schema-only export, not inference) to be a third variant matching neither `schema.sql` nor the tracked migrations, containing at least one entire table (`chat_history`) and two entire functions (`create_user_profile`, `delete_my_account`) that exist **only** in production.
- **`BR-001` (backup existence) is confirmed unfavorably** — zero backups, PITR off. This was previously the audit's single "top priority, could mean the app has literally no recovery path at all" unknown; that worst case is now the confirmed reality.
- **`PC-002` (account deletion) remediation scope narrows** — a working server-side deletion RPC already exists and is simply unwired from the client, rather than needing to be built from nothing.
- **All 5 original critical unknowns are now resolved** (3 favorably in isolation — Gemini, users-population, — wait, users-population resolution surfaces a *worse* systemic risk even though the immediate symptom is absent; 2 unfavorably — schema recoverability, backup existence).
- **Overall verdict impact:** Still, and more clearly, **NO-GO**. The single most important fact to come out of Phase 0: **if the Niswah production database were lost right now, it cannot be rebuilt from this repository (`BR-002`, confirmed twice), and there is no backup to restore from either (`BR-001`, confirmed)** — this is total, unmitigated, unrecoverable data-loss exposure for a live health-data product, now confirmed rather than merely suspected.

---

## Assumption Register

| Assumption ID | Description | Evidence | Risk if false | Must verify before GO? |
|---|---|---|---|---|
| `ASM-001` | The Flutter app (`lib/`) + Supabase backend (`supabase/`) is the release candidate under audit; `src/` (React/Vite web app) is a design-reference-only artifact, not a separate shipping product | Prior project guidance (persisted instruction); corroborated by `FLUTTER_UI_PARITY_GUIDE.md`, `MANIFEST.md`, golden-test parity suite, and `src/`'s Firebase/`@google/genai` dependencies matching the orphaned root-level Firebase config files (`CQ-001`/`DC-008`) rather than the Flutter app | If `src/` is actually also shipping (e.g., as a companion web app), this audit's scope is incomplete for that surface | YES, if incorrect — confirm with release owner |
| `ASM-002` | The live Supabase project referenced by the shipped `.env`/`SUPABASE_URL` is the same project all 15 migrations were intended for, in the order presented | Migration filenames are sequentially timestamped and internally reference each other's prior states | If multiple Supabase projects/environments exist with divergent history, `DI-001`/`BR-002`'s exact failure point could differ | Recommend confirming, not independently blocking beyond `UNK-002`/`UNK-007` |
| `ASM-003` | The two-commit git history (`6d59bfe`, `13a9387`) genuinely reflects a squashed/reset history rather than a deliberately obscured one | `RD-008` — the commit message itself uses "clean," consistent with intentional history removal for repository hygiene, not concealment; no evidence either way | Low — does not change the audited code's actual defects, only the confidence in provenance | NO, but should be acknowledged by the release owner |
| `ASM-004` | The audited commit (`13a9387e`) has not changed since the audit began | No RC-CHG-001+ entries recorded in `00_01_RELEASE_CANDIDATE_BASELINE.md`'s change log | If the working tree changed mid-audit, some evidence could be stale | Re-verify commit SHA at final sign-off |
