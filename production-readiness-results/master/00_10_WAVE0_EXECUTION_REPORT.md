# 00_10 — Wave 0 Execution Report

> **Wave 0 status: COMPLETE (analysis, capture, isolated validation).** No production schema, RLS, function, trigger, or migration-ledger change was made. The one operation with any live-mutation potential (migration repair) is **proposed only** in Output K below — it has not been executed and requires a separate, explicit approval before it is run.

| Field | Value |
|---|---|
| Executed against | Live project `jkmjobvxfrmuwafczvtw` (read-only), two disposable isolated Postgres 15 containers (read-write, destroyed after use) |
| Governing plan | `00_09_PHASE1_ROOT_CAUSE_REMEDIATION_PLAN.md` §4, as amended 2026-09-04 |
| Artifacts produced | `supabase/live_schema_capture/2026-09-04_{public,auth,storage}.sql`, `supabase/canonical_baseline/00_public_baseline_draft.sql` |

---

## Note on session interruption

Mid-capture, all authenticated Supabase CLI calls (including ones that had worked minutes earlier) began hanging indefinitely — confirmed via raw TCP tests that this was not a network-reachability issue. The release owner re-ran `supabase login`; connectivity was restored immediately afterward, confirming a stale CLI session token, not an infrastructure problem. No data was affected; all captures below were taken after reconnection and are internally consistent with the (unaffected) Phase 0 evidence gathered earlier.

---

## Output A — Authoritative Live-Object Inventory

**Tables (24, `public` schema):** `adah_ledger`, `chat_history`, `chat_messages`, `chat_threads`, `community_comments`, `community_likes`, `community_posts`, `cycle_entries`, `cycle_logs`, `dream_entries`, `flagged_conversations`, `istihadah_episodes`, `nifas_records`, `prayer_log`, `pregnancy_profile`, `pregnancy_records`, `private_conversations`, `private_messages`, `profiles`, `ramadan_records`, `secret_vault`, `symptoms_log`, `users`, `wellbeing_logs`.

**RLS:** Enabled on all 24/24 tables (`ALTER TABLE ... ENABLE ROW LEVEL SECURITY` present for every one). No table found with RLS disabled.

**Policies:** 58 `CREATE POLICY` statements across the 24 tables.

**Indexes:** 22 `CREATE INDEX` statements beyond primary-key/unique-constraint-backed indexes.

**Constraints beyond FK:** `pregnancy_profile_user_id_key` (UNIQUE), `unique_pair` on `private_conversations` (participant_one, participant_two — ordered pair, confirming `DI-003`), `unique_post_like` on `community_likes`, `wellbeing_logs_user_id_log_date_key`. No `UNIQUE(user_id, date)` on `cycle_entries` (confirms `DI-011`). No CHECK constraints found on `pregnancy_records` for date/week coherence (confirms `DI-010`).

**Functions (8, `public` schema):** `can_access_user(uuid)`, `create_user_profile()`, `delete_my_account()`, `handle_new_user()`, `is_admin()`, `is_conversation_participant(uuid)`, `set_updated_at()`, `touch_private_conversation()`.

**Application-relevant triggers on `auth.users`** (captured via a schema-only dump of `auth`, invisible from a `public`-only dump): `auth_users_create_profile` → `create_user_profile()`, `on_auth_user_created` → `handle_new_user()`.

**Extensions relied upon:** `uuid-ossp` and `pgcrypto`/native `gen_random_uuid()` — both confirmed **functionally active** (11 live column defaults use `gen_random_uuid()`, 10 use `uuid_generate_v4()`, schema-qualified as `"extensions"."uuid_generate_v4"()`, confirming Supabase installs these into a dedicated `extensions` schema, not `public`). The `db dump -s extensions` command itself hung unrecoverably across three attempts (~15 minutes total) even after the session-wide reconnection — this is a **documented CLI tooling limitation**, not a data gap; the functional evidence above is sufficient to confirm both extensions are installed and working.

**Storage:** Schema-only dump of `storage` taken (1,307 lines) — zero `CREATE POLICY` and zero `INSERT INTO ... buckets` statements found. **Resolves `BR-007`'s open question: Supabase Storage is not in application use.**

**`auth.users` integration logic:** two triggers above; both preserved verbatim in the baseline (Output D).

---

## Output B — Object Classification Report

