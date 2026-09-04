# 00_09 — Phase 1: Root-Cause Remediation Plan

> **PLANNING ONLY. NOTHING IN THIS DOCUMENT HAS BEEN IMPLEMENTED.** No code, configuration, migration, or production-database change has been made as part of this phase. This plan requires explicit review and approval before any execution wave begins. Per the remediation charter, this supersedes no specialist remediation plan (`SEC_remediation_plan.md`, `DI_remediation_plan.md`, etc.) — it sequences and gates them against each other and against the Phase 0 evidence in `00_05_UNKNOWN_ASSUMPTION_REGISTER.md`.

| Field | Value |
|---|---|
| Baseline | `1.0.0+1` / commit `13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f` |
| Precondition | Phase 0 complete — all 5 critical unknowns resolved (`00_05` §Phase 0 Resolution) |
| Status | **Wave 0 EXECUTED and COMPLETE (analysis/capture/isolated-validation only) — see `00_10_WAVE0_EXECUTION_REPORT.md` for full outputs A–K. No production mutation occurred; the proposed migration-repair operation (Output K) awaits separate explicit approval. Waves 1+ remain PROPOSED, not authorized.** |

> **Amendment (2026-09-04):** The release owner approved this plan with 17 binding amendments to Wave 0, incorporated into §4 below. In summary: the clean-rebuild gate is redefined as "zero material difference in application-owned schema," the canonical baseline must be deterministic (no blanket `IF NOT EXISTS`/`CREATE OR REPLACE` used to paper over drift), every live object must be classified into one of five categories before being canonized, no live migration-ledger or schema change of any kind occurs during Wave 0, and the migration-repair step at the end requires a separate, explicit, out-of-band approval — this document only *proposes* the exact command at that point, it does not execute it.

---

## 1. The One Rule That Governs Every Wave Below

> **No live production database mutation of any kind — schema, RLS policy, trigger, index, constraint, or migration-ledger metadata — may occur until Wave 0 (§4) is complete.**

This is stricter than "be careful." It applies even to changes that look small or safe in isolation (e.g. `SEC-004`'s RLS policy fix, `DI-011`'s `UNIQUE` constraint) — because Phase 0 proved the current migration chain does not replay, so *any* new migration authored on top of it inherits an unverified foundation. Every wave below is tagged **DB mutation: YES/NO**, and every YES is gated on Wave 0.

App-code-only changes (Flutter client, Edge Function logic, CI, signing config) are **not** subject to this gate and may proceed in parallel with Wave 0.

---

## 2. Findings Already Closed by Phase 0 — Excluded From Remediation

| Finding | Disposition | Why no remediation is needed |
|---|---|---|
| `AB-001` | **VERIFIED CLOSED** | Gemini endpoint/shape confirmed real and functional by live smoke test. No fix required. |
| `CQ-010` | **VERIFIED CLOSED** | Same evidence as `AB-001`. |
| `ROOT-001` | **DISPROVEN** | Not a defect. Removed from all remediation sequencing below. |
| `DI-004` | **CLOSED (favorable)** | Live-only trigger (`auth_users_create_profile`→`create_user_profile()`) populates `public.users` today. No FK-violation remediation needed on the *current* live table. |
| `PJ-001` | **CLOSED (favorable)** | Same mechanism as `DI-004`. The write path works today. |

**Important:** closing these findings does **not** remove their underlying evidence from this plan — the *mechanism* that makes `DI-004`/`PJ-001` safe (an untracked, live-only trigger) is now the leading evidence for Wave 0's priority. See §3.

`PC-002` is **not** closed, but its scope is narrowed (§7, Wave 5) — a working `delete_my_account()` RPC already exists; the fix is wiring, not building.

---

## 3. Findings Confirmed / Deepened by Phase 0 — Elevated Priority

| Finding | Change |
|---|---|
| `BR-001` | Was "critical unknown." Now **CONFIRMED**: `pitr_enabled: false`, zero backups exist. |
| `BR-002` | Was "traced by audit." Now **CONFIRMED twice, independently** (manual replay + official CLI shadow-db). |
| `DI-001` | **CONFIRMED, deepened**: live schema is a third variant matching neither `schema.sql` nor migrations; `chat_history` table and `create_user_profile()`/`delete_my_account()` functions exist **only** in production. |
| `ROOT-007` | Escalated from "highest" (tied with `ROOT-002`/`ROOT-005`) to **the single gating prerequisite for this entire plan** — see §4. |

---

## 4. Wave 0 — Production Database Preservation & Reproducibility (Priority 0, PREREQUISITE)

**Findings addressed:** `BR-001`, `BR-002`, `BR-003`, `BR-004`, `BR-005`, `BR-007`, `BR-008`, `DI-001`, `DI-005`, `DI-006`, `DI-004`/`PJ-001` (informing, already closed — see §4.0.4).
**Affected audits:** Database, Backup & Recovery, Final User Journey.
**Dependencies:** None — this is the root prerequisite.
**Production access required:** Read-only throughout this wave. **Zero live schema, RLS, function, trigger, or migration-ledger writes occur in Wave 0.** The one operation with any live-mutation potential (§4.11, migration repair) is *proposed only* at the end — it is not executed without a separate, explicit, out-of-band approval.
**Regression risk to production:** None — nothing in this wave touches production write paths.

### 4.0 — Definitions (binding for this wave and all later gated waves)

**4.0.1 — Clean-rebuild exit criterion (amended).** The gate is: **zero material difference across application-owned schema and required application behavior.** It is *not* literal zero-diff against every object Supabase's platform itself manages. Application-owned scope includes, where applicable: public tables, columns, constraints, indexes, RLS policies, application functions, RPCs, application-relevant triggers, and the auth-to-public integration logic Niswah actually depends on (the two provisioning triggers, `delete_my_account()`). Supabase-managed internals (platform schemas such as `auth`'s own internal tables/functions not authored by this project, `storage`'s internal machinery, `realtime`, `_analytics`, `pgbouncer`, `supabase_admin`-owned objects, etc.) are documented separately as platform context, not blindly reproduced or asserted equal.

**4.0.2 — Deterministic baseline (amended).** The canonical baseline migration must **not** use `IF NOT EXISTS` or `CREATE OR REPLACE` merely to paper over uncertainty about existing state. Default statements are plain `CREATE TABLE`, `CREATE FUNCTION`, `CREATE TRIGGER`, etc. — which already fail loudly (Postgres raises a duplicate-object error) if reality doesn't match expectation, which is the desired behavior per this amendment. Idempotent guards are permitted **only** where a specific, named technical reason requires them (e.g. `CREATE EXTENSION IF NOT EXISTS "uuid-ossp"` — extensions are commonly pre-installed by the platform itself and a bare `CREATE EXTENSION` failing on "already exists" is not a meaningful signal), and every such exception must be commented in the baseline file explaining why.