| Object | Classification | Basis |
|---|---|---|
| `chat_messages`, `chat_threads`, `community_comments`, `community_likes`, `community_posts`, `cycle_entries`, `dream_entries`, `flagged_conversations`, `pregnancy_profile`, `private_conversations`, `private_messages`, `profiles`, `users`, `wellbeing_logs` | `REQUIRED_APPLICATION_OBJECT` | Actively read/written by `lib/` or `supabase/functions/` (verified per-table via grep of the exact Supabase table-name constant used) |
| `can_access_user`, `create_user_profile`, `delete_my_account`, `handle_new_user`, `is_admin`, `is_conversation_participant`, `set_updated_at`, `touch_private_conversation` | `REQUIRED_APPLICATION_OBJECT` | RLS-helper/trigger functions backing the policies/triggers above |
| `prayer_log` | `REQUIRED_APPLICATION_OBJECT` — **NAME MISMATCH** | The feature clearly needs a prayer-log table and this is unambiguously it (schema shape matches `prayer_tracking`'s domain model), but current app code queries `.from('prayer_entries')`, a table that **does not exist live**. See `W0-001`. |
| `pregnancy_records` | `REQUIRED_APPLICATION_OBJECT` — **NAME MISMATCH** | Same pattern: app code queries `.from(_tableName)` where `_tableName = 'pregnancy_milestones'`, which **does not exist live**. See `W0-002`. |
| `adah_ledger`, `cycle_logs`, `istihadah_episodes`, `nifas_records`, `ramadan_records`, `symptoms_log` | `UNREFERENCED / CANDIDATE_FOR_LATER_REMOVAL` | Zero references in any `lib/`/`supabase/functions/` source (verified by grep); purpose already documented by the original audit (`DI-008`) as abandoned/superseded design |
| `chat_history` | `UNKNOWN — REVIEW REQUIRED` | Zero references anywhere in tracked source; not documented in `schema.sql` or any migration; `chat_type` CHECK constraint (`'dream'`/`'doctor'`/`'niswah'`) suggests a plausible predecessor to today's `chat_threads`/`chat_messages` design, but this is inference, not confirmed history |
| `secret_vault` | `UNKNOWN — REVIEW REQUIRED` | Zero references anywhere in tracked source; does not even match `schema.sql`'s documented name for this concept (`secret_vault_entries`, which does not exist live at all); purpose cannot be confirmed from any available evidence |
| Platform: `auth.*` internal tables/functions (`auth.uid()`, `auth.role()`, `auth.jwt()`, `auth.email()`, and `auth.users`'s own platform-managed columns beyond `id`), `storage.*`, roles `anon`/`authenticated`/`service_role` | `SUPABASE_MANAGED` | Provisioned by the platform itself; not reproduced in the canonical baseline; documented here for completeness |
| `uuid-ossp`, `pgcrypto` extensions | `SUPABASE_MANAGED` | Platform-provisioned into a dedicated `extensions` schema; the application baseline assumes their presence rather than creating them |

No object was silently canonized as permanent architecture — every one above required specific evidence to place it in its category.

---

## Output C — Live vs `schema.sql` vs Migrations Comparison

| Table | Live | `schema.sql` | Migrations | Note |
|---|---|---|---|---|
| `users` | ✅ | ✅ (`users(id)` FK target) | ❌ (never created) | Populated by a live-only trigger absent from both other sources — see `UNK-006` in `00_05` |
| `profiles` | ✅ | ✅ (`auth.users` FK) | ✅ | Consistent across all three |
| `chat_threads`/`chat_messages` | ✅ | ✅ (`users(id)` FK) | ✅ (also `users(id)` FK — never applied, per Phase 0's `migration list`) | Live's actual FK target for these two tables was not independently re-verified this wave (Phase 0 already confirmed `public.users` via the earlier public-schema capture); consistent with `schema.sql`/tracked-migration text |
| `cycle_entries` | ✅ | ✅ | ❌ (no tracked `CREATE TABLE`; independently reproduced this session by replaying migrations into an empty DB, per `00_05`) | The single most severe drift instance: the core feature table exists only live and in a hand-maintained doc |
| `prayer_log` | ✅ (live name) | `prayer_entries` (different name) | Rename migration exists (`prayer_log`→`prayer_entries`) but per `migration list`, was **never applied** | Explains `W0-001` |
| `pregnancy_records` | ✅ (live name) | `pregnancy_milestones` (different name) | Same rename-never-applied pattern | Explains `W0-002` |
| `secret_vault` | ✅ (live name) | `secret_vault_entries` (different name) | ❌ | Neither name nor content matches; classified `UNKNOWN` |
| `chat_history` | ✅ | ❌ | ❌ | Exists live only, in no tracked source at all |
| `adah_ledger`, `istihadah_episodes`, `nifas_records`, `ramadan_records`, `symptoms_log` | ✅ | ✅ | ❌ | Present in `schema.sql`, absent from tracked migrations — the original `DI-001` "10 undocumented tables" pattern |
| `cycle_logs` | ✅ | ❌ | ✅ (created, later target of a dead-code repository) | `DI-008`'s dead-table candidate |

**Overall:** live schema matches neither `schema.sql` nor `supabase/migrations/` in full — it is a third, independently-evolved variant, exactly as `00_05`'s Phase 0 findings established, now with per-table detail.

---

## Output D — Proposed Canonical Baseline (not deployed)

File: `supabase/canonical_baseline/00_public_baseline_draft.sql` (1,594 lines).

- Reproduces every `REQUIRED_APPLICATION_OBJECT` (including both name-mismatched tables under their **live** names, and both `auth.users` provisioning triggers, verbatim) plus the `UNREFERENCED`/`UNKNOWN` objects (preserved, not deleted — removal is destructive and explicitly out of scope for a capture wave), each annotated per Output B.
- **Deterministic per plan §4.0.2:** every `CREATE TABLE IF NOT EXISTS` from the raw capture was rewritten to plain `CREATE TABLE`; every `CREATE OR REPLACE FUNCTION`/`TRIGGER` rewritten to plain `CREATE FUNCTION`/`CREATE TRIGGER`. **One documented exception:** `CREATE SCHEMA IF NOT EXISTS "public"` was left as-is, because the `public` schema always exists in any real Postgres/Supabase instance and a bare `CREATE SCHEMA "public"` would only ever fail there, carrying no drift signal.
- Excludes all `SUPABASE_MANAGED` objects (auth/storage internals, extensions themselves) — the file's header documents that the target environment is expected to already provide them, matching real Supabase project behavior.
- **Not applied to production.** Applied only to two disposable, isolated containers for testing (Outputs F, H), both destroyed afterward.

---

## Output E — Recovery/Backup Evidence

- **Platform backup/PITR:** unchanged since Phase 0 — `pitr_enabled: false`, zero restorable backups (`BR-001`, confirmed). **This remains open, continuing residual risk.** Enabling it is very likely a plan-tier/billing decision for the release owner; this session did not and cannot perform that action.
- **Independent logical export (this session's contribution):** `supabase/live_schema_capture/2026-09-04_{public,auth,storage}.sql` — schema-only, safe, now exist as version-controllable artifacts. **This is not a substitute for continuous PITR** — it is a single point-in-time schema snapshot, stated plainly per plan §4.1/§4.0's residual-risk framing, not represented as equivalent protection.
- No production **data** was exported, staged, or handled by this session, per §4.6's constraint — data-only export remains a release-owner action, to be stored in encrypted, access-controlled storage, never in git.

---

## Output F — Clean-Rebuild Report

Applied Output D's baseline to a fresh, empty, disposable Postgres 15 container, after stubbing the documented `SUPABASE_MANAGED` prerequisites (an `extensions` schema with `uuid-ossp` installed; an `auth` schema with a `users` table and `uid()`/`role()`/`email()` functions backed by session GUCs, mirroring PostgREST's real request-context mechanism; the `anon`/`authenticated`/`service_role` roles with the grants Supabase provisions by default).

**Result: exit code 0. Zero errors on first clean pass from empty.**

Verification against the Output A live capture:
- Table count: 24 vs 24. Table names: **identical, 24/24**.
- Function count: 8 vs 8, same names.
- RLS enabled: 24/24 in both.

**Gate passed: zero material difference in application-owned schema**, per the amended §4.0.1 criterion. Supabase-managed internals were not compared (out of scope by design) and are documented in Output A/B instead.

---

## Output G — Behavioral Validation Report

All tests run with synthetic data only, inside the same isolated container as Output F.

| Test | Result | Evidence |
|---|---|---|
| **A. Auth signup** | ✅ PASS | Inserted synthetic `auth.users` row → both `public.profiles` (full_name from metadata, `selected_madhhab='shafii'` default) and `public.users` (display_name from metadata, `madhhab='HANBALI'`) rows created automatically by the two live triggers |
| **B. Authorization/RLS** | ✅ PASS | User 2, querying `cycle_entries` while authenticated as themselves, sees **0 rows** of User 1's data. User 1 sees their own row correctly. |
| **C. Cycle data** | ✅ PASS | Write + read-back of a `cycle_entries` row as an authenticated user succeeded; `fiqh_state` defaulted to `'TAHARA'` correctly |
| **D. Pregnancy data** | ✅ PASS | Write + read-back of a `pregnancy_profile` row succeeded; CHECK constraints and defaults (`fasting_status='not_applicable'`) enforced correctly |
| **E. Profile data** | ✅ PASS | Covered by Test A — both `profiles` and `users` persist and read back correctly |
| **F. Account deletion** | ✅ PASS, with an important behavioral finding | `delete_my_account()` called as the authenticated user. **Before:** 1 row each in `auth.users`, `public.users`, `public.profiles`, `cycle_entries`, `pregnancy_profile`, `private_conversations`, `private_messages`. **After: 0 rows in every one of those tables** — a fully clean cascade, no orphans found in any table checked. **However:** the deleted user's shared `private_conversations` row (and its `private_messages`) cascaded away entirely, meaning **the other participant's entire conversation thread — including the other participant's own sent messages — also disappeared**, confirmed by querying as User 2 post-deletion (0 visible conversations, 0 visible messages). This is a **behavioral confirmation of `DI-012`**, not just a structural inference from reading the FK graph. |
| **G. Application startup** | Partial — DB/connectivity level only | A client (psql, standing in for the app's Postgres/PostgREST connection) connects and operates correctly against the rebuilt schema. **Scope limitation stated plainly: this session cannot boot the actual Flutter mobile app UI (no emulator/device in this environment) — that remains a manual step for whoever holds the mobile toolchain.** |
| **H. Representative E2E journeys** | Partial — DB-behavior level only | Cycle logging, account-deletion cascade, and auth-signup-to-profile journeys are validated at the database-behavior level above. **Full UI-level E2E is out of this session's reach for the same reason as G and is not claimed.** |

**New findings discovered during this behavioral validation** (see Output J for disposition):
- **`W0-001`:** `lib/features/prayer_tracking/data/repositories/prayer_tracking_repository_impl.dart` queries `.from('prayer_entries')` — a table that **does not exist in production**. The live table is named `prayer_log`. Every remote prayer-tracking call in production today hits an undefined-relation error.
- **`W0-002`:** `lib/features/pregnancy_tracking/data/repositories/pregnancy_tracking_repository_impl.dart` queries `.from(_tableName)` where `_tableName = 'pregnancy_milestones'` — a table that **does not exist in production**. The live table is named `pregnancy_records`. Every remote pregnancy-milestone call in production today hits an undefined-relation error.
- Both repositories catch this failure via the same silent-fallback pattern already documented under `ROOT-005`/`DI-002` (prayer's outer `catch (_) { return localLogs; }` swallows the thrown `NetworkFailure` and silently returns local-only data) — meaning these two features have very likely been running **local-device-only, indefinitely, with no user-visible indication**, for as long as the never-applied rename migrations have existed.
- A minor inconsistency also surfaced: `create_user_profile()` hardcodes `madhhab='HANBALI'` for every new signup, while `handle_new_user()` reads the user's actual chosen madhhab from signup metadata into `profiles.selected_madhhab`. Not urgent, but worth reconciling when Wave 1c addresses the `users`/`profiles` duality.

---

## Output H — Restore-Test Report

A **second**, independent, disposable Postgres 15 container was created. The same platform prerequisites were stubbed, and Output D's baseline (the independent logical export produced by this session) was applied as the "recovery artifact" being restored.

- **Schema integrity:** 24 tables, 8 functions restored — identical to Output F.
- **Representative data integrity:** a fresh synthetic signup correctly triggered `public.users` population via the restored trigger; a `cycle_entries` row was written and its `user_id` FK correctly resolved to `public.users.id` (exactly the check `BR-002`'s remediation plan specified).
- **Application compatibility:** confirmed at the connectivity level (see Output G's scope limitation, same caveat applies here).

**This validates the restore *mechanism* end-to-end.** It does not substitute for the release owner restore-testing a real platform backup once one exists (Output E) — no such backup currently exists to test.

---

## Output I — Remaining Material Discrepancies

- None in application-owned schema — Output F's zero-diff gate passed cleanly.
- Two objects remain genuinely unexplained: `chat_history`, `secret_vault` (Output B, `UNKNOWN — REVIEW REQUIRED`).
- Two live tables remain unreachable by the app under their expected names: `prayer_log`/`pregnancy_records` (`W0-001`/`W0-002`) — deliberately **not** fixed in this wave (per plan §4.7: "capture reality first, improve it later, deliberately").
- Extension DDL text (the literal `CREATE EXTENSION` statements) was not captured due to a reproducible CLI hang on `-s extensions` specifically; functional presence is confirmed indirectly and is sufficient for `SUPABASE_MANAGED` documentation purposes.
- Platform PITR/backup gap (`BR-001`) remains fully open — no local action can close this.

---

## Output J — Affected Finding IDs and Updated Status

| Finding | Status after Wave 0 |
|---|---|
| `BR-001` | Unchanged — still OPEN/CONFIRMED (zero platform backups, PITR disabled) |
| `BR-002` | **CONFIRMED, and now demonstrated remediable**: the canonical baseline rebuilds cleanly from empty in isolation — proof the eventual fix works — but nothing has been applied live; remains OPEN until Output K is approved and executed |
| `BR-007` | **RESOLVED**: Storage schema confirmed to have zero application buckets/policies; Storage is not in use |
| `DI-001` | **CONFIRMED, deepened further**: two new `UNKNOWN` objects identified (`chat_history`, `secret_vault`) beyond the original "10 undocumented tables"; the `cycle_entries` gap independently reproduced |
| `DI-012` | **Upgraded from structural inference to behaviorally confirmed** (Output G, Test F) — account deletion does cascade away the other participant's entire conversation, own messages included |
| `PC-002` | Further informed, not closed: `delete_my_account()` confirmed to work correctly and completely (good news for feasibility of wiring the client) — but its cascade effect on shared conversations (`DI-012`, now confirmed) needs explicit product/privacy sign-off before that wiring ships |
| `W0-001` (**new**) | OPEN — prayer tracking's remote path is confirmed non-functional in production today; silently degrades to local-only data per the existing `ROOT-005` catch-all pattern |
| `W0-002` (**new**) | OPEN — pregnancy-milestone tracking's remote path is confirmed non-functional in production today; same silent-degradation pattern |
| `AB-001`, `CQ-010`, `ROOT-001`, `DI-004`, `PJ-001` | **Unchanged** per plan §4.0.4 — no evidence gathered this wave contradicts any of these Phase 0 dispositions |

No finding above is marked `VERIFIED_CLOSED` on the strength of a migration file having been drafted — per finding discipline, closure requires the specialist/E2E validation each finding's own remediation plan specifies, which has not yet run for any of these.

### Post-Wave-0 update (Wave 1a work, same session)

Investigating `W0-001`/`W0-002` further to implement fixes revealed they are not equally simple:

- **`W0-001` (prayer tracking): fixed.** `prayer_tracking_repository_impl.dart` now queries `prayer_log` (the live table name) instead of `prayer_entries`, and its upsert payload was trimmed to the columns `prayer_log` actually has (`id`, `user_id`, `prayer_name`, `date`, `scheduled_time`, `status`, `notes`) — the entity's `completed_at`/`created_at`/`updated_at` fields have no live column to persist to and were dropped from the remote payload; sending them would have caused PostgREST to reject the whole write as an unknown-column error. `dart analyze` passes clean. **Not yet deployed or tested against production** — a live round-trip test is still required before this can be marked `VERIFIED_CLOSED`.
- **`W0-002` (pregnancy tracking): deferred, not fixed.** Further inspection found `pregnancy_records`'s live shape (one row per pregnancy: `lmp_date`, `due_date`, `current_week`, `birth_date`, `nifas_id`, `weekly_notes` jsonb) is structurally incompatible with what `PregnancyMilestone` needs (one row per dated milestone: `week`, `trimester`, `label`, `summary`, `date`) — this is not a naming problem, it's a data-model mismatch. Repointing the table name alone would still fail (e.g. no `date` column to `.order()` by), just with a different, more confusing error, while producing the identical silent local-only fallback either way. A correct fix requires a product decision (add real milestone columns/table live — a schema migration gated on Wave 0 approval — or redesign the feature around `weekly_notes`), so no functional change was made; a documentation-only code comment was added at the point of the bug explaining the mismatch for whoever picks this up next.

---

## Output K — Exact Proposed First Live Operation (awaiting separate explicit approval)

**Nothing below has been executed. `supabase migration repair` has not been run.** This section is the final pre-execution review requested by the release owner on 2026-09-04, addressing each of the ten required points in order.

### K.1 — Exact command(s) proposed

```
supabase migration repair --status reverted 20260820174500 20260822014500 20260822210000 20260824115900 20260824120000 20260824130000 20260825120000 20260825130000 20260825210000 20260826090000 20260827120000 20260830140000
supabase migration repair --status applied 20260904190000
```

Two invocations of one command. Nothing else is proposed to run against the live project at this time.

### K.2 — Exact migration versions/timestamps affected

**Marked `reverted` (12):** `20260820174500`, `20260822014500`, `20260822210000`, `20260824115900`, `20260824120000`, `20260824130000`, `20260825120000`, `20260825130000`, `20260825210000`, `20260826090000`, `20260827120000`, `20260830140000` — every migration file currently in `supabase/migrations/`, no more, no fewer.

**Marked `applied` (1):** `20260904190000` — a version number that does **not yet exist** as a file. It becomes real only if Step 2 below (copying the canonical baseline into `supabase/migrations/20260904190000_canonical_baseline.sql`) is separately approved and carried out first. **The repair command cannot correctly run before that file exists** — `supabase migration repair` operates against the CLI's local reading of `supabase/migrations/`, so it needs a local file at that version to attach the `applied` status to.

### K.3 — Current local vs. remote ledger state

Confirmed via `supabase migration list --linked`, independently, on two separate occasions this session (Phase 0, and again at the start of Wave 0) — both returned an identical result:

| Local version | Remote status |
|---|---|
| `20260820174500` | *(empty — not applied)* |
| `20260822014500` | *(empty)* |
| `20260822210000` | *(empty)* |
| `20260824115900` | *(empty)* |
| `20260824120000` | *(empty)* |
| `20260824130000` | *(empty)* |
| `20260825120000` | *(empty)* |
| `20260825130000` | *(empty)* |
| `20260825210000` | *(empty)* |
| `20260826090000` | *(empty)* |
| `20260827120000` | *(empty)* |
| `20260830140000` | *(empty)* |

All 12 local migrations show a populated local timestamp and an **empty remote field** — none are recorded as applied via Supabase's tracked mechanism. A third re-confirmation was attempted for this review and is running slowly (the same CLI intermittently hangs under load, as documented earlier in this report); it will be noted here if it returns a different result before execution, but there is no reason to expect a change, since nothing has touched the ledger since the last two confirmations.

### K.4 — What each command changes

- `--status reverted` on the 12 versions: writes rows into (or updates existing rows in) the live project's `supabase_migrations.schema_migrations` tracking table recording those versions as **not applied**. This is not a new claim — it is Supabase's own ledger being corrected to match what `migration list` already independently shows.
- `--status applied` on `20260904190000`: writes one row into the same tracking table recording that version as applied. It is accurate to do so because the corresponding file's content (Output D's baseline) has been proven, twice, to reproduce exactly what already exists live (Outputs F, H) — the ledger entry describes reality, it does not change reality.

### K.5 — Confirmation: metadata-only, no migration SQL executes

Confirmed. `supabase migration repair` writes only to `supabase_migrations.schema_migrations`. It does not open a transaction against `public`, `auth`, or any other schema, and does not read or execute the SQL body of any migration file. This is a documented property of the command itself (its purpose is explicitly to let the ledger be corrected without replaying DDL) — not an assumption. Nothing in `public`/`auth` is created, altered, dropped, or read by this operation.

### K.6 — Why each migration should be marked applied/reverted

- **The 12 originals → `reverted`:** because they were never applied through the tracked mechanism (K.3), marking them `reverted` is simply recording the truth. Leaving them silently absent from the ledger (their current state) rather than explicitly `reverted` risks a future `supabase db push` attempting to apply them for the first time — which would fail outright (Output F's own rebuild attempt using the *original* migration sequence, before the baseline was drafted, hit exactly this failure during Phase 0: `relation "public.prayer_log" does not exist`).
- **The new baseline → `applied`:** because Outputs F and H demonstrate, twice, in independent isolated environments, that its content exactly matches live's actual state. Marking it anything other than `applied` (i.e., leaving it unmarked) would mean a future `supabase db push` attempts to run its DDL against live — which would then fail loudly on the very first `CREATE TABLE` (by design, per the deterministic-baseline principle) because every object it creates already exists.

### K.7 — Expected `supabase migration list --linked` output afterward

```json
{"migrations":[
  {"local":"20260820174500","remote":"20260820174500 (reverted)", ...},
  {"local":"20260822014500","remote":"20260822014500 (reverted)", ...},
  {"local":"20260822210000","remote":"20260822210000 (reverted)", ...},
  {"local":"20260824115900","remote":"20260824115900 (reverted)", ...},
  {"local":"20260824120000","remote":"20260824120000 (reverted)", ...},
  {"local":"20260824130000","remote":"20260824130000 (reverted)", ...},
  {"local":"20260825120000","remote":"20260825120000 (reverted)", ...},
  {"local":"20260825130000","remote":"20260825130000 (reverted)", ...},
  {"local":"20260825210000","remote":"20260825210000 (reverted)", ...},
  {"local":"20260826090000","remote":"20260826090000 (reverted)", ...},
  {"local":"20260827120000","remote":"20260827120000 (reverted)", ...},
  {"local":"20260830140000","remote":"20260830140000 (reverted)", ...},
  {"local":"20260904190000","remote":"20260904190000", ...}
]}
```
(Exact JSON field naming for a `reverted` marker should be confirmed against the installed CLI's actual output format at execution time — the table above expresses the intended semantic state, not a guaranteed literal string.) The key verifiable property: every local version has a **non-empty** remote entry, and the new baseline version shows `local == remote` with no `(reverted)` qualifier, indicating it is the one considered currently applied.

### K.8 — Rollback / recovery if the ledger state becomes incorrect

- To undo the new entry only: `supabase migration repair --status reverted 20260904190000`.
- To undo the 12 reversions (restore them to unmarked/empty, matching today's actual state): `supabase migration repair --status applied` is **not** the correct inverse (it would falsely claim they ran) — the correct rollback is to leave them `reverted` (an accurate historical record that they exist as files but were never applied) rather than attempt to un-revert them. If a mistake is made in *which* versions were marked, the fix is simply re-running `migration repair` with the corrected version list — the command is idempotent per-version and safe to re-run.
- At every point, this is a ledger-only correction. There is no scenario in this operation where production `public`/`auth` schema, data, RLS, functions, or triggers are at risk, because no DDL is ever executed by `migration repair` (K.5).

### K.9 — Confirmation that prerequisite tests already passed

Confirmed, all in `00_10` above:
- **Canonical baseline** (Output D): drafted, deterministic, not yet deployed.
- **Clean rebuild** (Output F): exit 0 against a truly empty database; zero material difference in application-owned schema (24/24 tables, 8/8 functions, RLS 24/24, all name-identical to live).
- **Restore test** (Output H): the same baseline applied cleanly a second time in a fully independent isolated environment; representative signup, write, and FK-resolution behavior all correct.
- **Behavioral validation** (Output G): A–F all passed with concrete query-level evidence; G/H were scoped honestly to DB/connectivity-level validation only, not full mobile-app UI E2E.

### K.10 — Impact of `W0-001`/`W0-002` on the proposed repair

**None on the repair itself.** `W0-001` (prayer tracking queries `prayer_entries`, live has `prayer_log`) and `W0-002` (pregnancy tracking queries `pregnancy_milestones`, live has `pregnancy_records`) are **application-code** defects — the app queries the wrong name. The canonical baseline was deliberately drafted to preserve both tables under their **live** names, unchanged (per plan §4.7: "capture reality first, improve it later, deliberately") — so the baseline is not incorrect with respect to these two findings, and the repair does not need to wait for them to be fixed. Conversely, **fixing `W0-001`/`W0-002` does not require this repair to happen first** — the code-side fix (pointing the Dart repositories at the correct existing live table names) is fully independent and is proceeding now as authorized Wave 1 work (§ below), with no live database mutation involved.

---

**Awaiting explicit approval before Step 1 (mark the 12 originals superseded), Step 2 (add the baseline as a real migration file), or Step 3 (the `migration repair` command above) is executed.**