**4.0.3 — Object classification (new requirement).** Every live object inventoried in §4.2 must be classified as exactly one of:
- `REQUIRED_APPLICATION_OBJECT` — the app depends on it; must appear in the canonical baseline.
- `SUPABASE_MANAGED` — platform-owned; documented, not reproduced.
- `LEGACY_BUT_CURRENTLY_REFERENCED` — old naming/shape (e.g. `prayer_log`, `pregnancy_records`, `secret_vault`) that live code still actually reads/writes; preserved under its live name in the baseline, flagged for a later, deliberate rename decision (not bundled into Wave 0).
- `UNREFERENCED / CANDIDATE_FOR_LATER_REMOVAL` — exists live, nothing in `lib/`/`supabase/functions/` references it; preserved in the baseline (removal is destructive and out of scope for a capture wave) but flagged for a future, separately-authorized cleanup migration.
- `UNKNOWN — REVIEW REQUIRED` — cannot be classified confidently from available evidence; preserved as-is, flagged for release-owner review before any future change touches it.
No object is silently canonized as permanent architecture just because it exists in production.

**4.0.4 — Phase 0 findings preserved.** `AB-001`, `CQ-010`, `ROOT-001`, `DI-004`, `PJ-001` keep their Phase 0 dispositions (§2) unless Wave 0 surfaces evidence that contradicts them. Wave 0 does add new root-cause implications from the hidden-trigger discovery (see `UNK-006`'s "however" paragraph in `00_05`) — those implications feed `DI-001`/`ROOT-007`, not a reopening of `DI-004`/`PJ-001` themselves.

### 4.1 — Establish a safe recovery point *(OWNER ACTION REQUIRED where platform-level; independent logical export performed by this session)*

Per the amended recovery prerequisite: the preferred state is Supabase PITR/backup enabled **plus** an independent logical export. Phase 0 confirmed `pitr_enabled: false`, `backups: []` — enabling PITR is very likely a plan-tier/billing decision outside what this session can or should perform unilaterally; it is called out explicitly, not silently assumed. **This session will produce the independent logical export itself** (schema-only, safe; data-only handled per §4.6's privacy constraint) as the recovery artifact this wave actually tests against (§4.10). If PITR remains disabled, that is recorded as **continuing residual risk**, not treated as equivalent to a manual dump — a manual export is a one-point-in-time artifact, not continuous protection.
- DB mutation: No.
- Exit criterion (Wave 0 scope): at least one independent logical export exists and has been restore-tested (§4.10). Full exit criterion for *later* production-mutating waves additionally requires platform PITR/backup — see §4.12.

### 4.2 — Authoritative live capture (read-only)

Produce a complete, application-relevant inventory, per schema, covering: tables, columns, data types, defaults, primary keys, foreign keys, unique constraints, check constraints, indexes, RLS enabled/disabled state, RLS policies, functions, RPCs, triggers, extensions relied upon, `auth.users` integration logic, and any Storage-related application objects if Storage is actually in use. Stored under a new, clearly-labeled path — **not** overwriting `schema.sql` yet.
- DB mutation: No.

### 4.3 — Object classification report

Classify every object from §4.2 into the §4.0.3 taxonomy. Produced as a standalone, reviewable table (see Output B, §4.14).
- DB mutation: No.

### 4.4 — Three-way comparison

For every object: present/absent/matching across **A. live production**, **B. `supabase/schema.sql`**, **C. `supabase/migrations/`**. This is the definitive "what is actually true" ledger `DI-001`/`BR-002` have circled since Wave 1 of the original audit.
- DB mutation: No.

### 4.5 — Understand preserved known-good behavior (before touching anything)

For each of `auth_users_create_profile`→`create_user_profile()`, `on_auth_user_created`→`handle_new_user()`, and `delete_my_account()`: read the exact live definition, trace every table/column it touches, every RLS policy that gates it, and every downstream cascade or side effect. Do not rewrite or replace any of them in this wave — this step is understanding only. `delete_my_account()`'s exact cascade/anonymization scope is tested behaviorally in §4.10.F, not assumed from reading the SQL alone.
- DB mutation: No.

### 4.6 — Preserve production data (constrained)

An independent **data**-only export is a real point-in-time artifact containing real health/religious/message data. Per this session's own operating constraints (never handle real user PHI-adjacent data outside owner-managed storage), any data-only export is **not** pulled into this session's local/disposable environment — it is documented as a required artifact for the release owner to produce and store in encrypted, access-controlled storage, not committed to git and not staged locally by this session. The restore test in §4.10 instead uses **synthetic** data created fresh inside the isolated test environment, which validates the *mechanism* without handling real records.
- DB mutation: No.

### 4.7 — Canonical baseline: proposed, not deployed

Draft **one** new, deterministic (§4.0.2) baseline migration file that reproduces every object classified `REQUIRED_APPLICATION_OBJECT` or `LEGACY_BUT_CURRENTLY_REFERENCED` (under its **live** name — e.g. `prayer_log`, not the never-applied `prayer_entries` rename), including both provisioning triggers/functions and `delete_my_account()`, verbatim as captured. `SUPABASE_MANAGED` objects are excluded and documented separately (§4.0.1). `UNREFERENCED`/`UNKNOWN` objects are included (to avoid silent data loss) but explicitly commented as flagged for future review, not asserted as intentional architecture. All 12 existing migration files are marked "SUPERSEDED — historical, do not replay" in place (`DI-006`'s append-only convention) — never deleted. `schema.sql` is regenerated from this baseline once it passes §4.9, becoming a generated artifact rather than hand-maintained.
- **Explicitly out of scope for this file:** any *behavioral* change (e.g. renaming `prayer_log`→`prayer_entries`, or `DI-004`'s original FK-retarget idea) — capture reality first; improve it later, deliberately, in a reviewed follow-up wave.
- DB mutation: No — this authors a new file in the repository only. **Not applied to production in this wave.**

### 4.8 — Clean rebuild test, isolated environment *(hard gate)*

Fresh, isolated Supabase-local-stack or disposable Postgres. From an empty starting point: (1) apply the §4.7 baseline; (2) verify every `REQUIRED_APPLICATION_OBJECT`/`LEGACY_BUT_CURRENTLY_REFERENCED` table/column/constraint/index/policy exists as expected; (3) verify every function/RPC/trigger exists and is callable; (4) verify basic connectivity (a client can connect and query); (5) confirm the entire rebuild required **zero** manual Studio/SQL-editor steps. **Exit criterion (amended): zero material difference in application-owned schema** against the §4.2 live capture — not literal identity with Supabase-managed internals.
- DB mutation: No (isolated test environment only).

### 4.9 — Behavioral rebuild validation *(the exit test verifies behavior, not only schema)*

Inside the same isolated environment, with synthetic data only:
- **A. Auth signup** — insert a synthetic `auth.users` row; verify both `public.profiles` and `public.users` rows are created correctly by the two live triggers.
- **B. Authorization/RLS** — as two distinct synthetic authenticated roles, verify representative permitted access (own row) and denied access (another user's row) on at least one RLS-protected table.
- **C. Cycle data** — representative `cycle_entries` (or its live name) write + read-back.
- **D. Pregnancy data** — representative `pregnancy_profile` write + read-back.
- **E. Profile data** — representative `profiles`/`users` persistence check.
- **F. Account deletion** — call `delete_my_account()` against synthetic populated data; document exactly what it deletes, cascades, anonymizes, and leaves behind, and whether the resulting state is technically consistent (cross-reference `DI-012`'s other-participant-message-visibility concern).
- **G. Application startup** — verified at the DB/API connectivity level (a client can connect and issue representative queries against the rebuilt schema). **Scope limitation, stated plainly:** this session does not have a way to boot the actual Flutter mobile app UI (emulator/device) against the rebuilt environment; that remains a manual verification step for whoever holds the mobile toolchain, not claimed as done here.
- **H. Representative E2E journeys** — validated at the DB-behavior level for the journeys database reconstruction affects (cycle logging, chat persistence, account deletion); full UI-level E2E is out of this session's reach for the same reason as G, and is explicitly not claimed.
- DB mutation: No (isolated test environment only).

### 4.10 — Restore test

Using the independent logical schema export (§4.1) plus synthetic data (§4.6's constraint): restore into a second, separate isolated environment and verify schema integrity, representative data integrity, and basic application-level (API/connectivity) compatibility. Record the exact procedure and evidence. This satisfies `BR-008`'s Golden Rule (an unexercised backup is unverified) **for the mechanism** — it does not substitute for the release owner separately restore-testing a real production backup once platform PITR/backups exist (§4.1's residual-risk note).
- DB mutation: No to live; yes to the disposable restore target only.

### 4.11 — Migration repair: proposed, not executed

Migration repair is **not** performed automatically, and not performed in this wave at all. Only after §4.2–§4.10 all pass does this document stop and present the **exact** proposed `supabase migration repair` command(s) — target version(s), intended before/after ledger state, exact effect, why it's required, rollback path, and the specific evidence (from §4.2–§4.10) that justifies it. Execution requires a separate, explicit approval. See §4.15 Output K.
- DB mutation: **None in Wave 0.** The eventual command, if and when approved, is metadata-only against Supabase's migration ledger — no schema DDL against `public`/`auth`.

### 4.12 — Wave 0 Exit Criteria

- [ ] 4.2–4.4: complete live-vs-repo comparison ledger produced and reviewed
- [ ] 4.3: every object classified per §4.0.3, no object silently canonized
- [ ] 4.5: known-good trigger/function/RPC behavior understood and documented before any preservation decision
- [ ] 4.7: deterministic baseline authored (no unjustified `IF NOT EXISTS`/`CREATE OR REPLACE`)
- [ ] 4.8: clean rebuild passes with zero material difference in application-owned schema
- [ ] 4.9: behavioral validation A–F pass in the isolated environment (G/H validated at DB-connectivity level only, scope limitation stated)
- [ ] 4.10: restore test demonstrated (mechanism-level, synthetic data)
- [ ] 4.11: proposed migration-repair operation presented and **awaiting separate explicit approval** — not executed
- [ ] §4.1's platform PITR/backup gap remains **open, documented residual risk** — required before *any later wave's* DB mutation, per §1's blanket rule, even though Wave 0 itself does not depend on it beyond the restore test

### 4.13 — Production Safety Rule

If any command in this wave's execution *could* mutate live production state, this session stops before running it and states: the exact command, the exact target, the exact effect, why it is required, the rollback/recovery path, and the evidence that all prerequisites passed — then waits for explicit approval. This applies with no exceptions in Wave 0, including to §4.11.

### 4.14 — Outputs Required at End of Wave 0

A. Authoritative live-object inventory · B. Object classification report · C. Live-vs-`schema.sql`-vs-migrations comparison · D. Proposed canonical baseline (file, not deployed) · E. Recovery/backup evidence (including the platform PITR/backup residual-risk statement) · F. Clean-rebuild report · G. Behavioral validation report (A–H, with G/H scope limitation stated) · H. Restore-test report · I. Remaining material discrepancies · J. Affected finding IDs and updated status (finding discipline per §4.0.4 — no automatic closure) · K. Exact proposed first live operation (migration repair), if still required, awaiting approval.

---

## 5. Root-Cause Table (dependency-aware, all finding IDs preserved)

| Root cause | Finding IDs | Affected audits | Dependencies | Proposed remediation | Production risk | Rollback | Tests required | E2E journeys |
|---|---|---|---|---|---|---|---|---|
| **P0 — DB not reproducible / no backup** | `BR-001,002,003,004,005,007,008`, `DI-001,005,006` (`DI-004`/`PJ-001` inform, closed) | Database, Backup/Recovery, Final User Journey | None (root prerequisite) | Wave 0, §4 | High if skipped/rushed; near-zero if sequenced as written (all DDL tested in isolation first) | `migration repair --status reverted`; no live DDL was run | Zero-diff rebuild test (4.9); restore test (4.10) | None required for the capture itself; all journeys re-verified after any later schema change |
| **P1a — Silent failure / write-path durability** | `DC-004`, `CQ-009`, `AB-010`, `DI-002`, `RR-001,002`, `FQ-002`, `OB-001–006,009,010`, `BR-005`, `PJ-002,004,006`, **`W0-001` (fixed)**, **`W0-002` (deferred — product decision needed)** (`ROOT-005`) | Database, Reliability, Observability, Backup/Recovery, Final User Journey, Functional QA | None blocking; app-code only, runs parallel to Wave 0. `W0-001` required no schema change and no Wave 0 dependency — fixed by pointing `prayer_tracking_repository_impl.dart` at the live table (`prayer_log`) and trimming its upsert payload to that table's actual columns. `W0-002` turned out to need a product decision, not a code fix: `pregnancy_records`'s live shape (one row per pregnancy) is structurally incompatible with what the repository needs (one row per dated milestone) — repointing the name alone would still fail; deferred, documented in code and in `00_04` | Repository-layer error surfacing + retry/backoff + UI "sync failed" state + crash/error reporting (coordinated with P3); `W0-001` DONE this session (table name + payload corrected); `W0-002` NOT fixed — documentation-only code comment added explaining why | Medium — touches every core repository's error contract; UI states may need new design. `W0-001`'s fix was Low risk (one table-name string + a trimmed payload), not yet deployed/tested against live | Per-repository revert (each is an independent commit per `DI`/`OB` plans) | Simulated remote-failure test per repository; red-flag chat failure-injection test (`PJ-004` regression); `W0-001` needs a live remote read/write round-trip test to confirm `prayer_log` now resolves correctly (not yet run — code-only change, no deploy performed this session) | Cycle logging, pregnancy tracking, community, Dr. Niswah chat (red-flag path), private messaging, prayer tracking |
| **P1b — RLS authorization gap** | `SEC-004` | Security | **Wave 0 complete** (new migration) | Column-scope `private_messages` UPDATE policy (`SEC` plan R1.3, option 2 recommended) | Low-medium | Standard migration rollback | Two-synthetic-user IDOR test | Private messaging |
| **P1c — Data-integrity hardening** | `DI-003,007,008,009,010,011,012` | Database | **Wave 0 complete**; `DI-009` also needs product/religious-review sign-off | Detection-query-first constraint additions per `DI` plan R3/R7/R8/R9/R10/R11/R12 | Low individually; `DI-011` is behavior-affecting (needs domain confirmation on one-entry-per-day) | Drop constraint/trigger | Concurrency test (`DI-003`); duplicate-detection queries before each constraint | Cycle logging, private messaging |
| **P2 — Gemini client-exposed key** | `SEC-001,002,005,006`, `DC-001,003`, `CQ-004,005`, `AB-002,003,004,005,006,007,008,009,011,012,013` (`ROOT-002`) | Security, Dependencies/Config, Code Quality, API/Backend | None blocking on Wave 0 (no schema change); simplified by Phase 0 (contract already verified correct — no need to re-derive it) | New edge functions mirroring `dr-niswah-chat`'s now-confirmed-working pattern; remove key from client asset bundle; rotate key only after old builds retired; add rate limits, timeouts, CORS scoping, idempotency key (`AB-003`'s fix is one additive migration — gated on Wave 0) | Medium — 3 features re-plumbed; key rotation is a one-way, carefully-sequenced action | Keep old direct-call path behind a flag during rollout; rotate key only after cutover confirmed | `grep -rn GEMINI_API_KEY lib/` returns zero; release-binary asset inspection; full AI-feature E2E | AI Advisor, Dream Interpreter, Dr. Niswah chat, general assistant |
| **P3 — Observability / detection gap** | `OB-001–012` (shared with P1a), `RR-002` (shared) | Observability, Reliability | Coordinated with P1a (same PRs where practical); `OB-010`'s DB audit-log trigger needs **Wave 0 complete** | Crash/error SDK, structured logging, alerting, version tagging, kill-switch (`OB` plan R1–R3) | Low — mostly additive | Feature-flaggable SDK/config | Synthetic failure injection per alert defined in `OB` plan §4 | All journeys (this is the mechanism that proves the P1a fixes worked) |
| **P4 — Release engineering** | `SEC-003`, `DC-002,005,006,007,010`, `RD-001–010`, `CQ-012`, `PF-001,002,003` (optional) | Dependencies/Config, Release/Deployment, Code Quality, Performance | Android/iOS signing + CI independent, run anytime; **migration deployment process definition depends on Wave 0** (can't define a sane process atop a broken chain); `RD-007`/privacy-policy content depends on P5 | Real signing, CI pipeline, SDK pin, build-number automation, env separation, store assets, kill-switch design (`DC`/`RD` plans) | Low for most items; Android signing is one-way once first published | Debug-signed path kept for non-prod CI only | Signature verification; CI failure-injection test; build-number increment test | None functionally — build/release pipeline only |
| **P5 — Privacy / product controls** | `PC-001,003,004,005,006,007,008,009,010,011`, `PC-002` (scope narrowed) | Privacy/Compliance, Release/Deployment | `PC-002`'s RPC-verification step needs Wave 0's read-only capture (4.2/4.3), not full baseline; `PC-001`/consent-gating depends on privacy policy (legal-authored, external track); `PC-002`'s `consent_events` table (if adopted) needs **Wave 0 complete** | First verify `delete_my_account()`'s exact cascade/anonymization scope against Privacy Audit's requirements, then wire client; consent-gating; policy authorship (legal); AI disclosure; onboarding relabel; retention (`PC` plan) | Medium for deletion flow (irreversible by design); low for copy/UX fixes | Feature-flaggable rollout for deletion flow | Controlled synthetic-account create→populate→delete→verify-zero-rows test; consent-gating manual test | Onboarding/consent, account deletion (new) |
| **P6 — Dead code / hygiene (non-blocking)** | `CQ-001,003,005,006,008,011`, `DC-008,009,011,012` (`ROOT-006`) | Code Quality, Dependencies/Config | None | Delete dead fiqh engine, orphaned Firebase artifacts, dead AI-key scaffolding; gate debug flags behind `kDebugMode` | Low | Git revert | `flutter analyze` clean; existing test suite green | None |
| **P7 — Accessibility & UX (non-blocking-but-launch-relevant)** | `AU-001–010` (`ROOT-010`) | Accessibility/UX | None; can run in parallel with everything | Shared accessible icon-button primitive, contrast fix (design sign-off), severity indicator, form validation, text-scale proofing (`AU` plan R1–R7) | Low individually; `AU-003` needs design sign-off | Trivial per-item revert | Static grep re-check; live VoiceOver/TalkBack pass (`AU-009`) | Onboarding, cycle logging, Dr. Niswah chat, dashboard |
| **P8 — Rollback / kill-switch capability** | `OB-009`, `RD-009` (`ROOT-008`) | Observability, Release/Deployment | Natural to build alongside P2 (edge functions) and P4 (CI) | Minimal remote-config/feature-flag table + documented manual kill-switch runbook | Low | Flip flag back | Toggle test in staging | AI features (fastest-to-break path) |
| **Backlog, not yet detailed** | `FQ-000` (golden-test triage), `FQ-001`, `AE-001` (informational, N/A audit) | Functional QA, Analytics | None | `FQ-000`: manually inspect the 8 failing golden diffs (regression vs. font-rendering noise). `FQ-001`: revisit during P1a re-test. `AE-001`: no action unless product revives the dead paywall stub. | None | N/A | Golden-test re-run | None |

---

## 6. Execution Waves — Summary Sequencing

| Wave | Priority | Finding IDs | Files/components | Prod access? | DB mutation? | Backup prerequisite | Regression tests | Specialist audits to rerun | E2E journeys to rerun | Rollback |
|---|---|---|---|---|---|---|---|---|---|---|
| **0** | P0 (gate) | `BR-001–008`, `DI-001,005,006` | New `supabase/live_schema_capture/`, one new baseline migration, `schema.sql` regenerated | Yes (read-only + 1 metadata write) | Yes (ledger metadata only, step 4.11) | **N/A — this wave establishes it** | Zero-diff rebuild test; restore test | Database, Backup & Recovery | None | `migration repair --status reverted` |
| **1a** | P1a | `DC-004,CQ-009,AB-010,DI-002,RR-001,002,FQ-002,OB-001-006,009,010,BR-005,PJ-002,004,006,W0-001(fixed),W0-002(deferred)` | Repository impls (incl. `prayer_tracking_repository_impl.dart` — fixed; `pregnancy_tracking_repository_impl.dart` — comment only, awaiting product decision), `main.dart`, `dr-niswah-chat/index.ts`, `failures.dart` | No (app/edge-function code only) | No | Not required — may start immediately | Failure-injection per repository; live round-trip test needed for `W0-001`'s corrected table name (not yet run against production) | Reliability, Database, Observability, Final User Journey | Cycle logging, pregnancy tracking, community, Dr. Niswah chat, private messaging, prayer tracking | Per-commit revert |
| **1b** | P1b | `SEC-004` | New migration, `private_messaging_repository.dart` (if option 2) | Yes | **Yes** | **Requires Wave 0 complete** | Two-user IDOR test | Security | Private messaging | Migration rollback |
| **1c** | P1c | `DI-003,007,008,009,010,011,012` | New migrations, `cycle_tracking_repository_impl.dart` | Yes | **Yes** | **Requires Wave 0 complete** | Detection queries pre-constraint; concurrency test | Database | Cycle logging, private messaging | Drop constraint |
| **2** | P2 | `SEC-001,002,005,006,DC-001,003,CQ-004,005,AB-002-013` | New edge functions, `gemini_service.dart` removal, `app_environment.dart` | Yes (Edge Function deploy + secret rotation) | No (Edge Function/secret config, not schema) | Not required for deployment; rotation gated on old-build retirement, not on Wave 0 | Asset-bundle secret scan; full AI E2E | Security, API/Backend, Code Quality | AI Advisor, Dream Interpreter, Dr. Niswah chat, general assistant | Feature-flagged fallback during rollout |
| **3** | P3 | `OB-001–012` | `main.dart`, new logging abstraction, `failures.dart`, (one DB audit-log trigger) | Mostly no; the one audit-log trigger (`OB-010`) needs prod access | Mostly No; `OB-010`'s trigger is **Yes** | `OB-010` sub-item only: **requires Wave 0 complete** | Synthetic failure injection per alert | Observability | All (this proves P1a worked) | SDK/config disable |
| **4** | P4 | `SEC-003,DC-002,005-007,010,RD-001-010,CQ-012,PF-001-003` | `build.gradle.kts`, Xcode project, new CI workflow, `.fvmrc` | Signing/CI: no prod DB access. Migration-deployment-process definition: conceptual only | No, **except** the migration-deployment-process definition depends on Wave 0's *output* (not itself a mutation) | Signing/CI: not required. Deployment-process definition: **requires Wave 0 complete** | Signature verification; CI failure-injection | Release/Deployment, Dependencies/Config | None functionally | Debug-signed non-prod path retained |
| **5** | P5 | `PC-001-011` | New "Delete account" screen, sign-up handler wiring, onboarding copy | Yes (RPC verification against live capture) | Only if `consent_events` table is adopted (**Yes**, gated) | RPC-verification sub-step needs Wave 0's read-only capture only (4.2/4.3); `consent_events` table needs full Wave 0 | Synthetic account create→delete→verify-zero-rows | Privacy/Compliance | Onboarding/consent, account deletion | Feature-flagged deletion rollout |
| **6** | P6 | `CQ-001,003,005,006,008,011,DC-008,009,011,012` | Dead-code removal, orphaned root files | No | No | Not required | `flutter analyze`; existing suite | Code Quality | None | Git revert |
| **7** | P7 | `AU-001-010` | Shared icon-button primitive, `app_theme.dart`, form migration | No (device testing only, no prod backend) | No | Not required | Static grep; live AT pass | Accessibility/UX | Onboarding, cycle logging, Dr. Niswah chat, dashboard | Per-item revert |
| **8** | P8 | `OB-009,RD-009` | New flags table (gated) or documented manual runbook | Depends on chosen mechanism | Only if a flags table is built (**Yes**, gated) | Manual-runbook option: not required. Flags-table option: **requires Wave 0 complete** | Toggle test in staging | Observability, Release/Deployment | AI features | Flip flag / revert runbook |

---

## 7. Parallelization Guidance

Waves **0, 1a, 2, 3 (minus `OB-010`), 4 (minus deployment-process definition), 6, 7**, and Wave 5's RPC-verification sub-step can all start **simultaneously** — none of them depend on each other or require live schema mutation. This is the fastest path to closing the largest number of BLOCKER findings without serializing unnecessarily.

Waves **1b, 1c**, `OB-010`, the migration-deployment-process definition (Wave 4), and `PC-002`'s `consent_events` table (Wave 5, if adopted) are the only items gated on Wave 0's full completion (§4.12).

The privacy-policy authorship (legal track, feeds `PC-001,003,004,006,007,009` and `RD-007`) is slow and external — start it immediately, in parallel, since multiple other items block on its output.

---

## 8. What This Plan Does Not Do

Per the charter: this plan does not implement any fix, does not touch the live database, and does not close any finding. Closure requires implementation, the specialist test named in §5/§6, and (for BLOCKER/HIGH findings) a rerun of the owning specialist audit plus the applicable Final Pre-Launch User Journey and Release & Deployment validations, per the charter's post-remediation regeneration requirement.

**Awaiting your review and approval of this sequencing before any wave begins.**

---

## 9. Wave 2 Update — Gemini Trust-Boundary Remediation Executed (2026-09-04)

**Findings addressed:** `SEC-001` (code-complete, deployment pending), `SEC-002` (closed), `SEC-006` (closed), `DC-001` (materially improved), `DC-003` (closed), `CQ-004` (closed), `CQ-005` (closed), `AB-002` (partially closed), `AB-012` (closed). `ROOT-002` code-side risk eliminated; residual risk now entirely deployment/rotation.

**Architecture, before → after:**
- **Before:** `gemini_service.dart` (client, held `GEMINI_API_KEY` from bundled `.env`) called directly by `ai_advisor_service.dart` (Fiqh, +Google Search grounding), `dream_interpreter_view_model.dart`, and `chat_view_model.dart`'s `_sendViaDirectModel` (handling `fiqhAdvisory`, a `drNiswah` fallback via `dr_niswah_persona.dart`'s client-side pregnancy fetch, and `general`/`dreamInterpreter`). Only `dr-niswah-chat` was already server-side.
- **After:** Four Edge Functions (`dr-niswah-chat`, `fiqh-advisor-chat`, `dream-interpreter-chat`, `ai-assistant-chat`) share one `_shared/gemini_client.ts` module (model fallback, per-attempt `AbortController` timeout, citation parsing). Each owns its system prompt server-side. The client never holds `GEMINI_API_KEY` — confirmed zero references anywhere in `lib/`. `gemini_service.dart` and `dr_niswah_persona.dart` deleted (fully dead once the direct paths were removed). `chat_view_model.dart`'s `drNiswah` fallback removed outright — backend-unavailable now throws a clear error instead of downgrading to an unaudited client call.

**Files changed:** `lib/core/config/app_environment.dart`, `lib/core/errors/app_error_reporter.dart` (new, Wave 1 work reused here), `lib/features/ai_advisor/ai_advisor_service.dart`, `lib/features/ai_assistant/presentation/screens/dr_niswah_chat_screen.dart`, `lib/features/ai_assistant/presentation/viewmodels/chat_view_model.dart`, `lib/features/dream_interpreter/presentation/viewmodels/dream_interpreter_view_model.dart`, `supabase/functions/dr-niswah-chat/index.ts` (added timeout, closes `AB-004` for this function), `supabase/functions/_shared/gemini_client.ts` (new), `supabase/functions/fiqh-advisor-chat/index.ts` (new), `supabase/functions/dream-interpreter-chat/index.ts` (new), `supabase/functions/ai-assistant-chat/index.ts` (new), `.env`, `.env.example`. Deleted: `lib/core/services/gemini_service.dart`, `lib/features/ai_assistant/domain/services/dr_niswah_persona.dart`.

**Tests executed:**
- `dart analyze lib/` — clean, 33 pre-existing issues (unrelated files), zero new.
- `flutter test` — 254/262 pass, same 8 pre-existing golden-image diffs as Phase 0's baseline, zero regressions.
- Controlled Gemini smoke test (standalone Deno script exercising the real `_shared/gemini_client.ts` against the live Gemini API — no production Supabase access involved): plain-text call **PASSED** (real reply, correct parsing — validates the exact call shape used by `dr-niswah-chat`/`ai-assistant-chat`/`dream-interpreter-chat`); deliberate 1ms timeout **PASSED** (`AbortController` confirmed to actually fire, not a no-op); Google-Search-grounded call (the `fiqh-advisor-chat` shape) hit `429 too_many_requests` — confirmed via raw error body to be an **account-level quota/billing limit specific to the Search-grounding tool**, not a code defect and not new (the same API key had this same constraint before this remediation). The retry/fallback logic itself behaved correctly (tried both models, surfaced a clear final error).
- Edge Functions' HTTP-layer guards (401 auth rejection, 400 validation) were **not execution-tested** — local Supabase stack startup (`supabase start`) hung unrecoverably in this environment even after `supabase init` scaffolded a missing `config.toml`; abandoned after reasonable effort rather than continuing to fight infrastructure. Confidence instead rests on structural equivalence: all three new functions use the exact same auth-check/validation pattern as `dr-niswah-chat`, which **is** already proven working in production (Phase 0's live smoke test).
- Full mobile-app-UI E2E for the four AI journeys was **not performed** (no emulator/device in this environment, same limitation noted throughout this engagement) — not claimed as done.

**Secret rotation / owner action still required (none of this was performed):**
1. Deploy the three new Edge Functions (`supabase functions deploy fiqh-advisor-chat dream-interpreter-chat ai-assistant-chat`).
2. Set `GEMINI_API_KEY` as a secret on all four functions (`supabase secrets set GEMINI_API_KEY=<value> --project-ref jkmjobvxfrmuwafczvtw`) — it currently exists only in the gitignored local `supabase/functions/.env` (used for this session's own local smoke test) and nowhere else.
3. **Rotate the actual Google Cloud API key** once the new client build (with no embedded key) is confirmed to be the only build in the wild — the current value has been distributed in prior client builds and is also present in this repository's git history (it was committed in `.env` before this remediation), so removing it from the working tree does not by itself invalidate it.
4. Confirm via a built release artifact (out of this task's scope — release engineering, Wave 4) that no `.env`-derived asset in the compiled app contains the key.

**Remaining AI-related blockers:**
- `AB-002`'s rate-limiting/cost-cap half is explicitly not done (separate item, `AB` plan R3-c).
- The Google-Search-grounding quota limit on the current API key is a pre-existing account/billing constraint, unrelated to this code change, and will affect Fiqh Advisor in production exactly as it did before — worth the release owner's attention independent of this remediation.
- Steps 1–4 above are all outstanding, owner-gated actions; until they're done, the new functions exist only in the repository and provide no production benefit yet.

**Not attempted:** any other remediation group (Wave 1's remaining items, observability, release engineering, privacy, accessibility) — stopped here per instruction.

---

## 10. Operational Closure Checkpoint — Gemini Trust-Boundary (2026-09-04)

Executed per explicit release-owner authorization, in five phases. **No database schema, RLS, function, trigger, or migration change was made at any point.** One disposable synthetic Auth account was created (manually, by the release owner, in the Supabase Dashboard, per their explicit instruction) solely for authenticated runtime testing, and fully deleted afterward via `delete_my_account()` — verified with zero residue.

### Phase A — Deployment readiness review
- Functions requiring deployment: `fiqh-advisor-chat`, `dream-interpreter-chat`, `ai-assistant-chat` (new) + `dr-niswah-chat` (code changed — now uses `_shared/gemini_client.ts`, gained a timeout, closes `AB-004`).
- Confirmed via `grep -rn "functions.invoke" lib/`: exactly 4 call sites, one per AI feature — no direct-Gemini client path remains.
- Confirmed via exhaustive `lib/` search: zero `GEMINI_API_KEY` references, zero old-endpoint references, zero references to the deleted `gemini_service.dart`/`dr_niswah_persona.dart`, zero client-side HTTP-to-Google fallback paths.
- Secret name confirmed exactly `GEMINI_API_KEY` (`Deno.env.get('GEMINI_API_KEY')` in `_shared/gemini_client.ts`). Value never printed at any point in this checkpoint.

### Phase B — Abuse/rate controls
Implemented `_shared/rate_limit.ts`: an in-memory, sliding-window limiter (15 requests / 5 minutes) keyed on the JWT-derived, server-authenticated `user.id` (never a client-supplied value), wired into all four functions. `dr-niswah-chat` explicitly **exempts red-flag/urgent messages** from the limit — a safety message must never be blocked by an abuse control. No database table was created; a DB-backed limiter was explicitly identified as the "durable" alternative but not implemented, per the no-schema-mutation constraint.

**Result, tested live in Phase C: the in-memory approach does not work in production** — see `W1-001`. It remains deployed (harmless — fails open, never blocks legitimate traffic) but provides no real protection today.

### Phase C — Deploy and runtime-validate
Deployed via `supabase functions deploy dr-niswah-chat fiqh-advisor-chat dream-interpreter-chat ai-assistant-chat` — succeeded, all 4 functions live. `GEMINI_API_KEY` set via `supabase secrets set --env-file` (value never printed; confirmed present by name via `supabase secrets list`, which itself only ever shows an opaque hash, never plaintext).

Runtime tests, all against the live deployed functions:

| Test | Result |
|---|---|
| Unauthenticated (missing header) — all 4 functions | ✅ `401 UNAUTHORIZED_NO_AUTH_HEADER` (platform gateway, before function code even runs) |
| Invalid/garbage bearer token — all 4 functions | ✅ `401 UNAUTHORIZED_INVALID_JWT_FORMAT` |
| Malformed payload w/ valid auth (missing field, oversized content, invalid enum) | ✅ `400` with a clean, specific error message, no internal detail |
| Valid authenticated request — `ai-assistant-chat` | ✅ `200`, real Gemini reply |
| Valid authenticated request — `dream-interpreter-chat` | ✅ `200`, real, contextually-correct reply (followed its system prompt's "ask clarifying questions" rule) |
| Valid authenticated request — `dr-niswah-chat`, non-urgent | ✅ `200`, real Arabic reply, `urgent:false`, persisted `messageId` |
| Valid authenticated request — `dr-niswah-chat`, **red-flag/urgent** | ✅ `200`, `urgent:true`, correct safety banner prepended, persisted `messageId` — the safety-critical path works end-to-end in production |
| Gemini upstream error (real, not simulated) — `fiqh-advisor-chat` | ✅ Google Search quota `429` occurred naturally; function caught it and returned the designed graceful fallback text with `citations:[]`, `200` to the client, zero leaked internal detail |
| Gemini timeout | Not independently forced against production (no reliable way to make Google's live API hang on demand); the `AbortController` mechanism itself was proven to fire correctly in the earlier local Deno smoke test |
| Rate-limit behavior | ❌ **Did not trigger** — 28 requests (15 sequential + 10 concurrent) against `ai-assistant-chat`, well past the 15/5min bound, zero `429`s. See `W1-001` |
| No sensitive info leaked in any error response | ✅ Confirmed across all tests above — no stack traces, no key material, no internal identifiers |

Test data cleanup: `delete_my_account()` called as the synthetic user → `204`. Verified after: `chat_threads`/`chat_messages`/`public.users`/`public.profiles` all return empty for that user id; a subsequent sign-in attempt with the same credentials returns `invalid_credentials`, confirming the `auth.users` row itself is gone. Nothing remains.

**Fiqh Advisor Search-grounding classification:** **B — DEGRADED.** The feature is not silently falling back to an ungrounded answer — it explicitly tells the user sources couldn't be reached and declines to give an unsourced ruling (matching the product's own safety design: no citations, no definitive ruling). This is graceful degradation, not silent failure. **Owner action required:** the Google Cloud quota/billing condition on the Search-grounding tool must be resolved (check quota/plan at the link in the raw API error: `https://ai.google.dev/gemini-api/docs/rate-limits`) before this feature can reach state A (READY).

### Phase D — Credential rotation plan

**Correction to the initial premise:** the key was **never committed to this repository's git history** — `.env` has been gitignored since the first commit (verified via `git log --all -S<key-fragment>` and `git log --all -- .env`, both empty). Its real, confirmed exposure vector is the compiled Flutter **asset bundle** (`pubspec.yaml`'s `assets: - .env`), which any built app package — debug or release — would contain.

Evidence bearing on which rotation path applies: the original audit's `RD-001`/`RD` findings independently establish no CI/CD pipeline, no store listing, and a debug-signed (never legitimately released) Android build — i.e., no evidence any build was ever distributed outside the original developer's own machine. This strongly suggests the "no active users" path applies, but it is a fact only the release owner can fully confirm (a build could have been manually side-loaded to a tester before this audit began, which repo evidence alone cannot rule out).

**Recommended plan (pending owner confirmation of the above):**
1. Confirm with the release owner: has any build (debug or release, any channel) of this app ever been installed on a device other than the development machine?
2. If no: create/use the new server-only key is already done (the current key now lives only as an Edge Function secret, confirmed working end-to-end in Phase C); **revoke the old key promptly** in Google Cloud Console. Since the Edge Functions now hold the same key value as a secret, this specific key doesn't need to change for the server to keep working — but the *distribution* channel (client asset bundling) it was exposed through has been closed, and if any local backup/copy of the old `.env` exists outside this repo, it should be treated as compromised and rotated to a fresh value if the owner wants a clean break.
3. If yes (any past distribution): identify affected build(s), decide whether those installs still call Gemini directly (they would, since old client code called Google directly with the embedded key) — revoking the key immediately would break AI features in any such install with no fallback, since old clients don't know about the new Edge Functions. A safest-cutover approach would be: rotate to a genuinely new key value, update the Edge Function secret to the new value, then revoke the *old* value only after confirming (however possible) that no old build is still active.
4. Either way: **this remediation does not perform Google Cloud key revocation/rotation itself** — no access to that console exists in this environment. This is an explicit, outstanding owner action.

### Phase E — Release-build secret verification

A full signed release APK could not be produced — `flutter build apk --release` failed at Android's native packaging stage (`:app:checkReleaseAarMetadata`: `flutter_local_notifications` requires core library desugaring, which is not enabled in `android/app/build.gradle.kts`). **This is a pre-existing, unrelated release-engineering gap** (Wave 4 / `RD`/`DC` territory), not something introduced by or in scope for this remediation.

However, Flutter's own **release-mode** asset-bundling stage completed successfully before that unrelated failure, producing a real release-configuration compiled asset bundle at `build/app/intermediates/flutter/release/flutter_assets/.env`. Inspected directly:
- Contains only `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `APP_ENV`, and the explanatory comment noting `GEMINI_API_KEY` is intentionally absent.
- `grep -rln "<old key value>" build/app/intermediates/flutter/release/` — zero matches anywhere in the release build tree.
- This is the exact mechanism `SEC-001`/`ROOT-002` were about — verified directly, not inferred.

**Per the explicit instruction, `SEC-001` and `ROOT-002` remain NOT VERIFIED_CLOSED** — two of three conditions are met (deployed-and-validated Edge Function path; client-artifact verification), the third (actual key rotation/revocation) is outstanding and owner-gated.

---

## 11. Checkpoint Summary

| # | Item | Status |
|---|---|---|
| 1 | Deployed functions | `dr-niswah-chat`, `fiqh-advisor-chat`, `dream-interpreter-chat`, `ai-assistant-chat` — all 4, confirmed live |
| 2 | Runtime tests | 401/400/200 paths, red-flag safety path, and a real Gemini upstream error all passed; rate-limit test failed (see `W1-001`); timeout not independently forced against prod (mechanism proven locally) |
| 3 | `AB-002` rate-control status | Implemented, deployed, **proven ineffective** in production (`W1-001`); DB-backed limiter proposed, not implemented |
| 4 | Fiqh Search-grounding status | **B — DEGRADED**: fails safely with a clear message, no silent ungrounded fallback; blocked on a Google Cloud quota/billing condition, an owner action |
| 5 | Key-rotation status | Not performed (no Google Cloud access in this environment); plan documented above, pending owner confirmation of build-distribution history |
| 6 | Compiled-client secret verification | Confirmed absent from the real release-mode asset bundle; full signed APK blocked by an unrelated, pre-existing Android Gradle gap |
| 7 | Findings `VERIFIED_CLOSED` this checkpoint | None of `SEC-001`/`ROOT-002` (explicitly withheld pending rotation, per instruction) |
| 8 | Remaining owner actions | (a) Rotate/revoke the Google Gemini API key; (b) resolve the Search-grounding quota/billing condition; (c) fix the Android desugaring gap to unblock a real signed release build (separate, Wave 4 item) |

**Not started:** any other remediation root cause. Stopping here for review, as instructed.

---

## 12. Proposed Database-Backed AI Rate Limiter (design only — NOT implemented)

Closes: `W1-001` (kept OPEN until this is implemented and load-tested), `SEC-005`, `AB-002` (rate-limit half), `AB-008`. Supersedes the in-memory approach (`_shared/rate_limit.ts`, proven ineffective in production — see `00_10`/checkpoint evidence). **Per explicit instruction: no further in-memory/process-local/per-instance/client-side throttling attempts.** This design requires a schema migration and is gated on Wave 0's approved database-mutation process — nothing below has been applied to any database.

### Schema

```sql
CREATE TABLE public.ai_rate_limit_counters (
  user_id       uuid NOT NULL,
  function_name text NOT NULL,
  window_start  timestamptz NOT NULL,
  request_count integer NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, function_name, window_start)
);
-- No client-facing RLS policy at all (same pattern as flagged_conversations) —
-- only the SECURITY DEFINER function below ever touches this table.
ALTER TABLE public.ai_rate_limit_counters ENABLE ROW LEVEL SECURITY;
```

Fixed 5-minute window buckets (not a true sliding window) — a standard, well-understood simplification: simpler to make atomic, at the cost of allowing up to ~2x the configured burst right at a window boundary. Documented as an accepted tradeoff, not an oversight.

### RPC — atomic increment/check in one statement

```sql
CREATE FUNCTION public.check_ai_rate_limit(
  p_function_name text,
  p_max_requests integer,
  p_window_minutes integer
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_window_start timestamptz;
  v_count integer;
BEGIN
  -- Bucket "now" to a p_window_minutes-aligned boundary.
  v_window_start := to_timestamp(
    floor(extract(epoch FROM now()) / (p_window_minutes * 60)) * (p_window_minutes * 60)
  );

  INSERT INTO public.ai_rate_limit_counters (user_id, function_name, window_start, request_count)
  VALUES (auth.uid(), p_function_name, v_window_start, 1)
  ON CONFLICT (user_id, function_name, window_start)
  DO UPDATE SET request_count = public.ai_rate_limit_counters.request_count + 1
  RETURNING request_count INTO v_count;

  -- Lazy, probabilistic cleanup (~1% of calls) instead of a scheduled job —
  -- avoids a hard dependency on pg_cron availability being confirmed.
  IF random() < 0.01 THEN
    DELETE FROM public.ai_rate_limit_counters
    WHERE window_start < now() - interval '1 day';
  END IF;

  RETURN v_count <= p_max_requests;
END;
$$;

REVOKE ALL ON FUNCTION public.check_ai_rate_limit FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_ai_rate_limit TO authenticated;
```

### Design properties (per the required checklist)

- **Atomicity:** `INSERT ... ON CONFLICT ... DO UPDATE ... RETURNING` is Postgres's documented atomic upsert-and-increment pattern — safe under concurrent calls via the database's own row-level locking, no application-level locking needed. This is the property the in-memory version could never provide (`W1-001`).
- **Identity:** keyed on `auth.uid()`, resolved server-side from the caller's verified JWT inside the `SECURITY DEFINER` function — never a client-supplied value. The client passes only `p_function_name`/`p_max_requests`/`p_window_minutes` (the *policy*, not the *identity*).
- **Window/quota model:** fixed 5-minute buckets, 15 requests/window (matching the original in-memory design's intent) — configurable per call site; `dr-niswah-chat` still exempts urgent/red-flag messages by simply not calling this RPC for those.
- **Concurrency:** correct by construction (see atomicity above) — two simultaneous requests from the same user cannot both see a stale count and both proceed past the limit.
- **Cleanup/retention:** lazy, probabilistic (~1% of calls) deletion of buckets older than 1 day. No dependency on `pg_cron` or any external scheduler.
- **Failure mode:** **fail open.** If the RPC call itself errors (network issue, unexpected DB error), the calling Edge Function should log it (`console.error`) and proceed with the request rather than block it — this is an abuse-prevention control, not a security boundary; a broken rate limiter must never take down a real feature (especially `dr-niswah-chat`, where a false block on a genuine safety message would be far worse than an occasional missed rate-limit check).
- **RLS/security implications:** the table has RLS enabled with **zero** client-facing policies — no direct client read/write is possible at all, by design (matching `flagged_conversations`'s established pattern in this codebase). All access goes through the one `SECURITY DEFINER` function, which itself only ever reads/writes rows scoped to `auth.uid()`. A modified client cannot inflate its own quota or inspect/tamper with another user's counters.
- **Rollout:** purely additive (new table + new function) — zero risk to any existing table, policy, or behavior. Each of the four Edge Functions calls `userClient.rpc('check_ai_rate_limit', {...})` right after their existing auth check, in place of the removed in-memory `checkRateLimit()` call.
- **Rollback:** `DROP FUNCTION public.check_ai_rate_limit; DROP TABLE public.ai_rate_limit_counters;` — fully reversible, no data elsewhere depends on this table.
- **Load test required for closure of `W1-001`:** repeat the exact test that disproved the in-memory version — ≥20 rapid requests (both sequential and concurrent) against a deployed function past the configured bound, against the **real deployed RPC this time**, confirming (a) a `429`/deny fires at the correct threshold and (b) concurrent bursts do not overshoot the limit beyond the single-bucket-boundary tradeoff already documented above. `W1-001` may only move to `VERIFIED_CLOSED` after this specific test passes against the deployed database function — not on the strength of the design alone.

**Not implemented in this session.** Requires: (1) approval to proceed with a production schema migration under the Wave 0 process, (2) the migration itself, (3) redeploying all four Edge Functions to call the new RPC instead of the in-memory limiter, (4) the load test above.

---

## 13. Cross-reference: Android core-library-desugaring build failure

Discovered during the Gemini trust-boundary checkpoint's Phase E (release-build verification): `flutter build apk --release` fails at `:app:checkReleaseAarMetadata` because `flutter_local_notifications` requires core library desugaring, not currently enabled in `android/app/build.gradle.kts`. **This belongs to Release Engineering (`DC`/`RD` domain, Wave 4) and was not modified as part of Gemini or silent-failure remediation.** Recorded here as a cross-reference so Wave 4 picks it up; it independently blocks producing any real signed release artifact, compounding `RD-001`/`DC-005`.

---

## 14. Gemini Trust-Boundary Remediation — Formally Closed Out

Per the confirmed absence of any distributed build containing the old key, the credential is being treated as compromised and the release owner is proceeding with rotation directly in Google Cloud Console (outside this session's access). Once rotation is complete and the new value is set as the Edge Function secret (by either party, without printing it), this session will re-run the authenticated runtime-test pattern from the checkpoint against all four deployed functions and update `SEC-001`/`ROOT-002` based on that result — not before.

**No further Gemini trust-boundary work begins without that verification.** Proceeding now to the silent-failure/data-durability remediation group.
