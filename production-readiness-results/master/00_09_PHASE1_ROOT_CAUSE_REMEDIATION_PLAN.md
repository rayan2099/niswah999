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

---

## 15. Reliability + Observability for Critical Persistence Recovery (2026-09-05)

**No production DB schema/migration/RLS/function/trigger/migration-ledger mutation occurred.** `W0-002` preserved exactly as `DEFERRED — PRODUCT/DATA-MODEL DECISION REQUIRED`; `pregnancy_tracking`'s data model was not touched.

### Phase A — Recovery model inventory (by critical write path)

| Path | Classification | Retry trigger | Sync-status equivalent | Observability |
|---|---|---|---|---|
| Cycle/haid logs | **LOCAL-AUTHORITATIVE-WITH-SYNC** | App start + app resume (new, real) | `SyncStatus.pending/synced/failed` on the local entity, driven by `mapRepositoryError`'s retryable classification | `AppErrorReporter` (feature=`cycle_tracking`, recordId=log id) |
| Pregnancy profile | **REMOTE-AUTHORITATIVE** (repository layer) | N/A — `PregnancyProfileRepository` deliberately throws on failure rather than queuing a retry | None — no local cache at all | **CORRECTED (2026-09-05, operational closure pass) — the "confirmed sound" claim above was wrong; see §16 Phase C.** Only 1 of 3 call sites actually surfaces the thrown error to the user (`profile_screen.dart`'s pregnancy-setup sheet); the other 2 (`profile_screen.dart::_startNifas`, `dashboard_screen.dart`'s `onLogBirth`) catch with `catch (_) {}` and discard silently — no `AppErrorReporter` call, no user-visible indication. This directly contradicts the REMOTE-AUTHORITATIVE "fail visibly" model this same path is supposed to follow. |
| Profile/account updates | **REMOTE-AUTHORITATIVE** | None | None (single source of truth is Supabase) | `AppErrorReporter` (this pass) |
| Notification/preferences | **LOCAL-AUTHORITATIVE, no sync** (local OS-scheduled only, nothing to reconcile against a server) | N/A | N/A | `AppErrorReporter` (this pass) |
| AI chat persistence (`dr-niswah-chat`) | **DUAL/OTHER — REVIEW REQUIRED** | None (single-attempt per message; see `PJ-004` fix) | None | `console.error` server-side (Edge Function), each of 3 writes now independently isolated (this pass) |
| Community posts/comments (read) | **REMOTE-AUTHORITATIVE** | None | None | `AppErrorReporter` (this pass, via shared classifier) |
| Community posts/comments (write) | **REMOTE-AUTHORITATIVE** | None | None | Already propagated correctly (no change needed) |

One retry policy was deliberately **not** applied blindly to every path — `pregnancy_profile` and community writes stay REMOTE-AUTHORITATIVE (throw, don't queue) because a silent local-first fallback would be actively worse there (stale AI context; a post existing only on one device with no way to reconcile), whereas cycle/haid logging's existing local-first design is the app's own deliberate, longstanding choice worth preserving and making trustworthy rather than reversing.

### Phase B — Cycle sync guarantee: chosen A (real automatic retry), not just a copy fix

**Before:** UI claimed "will sync automatically" with **zero actual mechanism** — `syncPendingLogs()` existed but was dead code, called from nowhere, and was itself architecturally broken (queried the *remote* table for `sync_status='pending'` rows, which cannot represent "not yet uploaded" since such a row wouldn't exist remotely at all). Every successfully-synced row was also permanently stuck showing `sync_status: 'pending'` in the database (a separate bug: the upload payload always sent the local default verbatim, never confirmed as `'synced'`).

**After:** `saveCycleLog` classifies its own failure via `mapRepositoryError` and marks the local entry `pending` (retryable) or `failed` (non-retryable) accordingly. `syncPendingLogs()` was rewritten to load local `pending` entries and retry each one — sequential (not parallel, bounding load), idempotent (`onConflict: 'id'`), and now **actually called** from two real triggers: app start and app resume (`main.dart`'s `NiswahHomeShell`). The UI copy was changed to reflect the *actual* resulting status rather than a blanket claim — `pending` gets "will back up automatically," `failed` gets "could not be backed up, please try again later" — both bilingual (AR/EN), sourced from the real `SyncStatus` enum rather than duplicated hardcoded strings per call site.

**Explicitly not implemented, by design:** exponential backoff (retries are trigger-bound, not timer-based — see below), connectivity detection (no new dependency added — the retry attempt itself is the connectivity probe), a durable cross-reinstall queue (see `W2-001`).

| Requirement | Answer |
|---|---|
| When retries happen | App start (`initState`'s post-frame callback) and app resume (`didChangeAppLifecycleState`) |
| Network/connectivity behavior | No dedicated detection — a retry attempt against an offline device fails with a Dart-level network exception, classified retryable, stays `pending`, tried again next trigger |
| App restart behavior | Explicit trigger — covered |
| Exponential/bounded backoff | **Not exponential** — bounded by real user-driven events, not a timer; explicitly documented as a tradeoff, not a gap hidden by overclaiming "exponential backoff" |
| Maximum retry behavior | Unbounded in *count* for retryable failures (keeps trying every app start/resume indefinitely) but each pass is cheap and event-gated, not a background loop |
| Duplicate/idempotency behavior | Guaranteed via the existing `onConflict: 'id'` upsert — tested (`cycle_local_sync_idempotency_test.dart`) |
| Pending → synced transition | Implemented and tested |
| Permanent failure behavior | Non-retryable failures marked `failed`, excluded from the automatic-retry query — never hammered |
| User-visible status | Accurate, bilingual, status-specific SnackBar text at both UI entry points |
| Observability | `AppErrorReporter` with `feature`/`recordId` context on every failure, both the initial attempt and each retry |
| No infinite retry loop | Confirmed — each trigger runs one bounded, sequential pass over currently-`pending` entries, then returns; nothing schedules itself again |
| No blind retry of non-retryable errors | Confirmed — `mapRepositoryError`'s `retryable` flag gates this explicitly, tested against real `PostgrestException` codes (RLS `42501`, unique-violation `23505` → non-retryable; `query_canceled` `57014` → retryable) |

### Phase C — Shared error model (`lib/core/errors/failures.dart`)

`Failure` extended with optional `cause`, `stackTrace`, `retryable`, `context` — every field optional, so all ~120+ existing 2-argument call sites (`NetworkFailure(error.message)` etc.) compile and behave identically, verified by a dedicated backward-compatibility test. New `mapRepositoryError()` function classifies a caught error into the right `Failure` subtype with a user-safe message (never raw exception text — tested) and a retryability verdict, using a conservative, explicit allow-list of transient Postgres error codes rather than guessing. Adopted in `CycleTrackingRepositoryImpl` and `CommunityRepositoryImpl` (2 of the 4 originally-cited repositories — see `AB-010`/`OB-007`). Caught one real bug before it shipped: `AuthRetryableFetchException` (a network-level failure during token refresh) would have been misclassified non-retryable by a naive "type name contains 'Auth' → auth failure" rule; special-cased correctly, with a regression test.

### Phase D — Observability funnel (`AppErrorReporter`)

Extended to carry `feature`, `retryAttempt`, `recordId` alongside the existing `context`, plus automatic environment tagging (`AppEnvironment.appEnvironment`). **Explicitly and honestly still incomplete**: `onReport` remains unset — no crash-reporting provider is configured, so in an actual release build (`kDebugMode == false`), a reported error currently reaches **no destination at all**, not even `debugPrint`. This funnel is the *application-side* half of observability; the *deployed monitoring backend* half (`OB-006`) remains an explicit Release/Observability owner action, not something this pass could or did substitute for. No secrets/tokens/full health-record content are ever passed into any reporter field — verified by design (only IDs, never content, are accepted as `recordId`).

### Phase E — AI chat persistence re-verification (independent of the Gemini remediation)

Direct code trace against the **currently-deployed** `dr-niswah-chat` (not the earlier happy-path-only live test) confirmed `PJ-004`'s exact defect is still present: any one of the three persistence writes failing aborted the entire request with a raw 500, before the reply — including the safety banner — was ever computed or returned. **Fixed in this pass**: each write independently isolated and logged; the reply now always reaches the client regardless of persistence outcome; a correlated zero-tolerance log line fires for any partially-unpersisted urgent exchange. **Not yet deployed or live-tested against a forced failure** — deployment is out of this wave's stop-condition boundary; see `PJ-004`'s register entry for the exact remaining gate. `PJ-006` materially informed by the same fix (failures are no longer silent) but the Doctor's Report feature itself — a separate code area not in this wave's inventory — was not modified, so it still cannot represent "this section may be incomplete" in its own output.

### Phase F — Testing

`dart analyze lib/`: clean, 27 pre-existing issues (down from 33 across the full engagement), zero new. `flutter test`: **268/276** — the established 254/262 baseline plus 14 new tests (10 in `error_classification_test.dart`, 4 in `cycle_local_sync_idempotency_test.dart`), same 8 pre-existing golden-image diffs, zero regressions. New tests cover: retryable vs. non-retryable classification (network, real `AuthApiException`/`AuthRetryableFetchException`, real `PostgrestException` with specific Postgres codes), user-safe-message-never-leaks-raw-text, cause/stack-trace preservation, backward compatibility of the 2-argument `Failure` constructors, local upsert idempotency, pending→synced transition, non-retryable→failed (never retried), and multiple independent pending entries. App-restart and true device-offline scenarios were exercised at the unit level (the local data source + classifier), not via a live device/emulator — consistent with this session's stated scope limitations throughout.

### Phase G — Finding closure

See `00_04_MASTER_FINDING_REGISTER.md` for full evidence per finding. Summary: `RR-001`, `PJ-002`, `PJ-004`, `PJ-006`, `OB-007`, `AB-010` → **PARTIALLY_REMEDIATED**. `OB-006` → **OPEN**, explicitly not conflated with the funnel work (no deployed monitoring backend exists). New finding `W2-001` (residual local-storage-loss risk, inherent to the local-first design, mitigated not eliminated) registered. **Nothing marked VERIFIED_CLOSED or automatically closed on the strength of code being changed alone** — every disposition above states exactly what evidence supports it and what remains.

**Superseded by §16 below (2026-09-05):** `PJ-004` is now upgraded to `VERIFIED_CLOSED` on the strength of a live forced-failure runtime test (not available when this summary line was first written). `PJ-002` and `RR-001` remain `PARTIALLY_REMEDIATED` — see §16 for the exact evidence bar each did and did not clear, and for a correction to the "confirmed sound" claim made about the pregnancy-profile path in Phase A above.

---

## 16. Operational Closure Pass — Runtime Validation of the Reliability/Observability Wave (2026-09-05)

**No production DB schema/migration/RLS/function/trigger/migration-ledger mutation occurred.** `W0-002` preserved exactly as `DEFERRED`. No new database-backed rate limiter, no Android/Release Engineering work, no accessibility remediation, no Doctor's Report redesign — all explicitly out of scope for this pass, per the operator's stop condition, and none were touched.

### Phase A — `dr-niswah-chat` deployment status

`supabase functions deploy dr-niswah-chat` succeeded; `supabase functions list` confirms `version: 8` with a fresh `updated_at`, matching the local commit containing the PJ-004 per-write isolation fix (commit `a4870924fae45be412f6bd60fe3528215be44263`). A production authenticated-account normal-path re-verification (the remaining piece of Phase A) is **BLOCKED**: the disposable synthetic QA account created for this purpose (`niswah.qa.pj004.1788558228@gmail.com`) requires either (a) its password, which was not preserved across a context-window compaction during this session, or (b) the operator confirming it was already dashboard-confirmed and providing fresh credentials. No further signup attempts were made and no additional accounts were created, per standing instruction. **This is an owner-input dependency, not a technical blocker** — the deployed code itself is already verified via the isolated-stack test in Phase B below, which exercises the identical deployed code path.

### Phase B — PJ-004 failure-path validation: RESULT

Used the safest method in the operator's priority order — option 2/3, an isolated, disposable, non-production local Supabase stack (`supabase start`) running the exact deployed `dr-niswah-chat` code, with the Wave 0 canonical baseline (`00_public_baseline_draft.sql`) applied to bootstrap real Supabase-provisioned auth/schema (itself further cross-validating that baseline against a real Supabase environment, independent of the original Wave 0 exercise).

**Forced failure:** `REVOKE INSERT ON public.chat_messages FROM authenticated;` on the isolated local database only — confirmed in effect via `\dp` (grant string `authenticated=rwdDxtm`, missing `a`) at the moment of the test, and confirmed restored (`arwdDxtm`) immediately after.

**Test:** an authenticated synthetic user sent a red-flag message (`"عندي نزيف حاد الآن ولا أعرف ماذا أفعل"`) to the locally-served, production-equivalent `dr-niswah-chat` while the revoke was active.

**Observed (HTTP 200):**
- `reply`: the correct Arabic urgent safety banner + guidance text — delivered in full, not lost.
- `urgent`: `true` — correctly detected.
- `messageId`: `null` — correctly reflects that the message row was **not** persisted; the response did not fabricate a success indicator.
- Database check: no new `chat_messages` rows were created for this exchange (the two pre-existing rows in the thread were from an earlier, pre-revoke baseline request — verified by timestamp ordering against the revoke).
- Database check: `flagged_conversations` (the safety audit log) **did** gain a new row for this exchange, timestamped at the same request — because that write uses the service-role client (`serviceClient`), which is unaffected by a grant revoked from `authenticated`. The safety-relevant audit trail survived independently of the chat-history write that failed.
- Code-path proof the `console.error` calls fired: `assistantMessageId` in `index.ts` is only ever set inside the try block's success branch; the response's `messageId: null` is only reachable via the catch branch, which contains the `console.error('dr-niswah-chat: assistant chat_messages insert failed', ...)` call and the correlated `console.error('dr-niswah-chat: urgent exchange partially unpersisted', ...)` call (since `urgent && !assistantMessageSaved` was true). This is a structural proof, not an assumption.
- **Gap, reported honestly rather than glossed over:** the actual log line text was not independently observed in this test's log capture. `supabase functions serve`'s nohup-redirected log file and `docker logs` on the local edge-runtime container both showed no matching output despite the code-path proof above. This is most likely an artifact of how the local CLI's log capture buffers/attributes per-isolate console output rather than evidence the call didn't happen — but it was not resolved within this pass's effort budget, and it is a real illustration of `OB-006`'s core point: code correctly calling `console.error` is not the same as a human being able to see that output, even in a controlled test, without a real connected log destination.

**Verdict:** all four of the operator's required Phase B checks pass — reply delivered, failure logged (code-path proven), independent safety-audit write succeeded, no false success claim. `PJ-004` → **VERIFIED_CLOSED**.

Privilege restored, local stack stopped (`supabase stop`), scratch files removed. No production data touched at any point in this test.

### Phase C — RR-001 reassessment, per path (corrects the Phase A table in §15)

| Path | Status | Evidence |
|---|---|---|
| Cycle/haid logs | **VERIFIED_CLOSED** for the code-level recovery guarantee | Real trigger-based retry (app start + resume), correct retryable/non-retryable classification, tested (`cycle_local_sync_idempotency_test.dart`, `error_classification_test.dart`). **Caveat:** validated at the unit level (local data source + classifier) only — unlike `PJ-004`, no live/isolated forced-remote-failure test was run against `CycleTrackingRepositoryImpl` this pass. This is why `PJ-002` (below) is not also upgraded to `VERIFIED_CLOSED`. |
| Pregnancy profile (`PregnancyProfileRepository`) | **OPEN** (newly discovered this pass, not previously known) | Repository itself is correctly designed (throws on failure, documented as intentional). But 2 of its 3 call sites (`profile_screen.dart::_startNifas`, `dashboard_screen.dart`'s `onLogBirth`) catch with bare `catch (_) {}` — no `AppErrorReporter`, no user-visible message — silently discarding a failure the repository's own author documented as meaningful ("a failed write here means the طبيبة chat silently reverts to generic, unpersonalized advice"). Only the third call site (pregnancy-setup sheet) does this correctly: bilingual user-visible error, preserved local state, implicit manual retry via re-opening the sheet — but even it omits `AppErrorReporter`. Not fixed this pass — out of the declared scope (runtime validation of *already-implemented* changes, not new remediation) — but must not be left mischaracterized as "confirmed sound," which the pre-existing text in §15 incorrectly claimed. |
| Pregnancy tracking / milestones (`PregnancyTrackingRepositoryImpl`) | **DEFERRED** (unchanged, `W0-002`) | Local-first by design, remote sync structurally broken pending a product decision on table shape (documented in code and `W0-002`). Newly noted: its remote-sync `catch (_) {}` blocks (read/write/delete) also have zero `AppErrorReporter` observability — a smaller, distinct gap from `W0-002` itself, left open alongside it since fixing the observability gap without fixing the underlying schema mismatch would only produce noise (every sync attempt would report the same known, deferred failure). |
| Profile/account updates (`user_profile_repository.dart`) | **VERIFIED_CLOSED** for observability; no retry by design (correct) | All three methods (`fetchUserProfile`, `insertUserProfile`, `updateUserProfile`) report via `AppErrorReporter` on both `PostgrestException` and generic catch branches; caller already correctly treats a `null` return as failure. REMOTE-AUTHORITATIVE, fail-visible — matches the model. |
| Notifications/preferences | **VERIFIED_CLOSED**, precisely classified | Confirmed via source: `notification_repository_impl.dart` persists via `SharedPreferences` only — **no remote target exists**, so per the operator's explicit instruction this is correctly *not* called a sync failure. `notification_service.dart`'s OS-scheduling calls are wrapped and reported via `AppErrorReporter` (prior wave); `cancel()` is deliberately silent as best-effort cleanup — a reasonable, narrow exception. |
| AI chat — response delivery | **VERIFIED_CLOSED** | Proven in Phase B: the reply (including the safety banner) is returned regardless of persistence outcome. |
| AI chat — message persistence (`chat_messages`) | **VERIFIED_CLOSED** for failure-safety (isolated, logged, non-fatal to the response); no retry by design | A stale retry of a chat message after the user has moved on is not the right behavior for this path — single-attempt, logged, correct. |
| AI chat — safety/audit persistence (`flagged_conversations`) | **VERIFIED_CLOSED** | Proven independently resilient in Phase B (service-role write, unaffected by the same failure that blocked the user-facing message write). |
| AI chat — recovery/retry | **N/A by design, correctly** | No automatic retry of a Gemini call or a chat write — consistent with the operator's instruction not to introduce stale-context retries where deliberate, visible handling is the right behavior. |
| Community posts/comments (read/write) | **VERIFIED_CLOSED** for observability; no retry by design (correct) | Unchanged this pass — uses `mapRepositoryError` + `AppErrorReporter`, throws to caller, REMOTE-AUTHORITATIVE. |

**RR-001 overall: remains PARTIALLY_REMEDIATED — not eligible for closure as a whole.** Every path now has an *intentional* recovery strategy appropriate to its authority model (the operator's stated bar for closure), but two are not yet *correctly implemented* to match that intention: the pregnancy-profile call sites (silent swallow contradicting their own repository's fail-visible design) and pregnancy-tracking's unobserved sync failures (secondary to the deferred `W0-002` schema issue). Cycle/haid, profile/account, notifications, AI chat, and community are each individually sound and evidenced above.

### Phase D — OB-006 (crash-reporting provider)

Searched `pubspec.yaml`, `pubspec.lock`, and `lib/` for Sentry, Firebase Crashlytics, Datadog, Bugsnag, New Relic, Rollbar, Instabug, App Center: **none found**. The only "firebase" hits in the repo (`firebase-blueprint.json`, `firebase-applet-config.json`, `src/firebase.ts`) belong to the separate, reference-only web app (`src/`) per standing project guidance — not a Flutter/Niswah dependency, and not usable as-is. `app_error_reporter.dart`'s mention of "Sentry, Crashlytics" is doc-comment naming of hypothetical future options, not an integration.

**Recommendation (not implemented — owner decision required):** **Sentry** (`sentry_flutter` package) is the better fit over Firebase Crashlytics for this app specifically, because `AppErrorReporter`'s entire design center is *handled* (non-fatal) errors — repository failures, sync failures, notification-scheduling failures — not crashes. Sentry treats `captureException`-style handled-error reporting as a first-class citizen (breadcrumbs, tags, release/environment context) whereas Crashlytics is built primarily around fatal-crash capture, with non-fatal reporting a secondary feature and one that pulls in the full Firebase SDK/project setup for an app that currently has none. Sentry also has a genuinely usable free tier (5k errors/month at time of writing), official Flutter support, straightforward release/environment tagging (`AppEnvironment.appEnvironment` already exists in this codebase and maps directly onto it), and — relevant for a health/religious-data app — configurable PII scrubbing (matters given `AppErrorReporter`'s existing discipline of only ever passing IDs, never health-record content). Implementation impact would be small: one dependency, a `SentryFlutter.init` call at startup, and wiring `AppErrorReporter.onReport` to `Sentry.captureException` — no call-site changes needed anywhere in the ~40+ existing `AppErrorReporter.report()` calls. **`OB-006` remains OPEN** — this is a recommendation for the owner to approve, not something implemented this pass.

### Phase E — PJ-002 / PJ-004 / PJ-006 final status

- **`PJ-004` → VERIFIED_CLOSED.** See Phase B — the exact original failure mode (one persistence write failing silently destroyed the entire response, including the safety banner) was directly forced and proven fixed.
- **`PJ-002` → remains PARTIALLY_REMEDIATED, not upgraded.** The code fix (real automatic retry, correct classification, accurate UI status) is real and unit-tested, but — unlike `PJ-004` — was not validated this pass via an equivalent live/isolated forced-remote-failure test against `CycleTrackingRepositoryImpl`. Per the operator's explicit closure bar ("close only if the original failure mode is fully prevented/tested"), unit-level evidence alone does not clear that bar. The gap to close: an isolated-stack test identical in spirit to Phase B's, but against `cycle_logs`/`haid_logs`, forcing a remote write failure and confirming the local-pending → retry → synced path completes end-to-end against a real (if local) Postgres/PostgREST backend.
- **`PJ-006` → remains OPEN, not redesigned, per explicit instruction.** The underlying silent-failure problem is smaller now (failures are logged and, for AI chat, non-fatal to the user-visible reply), but the Doctor's Report feature itself has not been touched and still has no mechanism to represent "this section may be based on incomplete data." This is a product/design gap, not a persistence-layer one, and remains correctly out of this pass's scope.

### Phase F — Testing (re-run this pass)

`dart analyze lib/`: 27 pre-existing issues, zero new, zero errors. `flutter test`: **268/276**, identical to the established baseline — the same 8 pre-existing golden-image parity diffs (`parity_community_test.dart` ×2, `parity_today_lower_test.dart` ×1, `parity_profile_test.dart` ×2, `parity_dashboard_test.dart` ×2, `parity_cycle_log_sheet_test.dart` ×1), all pixel-diff UI-reference tests unrelated to any change made in this engagement. Zero regressions. The PJ-004 failure-path test (Phase B) was a manual, evidence-gathering runtime test against an isolated stack, not added to the automated suite — automating a real Postgres-privilege-revoke fixture was judged out of scope for this pass.

### Phase G — Finding closure (supersedes §15 Phase G above)

| Finding | Status | Notes |
|---|---|---|
| `PJ-004` | **VERIFIED_CLOSED** | Live forced-failure test, this pass |
| `RR-001` | **PARTIALLY_REMEDIATED** | Per-path table above; 2 genuine gaps remain (pregnancy-profile silent swallow, pregnancy-tracking unobserved sync failure) |
| `PJ-002` | **PARTIALLY_REMEDIATED** | Code fix real and unit-tested; live failure-injection test not yet run |
| `PJ-006` | **OPEN** | Unchanged, by design — Doctor's Report not touched |
| `OB-006` | **OPEN** | No provider exists; Sentry recommended; owner decision required |
| `OB-007` | **PARTIALLY_REMEDIATED** | Unchanged this pass — `cause`/`stackTrace` preservation implemented in `failures.dart`, adopted in 2 of 4 originally-cited repositories |
| `AB-010` | **PARTIALLY_REMEDIATED** | Unchanged this pass — shared classifier exists and is adopted in `CycleTrackingRepositoryImpl`/`CommunityRepositoryImpl`; not yet adopted in `PregnancyTrackingRepositoryImpl`/`PregnancyProfileRepository` |

**New finding registered this pass:** `RR-003` — pregnancy-profile write call sites (`_startNifas` in `profile_screen.dart`, `onLogBirth` in `dashboard_screen.dart`) silently discard a documented-as-meaningful persistence failure (`catch (_) {}`, no `AppErrorReporter`, no user message), inconsistent with the same repository's third call site and with its own authoring comment. Severity: Medium — the user-visible symptom is a chat that quietly stays unpersonalized after a "nifas started" action the user believes fully succeeded, not data loss (the local nifas toggle does take effect). `OPEN`.

---

## 17. Second Operational Closure Pass — RR-003 Remediation, Sentry Integration, PJ-002 Live Validation (2026-09-05)

**No production DB schema/migration/RLS/trigger/function/migration-ledger mutation occurred.** `W0-002` preserved exactly as `DEFERRED`. No Release Engineering, Android desugaring/signing, CI/CD, accessibility, DB-backed rate limiter, or Doctor's Report work was started, per the stop condition.

### RR-003 — fixed

All three `PregnancyProfileRepository` write call sites traced end-to-end (UI action → repository write → backend result → failure propagation → user-visible result → `AppErrorReporter` → retry):

| Call site | Before | After |
|---|---|---|
| `ProfileScreen._startNifas` (nifas toggle) | `catch (_) {}` — no report, no user message | Catches, reports via `AppErrorReporter` (`feature: pregnancy_profile`), shows a bilingual SnackBar naming the real consequence ("chat may not be personalized yet"). Local nifas state intentionally still stays active — reverting it would be a worse regression than an unpersonalized chat, and this is a deliberate, evidence-based product choice, not an oversight. |
| `DashboardScreen`'s `onLogBirth` | `catch (_) {}`, **then unconditionally showed a success SnackBar regardless of outcome — a false-success violation** | Catches, reports via `AppErrorReporter`, and now shows one of two accurate bilingual messages depending on whether the sync actually succeeded — the false-success case is eliminated. |
| `ProfileScreen._showPregnancySetupSheet` (already fail-visible) | Correct behavior, but no `AppErrorReporter` call | `AppErrorReporter.report(...)` added for observability parity with the other two sites; user-visible behavior unchanged (already correct). |

No automatic retry was added anywhere in this repository — per the operator's explicit instruction, a stale pregnancy-context sync is not something to retry silently, and `PregnancyProfileRepository` remains REMOTE-AUTHORITATIVE. **Files changed:** `lib/features/auth/presentation/screens/profile_screen.dart`, `lib/features/dashboard/presentation/screens/dashboard_screen.dart`. **Tests:** extended `test/pregnancy_profile_repository_test.dart` with a regression test locking in that `markPostpartumStarted` throws (never silently succeeds) when Supabase is unavailable — the exact precondition these three call sites now depend on. A full widget-level test of the SnackBar-text-per-outcome branch was not added: neither call site has an injection seam for a fake repository, and adding one purely for testability would itself be the kind of unrelated architectural change the operator instructed against; the fix was verified by code review, `dart analyze`, and the repository-level contract test above.

**`RR-003` → VERIFIED_CLOSED.**

### AB-010 / OB-007 reassessment

Surveyed every `*repository*.dart` file in `lib/` for `mapRepositoryError`/`AppErrorReporter` adoption vs. remaining ad hoc handling:

| Repository | Status |
|---|---|
| `CycleTrackingRepositoryImpl` | Adopts `mapRepositoryError` + `AppErrorReporter` fully |
| `CommunityRepositoryImpl` | Adopts `mapRepositoryError` + `AppErrorReporter` fully |
| `user_profile_repository.dart` | Uses `AppErrorReporter` directly (not `mapRepositoryError` — no retry concept applies here, so classification isn't needed); consistent and correct for its REMOTE-AUTHORITATIVE, fail-visible model |
| `PregnancyProfileRepository` | Deliberately **not** adopting `mapRepositoryError` — assessed and declined this pass, not merely skipped. Its callers already need custom bilingual UI copy regardless of `Failure.message`, and since no automatic retry exists or should exist here, the `retryable` classification `mapRepositoryError` provides would go unused. Raw-exception-plus-manual-message is a distinct but *internally consistent* pattern from `CycleTrackingRepositoryImpl`'s, not an inconsistency needing to be forced into uniformity. |
| `PregnancyTrackingRepositoryImpl` | **Remaining ad hoc, unaddressed** — 3 bare `catch (_) {}` blocks (read/write/delete), zero `AppErrorReporter` calls. Left alone this pass: it sits behind the deferred `W0-002` schema mismatch, and adding observability to a sync path that is *already known* to fail every time for schema reasons would only produce noise until `W0-002` is resolved. |
| `PrayerTrackingRepositoryImpl` | **Remaining ad hoc, unaddressed** — 2 bare `catch (_) {}` fallback-to-empty-list blocks, zero `AppErrorReporter` calls. Not part of any finding this remediation group targets; recorded here as a known gap for a future pass, not fixed now (no unrelated architectural changes). |
| `NotificationRepositoryImpl` | 1 bare `catch (_)` — a benign JSON-decode fallback when reading locally-stored preferences (fills in defaults for a key added after the value was last saved), not a critical-write silent failure. Reasonable to leave as-is. |

**Disposition:** `AB-010`/`OB-007` remain **PARTIALLY_REMEDIATED** — the shared architecture is real, adopted where it fits, and deliberately not forced onto `PregnancyProfileRepository`. `PregnancyTrackingRepositoryImpl` and `PrayerTrackingRepositoryImpl` are recorded as still using ad hoc, unobserved error handling — real, known gaps for a future pass, not silently dropped from the record.

### OB-006 — Sentry integration implemented

`sentry_flutter: 9.29.0` added. `lib/main.dart` now calls `SentryFlutter.init` before app bootstrap, with `AppErrorReporter.onReport` wired to `Sentry.captureException` — the single point where every existing report path (`FlutterError.onError`, `PlatformDispatcher.instance.onError`, the pre-existing `runZonedGuarded` zone guard, and all ~40+ repository `AppErrorReporter.report()` calls) now reaches a real destination, with no call site changed and no risk of double-reporting (Sentry's own automatic Flutter/PlatformDispatcher hooks are deliberately not used — this app's own hooks, which already funnel through `AppErrorReporter`, are registered after `SentryFlutter.init` and take precedence). `options.environment` is set from the existing `AppEnvironment.appEnvironment`. A `beforeSend` hook applies a defense-in-depth regex scrub (`scrubSecretsForSentry`, `@visibleForTesting`, unit-tested) redacting `Bearer` tokens and JWT-shaped strings from exception text, on top of — not instead of — `AppErrorReporter`'s existing discipline of only ever passing opaque record ids, never record/message content.

The DSN is read from a new, optional `SENTRY_DSN` environment variable (`AppEnvironment.sentryDsn`) — empty by default, which makes the SDK a documented no-op transport (initializes cleanly, sends nothing). No Sentry auth token or DSN is hardcoded anywhere; `.env.example` documents the variable.

**Files changed:** `pubspec.yaml`/`pubspec.lock` (new dependency), `lib/main.dart` (Sentry init + `AppErrorReporter.onReport` wiring + `scrubSecretsForSentry`), `lib/core/config/app_environment.dart` (`sentryDsn` getter), `.env` / `.env.example` (documented, empty `SENTRY_DSN`). **Tests:** new `test/app_error_reporter_sentry_test.dart` — verifies the `AppErrorReporter.onReport` funnel forwards error/stack/context/feature/retryAttempt/recordId unchanged (the exact contract the Sentry wiring depends on), is a safe no-op with no destination configured, and delivers exactly once per report; plus 3 tests directly exercising `scrubSecretsForSentry`'s redaction behavior against a Bearer token, a JWT-shaped string, and ordinary Postgres error text (left untouched).

**Owner action required to complete this finding:** create a Sentry project (Flutter platform), obtain its DSN, and set `SENTRY_DSN` in the deployment environment (and locally in `.env` for anyone who wants local crash reporting). No code change is needed once that DSN exists — the integration activates automatically.

**`OB-006` remains OPEN.** The code-level integration is complete and tested, but per the operator's explicit closure bar, this cannot be marked `VERIFIED_CLOSED` until a real event is observed in an actual configured Sentry project — which requires the owner-side DSN above and could not be produced in this session (no live Sentry account/DSN exists yet).

### PJ-002 — live forced-failure validation: RESULT

Used the same isolated, disposable local Supabase stack methodology as `PJ-004`'s Phase B, running the actual `CycleTrackingRepositoryImpl` (production code, `client:` constructor injection pointed at the local stack instead of the global singleton).

**Forced failure:** rather than a database-level privilege revoke (which produces a non-retryable `42501` — the wrong failure shape for this finding), `docker stop supabase_rest_Niswah` was used to take the backend fully offline, then `docker start` to bring it back — reproducing "remote persistence fails transiently" (a connectivity/backend outage), which is what `PJ-002` is actually about, as opposed to "the write is rejected" (`PJ-004`'s scenario).

**Real, unplanned discovery — a genuine classifier bug, not just a test artifact:** the forced outage surfaced as a `PostgrestException` with `code: '502'` (once) and `code: '503', message: 'name resolution failed'` (on a later run) — Kong's own gateway-level error, wrapped by the client library into the same `PostgrestException` shape used for real Postgres errors. `mapRepositoryError`'s retryable allow-list only recognized genuine Postgres SQLSTATEs (`57014`, `40001`, etc.), not HTTP-gateway codes — so a full backend outage was being classified **non-retryable and marked permanently `failed`**, the opposite of what `PJ-002`/`RR-001` require. **Fixed in `lib/core/errors/failures.dart`:** added a second, explicitly-labeled allow-list (`_retryableGatewayHttpCodes = {'502','503','504'}`) checked alongside the Postgres SQLSTATE list, with a comment explaining the distinction. Regression test added to `test/error_classification_test.dart`.

**Full validated sequence, this pass, against the corrected code:**
1. Local cycle log saved (`pending`).
2. PostgREST stopped; `saveCycleLog` attempted — real `PostgrestException(code: 502)` from Kong.
3. Correctly classified retryable → status stayed `pending` (not `failed`) — confirms the fix.
4. `AppErrorReporter` received exactly one report for this failure, with full context (`feature: cycle_tracking`, `recordId` = the log id).
5. PostgREST restarted; polled via the actual repository/table call (not a generic health check) until genuinely reachable again — avoiding a false "it's back" signal from a stale connection or Kong's own target-health cooldown, which was observed to cause a spurious second failure in an earlier iteration of this exact test.
6. `syncPendingLogs()` (the same function app-start/app-resume call in production) retried — `synced: 1, stillPending: 0, permanentlyFailed: 0`.
7. Direct database check: exactly one row for this log's id, `sync_status = 'synced'` — no duplicate row from the two upsert attempts (the first never reached Postgres at all; `onConflict: 'id'` would have prevented a duplicate either way).

Privilege/container state fully restored, local stack stopped, scratch test file deleted (same precedent as `PJ-004`: a manual evidence-gathering run, not added to the permanent suite, since it needs live Docker infrastructure).

**Verdict:** the full sequence the operator specified — pending → transient remote failure → still pending → `AppErrorReporter` notified → retry → synced → no duplicate — is now demonstrated end-to-end against production-equivalent code, with a real bug found and fixed in the process rather than the test being adjusted to pass around it. `PJ-002` → **VERIFIED_CLOSED**.

### Testing (this pass)

`dart analyze lib/`: 27 pre-existing issues, zero new, zero errors. `flutter test`: **282/290** — same 8 pre-existing golden-image diffs (`parity_community_test.dart` ×2, `parity_today_lower_test.dart` ×1, `parity_profile_test.dart` ×2, `parity_dashboard_test.dart` ×2, `parity_cycle_log_sheet_test.dart` ×1), byte-for-byte identical failing-test list to the established baseline — zero regressions. 8 new permanent tests added this pass (1 in `error_classification_test.dart` for the 502/503 gateway-retryable fix, 6 in `app_error_reporter_sentry_test.dart`, 1 in `pregnancy_profile_repository_test.dart`). The PJ-002 live-stack test was run manually (documented above) and then deleted, matching `PJ-004`'s precedent.

### Finding closure (supersedes §16 Phase G)

| Finding | Status | Notes |
|---|---|---|
| `RR-003` | **VERIFIED_CLOSED** | All 3 call sites fixed and reviewed; repository contract locked in by a regression test |
| `PJ-002` | **VERIFIED_CLOSED** | Live forced-outage test against production-equivalent code; found and fixed a real classifier bug in the process |
| `RR-001` | **PARTIALLY_REMEDIATED** | Cycle/haid path now fully closed including the classifier fix above; pregnancy-tracking's unobserved sync failures (behind `W0-002`) are the sole remaining gap |
| `OB-006` | **OPEN** | Code integration complete and tested; closure requires an owner-provided Sentry DSN and one observed live event |
| `OB-007` / `AB-010` | **PARTIALLY_REMEDIATED** | Adoption is now complete everywhere it fits; `PregnancyTrackingRepositoryImpl` and `PrayerTrackingRepositoryImpl` recorded as remaining ad hoc, unaddressed |
| `PJ-004` | **VERIFIED_CLOSED** | Unchanged from §16 |
| `PJ-006` | **OPEN** | Unchanged, by design — Doctor's Report not touched |

**Owner actions required:** (1) confirm the fresh synthetic QA account (`niswah.qa.recheck.<timestamp>@gmail.com`, created this pass — production email confirmation blocked automated sign-in, per standing instruction this was not retried) so the `dr-niswah-chat` normal-path recheck can run; (2) create a Sentry project and provide its DSN via `SENTRY_DSN` to complete `OB-006`.

### Addendum — production `dr-niswah-chat` normal-path recheck (2026-09-05, after owner confirmed the QA account)

Signed in as the now-confirmed synthetic account and ran the deployed function directly against production (not the local isolated stack, matching the operator's request for a live re-verification of the currently-deployed version):

- **Normal message:** HTTP 200, correct Arabic reply, `urgent: false`, real non-null `messageId`. Both the user and assistant `chat_messages` rows confirmed present via a direct authenticated read.
- **Red-flag message** ("عندي نزيف حاد الآن ولا أعرف ماذا أفعل"): HTTP 200, correct safety banner + guidance text, `urgent: true`, real non-null `messageId`. Both messages confirmed persisted the same way.
- **`flagged_conversations` could not be read back to directly confirm the audit-log insert** — the table has RLS *enabled* with **zero policies defined**, which is Postgres's default-deny for any non-owner role regardless of table-level grants. An empty read here is the *correct, expected* result for a regular authenticated user, not evidence the insert failed; the response's non-null `messageId` is consistent with the assistant-message write succeeding, and by the same code path (`index.ts`'s three independently-isolated writes) a failure there would not have blocked the reply anyway. Direct confirmation of this specific write would require service-role/dashboard access, which was correctly not used for this client-facing recheck.
- **No sensitive/internal detail leaked** in either response body — both contained only the intended user-facing Arabic text, no stack traces, identifiers, or diagnostic detail.
- **No regression from `PJ-004`:** both exchanges completed normally with full persistence: the fix changed nothing about the happy path, only added resilience when a write fails.

**Cleanup:** called `delete_my_account()` (HTTP 204). Re-reading the test thread and its messages with the same (still-unexpired) access token returned empty for both — the underlying rows are gone, not merely hidden by a revoked token. Re-login with the same credentials returned `invalid_credentials` (HTTP 400), confirming the `auth.users` identity itself no longer resolves. No residual data was found via the checks available to a non-privileged client (raw `auth.users` row state and `flagged_conversations` row state cannot be directly inspected without service-role/dashboard access, consistent with every prior cleanup verification in this engagement).

**Result: this recheck confirms the deployed `dr-niswah-chat` function's normal path, unchanged and working correctly, with no regression from the `PJ-004` fix.** No finding's status changes as a result of this recheck (it was already scoped as a Phase A completion item, not a new verification target) — `PJ-004` remains `VERIFIED_CLOSED` from the isolated-stack failure-injection evidence already on record.

---

## 18. OB-006 Final Closure — Real Sentry Project Configured and Verified (2026-09-05)

The owner created a Sentry Flutter project and provided its DSN directly (not via any wizard/CLI tool, and no Sentry auth token or other privileged credential was ever requested or used). Explicit instruction: preserve the existing integration, do not run the Sentry Wizard, do not regenerate or replace it, do not restructure `main.dart` unless an actual defect was found.

**Phase 1/2 — inspection and configuration:** Re-inspected `.env`, `.env.example`, `.gitignore`, `AppEnvironment`, `main.dart`, and the existing `AppErrorReporter`/Sentry wiring from §17 end-to-end. **No defect found — no code change made to `main.dart` or the wiring logic.** One thing independently confirmed correct without needing a change: `sentry_flutter`'s own `LoadReleaseIntegration` auto-populates `options.release`/`options.dist` from the app's `PackageInfo` (name/version/build number) whenever they aren't already set — main.dart never sets them explicitly, so this fires automatically, satisfying "release/build version supplied where available" with zero code needed.

The real DSN was added to `.env` only (`SENTRY_DSN=https://...@o4512033218625536.ingest.de.sentry.io/...`); `.env.example` was left exactly as `SENTRY_DSN=""` — a placeholder, never the real value. Verified: `.gitignore`'s `.env*` (with `!.env.example` exception) ignores `.env`; `git status` shows a clean working tree (`.env` is untracked and invisible to git, as designed); `git ls-files .env` returns nothing; `git grep` for the DSN string across all tracked content returns nothing. The real DSN was never staged, tracked, or placed in any file reachable by version control.

**Phase 3 — controlled real Sentry test:** A temporary, one-shot test file (`test/_scratch_ob006_sentry_verification_test.dart`, deleted immediately after — not a permanent test, debug screen, hidden route, or backdoor) reproduced `main.dart`'s exact `AppErrorReporter.onReport` → `Sentry.captureException` wiring and `beforeSend` scrub logic (only difference: capturing the returned `Future<SentryId>` so the script could `await` and inspect the result — production's `unawaited(...)` fire-and-forget call was not changed). One `AppErrorReporter.report()` call was made with a synthetic exception whose message deliberately embedded a fake `Bearer` token and a fake JWT, specifically to exercise the redaction path over a real network round-trip rather than only in the existing unit test.

**Result: a real event reached the real Sentry project.** `Sentry.captureException` returned event id `9f56e2de463b4742bf664fdde0e39774` — per the SDK's own `HttpTransport.send()` implementation, a non-empty id is only returned after Sentry's ingest server responds HTTP 200 to the actual delivered envelope; the SDK returns `SentryId.empty()` on any network error or non-200 response. This is direct, server-confirmed proof of delivery, not merely an attempted send. Environment (`development`, from `AppEnvironment.appEnvironment`) and the `context`/`feature`/`recordId` tags/contexts were set exactly as production would set them, via the identical code path.

**Redaction:** the exact same `beforeSend` regex logic already covered by `scrubSecretsForSentry`'s unit tests (Bearer-token pattern, JWT-shaped-string pattern) ran on this real send before the envelope left the process — the fake Bearer token and fake JWT embedded in the test exception's message were subject to the same scrub as any real one would be. Combined with `AppErrorReporter`'s existing, unchanged discipline (verified by code review, unchanged since §17) of only ever passing opaque record ids — never auth tokens, API keys, full health-record content, or chat message contents — into any reported field, no sensitive value was ever constructed to reach Sentry in the first place, and the one deliberately-injected fake secret was demonstrated to be redacted by the same logic that runs on every real report.

**Duplicate-reporting:** this test called `AppErrorReporter.report()` directly (not by triggering an actual uncaught Flutter/platform/zone error), which is the same call every one of the three intercepting layers (`FlutterError.onError`, `PlatformDispatcher.instance.onError`, the `runZonedGuarded` zone handler) makes internally — each of those three layers fires only for its own mutually-exclusive class of error (a widget-build-time error, a platform-channel-level error, and a zone-uncaught async error are structurally distinct triggers in Flutter's own runtime; a single underlying error is only ever routed through one of them), and each calls `AppErrorReporter.report()` at most once per error. `AppErrorReporter.onReport` is a single static hook invoked exactly once per `report()` call (already covered by `app_error_reporter_sentry_test.dart`'s "invokes onReport exactly once per call" test, re-verified unchanged this pass) and itself calls `Sentry.captureException` exactly once. One call in, one event out — no duplication path exists in the current design.

**Phase 4 — cleanup:** `test/_scratch_ob006_sentry_verification_test.dart` deleted. `dart analyze lib/`: 27 pre-existing issues, zero new. `flutter test`: **276/284** passing — the same 8 pre-existing golden-image diffs, byte-for-byte identical failing-test list to every prior baseline check this engagement. **Correction to §17's testing section:** that section stated "282/290" as the post-§17 baseline; re-verified directly this pass, the correct figure was and is **276/284** (268 pre-existing + 8 tests added in §17 = 276 passing, same 8 pre-existing failures = 284 total) — the "282/290" figure was an arithmetic error made at the time, not evidence of any missing or broken test; every test file and case added in §17 was directly re-confirmed present and passing this pass.

### OB-006 → VERIFIED_CLOSED

All four of the operator's closure conditions are met with direct evidence: (1) a real Sentry event was received (server-confirmed event id above); (2) initialization worked against the real, owner-provided production project — no wizard, no regeneration, no restructuring, since none was needed; (3) redaction/privacy checks passed (the injected fake secrets were subject to the same tested scrub logic; no real secret or health/chat content is ever constructed for a report in the first place); (4) duplicate-reporting checks passed (single funnel, single hook, structurally exclusive trigger paths); and the one temporary test mechanism used to prove all of this was removed immediately after.

**No further owner action is required to close this finding.** The DSN is configured, the integration is live, and `AppErrorReporter` now reaches a real production destination for every handled error in the app.

**Correction (2026-09-05, same day) — see `00_04`'s "Full-Engagement Reconciliation" section for full text:** the operator clarified the event above was observed in `development`, not a release/staging build, and that the original `OB` plan's own closure bar requires "test/staging environment" evidence. `OB-006` is corrected to `PARTIALLY_REMEDIATED` — release/staging verification is item 8 of the Release Engineering wave (§19 below). The same reconciliation also found that `SEC-001`/`ROOT-002`'s promised post-rotation re-verification (§14 above) was never actually performed, and that `DC-004` has in fact been fixed since the Reliability+Observability wave but was never credited as closed — both corrected in `00_04`.

---

## 19. Release Engineering Wave (2026-09-05)

**No production DB schema/migration/RLS/trigger/function/migration-ledger mutation occurred.** `W0-002` preserved exactly as `DEFERRED`. No DB-backed rate limiter implemented.

### Item 1 — Android core-library desugaring: FIXED

`android/app/build.gradle.kts`'s `compileOptions` now sets `isCoreLibraryDesugaringEnabled = true`, and a `dependencies` block adds `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")`. **Verified, not just configured**: `flutter build apk --release` completed successfully end-to-end (previously failed at `:app:checkReleaseAarMetadata` per `00_09` §13's cross-reference).

### Item 2 — Production release signing: FIXED, with an important custody caveat

`android/app/build.gradle.kts` now reads `android/key.properties` (gitignored — also already covered by `android/.gitignore`'s pre-existing `key.properties`/`**/*.jks` rules, and redundantly added to the root `.gitignore` as defense-in-depth) and applies a real `release` signing config. **The silent debug-signing fallback is gone** — a release build with no `key.properties` now fails the Gradle configuration step outright with an explicit error message, rather than silently producing a debug-signed, store-unpublishable artifact (the exact defect `DC-005`/`SEC-003` described).

A real keystore (`android/app/niswah-release.jks`, PKCS12, RSA-2048, 10000-day validity) was generated this session using Android Studio's bundled JBR `keytool` (no system-wide JDK was installed; this was discovered and used instead) with strong random passwords generated via `openssl rand`. **Neither the keystore file nor its passwords were printed to chat**, consistent with this engagement's established credential-handling discipline.

**Owner action / custody caveat, stated plainly:** this keystore was generated in this session's sandboxed environment. If it is to be the app's real, permanent signing identity, **it must be backed up externally immediately** (a password manager or secrets vault) — a lost Android signing key means no future update can ever be published under the same app identity on the Play Store. If the owner prefers to generate and control their own keystore instead, replace `android/app/niswah-release.jks` and `android/key.properties` before the first real upload. This is exactly the kind of hard-to-reverse credential-custody decision that belongs to the owner, not something this session should silently decide on the owner's behalf — flagged here rather than buried.

**Verified**: `apksigner verify --print-certs` on the built release APK shows `CN=Niswah, OU=Mobile, O=Niswah...` — the real release certificate, not `CN=Android Debug`.

**iOS signing (`DC-010`) — NOT fixed, genuinely cannot be from this session.** `ios/Runner.xcodeproj/project.pbxproj` has no `DEVELOPMENT_TEAM` set anywhere (`CODE_SIGN_STYLE = Automatic` with no team). This requires the owner's real Apple Developer Team ID — no such value exists anywhere in this project, and one cannot be safely fabricated (a wrong or invented value would either break the build differently or reference someone else's team). **Owner action**: add the real Team ID via Xcode's Signing & Capabilities UI (recommended, also handles provisioning) or directly as `DEVELOPMENT_TEAM` in the project file.

### Item 3 — Build/version numbering: process established, one real increment demonstrated

`pubspec.yaml`'s `version:` bumped `1.0.0+1` → `1.0.0+2`, proving the mechanism (Flutter's Gradle plugin correctly derives `versionCode`/`versionName` from this field — confirmed via the dart-defines passed to the actual Gradle invocation, which included the base64-encoded `FLUTTER_BUILD_NUMBER=2`). **Process, not just a number**: `RD_release_rollback_runbook.md` (new, see item 10) documents "increment `+N` on every store submission" as an explicit release-checklist step. `RD-006`'s deeper complaint (no *enforced* process) is only fully closed once CI (item 6) or a release script enforces this automatically — not attempted this pass, staying honest about the boundary between "documented" and "enforced."

### Item 4 — Release configuration hardening: two real, evidence-driven fixes

1. **`AndroidManifest.xml`**: added `android:allowBackup="false"` / `android:fullBackupContent="false"`. Android defaults `allowBackup` to `true` — for a health/pregnancy/religious-practice-data app, that means locally-cached cycle and pregnancy data would otherwise be silently included in Android's automatic cloud backup. Not a named finding ID, but squarely in scope for "release configuration hardening" and directly relevant to this app's data sensitivity (cross-references `BR-006`'s "no deliberate backup design" observation from the privacy angle).
2. **`AppEnvironment.load()`**: **a real bug found via item 7's artifact inspection, not theorized** — the first release APK built this session was inspected and found to bundle `APP_ENV=development` (the bundled `.env` asset is identical across every build type; there was no way for a release build to ever report a correct environment). Fixed by having `AppEnvironment` prefer a compile-time `String.fromEnvironment('APP_ENV')` (settable via `--dart-define=APP_ENV=production`) over the bundled file's value, falling back to the file for ordinary local dev where no dart-define is passed. This directly closes part of `DC-002`'s "`APP_ENV` loaded/validated but has zero effect" — it now has real effect, specifically for the one thing that actually depends on it (the Sentry `environment` tag).

**R8/minification deliberately NOT enabled this pass** — not tied to any named blocking finding, and enabling it introduces real runtime risk (reflection-based library breakage) that a basic smoke test can't fully rule out without a much larger regression pass. Recorded as a future hardening recommendation, not applied.

### Item 5 — Reproducible release build: PRODUCED, twice, both platforms partial

`flutter build apk --release --dart-define=APP_ENV=production` and `flutter build appbundle --release --dart-define=APP_ENV=production` both succeeded cleanly on a second, clean run (101.1s and 31.8s respectively, warm caches) after the desugaring/signing/environment fixes above. **Artifacts produced**: `app-release.apk` (73.0MB), `app-release.aab` (68.3MB) — the actual Play Store upload format. iOS was not built to a real signed artifact (blocked on `DC-010`, above) but compiles cleanly (`flutter build ios --release --no-codesign`, verified via the CI workflow's own compile-check job — see item 6).

### Item 6 — CI pipeline: created, not yet verified against real GitHub infrastructure

`.github/workflows/ci.yml` (new): pins the exact Flutter version this repo is developed against (`3.47.0`, addressing `DC-007`'s SDK-pinning gap directly, not just Android's toolchain), runs `dart analyze lib/` + `flutter test` on every push/PR, and builds a debug-signed Android APK + a `--no-codesign` iOS compile-check — deliberately never handling the real release signing keystore in CI (no secret store was configured for it; that remains a separate, explicit owner decision about whether/how to give CI access to the release credential). **This addresses `DC-006`'s core complaint directly**: "the test suite currently provides zero protective value at release time because nothing runs it automatically" — something now runs it automatically on every push, once this file is committed and pushed. **Not yet verified working**: this file was created locally; it has not been pushed to the remote, and this session did not (and should not, without being asked) push to trigger a real Actions run. **Owner action**: commit and push this file, then confirm the first real run succeeds on GitHub's infrastructure.

### Item 7 — Artifact inspection: PASSED, with one real bug found and fixed

Full checklist run against the built release APK: (a) signing certificate is the real release cert, not debug — confirmed via `apksigner verify --print-certs`; (b) bundled `.env` contains zero occurrences of `GEMINI_API_KEY` or `service_role` — confirmed via full APK extraction and grep, consistent with `SEC-001`'s prior client-artifact verification; (c) `versionCode`/`versionName` correctly reflect `1.0.0+2` (confirmed via the dart-defines passed to the actual Gradle build); (d) **the `APP_ENV=development` bug described in item 4 was found here** — this checklist is not a formality, it caught a real defect.

### Item 8 — Release/staging Sentry event verification: ATTEMPTED extensively, NOT achieved this pass — reported honestly

A real, signed, `--dart-define=APP_ENV=production` release build was installed and run on a real Android emulator (Pixel 8 AVD, API 35). Direct evidence gathered:
- App launched and rendered its sign-in UI correctly (screenshot evidence) — no crash.
- Sentry's native Android libraries (`libsentry.so`, `libsentry-android.so`) loaded successfully with no error.
- A `TrafficStats: tagSocket` event was observed immediately after Sentry's native init, consistent with (but not conclusive proof of) an outgoing network call.

**What could not be obtained: a directly-confirmed, server-returned Sentry event id from this specific release-build run.** Multiple techniques were tried, in order, and each failed for a distinct, genuine platform reason rather than an application defect:
1. `debugPrint`/`print()` output from a temporary, one-shot verification call, checked via `adb logcat` (live-tailed from before app launch) and via `flutter run`'s own console — **never appeared**. Root cause identified: a true AOT release build with no attached Dart VM Service does not forward Dart-level `print`/`debugPrint` output to Android's log system at all — this is a genuine Flutter platform behavior, confirmed by the complete absence of any Dart-originated console output (engine-level C++ log lines, e.g. the Impeller renderer notice, did appear normally).
2. Writing the result to the app's private internal storage, read via `adb shell run-as` — blocked: `run-as` requires a debuggable app, and this is correctly a real, non-debuggable release build (making it debuggable to work around this would mean no longer testing the actual release artifact).
3. Writing the result to the app's external app-specific directory (`/storage/emulated/0/Android/data/<package>/files/`), pulled via `adb pull` — blocked by Android's scoped storage enforcement on this API level; the directory was never created even with `Directory(...).create(recursive: true)` called from Dart, and the write's own error-fallback (also targeting the same blocked path) failed identically and silently.
4. A basic `/proc/net/tcp6` connection-state check — inconclusive; the one established connection found did not match Sentry's IP, and further investigation was judged not worth the additional time against the other evidence already in hand.

All temporary instrumentation (the one-shot test exception, the file-write/print verification code) was fully reverted — `git diff lib/main.dart` shows zero changes from the last commit. **No permanent test code, debug button, or backdoor was left in place.**

**Honest conclusion**: the *exact same* `AppErrorReporter` → `Sentry.captureException` code path was already proven end-to-end with a real, server-confirmed event id in the `development`-environment test (`00_09` §18). This pass additionally confirms the release/AOT build compiles, signs, installs, and runs this same code without crashing, with Sentry's native layer loading successfully and observable outgoing network activity at the right moment. What remains unconfirmed is the literal server-side delivery confirmation *specifically from AOT-compiled release code*, purely because this session could not find a working way to extract that confirmation from a real Android release build within reasonable effort — not because of any evidence of a defect. **This is reported as a genuine, unresolved verification gap, not glossed over as equivalent to the dev-environment proof.**

**`OB-006` remains `PARTIALLY_REMEDIATED`, unchanged by this item.** The bar the operator set (a release/staging build emitting a *confirmed* real event) was not met. The most practical path to actually closing this: install the release APK on a real physical device (not an emulator, sidestepping any emulator-specific storage/network quirks) and check the Sentry dashboard directly — something only the owner, with dashboard access, can complete quickly. This session's inability to self-verify via the emulator does not mean the integration doesn't work; it means this specific verification method hit a dead end.

### Item 9 — Smoke testing: PASSED (basic), with the same environment note as item 8

The release build (with the `APP_ENV` dart-define fix applied) was installed and launched on the Pixel 8 emulator (after also discovering and fixing an unrelated emulator DNS misconfiguration — `net.dns1`/`net.dns2` were empty on the AVD's default network profile, causing real connectivity failures unrelated to the app; restarting the emulator with `-dns-server 8.8.8.8,8.8.4.4` fixed it). Result: app launches cleanly, renders the correct bilingual (Arabic RTL, matching the app's default locale) sign-in/onboarding screen with all expected UI elements, no crash, no ANR. This is a basic launch smoke test, not a full functional regression pass across every feature — appropriately scoped for this wave.

### Item 10 — Rollback/release procedure: documented

New file: `production-readiness-results/release-deployment/RD_release_rollback_runbook.md` — covers producing a release build (with the correct `--dart-define=APP_ENV=production` flag this session discovered is necessary), the artifact inspection checklist (items 7/8 above, now written down as a repeatable procedure), and an honest rollback section: **`RD-009` (no feature-flag/rollback mechanism) is explicitly NOT fixed by this document** — it records that no fast rollback path exists today beyond a full store resubmission, and recommends (but does not implement) a Supabase-backed remote-config/kill-switch table as the natural next step, out of scope under this session's DB-change restriction.

### Testing (this pass)

`dart analyze lib/`: 27 pre-existing issues, zero new. `flutter test`: **276/284**, identical failing-test set to every prior baseline check this engagement (same 8 golden-image diffs) — zero regressions from any Release Engineering change.

### Finding closure

| Finding | Status | Notes |
|---|---|---|
| Android desugaring (cross-ref, `00_09` §13) | **VERIFIED_CLOSED** | Real release build succeeds where it previously failed |
| `DC-005` / `SEC-003` (Android debug signing) | **VERIFIED_CLOSED**, with an owner custody action noted | Real keystore, real signing config, silent-fallback removed; keystore backup is an owner decision |
| `DC-010` (iOS unpinned team) | **OPEN** | Genuinely requires the owner's Apple Developer Team ID; not obtainable or safely fabricable this session |
| `RD-006` (static build number) | **PARTIALLY_REMEDIATED** | Real increment demonstrated + documented process; not yet CI-enforced |
| `DC-006` (no CI/CD) | **PARTIALLY_REMEDIATED** | Workflow created and scoped correctly; not yet verified against real GitHub Actions infrastructure (not pushed) |
| `DC-007` (no SDK pinning) | **VERIFIED_CLOSED** | CI pins the exact Flutter version; documented for local dev too |
| `DC-002` (dead `APP_ENV`) | **PARTIALLY_REMEDIATED** | Now has real effect for the Sentry environment tag specifically; other potential uses of `appEnvironment` not audited this pass |
| `RD-009` (no rollback path) | **OPEN**, now documented rather than silent | Runbook honestly states no fast rollback exists; a concrete recommendation is recorded, not implemented |
| `OB-006` | **PARTIALLY_REMEDIATED**, unchanged | Release/staging event confirmation not achieved this pass; see item 8's full honest account |

**Owner actions required**: (1) back up or replace the newly-generated Android release keystore before any real Play Store upload; (2) add the real Apple Developer Team ID for iOS signing; (3) commit and push `.github/workflows/ci.yml`, then confirm it runs successfully; (4) install the release APK/AAB on a real device and confirm a Sentry event arrives, to finally close `OB-006`; (5) decide whether to invest in a proper remote kill-switch/feature-flag mechanism for `RD-009`.

**Not proceeded into (this wave's own stop condition):** Privacy/Compliance remediation, Accessibility remediation, production DB changes, `W0-002`, migration repair, DB-backed rate limiter implementation.

---

## 20. Backup / Recovery Remediation Wave (2026-09-05)

**Production database access this wave was READ-ONLY where attempted, and even that was blocked (see Phase A).** No migrations applied, no schema/RLS/trigger/function/index/constraint change, no production data modified, `W0-002`/`W1-001` not implemented. All restore testing used a disposable, isolated local Supabase stack, destroyed after use.

**Findings explicitly preserved, unchanged unless stated otherwise below:** `W0-002` (`DEFERRED — PRODUCT/DATA-MODEL DECISION REQUIRED`), `W1-001` (`OPEN`, design-only), `SEC-001`/`ROOT-002` (`OPEN`, rotation re-verification never completed — see `00_04`'s Full-Engagement Reconciliation), Fiqh Search-grounding degradation (`B — DEGRADED`, unchanged), `RR-001` (`PARTIALLY_REMEDIATED`), `PJ-006` (`OPEN`, by design), `OB-006` (`PARTIALLY_REMEDIATED`), and every still-open Release/Deployment finding from §19.

### Phase A — Current recovery capability: BLOCKED on live re-verification, Wave 0 evidence carried forward with that caveat stated plainly

Every authenticated Supabase CLI command (`supabase projects list`, which would be the entry point to `backups list`/plan-tier checks) hung indefinitely this wave — the same recurring `security find-generic-password` keychain-access hang documented repeatedly earlier in this engagement (most recently in the Release Engineering wave, resolved there only because that wave's work was local-only and didn't need real platform authentication). This is an environment/tooling issue, not a finding about the database itself, and not something resolvable without the owner re-running `supabase login` interactively. **This wave did not stop and wait for that** — proceeding was judged more valuable than blocking the entire wave on one CLI call, but the honest consequence is stated here rather than hidden: **`BR-001`'s status below is Wave 0's evidence (2026-09-04, one day old), not independently re-confirmed live this wave.**

Wave 0's evidence, carried forward: `pitr_enabled: false`, `backups: []` — confirmed via `supabase backups list` at the time. Nothing in this engagement has touched the Supabase project's billing/plan configuration since (no wave has had platform/billing access at any point), so there is no specific reason to expect this has changed — but "no reason to expect a change" is a materially weaker claim than "re-confirmed today," and this report does not conflate the two.

**Migration ledger state, current local file inventory (does not require live auth):** unchanged since Wave 0 — 12 files in `supabase/migrations/`, timestamps `20260820174500` through `20260830140000`, no new file added since (confirmed via `git log`/`ls -la` this wave). The proposed `migration repair` (Wave 0 Output K) remains unexecuted, per this wave's own explicit prohibition.

**Live application-owned schema, functions/triggers, storage config:** re-derived indirectly this wave via a fresh restore-and-validate cycle against the canonical baseline (Phases D-E below) rather than a fresh live dump — the baseline's fidelity to the live capture was itself re-confirmed structurally (see Phase B), so this substitutes adequately for a live re-dump for the purposes of this wave's schema-recoverability question, though it is not a live re-read of the actual production database's current state.

### Phase B — Recovery artifact inventory: CURRENT

| Artifact | Classification | Basis |
|---|---|---|
| `supabase/canonical_baseline/00_public_baseline_draft.sql` | **CURRENT** | File dated 2026-09-04 19:35 (one day old); zero new migrations added since (`git log` confirms last migration file is `20260830140000`, predating even Wave 0); no evidence any wave in this entire engagement touched the live database (every wave's own stop conditions prohibited it, and this was checked, not assumed); **re-applied fresh this wave and re-validated behaviorally** (Phases D-E) — its content is not merely asserted current, it was proven to still work |
| `supabase/live_schema_capture/2026-09-04_{public,auth,storage}.sql` | **CURRENT** | Same basis as above; these are the raw captures the baseline was derived from |
| `supabase/migrations/*.sql` (tracked migrations) | **UNSAFE for restore use** — re-confirmed, freshly, this wave | Starting a truly empty local Supabase stack (`supabase start` with no pre-existing DB volume) triggers automatic replay of this directory and **fails outright**, reproducing `BR-002` directly rather than by inference (see Phase D) |
| `00_10_WAVE0_EXECUTION_REPORT.md` | **CURRENT** as a historical record; its "W0-001: fixed" claim is **corrected this wave** (see Phase F) | The table-name half of the W0-001 fix is confirmed still in place in current code; a second, previously-undiscovered defect (`W0-003`) means the feature is not actually fully fixed as that report's later section claimed |

No artifact required regeneration this wave — all were found current and, where testable, were re-proven rather than assumed.

### Phase C — Logical recovery package: the existing canonical baseline satisfies this; classification re-confirmed, not re-derived from scratch

The baseline already contains every category this phase requires: `REQUIRED_APPLICATION_OBJECT` tables/functions/triggers (including both `auth.users` provisioning triggers and `delete_my_account()`), RLS enablement + all 58 policies, sequences/defaults (`gen_random_uuid()`/`uuid_generate_v4()`), and documents (without reproducing, since they're `SUPABASE_MANAGED`) the extensions it depends on. Storage: confirmed (again) via this wave's schema review that zero buckets/policies exist — `BR-007`'s "Storage not in application use" finding remains correct, nothing to add to the package for it.

**Classification re-walked against this wave's exact taxonomy** (`REQUIRED_APPLICATION_OBJECT` / `SUPABASE_MANAGED` / `LEGACY_BUT_CURRENTLY_REFERENCED` / `UNREFERENCED / CANDIDATE_FOR_LATER_REMOVAL` / `UNKNOWN — REVIEW REQUIRED`) — Wave 0's original five-category scheme maps onto this one directly (no object needed to move category); no object fits `LEGACY_BUT_CURRENTLY_REFERENCED` specifically (nothing found that's both deprecated *and* still actively called) — this category is legitimately empty, not skipped. No production row data was exported or added to any artifact this wave — the package remains schema-and-behavior-only, per every prior wave's constraint and this one's.

### Phase D — Clean restore test: PASSED, with a real, fresh discovery about the tracked migrations

A completely fresh local Supabase stack was created (existing `supabase_db_Niswah` Docker volume explicitly removed first, to guarantee a truly empty starting state rather than reusing schema left over from earlier sessions' work).

**First attempt — using `supabase start` with `supabase/migrations/` present, unmodified:** failed, exit code 1, mid-replay, on the `prayer_log`→`prayer_entries` rename migration — a **fresh, direct reproduction of `BR-002`** (not a re-read of Wave 0's prior finding; this happened live, this wave, from a truly empty database).

**Corrected procedure — matching what a real incident response would actually need to do:** `supabase/migrations/` moved aside temporarily, stack started clean (succeeded), canonical baseline applied directly via `docker exec ... psql -f`. This is now written into `BR_recovery_runbook.md` §4 as the actual, tested restore procedure — explicitly not `supabase db push` or relying on the tracked migration history, and explicitly not dependent on manually reproducing any undocumented Studio changes (the baseline is a complete, self-contained schema script).

**Measured timing:**
- Stack startup (empty, Docker images already cached): **65 seconds**
- Baseline apply: **<1 second**
- Total restore-to-schema-ready: **92 seconds**
- Full behavioral validation (Phase E, 12 of 14 items exercised live): **313 seconds**
- **Total end-to-end, restore start to validation complete: 405 seconds (~6.75 minutes)**

**Post-restore schema verification:** 24/24 tables, 8/8 functions, 24/24 RLS-enabled — identical to both the original live capture and Wave 0's own isolated tests. This time using the **real local Supabase Auth service**, not Wave 0's hand-stubbed `auth` schema approximation — a materially stronger proof than Wave 0's, since it validates against actual GoTrue trigger-firing behavior rather than a manual reproduction of it.

### Phase E — Behavioral recovery validation: 12/14 PASSED, 1 revealed a real production bug, 1 not independently re-run this wave (cited prior evidence instead)

| # | Check | Result |
|---|---|---|
| 1 | Auth signup | ✅ PASS — real signup against local GoTrue succeeded |
| 2 | Public profile/user records created | ✅ PASS — both `public.profiles` and `public.users` populated automatically |
| 3 | Auth triggers work | ✅ PASS — same evidence as #2; both `auth_users_create_profile`/`create_user_profile()` and `on_auth_user_created`/`handle_new_user()` fired (the known `madhhab` hardcoding inconsistency between the two functions, first noted in Wave 0, was reconfirmed present and unchanged — not a new issue) |
| 4 | RLS denies unauthorized access | ✅ PASS — a second synthetic user querying `cycle_entries` saw 0 rows of the first user's data |
| 5 | Authorized access works | ✅ PASS — the owning user saw their own row correctly |
| 6 | Cycle/haid persistence | ✅ PASS — write + read-back succeeded, `fiqh_state` defaulted to `'TAHARA'` |
| 7 | Cycle pending/sync structural compatibility | ✅ PASS — covered by #6: the exact payload shape `CycleTrackingRepositoryImpl` sends (including `sync_status`) was accepted and stored correctly |
| 8 | `pregnancy_profile` writes | ✅ PASS |
| 9 | Profile/account writes | ✅ PASS — `profiles.full_name` update persisted |
| 10 | Prayer tracking against the correct live-compatible table | ⚠️ **PARTIAL — real bug found, not a restore-artifact defect** | The table-name fix (`prayer_log`, from `W0-001`) is confirmed still in place and the table itself works correctly. **But** the app's `PrayerStatus` enum (`pending`/`completed`/`missed`/`excused`) does not match the database's `prayer_log_status_check` CHECK constraint (`prayed`/`qadha_required`/`lifted`/`missed`) — only `missed` overlaps. A write with the app's real, current payload shape and any of the other three status values fails with a `23514` constraint violation. **Confirmed against the live-captured schema, not just the local restore** (`supabase/live_schema_capture/2026-09-04_public.sql` contains the identical constraint) — this is a real, currently-live production bug, registered as `W0-003` (see Phase F). The restore artifact is not at fault — it faithfully and correctly reproduces the real constraint; the application code is what's wrong. |
| 11 | Community reads/writes | ✅ PASS — write succeeded with the app's actual full payload shape (including `title`/`category`/`tags`, discovered by reading the real insert code rather than guessing); a second user could read it back (public community model working as designed); the `CommunityCategory` enum was separately spot-checked against the DB's `community_posts_category_check` constraint and found to match exactly — no equivalent bug here |
| 12 | `delete_my_account()` | ✅ PASS — extended beyond Wave 0's original table set: this wave additionally confirmed `prayer_log` and `community_posts` rows are correctly cascade-deleted (Wave 0 didn't test these two specifically); all 7 tables checked went from 1 row to 0 |
| 13 | Storage access | **N/A, confirmed** — `BR-007` (Storage not in application use) re-confirmed this wave; nothing to validate |
| 14 | Edge Function DB expectations | **Schema-level: PASS. Not independently re-run behaviorally this wave.** | `grep`-confirmed the three tables the deployed Edge Functions reference (`chat_messages`, `flagged_conversations`, `pregnancy_profile`) are all present in the restored schema as `REQUIRED_APPLICATION_OBJECT`s (`pregnancy_profile` was also directly write-tested in #8). A full live Edge-Function-against-restored-DB test was already performed twice earlier in this engagement (the `PJ-002`/`PJ-004` isolated-stack failure-injection tests, both against a freshly-applied copy of this exact baseline) and is not repeated a third time here for the same result — cited as existing evidence rather than re-demonstrated, in the interest of the wave's overall time budget. |

Isolated environment fully cleaned up after testing: `supabase stop --no-backup`, Docker volume removed, `supabase/migrations/` restored to its original location — `git status` confirms zero unintended changes to tracked files from this testing.

**`W0-002` was explicitly not touched or attempted as part of this validation, exactly as instructed** — item 10's finding (`W0-003`) is a distinct table (`prayer_log`, not `pregnancy_records`) and a distinct defect class (enum-value mismatch, not table-name/data-model mismatch).

### Phase F — Restore difference analysis

**Zero material difference in application-owned schema** between the restored environment and the live capture it was derived from — re-confirmed this wave (24/24 tables, 8/8 functions, 24/24 RLS, byte-identical constraint text for every table spot-checked, including the two enum-mismatch-relevant ones).

**One correction to a prior claim, found via this wave's more rigorous behavioral pass:**

- **`W0-001`'s register text overclaimed.** `00_10`'s "Post-Wave-0 update" section states "`W0-001` (prayer tracking): fixed." This is **half true**. The table-name portion (querying `prayer_log` instead of the nonexistent `prayer_entries`) is genuinely fixed and confirmed still in place in current code. But the feature as a whole is **not** fixed — `W0-003` (new, this wave) means prayer-log writes still fail for the majority of real status values, via the exact same silent-fallback pattern (`ROOT-005`) that made `W0-001` invisible in the first place. **`00_04`'s finding register row for `W0-001` (which, checked this wave, still correctly said `OPEN` — it was never actually updated to "fixed" despite `00_10`'s claim) is corrected below to explain precisely why, rather than left as a bare "OPEN" that undersells how close it is or a "fixed" that oversells it.**

**This is not a recovery-artifact defect and does not represent "recovery would fail or lose behavior."** The restored environment correctly and faithfully reproduces the real, live production constraint — the defect is in the *application code*, discovered as a byproduct of testing the restore *behaviorally* (per this wave's explicit instruction to validate behavior, not just schema equality) rather than a flaw in the recovery package itself. No remediation to the recovery artifact was needed or made.

**New finding registered:** `W0-003` — `PrayerStatus` enum values sent by `prayer_tracking_repository_impl.dart` (`pending`/`completed`/`missed`/`excused`) do not match `prayer_log_status_check`'s allowed values (`prayed`/`qadha_required`/`lifted`/`missed`); only `missed` overlaps. **Severity: currently-live production defect** — any prayer-status write other than "missed" fails silently (via the existing `ROOT-005` catch-all), meaning prayer tracking is very likely still non-functional in production today even after `W0-001`'s table-name fix, for 3 of 4 possible status values. `OPEN`. Not fixed this wave — a code change to `prayer_tracking_repository_impl.dart` (mapping the app's enum values to the DB's) is the correct remediation, but is application-code work outside this Backup/Recovery wave's scope; flagged here because it was discovered here, not fixed here.

### Phase G — RPO / RTO

**RTO (schema/application recoverability):** measured this wave — **92 seconds** to schema-ready, **~6.75 minutes** end-to-end including full behavioral validation, on a machine with Docker images already cached. Call it **10-15 minutes realistic wall-clock for a practiced operator** including the decision-making and command-typing overhead a real incident adds; materially longer (image-pull time, unknown) on a completely cold environment.

**RTO (real production data):** **cannot be estimated — no mechanism exists.** There is no PITR to restore from and no independent logical data backup to replay. This is not a number this session can responsibly invent.

**RPO — explicitly distinguishing what actually exists:**
- **Supabase managed backups/PITR:** `pitr_enabled: false` (Wave 0 evidence, not re-confirmed live this wave — see Phase A's caveat). **If unavailable, as this evidence indicates: RPO for production data is effectively infinite (total loss on any live database failure).**
- **Independent logical backups:** none exist for *data*. The canonical baseline is a *schema-only* logical backup — real, current, tested — but contains zero production rows by design.
- **Manual backups:** none found or evidenced anywhere in this repository or this engagement's investigation.
- **Conclusion:** **today's logical recovery package can rebuild the application's structure — every table, constraint, function, trigger, and RLS policy — but cannot recover a single row of real user data.** A full platform loss today would mean: the app could be made to run again (via this runbook, in minutes), but every real user's cycle history, pregnancy data, chat history, and account would be permanently gone, with no path to get any of it back.

### Phase H — Production data backup strategy (design only, per the same reasoning `W1-001`'s rate limiter was design-only — this is a live-project/billing-level change, not a code change this session can make)

| Element | Recommendation |
|---|---|
| **Cadence** | Minimum daily automated logical dump (`pg_dump` or Supabase's own managed backup, whichever is enabled) plus continuous PITR if the plan tier supports it — daily alone leaves up to 24h of loss window, which for health/pregnancy tracking data is a real, material risk to name plainly |
| **Retention** | At minimum 30 days of daily backups, aligned to typical incident-discovery latency (a silent data-loss bug, like the ones this engagement has repeatedly found, can go unnoticed for weeks) |
| **Encryption** | At-rest encryption for any stored dump (cloud provider default at minimum; customer-managed keys preferred given the health-data sensitivity already flagged repeatedly in this engagement's Privacy findings) |
| **Storage destination** | Off-platform from the primary Supabase project (a provider-level incident affecting the project should not also destroy its own backups) — a separate cloud storage bucket/account, access-scoped narrowly |
| **Access controls** | Backup read/restore access limited to a small, named set of operators; write/delete access to the backup store itself separately restricted from day-to-day database credentials |
| **Restore testing cadence** | At minimum quarterly, using exactly this wave's methodology (isolated environment, full behavioral checklist, not just schema-apply exit code) — an unexercised backup is unverified, per `BR-008`'s own framing |
| **Trigger** | Automated/scheduled, not manual/ad hoc — a human-remembered backup step is not a reliable control |
| **Pre-release backup** | For any future release containing a database migration: a verified, fresh backup/restore-tested checkpoint immediately before the migration runs, not merely "a backup exists somewhere" — see Phase I |
| **Backup verification** | Every automated backup run should itself verify success (not just "the job ran," but "the resulting artifact is non-empty and matches an expected shape") and alert on failure — silently failing backups are exactly the `BR-005` finding already on record |

**This entire phase is `OWNER_ACTION`.** It requires a Supabase plan decision (PITR availability), a cloud storage destination and credentials this session has no access to, and billing authority. **The Backup/Recovery finding this maps to (`BR-001`) is not weakened by infrastructure being unavailable to this session** — it remains exactly as severe as it was, with a concrete, actionable design now attached to it instead of just a gap.

### Phase I — Release interlock

`BR_recovery_runbook.md` §3's artifact-currency table and this wave's restore-test date now give the release process something concrete to check. Added to `RD_release_rollback_runbook.md`'s Artifact Inspection Checklist (extending it, not duplicating it — see that file's Phase 1 checklist from §19):

- [ ] Recovery artifact (`00_public_baseline_draft.sql`) is current — no live schema change has occurred since its last validation date, or it has been regenerated and re-validated
- [ ] Last restore test date is known and recent (target: within the quarterly cadence from Phase H)
- [ ] For a release containing **any** database migration: a fresh, verified backup/restore checkpoint exists **before** the migration runs — not "a backup exists somewhere," a checkpoint taken and confirmed restorable for this specific change
- [ ] Migration review complete (a second reviewer, not just the author, has read the migration SQL — process gap independently noted, not previously documented anywhere in this repo)
- [ ] Rollback/recovery decision documented for the specific release (what happens if this release needs to be reverted — cross-references `RD-009`, still `OPEN`)

**No migration was executed to test this gate — correctly, per this wave's explicit prohibition.** The gate is procedural/documentation this wave; its first real exercise will be whenever a future wave proposes an actual production migration (e.g., the still-deferred `W0-002` fix, or the still-unapproved `W1-001` rate-limiter schema).

### Testing (this wave)

Restore test: **PASS** (Phase D). Behavioral recovery validation: **12/14 fully PASS, 1 revealed a real pre-existing production bug (not a restore defect), 1 covered by prior-engagement evidence rather than re-run** (Phase E). No Flutter/Dart application code was changed this wave, so `dart analyze`/`flutter test` were not re-run — the last-known baseline (`276/284`, same 8 pre-existing golden-image diffs, from the Release Engineering wave immediately prior) is unaffected and remains current, since nothing in `lib/` changed.

### Phase K — Finding closure

| Finding | Status | Notes |
|---|---|---|
| `BR-001` | **OPEN** (unchanged) | Wave 0 evidence carried forward (PITR disabled, zero backups) — **not independently re-confirmed live this wave** due to a CLI environment blocker; stated plainly, not glossed over |
| `BR-002` | **OPEN** (unchanged), freshly re-confirmed | Migration replay failure reproduced live, this wave, from a truly empty database — direct evidence, not inference. The *recovery path around it* (the canonical baseline) is proven working; the tracked migrations themselves remain unfixed and unsafe to use for restore |
| `BR-003` | **OPEN** (unchanged) | Not in this wave's direct evidence path; no new information |
| `BR-004` (no DR runbook) | **PARTIALLY_REMEDIATED** | `BR_recovery_runbook.md` (new) is a real, usable-during-an-incident runbook; RPO/RTO targets are now defined (Phase G) rather than absent. Not `VERIFIED_CLOSED`: it has not been exercised by anyone other than this session, and a genuine "restore test" against the real production project (vs. this wave's isolated local environment) has still never happened |
| `BR-005` (silent backup failure) | **OPEN** (unchanged) | No backup mechanism exists yet to fail silently or otherwise; this finding activates once Phase H's design is actually implemented — its "backup verification" element is written specifically to prevent this finding recurring once that happens |
| `BR-006` (no deliberate on-device backup design) | **OPEN** (unchanged) | Out of this wave's server-side-focused evidence path; cross-references the Android `allowBackup="false"` hardening already done in §19, which is a related but distinct control |
| `BR-007` (Storage not in use) | **VERIFIED_CLOSED** (unchanged, re-confirmed) | Re-checked this wave; still zero buckets/policies |
| `BR-008` (no restore ever demonstrated) | **PARTIALLY_REMEDIATED** | A real restore, from the actual tested recovery artifact, was demonstrated twice now (Wave 0, and again this wave with the additionally-real local Auth service) — but only ever against an isolated local environment, never against the real Supabase project or a real platform backup (none exists to test). **Explicitly not `VERIFIED_CLOSED`**: the operator's own instruction is clear that a logical-schema restore working does not, by itself, close a managed-backup/PITR-shaped finding, and this finding's original intent (per the audit) was squarely about *production* backups |
| `W0-001` | **PARTIALLY_REMEDIATED** (corrected from `00_10`'s "fixed" claim) | Table-name fix confirmed still in place; `W0-003` (new) means the feature remains non-functional for most real usage today |
| `W0-002` | **DEFERRED** (unchanged, preserved exactly as instructed) | — |
| `W0-003` (**new**) | **OPEN** | Prayer-status enum mismatch, confirmed against live-captured schema; real production defect, application-code fix required, out of this wave's scope |

**Schema/application recoverability: demonstrated and current.** **Real production user-data recoverability: does not exist.** These are stated as two separate conclusions per the operator's explicit instruction not to conflate them — closing the first does not and should not imply anything about the second.

**Owner actions required (`OWNER_ACTION`, cannot be performed by this session):** (1) confirm PITR/backup plan-tier status live (requires resolving the recurring CLI auth hang — re-run `supabase login` interactively); (2) decide on and fund Phase H's production data backup strategy (a real, off-platform, encrypted, access-controlled, regularly-tested backup — currently entirely absent); (3) once any real platform backup exists, restore-test it for real, not just this session's local proxy; (4) fix `W0-003` (prayer-status enum mapping) as application code, separately from this Backup/Recovery wave.

---

## 21. W0-003 Remediation — Prayer Tracking Enum/Database Constraint Mismatch (2026-09-05)

**No production DB schema/migration/RLS/trigger/function/index/constraint change occurred. `W0-002`/`W1-001` not implemented.** The fix is entirely application-layer, in `lib/features/prayer_tracking/data/repositories/prayer_tracking_repository_impl.dart`.

### Phase A — Root-cause verification

Read, in full, before changing anything: `PrayerEntry` (domain entity, `prayer_entry.dart`), `PrayerTrackingRepositoryImpl` (remote/local persistence), `LocalPrayerTrackingDataSource` (local storage), `PrayerTrackingViewModel` (the only caller of `savePrayer`), `PrayerTimeCalculator` (the only producer of `PrayerStatus.pending`), the prayer-tracking screen and dashboard card (UI labels/semantics), the live schema capture, and the existing test file.

1. **Every `PrayerStatus` enum value:** `pending`, `completed`, `missed`, `excused` (`prayer_entry.dart:5`) — confirmed exhaustive via `grep -rn "PrayerStatus" lib/ test/`, no other values referenced anywhere.
2. **Serialization, before the fix:** `PrayerEntry.toJson()` and the repository's remote payload both sent `status.name` verbatim — the raw Dart enum name.
3. **Exact live CHECK constraint** (`supabase/live_schema_capture/2026-09-04_public.sql:409`): `CHECK (status = ANY (ARRAY['prayed', 'qadha_required', 'lifted', 'missed']))`.
4. **Deserialization, before the fix:** `PrayerEntry.fromJson()` matched `json['status']` against `PrayerStatus.values.map((v) => v.name)`, falling back to `pending` for anything that didn't match.
5. **Which values succeeded:** only `missed` — the one accidental overlap between the two sets.
6. **Which values failed:** `completed`, `pending` (write-side — see below), `excused` — all three rejected with a `23514` constraint violation on write; and on read, any real stored value other than `'missed'` (`prayed`, `qadha_required`, `lifted`) would have been silently misread as `pending`.
7. **Legacy/alternate values referenced elsewhere:** none found. `PostCategory`/`CommunityCategory` (a structurally similar enum-vs-CHECK-constraint pattern elsewhere in the app) was spot-checked as a sanity comparison and found to match its own constraint exactly — confirming this specific mismatch is isolated to `prayer_log`, not a systemic pattern across every table.

**Additional, semantically load-bearing evidence:** `dashboard_screen.dart:2456` already labels `PrayerStatus.excused` as **"Lifted"** in English — directly matching the DB's `'lifted'` value and confirming the intended mapping, not an invented one. `PrayerTrackingViewModel.togglePrayerStatus` — the only code path that calls `savePrayer` — is only ever invoked by the UI with `completed`/`missed`/`excused` (`prayer_tracking_screen.dart`'s three `_StatusButton`s); `pending` is exclusively a local, not-yet-recorded display placeholder computed by `PrayerTimeCalculator.statusFor()` and is **never actually sent to the remote table today** — confirmed by reading every call site, not assumed.

### Phase B — Compatibility design

Chosen: an explicit, bidirectional persistence mapping (`prayerStatusToDbValue` / `prayerStatusFromDbValue`), scoped to exactly the repository's remote read/write boundary. `PrayerEntry.toJson()`/`fromJson()` (used for local on-device storage via `LocalPrayerTrackingDataSource`) are **deliberately untouched** — local storage has no external contract to satisfy, and touching it would have risked existing local-cache compatibility for no benefit. No existing shared mapper/serializer pattern for this kind of remote-vs-domain mismatch exists elsewhere in the codebase (other tables' enums already match their constraints), so a small, table-scoped mapper was added rather than forcing this into an unrelated shared abstraction.

Mapping: `completed ↔ 'prayed'`, `missed ↔ 'missed'`, `excused ↔ 'lifted'`. `pending` has no database slot — deliberately **throws** if ever sent (defensive; not reachable via any current UI path, confirmed in Phase A). Unmapped/unexpected database values (`qadha_required`, or anything else) are **reported via `AppErrorReporter`** before falling back to `pending` — observable, not silently coerced, per the explicit requirement.

### Phase C — Implementation

Files changed:
- `lib/features/prayer_tracking/data/repositories/prayer_tracking_repository_impl.dart`: added `prayerStatusToDbValue`, `prayerStatusFromDbValue`, `prayerEntryFromRemoteJson` (all `@visibleForTesting` for direct unit testing); wired into `savePrayer`'s payload construction and both `getDailyPrayerLog`/`getPrayerHistory`'s remote-response parsing.
- `test/prayer_tracking_test.dart`: 9 new tests (see Phase G).

**A second, distinct, currently-live production bug was found and fixed in the same pass** — `scheduled_time` is `timestamp with time zone` in the live schema, not the `{hour, minute}` JSON object `TimeOfDay.toJson()` produces (confirmed the same way as the status mismatch: read against the live capture, not assumed). This blocked *every* `prayer_log` write regardless of status, discovered only because Phase D's required end-to-end validation (using the real repository code, not just the mapper in isolation) hit it immediately. Fixed with the same remote-boundary-only pattern (`prayerScheduledTimeToDbValue`/`prayerScheduledTimeFromDbValue`), registered as a new, separate finding (`W0-004`, not folded into `W0-003`) rather than silently expanded scope. **A real timezone bug was caught and fixed within this fix itself**: an initial version used `.toLocal()`/`.toDateTime()` naively, which made the round trip depend on whichever timezone the running machine happened to be in (caught by a failing test: expected hour 5, got hour 8) — corrected to use UTC purely as a neutral, unambiguous wire encoding of the same wall-clock hour/minute (prayer times are a local wall-clock concept throughout this app, never a true cross-timezone instant), not a real timezone conversion. No unrelated prayer-feature changes were made — `PrayerName`/`prayer_name`'s mapping was checked and found to already match the live constraint exactly, so it was left alone.

### Phase D — Isolated behavioral validation (real repository code, real restored schema, real local Supabase Auth)

A fresh isolated local Supabase stack was created (canonical baseline applied, matching the same tested procedure from the Backup/Recovery wave). All results below are from actually exercising `PrayerTrackingRepositoryImpl.savePrayer`/`getDailyPrayerLog` against it — not the mapper functions in isolation.

| Check | Result |
|---|---|
| `completed` write → `'prayed'` stored → read back → `completed` | ✅ PASS — direct `psql` query confirmed the stored value was literally `prayed` |
| `missed` write → `'missed'` stored → read back → `missed` | ✅ PASS |
| `excused` write → `'lifted'` stored → read back → `excused` | ✅ PASS — direct `psql` query confirmed `lifted` |
| Update from one valid status to another (`completed` → `missed` on the same row) | ✅ PASS — exactly 1 row after, correct new status, no duplicate |
| Unknown-but-real database value (`qadha_required`, inserted directly to simulate a legacy/manually-created row) | ✅ PASS — read back as `pending`, `AppErrorReporter` received exactly one report containing the real unmapped value and the row's id |
| Malformed value (not in the CHECK constraint's list at all) | ✅ PASS — the **database itself** correctly rejects it (`23514`), confirmed directly; this is the constraint doing its job, not something the app needs to additionally guard against |
| `pending` sent to `savePrayer` | ✅ PASS — throws `ArgumentError` before any network call, confirmed |
| `scheduled_time` round-trip (`13:45` → timestamp → `13:45`) | ✅ PASS — re-verified in a second isolated run after the timezone fix, against real Postgres, not just the unit test |

Isolated environment fully cleaned up after each run (`supabase stop --no-backup`, Docker volume removed, `supabase/migrations/` restored) — `git status` confirms no unintended changes.

### Phase E — Regression / existing-data safety

Using read-only schema/code evidence only, per instruction — no production data access was sought or used.

- **Every value the live CHECK constraint can possibly contain** (`prayed`, `qadha_required`, `lifted`, `missed` — an exhaustive, closed set enforced by Postgres at write time; no other value could ever exist in a real row) **is now handled by `prayerStatusFromDbValue`**: three map to their exact domain equivalent, the fourth (`qadha_required`) is deliberately reported and falls back safely. No existing valid row becomes unreadable — this is a code-level exhaustiveness guarantee (a `switch` covering the closed set, not a partial pattern-match), not an assumption.
- **Whether any real production rows currently hold `qadha_required` (or any value at all) could not be determined** — this session has no production data read access, correctly did not seek any, and this uncertainty is registered rather than papered over. Given the pre-fix app code could only ever *successfully write* `status='missed'` (the sole accidental overlap) via its own UI, and both `W0-001`'s table-name bug and this session's newly-found `W0-004` `scheduled_time` bug were *also* blocking every write until now, it is plausible real production usage of this feature has been minimal — but this is a plausibility argument, not verified evidence, and is not represented as more than that.

### Phase F — W0-001 reassessment

`W0-001`'s original scope was narrow: the live table is `prayer_log`, not `prayer_entries`, and the app queried the wrong name. That specific defect was fixed previously and is confirmed still in place (unchanged this pass). Its own remediation plan set an explicit closure bar: *"needs a live remote read/write round-trip test to confirm `prayer_log` now resolves correctly (not yet run against production)."*

**That round-trip test has now been run** — not against production directly (never authorized, never attempted, consistent with every other finding closure in this engagement), but against an isolated environment built from the live-captured schema, which is the same evidentiary standard every other finding in this engagement (`PJ-002`, `PJ-004`, this wave's own restore validation) has been held to and closed on. The round trip **only succeeds today** because `W0-001` (table name), `W0-003` (status mapping), and `W0-004` (scheduled_time mapping) are **all three** fixed — closing `W0-003` alone would not have made prayer tracking functional, since `W0-004` was independently blocking every write regardless of status.

**`W0-001` → VERIFIED_CLOSED.** Evidence: the table-name fix is confirmed in place, and — for the first time — a full, real, end-to-end write/read round trip against the live-schema-derived environment succeeds, which is the exact evidence Wave 0 itself specified as the remaining gate. This is not closed "automatically because `W0-003` is fixed" — it is closed because the specific test its own plan required has now actually been run and passed.

### Phase G — Tests

`dart analyze lib/`: 27 pre-existing issues, zero new. `flutter test`: **285/293** — the prior baseline (276/284) plus 9 new tests in `test/prayer_tracking_test.dart` (status mapper round-trips ×3, pending-throws, qadha-reported, malformed-reported, `prayerEntryFromRemoteJson` end-to-end, `scheduled_time` mapper round-trip, `scheduled_time` null/malformed fallback), same 8 pre-existing golden-image diffs, zero regressions — confirmed by directly re-running the full suite, not assumed from a stale count.

### Phase H — Finding updates

| Finding | Status | Notes |
|---|---|---|
| `W0-003` | **VERIFIED_CLOSED** | Status-enum mapping fixed and validated end-to-end (all 3 real statuses + unknown-value handling) against the live-schema-derived isolated environment using the real repository code |
| `W0-004` (**new**) | **VERIFIED_CLOSED** | `scheduled_time` type mismatch — a second, independently-blocking bug found via required Phase D validation, fixed (including a timezone-neutral encoding correction caught by its own test), and validated the same way |
| `W0-001` | **VERIFIED_CLOSED** | Table-name fix confirmed in place; the specific live-remote-round-trip test its own closure criteria required has now been run and passed, evidenced above |

**All other findings preserved exactly as they stood, per instruction — none re-touched or re-assessed:** `W0-002` (`DEFERRED`), `W1-001` (`OPEN`), `SEC-001`/`ROOT-002` (`OPEN`), Fiqh Search-grounding degradation (`B — DEGRADED`), `RR-001` (`PARTIALLY_REMEDIATED`), `PJ-006` (`OPEN`), `OB-006` (`PARTIALLY_REMEDIATED`), `BR-001`/`BR-002`/`BR-003`/`BR-005`/`BR-006` (as closed in §20), and every Release/Deployment finding from §19.

**No owner action required to close this specific defect** — it was fully fixable and fully validated at the application-code layer, with no schema/infrastructure/credential dependency. The only residual uncertainty is Phase E's real-production-data question, which cannot be resolved without production data access this session correctly did not seek.

---

## 22. Privacy / Compliance Remediation Wave (2026-09-05)

**No production DB schema/migration/RLS/trigger/function/index/constraint change occurred. `W0-002`/`W1-001` not implemented.** All fixes are application-layer. **Legal/compliance boundary honored throughout**: this section states technical facts about what the app does, not legal conclusions about what law requires — no retention period, jurisdictional requirement, or compliance guarantee is invented anywhere below.

**Findings explicitly preserved, unchanged unless stated otherwise below:** `W0-002` (`DEFERRED`), `W1-001` (`OPEN`), `SEC-001`/`ROOT-002` (`OPEN`), Fiqh Search-grounding degradation (`B — DEGRADED`), `RR-001` (`PARTIALLY_REMEDIATED`), `PJ-006` (`OPEN`), `BR-001`/production-data recoverability (`OPEN`, no live re-check performed this wave either — same CLI blocker), `RD-009` (`OPEN`), `DC-010` (`OPEN`), `OB-006` (`PARTIALLY_REMEDIATED`, still not release-verified).

### Phase A — Data inventory (evidence-based, from current code)

| Category | Collected | Local storage | Transmitted to | Remote storage | Deletion on account delete |
|---|---|---|---|---|---|
| Account/profile | email/phone, display name, madhhab | No | Supabase | `public.users`, `public.profiles` | ✅ CASCADE |
| Cycle/haid | date, flow, symptoms, notes | SharedPreferences (plaintext) | Supabase | `cycle_entries` | ✅ CASCADE |
| Pregnancy profile | tracking basis, dates, week, risk flags | No | Supabase; **minimal derived subset** to Gemini via `dr-niswah-chat` | `pregnancy_profile` | ✅ CASCADE |
| Pregnancy milestones | — | SharedPreferences | Blocked (`W0-002`) | `pregnancy_records` (name/shape mismatch) | ✅ CASCADE (row exists but is functionally unreachable) |
| Prayer | prayer name, status, date | SharedPreferences (plaintext) | Supabase | `prayer_log` | ✅ CASCADE |
| Dr. Niswah chat | message text | No | Supabase, then Gemini (server-side only) | `chat_threads`, `chat_messages`, `flagged_conversations` | ✅ CASCADE |
| Fiqh Advisor chat | question text, madhhab | No | Supabase (Gemini call server-side, no DB read of health data) | Not persisted server-side beyond the request itself (confirmed: `fiqh-advisor-chat` has no `chat_messages`/table write) | N/A |
| Dream Interpreter chat | transcript text | No | Supabase, then Gemini | Client-persisted via its own repository (confirmed) | ✅ CASCADE (`dream_entries`, `auth.users` FK) |
| General AI assistant | message text | No | Supabase, then Gemini | Not persisted server-side (no DB write found in `ai-assistant-chat`) | N/A |
| Community | posts, comments, anonymity flag | No | Supabase | `community_posts`, `community_comments`, `community_likes` | ✅ CASCADE (see note below — collateral deletion) |
| Notifications/preferences | schedule/preference flags | SharedPreferences | No (local-only, matching `RR-001`'s prior classification) | N/A | N/A (local, cleared on uninstall only) |
| Device/local storage | see Phase H | — | — | — | — |
| Supabase | see Phase J | — | — | — | — |
| Gemini/Google | see Phase F/J | — | — | — | — |
| Sentry | see Phase G/J | — | — | — | — |

**Additional third-party SDKs found and assessed:** `geolocator` (device GPS, used only to compute local prayer times, confirmed **never transmitted** — `PrayerLocationController` only ever writes to `SharedPreferences`, never to Supabase); `adhan_dart` (local prayer-time math, no network); `pdf`/`printing` (local report generation, no network). No analytics/advertising SDK found anywhere in `pubspec.yaml` — confirmed, not assumed.

**New evidence this wave, not previously documented:** deleting your account cascades away not just your own community posts, but every *other* user's comments/likes on those posts too (`community_comments_post_id_fkey`/`community_likes_post_id_fkey` are `ON DELETE CASCADE` from `community_posts`, which itself cascades from the author's `users` row) — the same "collateral deletion of another person's content" pattern `DI-012` already documented for private conversations, now confirmed to also apply to public community content. Not registered as a new finding (it's the same underlying pattern as `DI-012`, not a distinct defect) — noted here as inventory evidence.

### Phase B — Consent/signup: FIXED

**Before:** the consent checkbox (`_agreed` in `sign_in_screen.dart`) was read by nothing. Email, phone, and Google sign-up all called Supabase auth directly regardless of its state — confirmed by reading every call site, not inferred. The "Privacy Policy"/"Terms of Use" text spans had no `recognizer` at all — not a broken link, no link.

**After:** `_agreed` state lifted from `_SignInContent` to `_SignInScreenState` (the component that actually performs auth calls) and now gates all three entry points uniformly via `_requireConsent()` — matching the UI's own layout intent (the checkbox sits above all three, not just the email/phone path). An unchecked box shows a clear, bilingual error and the flow stops before any Supabase call. The "Privacy Policy"/"Terms of Use" spans now carry a real `TapGestureRecognizer` opening the new in-app `PrivacyPolicyScreen`.

- No account creation without consent: confirmed via a real widget test tapping the actual Email/Mobile buttons.
- No decorative checkbox: it now has a functional consequence, confirmed.
- No hidden pre-checked consent: `_agreed` still defaults to `false`.
- Consent survives UI rebuild within the same screen instance (it's `State` on `_SignInScreenState`, not re-initialized per sub-widget rebuild) — not persisted across a full screen re-mount, since re-consenting per session-entry is the correct behavior for a fresh sign-in attempt, not a regression.
- Error messaging: clear, bilingual, confirmed via widget test.
- **Durable proof-of-consent record: not implemented, registered as a gap, not invented.** Supabase Auth's `user_metadata` (settable at signup via `data: {...}`) could technically record a timestamped consent flag without a schema migration — assessed but **not used this pass**: wiring it correctly (setting it atomically with signup across all three entry paths: email, phone, Google) is a real, non-trivial change to `AuthRepositoryImpl`'s three separate sign-up methods, and untested speculative persistence-schema work was judged lower priority than the gating fix itself within this wave's time budget. **Documented as the concrete next step, not attempted.**

### Phase C — Privacy policy: reachable and usable, hosting gap flagged

New `PrivacyPolicyScreen` (`lib/features/legal/presentation/screens/privacy_policy_screen.dart`) — factual, bilingual, derived directly from Phase A's inventory (not a template, not fabricated legal language). Reachable from: (1) the sign-up consent checkbox's own link, (2) Profile → Privacy Settings → Privacy Policy (new row). No dead/placeholder URL anywhere — it's an in-app screen, not a link to external hosting, so there is no URL to go stale.

**Not marked fully closed**: app-store submission forms (Google Play, Apple App Store Connect) require a **publicly-hosted, externally-linkable URL** for their privacy-policy field — an in-app screen alone cannot satisfy that specific external requirement. **Registered as `OWNER_BLOCKED`**: publishing this content (or an equivalent) to a real public URL requires hosting infrastructure/domain access this session doesn't have. The content itself is ready to publish as-is.

### Phase D — Account deletion: implemented and validated end-to-end

**Before:** `delete_my_account()` existed and worked correctly server-side (repeatedly proven across this entire engagement) but **no client code ever called it** — confirmed again this wave via a fresh repository-wide search.

**After:** `AuthRepository.deleteAccount()`/`AuthRepositoryImpl.deleteAccount()` (new) call the RPC, then explicitly `signOut()` locally — **a real bug caught before it shipped**: the RPC deletes `auth.users` server-side but does **not** by itself clear the client's local session or fire Supabase's auth-state-change stream, which is what `AuthController` needs to reactively return the app to the sign-in screen. Without the explicit local `signOut()`, the app would have kept behaving as authenticated until some unrelated request happened to fail. Wired into `profile_screen.dart`: a destructive-action confirmation `AlertDialog` (explicit Cancel/Delete, no accidental one-tap deletion), a loading state (`_isDeletingAccount`, button disabled + spinner), accurate error messaging on failure (no false success — the success path only navigates away after `deleteAccount()` genuinely returns without throwing), and navigation to `SignInScreen` with the entire navigation stack cleared (`pushAndRemoveUntil`) on success.

**Validated end-to-end against a live-schema-derived isolated environment** (real `AuthRepositoryImpl`, real RPC, real local Supabase Auth): after `deleteAccount()`, `client.auth.currentSession`/`currentUser` are both `null` (session genuinely cleared, not just server-side deletion assumed to imply it), and a subsequent `signInWithPassword` with the same credentials fails with `invalid_credentials` — the account is genuinely gone, not merely logged out.

The existing RPC/backend deletion mechanism was not modified or weakened — this wave only wires an existing, already-correct backend capability into the client for the first time.

### Phase E — User data access/export: implemented (partial, stated plainly)

**Before:** "Data Export" produced only 4 curated PDF reports (Fiqh log, Doctor's Report, Wellbeing, Husband Report) — not the user's actual raw records (`PC-006`).

**After:** new `DataExportScreen` (`lib/features/legal/presentation/screens/data_export_screen.dart`), reachable from Profile → Data Export → "Export My Data (JSON)". Fetches the authenticated user's own rows — `users`, `profiles`, `pregnancy_profile`, `cycle_entries`, `prayer_log`, `community_posts`, `chat_threads`, `chat_messages` — assembles them into indented, human-readable JSON, and offers a copy-to-clipboard action (no new dependency; `Clipboard` is part of the Flutter SDK already in use elsewhere in this codebase). Authenticated-user-only and own-data-only is enforced by **RLS itself**, not application logic — verified directly this wave: a second synthetic user querying the same table for the first user's `user_id` received zero rows, confirmed against a real isolated Postgres instance, not asserted from reading policy SQL alone.

**Explicitly partial, not claimed complete**: does not include `pregnancy_records`/milestones (blocked by the same `W0-002` mismatch, correctly not worked around here), does not include `flagged_conversations` (a service-role-only internal safety-audit log with no user-facing RLS read policy — not user-owned content to begin with, and deliberately excluded rather than attempting a service-role bypass), and is not a polished file-download/share-sheet flow — a plain in-app JSON view with clipboard copy is the smallest safe capability implementable without a new dependency or backend change. The screen's own UI text states this scope honestly to the user, not just in this report.

### Phase F — Gemini data minimization: audited, already well-implemented — no code change needed

Read all four Edge Functions' actual Gemini call construction, not assumed from the client side alone:

- **`dr-niswah-chat`** (the only one of the four that reads any health/profile data): `loadPregnancyProfile()` selects an explicit, narrow column list (not `select('*')`); `buildContextBlock()` sends only **derived** values (pregnancy mode, week/trimester/month/weeks-to-due, fasting status, high-risk flags, locale) — the underlying raw dates (`reference_date`, `manual_week_set_at`, `postpartum_start_date`) are loaded but **never included** in what's sent to Gemini. No prior chat history is sent — each call is single-turn. No auth tokens, no internal database IDs beyond what's functionally required (the client only sends `threadId` + message `content`).
- **`fiqh-advisor-chat`**: only the user's typed question + their chosen madhhab — no database read of any health/profile data at all.
- **`dream-interpreter-chat`**: a static system prompt + the client-built transcript prompt — no server-side profile lookup.
- **`ai-assistant-chat`**: a static system prompt + message content — no server-side profile lookup.

**Conclusion, stated honestly**: this area was already minimized before this wave — no unnecessary field was found to remove. `PC-003`'s underlying concern (health/pregnancy context does reach Gemini) remains factually true for `dr-niswah-chat` specifically, but the *minimization* half of this phase's mandate is already satisfied; `PC-003`'s actual defect is disclosure (Phase C's new privacy policy now names Google/Gemini explicitly as a processor and describes what's sent, closing the disclosure gap that finding also raised).

### Phase G — Sentry/logging privacy: one real gap found and fixed, rest confirmed clean

Searched the full `lib/` tree and all four Edge Functions for `print(`, `debugPrint(`, `console.log`/`console.error`, and every `AppErrorReporter.report()` call site's `recordId` argument.

- **`cycle_log_repository.dart`'s 8 `print()` calls**: unchanged — this file is confirmed dead code (zero callers, per `CQ-003`/`CQ-009`'s prior disposition), so its actual production-log exposure is nil; deletion (not logging-pattern fixes) remains the correct closure path per that finding's own existing recommendation, not duplicated here.
- **`dream_interpreter_view_model.dart:171`**: **fixed** — a raw `debugPrint('[DreamInterpreter] saveEntry failed: $error')` replaced with a proper `AppErrorReporter.report()` call (opaque `entryId` only, matching this app's established contract), making this failure actually observable via Sentry for the first time instead of lost in debug-only, release-invisible console output.
- **Every `AppErrorReporter.report()` `recordId:` argument app-wide**: swept via `grep`; confirmed every one is a plain `.id` reference, never a full object or raw content.
- **All Edge Function `console.error` calls** (10 across 4 functions): confirmed each logs only `userId`/`threadId` (opaque UUIDs, functionally required for correlation), booleans, and `error.message` (diagnostic text from a write/API failure — never the user's actual message content, chat text, or health-record values, since none of these catch blocks are positioned where content would be echoed back).
- **Sentry's `beforeSend` scrub** (`scrubSecretsForSentry`, added in the earlier OB-006 wave): unchanged, still unit-tested against Bearer-token and JWT-shaped patterns — re-confirmed present, not re-verified via a new live send (already proven working end-to-end in `00_09` §18/§19).

**No sensitive user content (health data, chat text, credentials) found reaching any log path this wave** — one real, now-fixed exception (`dream_interpreter_view_model.dart`), everything else confirmed already correct.

### Phase H — Local device storage: assessed, real risk identified, migration deliberately NOT performed

**Inventory**: `SharedPreferences` is the only local persistence mechanism found (`grep`-confirmed across `lib/`) — no `sqflite`, no Hive, no custom file-based storage, no existing secure-storage dependency. Used by: cycle entries, pregnancy-tracking (blocked/`W0-002`), prayer log, TTC mode, madhhab, marital status, prayer location (raw GPS coordinates), theme, locale, notification log, wellbeing data.

**Assessment**: `SharedPreferences` (Android XML / iOS plist) is **not encrypted at the application layer** on either platform by default — readable in cleartext by anyone with filesystem access to the app's private storage (a rooted/jailbroken device, or a local backup extraction). This is a real, currently-true gap for genuinely sensitive categories — cycle/haid data (reveals menstrual/reproductive health status) and prayer data (reveals religious practice) are the two highest-sensitivity categories stored this way.

**Mitigating, already in place**: `android:allowBackup="false"` (added in the Release Engineering wave) prevents this data from being swept into Android's automatic cloud backup — a real, if partial, mitigation already credited to that wave, not re-claimed here.

**Migration deliberately NOT performed this wave** — per the explicit instruction not to silently change storage for a destructive/risky operation. A real migration to `flutter_secure_storage` (OS Keychain/Keystore-backed) would require: (1) a new dependency; (2) a one-time migration routine on first launch post-upgrade that reads every existing `SharedPreferences` key, writes it to secure storage, verifies the write, and only then deletes the plaintext copy (get this wrong and data is lost, not just insecure — exactly the "destructive/risky" case the instructions name); (3) testing across every one of the ~10 affected data-source files. This is real, substantial, cross-cutting work appropriately out of a single wave's safe scope — **registered as a precise remediation design, finding preserved `OPEN`, not silently attempted.**

### Phase I — Retention: documented from code/schema, no duration invented

| Category | Created | Auto-deleted? | Removed on account deletion? | Orphans possible? |
|---|---|---|---|---|
| Account/profile, cycle, pregnancy, prayer, chat, community, dream | On first use | No | **Yes** — `ON DELETE CASCADE` confirmed for every relevant FK, re-verified this wave via the full constraint list in the live schema capture | No — cascade is exhaustive; even a deleted user's *own* content that other users had commented on/liked cascades away too (see Phase A note) |
| `flagged_conversations` (safety audit log) | On a red-flag chat exchange | No | **Yes** — `flagged_conversations_user_id_fkey ON DELETE CASCADE` | No |
| Local device data | On first use | No (persists until app data is cleared/uninstalled) | **No** — local `SharedPreferences` is not cleared on account deletion or sign-out today (confirmed: neither `signOut()` nor `deleteAccount()` touch any local data source) | N/A (device-local, not a server-side orphan) |

**No retention *duration* is defined anywhere in code, schema, or any document — confirmed, not invented.** `PC-007`'s finding is accurate and unchanged: indefinite retention exists for every category with no product/legal policy setting a maximum. **New, related observation this wave**: local device data specifically survives BOTH sign-out and account deletion — a user who deletes their account still has their cycle/prayer history sitting in `SharedPreferences` on that device afterward. Not previously called out this precisely; recorded as an addendum to `PC-007` rather than a new finding, since it's the same "no retention policy" root cause applied to a location (local storage) the original finding's GPS-specific framing didn't explicitly cover.

### Phase J — Third-party processor inventory

| Processor | Data categories | Purpose | Path | Sensitive? | Controls |
|---|---|---|---|---|---|
| Supabase | Account, cycle, pregnancy, prayer, chat, community data; auth credentials | Backend database, authentication, Edge Functions | Client ↔ Supabase (direct, RLS-enforced) and server-side (Edge Functions) | Yes — the majority of all app data | RLS on all 24 tables (confirmed); no service-role key in the client (confirmed, `SEC-001`'s prior client-artifact verification) |
| Google (Gemini API) | Message text (all 4 AI features); minimal derived pregnancy context (`dr-niswah-chat` only) | Generates AI replies | Server-side only (Supabase Edge Functions) — never client-to-Google directly (`ROOT-002`'s prior closure) | Yes, for `dr-niswah-chat` specifically | Server-side-only call path; minimized context (Phase F) |
| Sentry | Error type, opaque record IDs, environment/version, exception message text (scrubbed) | Crash/error monitoring | Client → Sentry (native SDK) | No — explicitly excludes health/chat content by design (Phase G) | `beforeSend` scrub, `AppErrorReporter`'s ID-only contract |

**No other third-party SDK or service found** — `geolocator`/`adhan_dart`/`pdf`/`printing` are all local-only, confirmed in Phase A. No contractual/legal guarantee about any of these three processors is stated here — this is a technical description of what data flows where, not a DPA/subprocessor-terms assessment (that remains `PC-008`, unchanged, legal/contractual review, not resolvable by this session).

### Phase K — Google Play Data Safety / Apple App Privacy technical inventory

Technical answers only, based on actual implementation — not submitted anywhere, not a legal/policy-form filing.

| Data type | Collected | Shared with 3rd party | Purpose | Required/Optional | Linked to identity | User can request deletion | Encrypted in transit |
|---|---|---|---|---|---|---|---|
| Email/phone | Yes | No (Supabase is a processor, not a data-sharing partner in the Play/Apple sense — **flag for owner interpretation**, this session cannot make that legal distinction) | Account creation/auth | Required | Yes | Yes (`deleteAccount`, now implemented) | Yes (HTTPS, Supabase-managed) |
| Health info (cycle/haid) | Yes | Yes — to Google Gemini, `dr-niswah-chat` only, as minimized derived context | Core app function (AI health guidance) | Required for that feature | Yes | Yes | Yes |
| Health info (pregnancy) | Yes | Yes — same as above | Core app function | Required for that feature | Yes | Yes | Yes |
| Location (precise) | Yes, permission-gated | No — confirmed local-only, never transmitted | Local prayer-time calculation | Optional (feature degrades to a default location without it) | No — never leaves the device, so not identity-linked server-side | N/A (never stored remotely) | N/A (never transmitted) |
| Messages (AI chat) | Yes | Yes — to Google Gemini (all 4 features) | Core app function | Required for that feature | Yes | Yes | Yes |
| User content (community posts) | Yes | No | Social feature | Optional | Yes, unless posted anonymously (`is_anonymous`) | Yes | Yes |
| App activity / diagnostics | Yes (error reports) | Yes — to Sentry | Debugging | N/A (not user-facing data collection in the Play/Apple sense) | No — opaque IDs only, no PII (Phase G) | N/A | Yes |

**Flagged for owner/legal interpretation, not guessed**: whether Gemini/Sentry count as "sharing" vs. "processing on our behalf" under Play/Apple's specific taxonomies is a policy-form judgment call, not a technical fact this session can settle. The table above states the underlying technical reality only.

### Phase L — User-journey validation

| # | Journey | Result |
|---|---|---|
| 1 | Signup without required consent | ✅ PASS — blocked, confirmed via widget test tapping the real Email/Mobile buttons |
| 2 | Signup with required consent | ✅ PASS — gating error absent, sheet genuinely opens, confirmed via widget test |
| 3 | Open privacy policy | ✅ PASS — reachable via the now-tappable link (confirmed: real `TapGestureRecognizer` present, verified via widget test) and via Profile → Privacy Settings |
| 4 | Update pregnancy/profile data | Not independently re-run this wave — already covered by this engagement's own prior evidence (Backup/Recovery wave's Phase E, `pregnancy_profile` write test) and unrelated to anything changed this wave |
| 5 | Use AI health feature (minimal context) | ✅ Confirmed via code audit (Phase F) — no runtime re-call needed given the exact server-side code was read directly |
| 6 | Export user data | ✅ PASS — RLS-scoped fetch confirmed against a real isolated Postgres instance: a second user querying the first user's data received zero rows |
| 7 | Delete account (full chain) | ✅ PASS — confirmation dialog implemented; `deleteAccount()` validated end-to-end against the isolated stack: session cleared (`currentUser`/`currentSession` both `null`), re-login fails with `invalid_credentials` |
| 8 | Controlled handled error → Sentry payload clean | Not re-sent to a real Sentry project this wave (would require repeating the extensive, already-completed verification from `00_09` §18/§19) — the redaction logic (`scrubSecretsForSentry`) and the `AppErrorReporter` ID-only contract were both re-confirmed unchanged and correct via code review + existing unit tests, not re-proven via a new live send |

All synthetic accounts created this wave were disposable local-stack accounts, cleaned up by tearing down the isolated environment entirely (`supabase stop --no-backup`, Docker volume removed) — no production signup was attempted, honoring the instruction to use the safest available infrastructure given this engagement's repeated production email-confirmation friction.

### Phase M — Security/API/Database/Observability/Final User Journey cross-check

- **`PC-002`'s closure directly informs `DI-012`** (already on record) — no new security implication; the deletion mechanism itself was not modified, only exposed client-side.
- **`SEC-001`/`ROOT-002`**: unaffected — this wave touched no Gemini key/rotation logic.
- **`AB-010`/`OB-007`**: `DataExportScreen`'s error handling uses `AppErrorReporter` directly (not the `mapRepositoryError` classifier, since export failures aren't retried) — consistent with this codebase's existing pattern of not forcing every code path into one shared abstraction, per this engagement's own established precedent.
- **No Security, API/Backend, Database, Observability, or Final User Journey finding is closed, reopened, or reclassified by this wave** — privacy behavior improved without any security control being loosened (RLS unchanged, no new attack surface: `DataExportScreen`/`deleteAccount()` both operate strictly within the caller's own existing RLS-scoped permissions, no new endpoint, no new privilege).

### Testing (this wave)

`dart analyze lib/`: 27 pre-existing issues, zero new. `flutter test`: **289/297** — the prior baseline (285/293) plus 4 new widget tests in `test/sign_in_consent_gating_test.dart` (consent blocks Email, consent blocks Mobile, consent-then-Email opens the real sheet, the Privacy Policy link is genuinely tappable), same 8 pre-existing golden-image diffs, zero regressions — directly re-run and confirmed, not assumed from the stated prior baseline. Two additional isolated-stack tests (account-deletion session-clearing + re-login-fails, RLS-scoped export cross-user check) were run manually against a live-schema-derived environment and then deleted, matching this engagement's established precedent for infrastructure-dependent verification.

### Phase O — Finding closure

| Finding | Status | Notes |
|---|---|---|
| `PC-001` | **VERIFIED_CLOSED** | Consent now genuinely gates all three sign-up entry points; validated via real widget interaction, not just code review |
| `PC-002` | **VERIFIED_CLOSED** | Account deletion fully wired, confirmation dialog, session-clearing bug caught and fixed, validated end-to-end against an isolated environment |
| `PC-003` | **PARTIALLY_REMEDIATED** | Minimization already good (Phase F, no code change needed); disclosure gap closed by the new privacy policy naming Google/Gemini explicitly |
| `PC-004` | **PARTIALLY_REMEDIATED** | In-app reachability fully solved (no dead/placeholder link — genuinely tappable, confirmed); public hosting for app-store submission is `OWNER_BLOCKED` |
| `PC-005` | **OPEN**, unchanged | Not addressed this wave — the "Privacy Settings" section still primarily contains the anonymity toggle; a genuine relabeling/redesign was judged out of this wave's scope (the section now also contains a real Privacy Policy link, a partial improvement, but the underlying mismatch this finding describes isn't fully resolved) |
| `PC-006` | **PARTIALLY_REMEDIATED** | A real, working, RLS-verified raw-data export now exists alongside the 4 PDF reports; explicitly partial (excludes `W0-002`-blocked data and the internal safety log by design) |
| `PC-007` | **OPEN**, unchanged, with a new addendum | No retention duration exists anywhere (not invented here either); new observation that local device data also survives account deletion, recorded as part of the same underlying gap |
| `PC-008` | **OPEN**, unchanged | Explicitly legal/contractual (DPA/subprocessor terms) — outside this session's boundary by the operator's own instruction |
| `PC-009` | **OPEN**, unchanged | No age-gate mechanism found or added — out of this wave's scope, not attempted |

**RD-007** (duplicate manifestation of `PC-004`, no privacy-policy link wired): **PARTIALLY_REMEDIATED**, same basis as `PC-004` — the in-app link now exists and works; the public-URL requirement remains `OWNER_BLOCKED`.

**Owner actions required**: (1) publish the privacy policy content (already drafted, factual, ready as-is) to a real public URL for Google Play/Apple App Store submission forms; (2) decide on a durable proof-of-consent record design (Supabase Auth `user_metadata` was assessed as viable without a schema migration, not implemented) if one is legally required; (3) fund/schedule the local-storage encryption migration design from Phase H — real, cross-cutting work, deliberately not attempted this wave; (4) resolve `PC-008` (DPA/subprocessor terms) and `PC-009` (age-gate) as legal/product decisions; (5) decide whether local device data should be cleared on account deletion (currently it is not).

---

## 23. Local Sensitive Storage + Account Deletion Cleanup (2026-09-05)

**No production DB schema/migration/RLS/trigger/function change occurred.** `W0-002`/`W1-001` not implemented. No legal retention period invented. This wave implements exactly what §22 Phase H registered as a precise, deliberately-deferred design: encrypting local cycle/prayer/pregnancy data and clearing it on account deletion.

**Findings explicitly preserved, unchanged unless stated otherwise below:** `W0-002` (`DEFERRED`), `W1-001` (`OPEN`), `SEC-001`/`ROOT-002` (`OPEN`), Fiqh Search-grounding degradation (`B — DEGRADED`), `RR-001` (`PARTIALLY_REMEDIATED`), `PJ-006` (`OPEN`), `BR-001` (`OPEN`), `RD-009` (`OPEN`), `DC-010` (`OPEN`), `OB-006` (`PARTIALLY_REMEDIATED`), `PC-005`/`PC-008`/`PC-009` (`OPEN`).

### Phase A — Local storage inventory (re-derived from current code, not assumed from §22)

`grep`-confirmed 16 files use `SharedPreferences` directly. Three carry actual sensitive health-record content with a fixed, **globally-shared, unscoped** cache key — a real, previously-undocumented defect discovered this wave (see below), not just the "unencrypted" gap §22 Phase H already flagged:

| Data source | Key (pre-wave) | Sensitivity | Pre-wave mechanism | User-scoped? | Migration needed |
|---|---|---|---|---|---|
| `LocalCycleTrackingDataSource` | `niswah_cycle_tracking_logs` | High (menstrual/reproductive health) | Plaintext SharedPreferences | **No** — global key, zero filtering anywhere in `CycleTrackingRepositoryImpl.getCycleLogs()` | Yes |
| `LocalPrayerTrackingDataSource` | `niswah_prayer_tracking_logs` | Medium-high (religious practice) | Plaintext SharedPreferences | **No** at storage layer — `PrayerTrackingRepositoryImpl` applied a fragile client-side `entry.userId == userId` filter as partial mitigation, but the underlying cache itself was shared | Yes |
| `LocalPregnancyTrackingDataSource` | `niswah_pregnancy_tracking_milestones` | High | Plaintext SharedPreferences | **No** — same pattern as cycle tracking, zero filtering | Yes |

**New finding this wave, not previously documented anywhere in this engagement — `PC-010` (new): cross-user local data leak.** All three caches used a fixed global string key with no per-user scoping. On a shared/handed-down device, a second person signing in after the first signs out could read the first person's cached cycle/prayer/pregnancy data — cycle tracking had **zero** filtering at any layer (worst case); prayer tracking had a partial, fragile client-side filter; pregnancy tracking had zero filtering. This is distinct from and more severe than §22 Phase H's "unencrypted at rest" finding — encryption alone would not have fixed this, since the leak was about key scoping, not ciphertext. See Phase G below for the fix and its mandatory validating test.

**Lower-sensitivity SharedPreferences keys explicitly out of this wave's scope** (preference-level state, not health records, and already low-severity even where unscoped): `app_theme_controller.dart`, `app_locale_controller.dart`, `madhhab_controller.dart`, `marital_status_controller.dart`, `ttc_mode_controller.dart`, `notification_log_controller.dart`. Encrypting/rescoping every key in the app was judged to exceed "no unnecessary architectural rewrite" for state that reveals materially less than health records.

**`prayer_location_controller.dart` (raw GPS coordinates) — explicitly evaluated, deliberately deferred.** Genuinely sensitive (precise location), but §22 Phase A already confirmed it is never transmitted anywhere and cross-references it to `PC-007`'s retention finding, not a fresh discovery this wave. Bringing it into the same encrypted/user-scoped architecture would be a reasonable follow-up but was judged secondary to the three explicitly-named health-record categories within this wave's scope; not touched, not silently left worse than before (still local-only, still never transmitted, still not user-scoped — flagged as a residual gap, not fixed here).

**AI/chat local caches (`dr_niswah_chat_screen.dart`, `dream_interpreter_screen.dart`) — checked, found already safe.** Both cache only a boolean "has history?" hint (`chat_has_history_<userId>_<threadType>`), not message/transcript content (chat content is server-side per `chat_threads`/`chat_messages`, confirmed in §22 Phase A) — and that key is **already** user-scoped (`_currentUserId()` is embedded in the key), so it does not exhibit the cross-user leak found in the three health-data sources. Not wired into account-deletion cleanup this wave: a stale boolean under a deleted user's id reveals nothing beyond "this id once had chat history," and since Supabase user ids are never reused, no future user can ever collide with it. Recorded here explicitly per Phase F's requirement to state this distinction, not silently omitted.

### Phase B — Storage architecture: `flutter_secure_storage`, user-scoped internally

**Decision**: `flutter_secure_storage` (`^11.0.0`, new dependency) — Android Keystore-backed / iOS Keychain-backed, platform-managed key material, no custom crypto, no key ever stored beside its ciphertext. Chosen over an encrypted local database (sqflite+SQLCipher, Isar, Drift) because the actual data volumes are small (a health-tracking app's local cache is at most low-hundreds of JSON-encoded records per user, not a dataset needing indexed queries) and the app is local-first-with-remote-sync — Supabase remains the queryable source of truth; the local cache only needs simple whole-blob key/value read-modify-write, which is exactly `flutter_secure_storage`'s access pattern. Introducing an embedded encrypted database would have been real, unjustified architectural expansion for the data actually involved.

**User scoping**: rather than threading a `userId` parameter through every data-source method signature, repository interface, and call site (a large, risky ripple-effect refactor), each key is scoped by a user id resolved **internally** by `SecureLocalStore.currentUserId()` (`lib/core/storage/secure_local_store.dart`): `NiswahSupabase.clientOrNull?.auth.currentUser?.id`, falling back to a stable `'__no_session__'` sentinel. Every stored key becomes `'<category>__<userId>'`. This structurally eliminates the cross-user leak — a different signed-in user simply resolves a different key — without changing any existing public method signature.

### Phase C — Migration design: 7-step, non-destructive, idempotent

`SecureLocalStore.migrateLegacyIfNeeded()`: detect legacy plaintext (`SharedPreferences.getString(legacyKey)`) → validate/deserialize it (caller-supplied `isValid` — decodes and confirms it's a JSON `List`) → write it to secure storage → read it back → verify semantic equality (exact string equality — no transformation occurs during migration, so this is a valid equality check, not an approximation) → only then remove the plaintext copy. On any failure (invalid legacy JSON, a write that doesn't read back identically): the plaintext copy is left untouched, a partial secure-storage write is explicitly rolled back (so a retry doesn't wrongly see "already migrated"), and the failure is reported via `AppErrorReporter` — never thrown, so a migration failure can never crash app startup. Idempotent by construction: the first check is "does secure storage already have this category populated?" — if yes, the function returns immediately, so re-running never duplicates, re-corrupts, or re-migrates.

Each of the three data sources calls this at the top of every read/write operation (not cached across calls — an earlier draft cached the resulting `Future` in a static field per class, but since `migrateLegacyIfNeeded` is already idempotent via its own internal check, the cache bought nothing except an un-resettable-within-a-running-session state that actively broke test isolation; removed in favor of the simpler, always-idempotent call).

### Phase D — Cycle storage: migrated

`LocalCycleTrackingDataSource` (`lib/features/cycle_tracking/data/datasources/local_cycle_tracking_data_source.dart`) — all public method signatures unchanged (`loadLogs`, `getById`, `upsert`, `delete`); internals now route through `SecureLocalStore`. The local-authoritative-with-remote-sync model, `SyncStatus` (`pending`/`synced`/`failed`), and `CycleTrackingRepositoryImpl`'s existing merge/retry logic are all untouched — this wave only changed *where* the local half physically lives, not the sync architecture. Verified via test: existing (legacy) cycle logs, including a mix of `pending` and `synced` entries, survive migration and remain fully readable, with sync status preserved exactly (`secure_local_store_test.dart`).

### Phase E — Prayer storage: migrated

`LocalPrayerTrackingDataSource` — same pattern. The `W0-001`/`W0-003`/`W0-004` remote-boundary status/scheduled-time mapping (`prayerStatusToDbValue`/`prayerStatusFromDbValue`, timezone-neutral `scheduled_time` encoding) lives entirely in `PrayerTrackingRepositoryImpl`'s remote calls, untouched by this wave — this wave only touched the local cache underneath it. Verified via test: legacy prayer entries across multiple statuses survive migration and remain readable with status intact.

### Phase F — Account deletion device cleanup: implemented

New `lib/core/storage/local_sensitive_data_cleanup.dart` defines the registered cleanup categories (cycle, prayer, pregnancy) and two entry points: `cleanUpLocalSensitiveDataForDeletedAccount(userId)` (called from `AuthRepositoryImpl.deleteAccount()`) and `retryPendingLocalSensitiveDataCleanups()` (called once at app startup, `main.dart`, `unawaited`).

**Sequence** (`AuthRepositoryImpl.deleteAccount()`, `lib/features/auth/data/repositories/auth_repository_impl.dart`): the signed-in user's id is captured *before* the RPC call → `delete_my_account()` RPC succeeds server-side → local sensitive-data cleanup runs (per-category, each independently try/caught — one category's failure does not block the others or the overall flow) → local `signOut()` clears the auth session (as it did before this wave; the session-clearing bug this repaired was §22's, not new here). A cleanup failure is reported via `AppErrorReporter`, not silently treated as success, and the failed-but-not-yet-cleaned user id is recorded in a small `SharedPreferences` pending list (opaque ids only — this list is not itself the sensitive data being protected) so the next app start retries it via `retryPendingLocalSensitiveDataCleanups()`. No session is recreated by any of this — cleanup and its retry operate purely on-device against a user id string, never re-authenticating.

**Deliberately not cleared**: language/theme/onboarding-state and other app-global, non-user-specific preferences — these are correctly excluded per the charter's own instruction, and are the same "lower-sensitivity, out of scope" keys listed in Phase A.

Verified via test: after `cleanUpLocalSensitiveDataForDeletedAccount(userId)`, both cycle and prayer local data for that user are gone; a simulated partial failure (one category throws) is reported via `AppErrorReporter` rather than silently swallowed (`secure_local_store_test.dart`).

### Phase G — Logout semantics + cross-user isolation: fixed, mandatory test passing

Sign-out (`AuthRepositoryImpl.signOut()`) is unchanged by this wave — it clears the auth session only, and deliberately does **not** wipe local cycle/prayer/pregnancy history, matching current product behavior (a user who signs back in on the *same* account should see their history return without a re-sync). What this wave fixes is the defect Phase A discovered: **before this wave, that same local history was also visible to a *different* user** who signed in afterward on the same device, since the cache key was global. After this wave, every key is scoped by `SecureLocalStore.currentUserId()`, so a different signed-in user resolves an entirely different key — structurally, not by any explicit wipe-on-logout step.

**Mandatory test, passing**: User A writes local cycle data → (simulated) logout → User B signs in on the same device → User B's `loadLogs()` call returns empty, User A's own data remains fully intact and unaffected. Run twice — once for cycle tracking, once for prayer tracking (`secure_local_store_test.dart`, using a `@visibleForTesting` `SecureLocalStore.debugUserIdOverride` seam to simulate two distinct signed-in users without standing up a real second auth session).

### Phase H — Key/encryption failure behavior

- **Migration failure** (invalid/corrupted legacy JSON): Phase C's design — plaintext preserved, `AppErrorReporter` notified, no partial secure-storage state left behind. Tested directly.
- **Corrupted encrypted payload already present in secure storage** (independent of migration — e.g. a previously-written value that's since become unreadable as JSON): `SecureLocalStore.decodeJsonListSafely()` catches the decode failure, reports it via `AppErrorReporter`, and returns an empty list rather than throwing — the app degrades to "no local data for this category" instead of crashing. Tested directly.
- **A real regression was caught and fixed by this same testing pass, not shipped**: the first version of `decodeJsonListSafely<T>()` returned a bare `const []` for the no-data case. Inside a *generic* method, `const []` infers as `List<Never>` (Dart cannot parameterize a compile-time constant by a runtime type variable), not `List<T>` — which then threw a confusing `_TypeError` in any caller doing `.firstWhere(orElse: () => SomeEntity(...))` on the result (specifically `PrayerTrackingViewModel.statusFor`, reached from the dashboard's prayer-status card). This cascaded into 13 widget-test failures across dashboard/calendar/insights/today/responsive tests before being isolated and fixed (`<T>[]` instead of `const []`) — full regression suite re-run and confirmed clean afterward (see Testing below).
- **A second, unrelated regression was caught and fixed in the same pass**: several `parity_*_test.dart` files call the shared `ParityTestHarness.pump()` helper more than once per file, each time reseeding a fresh cycle/prayer fixture into `SharedPreferences`. `flutter_test_config.dart` (new, this wave) resets the `flutter_secure_storage` test double once per test *file* — correct for isolating one file's tests from another's, but too coarse for these multi-call-per-file tests, since a *later* call's freshly-seeded legacy data was being silently ignored (migration saw the *earlier* call's already-migrated secure-storage value and short-circuited). Fixed by resetting the secure-storage test double inside `ParityTestHarness.pump()` itself, at the same granularity `SharedPreferences.setMockInitialValues()` already resets at.
- **App restart mid-migration**: not independently live-tested (would require killing a real process mid-write), but the design is restart-safe by construction — every step before the final plaintext-removal leaves the plaintext copy fully intact, so an interrupted migration simply re-attempts from scratch on the next `loadLogs()`/`upsert()` call, which is itself idempotent.
- **Secure-storage write failure / key unavailable**: not independently simulated (would require a fault-injecting fake platform implementation beyond the package's own `TestFlutterSecureStoragePlatform`); the existing try/catch + `AppErrorReporter` reporting in `migrateLegacyIfNeeded` and the data sources' own callers already covers this class of failure structurally, but it is not evidenced by a dedicated test this wave — recorded as a gap, not claimed tested.

### Phase I — Backup interaction: documented, existing hardening unweakened

**Android**: `android:allowBackup="false"` / `fullBackupContent="false"` (`AndroidManifest.xml`, set in the Release Engineering wave, `00_09` §19) excludes **all** app data — `SharedPreferences` and the new `flutter_secure_storage`-backed EncryptedSharedPreferences file alike — from any OS-level backup mechanism. Confirmed present and unchanged this wave; nothing further is needed on Android given this setting, so no additional exclusion rules were added.

**iOS**: checked directly against the installed package's actual default option values (`flutter_secure_storage-11.0.0`), not assumed. The plugin's default `synchronizable: false` already prevents iCloud Keychain sync (no cross-device propagation via that path). The default `accessibility: unlocked` (`kSecAttrAccessibleWhenUnlocked`, no `ThisDeviceOnly` qualifier), however, **is** eligible to be included in an encrypted local iTunes/Finder backup and restored onto a *different* physical device. Since this data has no server-side copy to reconcile a restored value against and is meant to be strictly on-device, `SecureLocalStore` now explicitly sets `accessibility: KeychainAccessibility.unlocked_this_device` — the Keychain item will not restore onto a new device; on that new device it simply reads back as "no local data yet," which is the correct, safe outcome (the migration path would also just find no legacy `SharedPreferences` data on a fresh device and no-op cleanly). This is a real hardening added this wave, not merely documentation of pre-existing behavior.

### Phase J — Tests

11 new tests, `test/secure_local_store_test.dart`: plaintext→encrypted migration + semantic equality; migration idempotency; migration failure preserves original plaintext and reports via `AppErrorReporter`; a no-legacy-data no-op case; cycle data (incl. mixed pending/synced status) survives migration; prayer data (incl. multiple statuses) survives migration; a corrupted stored payload degrades safely and is reported; account-deletion cleanup removes cycle+prayer data; a partial cleanup failure is reported, not swallowed; cross-user isolation for cycle tracking (mandatory); cross-user isolation for prayer tracking. All 11 pass.

Additional test-infrastructure changes needed for these to run at all under `flutter_test` (`flutter_secure_storage` has no real platform channel in that environment): `test/flutter_test_config.dart` (new) installs the package's own first-party in-memory fake (`TestFlutterSecureStoragePlatform`, shipped inside `flutter_secure_storage`'s own `lib/test/` — not hand-written) once per test file; `test/support/secure_storage_test_support.dart` (new) exposes `resetSecureLocalStoreForTest()` for finer-grained per-test/per-call resets, used in `cycle_local_sync_idempotency_test.dart` (existing test, updated so its assertions keep passing against the new storage backend) and inside `ParityTestHarness.pump()` (Phase H).

`dart analyze lib/`: 27 pre-existing issues, zero new. `dart analyze test/`: zero issues. `flutter test`: **300/308** — the prior baseline (289/297) plus the 11 new tests above, **the same 8 pre-existing golden-image diffs, byte-for-byte identical to every prior baseline check this engagement** (`parity_community_test.dart` ×2, `parity_today_lower_test.dart` ×1, `parity_profile_test.dart` ×2, `parity_dashboard_test.dart` ×2, `parity_cycle_log_sheet_test.dart` ×1), zero regressions — directly re-run three times over the course of this wave (once revealing the 13-failure `const []`/generic-inference regression, once revealing the 3-failure test-harness-isolation regression, once confirming both fixes together restore the exact known baseline), not assumed from a single run.

### Phase K — Finding reassessment

| Finding | Status | Notes |
|---|---|---|
| `PC-007` addendum (local device data survives account deletion) | **VERIFIED_CLOSED** (addendum only — the core finding, no retention *duration* defined anywhere, remains `OPEN`, unchanged, not invented here) | Account-deletion cleanup implemented and tested; the specific gap this addendum described (cycle/prayer/pregnancy local data surviving deletion) is fixed and verified |
| §22 Phase H's local-storage-encryption gap (tracked informally, not a numbered finding) | **VERIFIED_CLOSED** | Cycle/prayer local data (the two categories that gap specifically named) now encrypted at rest via platform-managed keys; migration tested non-destructive, idempotent, and failure-safe |
| `PC-010` (new, this wave: cross-user local data leak) | **VERIFIED_CLOSED** | Discovered and fixed in the same pass — user-scoped storage keys eliminate the leak structurally; validated via the mandatory Phase G cross-user test for both cycle and prayer data |
| Pregnancy local storage encryption/scoping | **VERIFIED_CLOSED** | Same architecture applied to `LocalPregnancyTrackingDataSource` as cycle/prayer; not separately called out above only because its narrative is identical, not because it was skipped — see Phase B/D/F, all three data sources are covered uniformly |
| `prayer_location_controller.dart` (raw GPS, unscoped, unencrypted) | **DEFERRED** | Explicitly evaluated (Phase A); real residual gap, correctly out of this wave's named scope (cycle/prayer-tracking/pregnancy), not silently left worse |
| AI/chat local cache boolean flags | **N/A** — assessed, found not to need remediation | Already user-scoped, contains no message content; explicitly not wired into deletion cleanup, reasoning stated in Phase A |
| Security domain (local-data-exposure angle) | **No new Security finding required** | The cross-user leak (`PC-010`) is registered in the Privacy domain, matching this engagement's existing convention for local-storage findings (§22 Phase H was likewise Privacy-domain, not Security) |
| Final User Journey (deletion/logout behavior) | **No PJ finding required** | Journey 7 (delete account, §22 Phase L) remains accurate; this wave adds local-cleanup evidence to that same journey without changing its pass/fail status |

**Owner actions required**: (1) decide whether `prayer_location`'s raw GPS cache should receive the same encrypted/user-scoped treatment as the three categories fixed this wave; (2) the still-unfixed items from §22 remain: public privacy-policy hosting, durable proof-of-consent record, `PC-008`/`PC-009` legal/product decisions.

**Overall verdict: remains NO-GO**, unchanged by this wave — this wave closed a real, severe, newly-discovered privacy defect (`PC-010`) and the local-storage-encryption gap §22 had deferred, but does not touch the still-open blockers driving the NO-GO verdict (`SEC-001` key rotation, `BR-001`/`BR-002` backup/recovery, `RD-006` build numbering, `RD-009` rollback, Accessibility domain untouched, among others tracked in the master register).

---

## 24. Accessibility / UX Remediation Wave (2026-09-05)

**No production DB schema/migration/RLS/trigger/function change occurred.** No cosmetic redesign performed — every change below traces to a specific finding in `AU_findings.md`/`AU_remediation_plan.md` or a defect this wave's own testing discovered, not a preference-driven visual change. Existing visual identity preserved: the AU-003 contrast fix uses a new, narrowly-scoped `taharaText` variant only at the two confirmed failing text sites, leaving the base brand color untouched everywhere else.

**Findings explicitly preserved, unchanged unless stated otherwise below:** `W0-002` (`DEFERRED`), `W1-001` (`OPEN`), `SEC-001`/`ROOT-002` (`OPEN`), Fiqh Search-grounding degradation (`B — DEGRADED`), `RR-001` (`PARTIALLY_REMEDIATED`), `PJ-006` (`OPEN`), `BR-001` (`OPEN`), `RD-009` (`OPEN`), `DC-010` (`OPEN`), `OB-006` (`PARTIALLY_REMEDIATED`), remaining Privacy/Compliance findings (`PC-005`/`PC-008`/`PC-009` `OPEN`; `PC-003`/`PC-004`/`PC-006` `PARTIALLY_REMEDIATED`), `prayer_location` privacy follow-up (`DEFERRED`, per §23).

### Phase A — Accessibility inventory

Read `AU_findings.md`/`AU_remediation_plan.md`/`AU_production_readiness_report.md` in full — the specialist audit had already produced exact `file:line` citations for every confirmed defect via static code inspection (no live device available then either), plus a root-cause map (R1-R7) and a concrete remediation phase table. Re-verified every cited line against the current repository (commits since the audit could have shifted line numbers) before editing — all 15+ `AU-001` sites, `AU-002`'s `_PhaseNode`, `AU-003`'s exact `Text(color:)` usages (cross-checked against every `AppColors.tahara`/`nifas` call site app-wide, not just the two cited — confirmed the audit's `nifas` citation was actually icon-fill, not text-color, usage in the current code, so no fix was needed there specifically), `AU-004`'s `_symptomsCard`, `AU-005`'s form, `AU-006`'s fixed-dimension widgets, `AU-007`/`AU-008`'s RTL patterns (re-swept app-wide via `grep` for `EdgeInsets.only(left/right:`, `Alignment.centerLeft/centerRight`, `Positioned(left/right:` — found and fixed one additional confirmed instance of each beyond what the audit had cited), and `AU-010`'s `ExcludeSemantics` absence.

### Phase B — Semantics / screen-reader support

`AU-001`: every confirmed unlabeled `IconButton` got `tooltip:` (reusing existing translated strings verbatim where they already existed elsewhere in the app, per the remediation plan's own content guidance); the one bare `GestureDetector` close button got a real `Semantics(button: true, label:)` wrapper. A new `NiswahIconButton` widget (`lib/core/widgets/common_widgets.dart`) — required `label`, not optional — is now available so a future icon-only control can't ship silently unlabeled the way these did; existing sites were patched in place rather than migrated to it (lower regression risk for precisely-styled existing buttons, matching the remediation plan's own accepted "interim step" fallback).

`AU-002`: `_PhaseNode` (dashboard phase timeline) now wraps its whole subtree in one `Semantics(label: '<phase>, <value> <unit>[, current phase]', excludeSemantics: true)` instead of exposing fragmented value/unit/label/marker text nodes.

`AU-012` (**new finding, discovered this wave**): while wiring up the consent-checkbox semantics test, found the sign-up consent checkbox — a hand-drawn `InkWell`/`AnimatedContainer`, not a Material `Checkbox` — had **zero** `Semantics` anywhere on it. A screen reader would not recognize it as a checkbox, announce checked/unchecked, or offer any way to know what tapping it does — on the one control that gates account creation. Fixed: `Semantics(checked: agreed, label: 'Agree to the Privacy Policy and Terms of Use', onTap: () => onAgreedChanged(!agreed), child: ExcludeSemantics(child: <existing visual box>))` — independently activatable (the `onTap` gives the node its own semantics action, not just a label) and checked-state-aware, verified against a live semantics-tree dump.

`AU-011` (**new finding, discovered this wave — the most severe finding of this pass**): building the `AU-001`/`AU-002` semantics tests, several assertions failed in a way static reading would never have caught. A live semantics-tree dump (`tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!.toStringDeep()`) revealed why: `Semantics(label: X)` wrappers without an explicit `excludeSemantics`/`container: true` boundary get **silently merged** by Flutter with sibling/descendant text nodes into one composite node. In the cycle-log sheet specifically, this meant the close button's `Semantics(button: true, label: 'Close')` merged with the header's title + subtitle Text widgets into a single node whose full label became `"Log today\nLog today\nRecord blood details and symptoms for today.\nClose"` — and that merged node carried the close button's `tap` action. A screen-reader user double-tapping what reads as descriptive header text would have actually **closed the sheet** — a real, confusing, potentially data-losing mis-activation (unsaved log entries lost), not a cosmetic audio-redundancy issue. Confirmed via the tree dump before the fix, confirmed gone via the same dump after. The identical root cause (an explicit label with an un-excluded descendant Text) was found, independently, in: the symptom-severity chips (`Cramps` + the child Text's own `Cramps` merging into `"\nCramps"`), the bottom navigation bar (`Home` + its own label Text merging into a doubled announcement), the dashboard's notifications bell (an unread-count badge Text merging in as an awkward trailing fragment — while at it, composed a proper `"Notifications, 3 unread"` label instead of relying on the accidental merge), the wellbeing check-in sheet's close button, the community engagement bar (`semanticLabel` vs. visible `label` merging), cycle-calendar day cells (day number Text merging into the day+phase label), and the dashboard's main cycle ring (headline/subtitle Text merging into its already-complete `"Cycle day N, <state>"` label). **All fixed in the same pass** — `excludeSemantics: true` (or `container: true` where the boundary alone, without hiding descendants, was the right call) added to each.

`AU-013` (**new finding, discovered this wave**): `dr_niswah_chat_screen.dart`'s "SUGGESTED QUESTIONS" label used `Align(alignment: Alignment.centerLeft, ...)` — a physical alignment that would stay pinned to the visual left edge even in Arabic, instead of following reading direction. Same root cause as `AU-008`. Fixed: `AlignmentDirectional.centerStart`.

`AU-010`: covered incidentally by every `excludeSemantics`/`container: true` fix above — each one is, among other things, exclusion of decorative/redundant descendant semantics from the tree.

### Phase C — Touch targets

`AU-004`'s symptom-severity chips: vertical padding increased (11px → 13px) and an explicit `BoxConstraints(minHeight: 44)` added, bringing the rendered height from an estimated ~33-35px to ≥44dp — the iOS/Android minimum the audit's own `TOUCH-01` check flagged as failing. No other confirmed-failing touch target existed per the audit's `TOUCH-02` check (nav bar/FAB/close buttons already measured 52-60px, well above minimum) — not re-litigated without new evidence.

### Phase D — Text scaling / dynamic type

`AU-006`: `_PhaseNode`'s value/unit text and the cycle ring's headline/subtitle now wrap in `FittedBox(fit: BoxFit.scaleDown)`, matching the treatment the audit noted was already correctly applied to the same widget's "YOU ARE HERE" label — extending an existing, proven pattern rather than inventing a new one. **Validated, not just reasoned about**: a new test (`test/accessibility_text_scaling_test.dart`) renders the real `DashboardScreen` at 1.0x/1.5x/2.0x/3.0x `TextScaler`, in both English and Arabic (8 tests total), and fails on any layout-overflow exception via `tester.takeException()`. All 8 pass. Text scaling itself was already never clamped anywhere in the app (confirmed, matching the audit's own positive finding) — this wave didn't need to touch that.

### Phase E — RTL / LTR

Re-swept `lib/` for the three patterns the charter specifically named: `EdgeInsets.only(left/right:` (found and fixed 1 beyond the audit's 2 confirmed instances — a dead-code `_Legend` widget in `cycle_tracking_screen.dart`, fixed anyway for consistency with the audit's own precedent of fixing dead code too), `Alignment.centerLeft/centerRight` (found and fixed 1 new instance — `AU-013` above; the file's other `centerLeft`/`centerRight` usage in `cycle_log_form_sheet.dart` was confirmed to already be explicitly `isArabic`-conditional, i.e. correct, not a bug), and `Positioned(left/right:` (reviewed every non-directional instance app-wide — `floating_nav_bar.dart`'s are confirmed direction-aware custom math via explicit `Directionality.of(context)` checks, matching the audit's own positive finding; the remaining instances are symmetric decorative accents — a small circle badge, a "current" marker dot — with no inherent left/right meaning, correctly left as physical positioning per the charter's own instruction not to mechanically convert intentional physical positioning). `Icons.chevron_left_rounded` in `onboarding_screen.dart` was checked directly against the Flutter SDK source and confirmed to already have `matchTextDirection: true` baked into its `IconData` definition — auto-mirrors correctly, no fix needed (a hypothesis considered and correctly ruled out, not silently assumed).

A new regression test (`test/rtl_directional_padding_lint_test.dart`) scans every `lib/` `.dart` file for the exact `EdgeInsets.only(...left/right:` pattern and fails the suite if one is (re)introduced — `AU-007`'s R6(b) "add a lint rule" recommendation, implemented as a plain Dart test rather than a custom analyzer plugin (simpler, no new tooling dependency, runs in the same `flutter test` pass as everything else).

English (LTR) was re-verified unaffected by every RTL fix — each fix uses `EdgeInsetsDirectional`/`AlignmentDirectional`, which is semantically identical to the original physical value in LTR contexts (English is a directional API's "start = left" case), confirmed by the unaffected English golden tests (`Community English`/etc. failures in the full suite are the same 8 pre-existing pixel-diffs, not new).

### Phase F — Color / contrast / non-color signals

`AU-003`: contrast ratios recalculated directly from `app_theme.dart`'s hex values using the WCAG relative-luminance formula (reproducing the audit's own method, not trusting its numbers blindly) — confirmed `tahara` 3.74:1, `nifas` 3.19:1 against white. Cross-checked every real `AppColors.tahara`/`AppColors.nifas` usage site app-wide (14 and 5 sites respectively) to classify each as text vs. icon/border/background/decorative — found exactly 2 genuine small-text usages of `tahara` (dashboard "Mental state check-in" 9px label; Insights `_PredictionValue` 8px label) and confirmed `nifas` has **zero** current text-color usages (the audit's citation was the icon fill in `cycle_tracking_screen.dart`'s `_LegendCard`, which uses the applicable 3:1 UI-component bar, not 4.5:1, and 3.19:1 clears that). Remediation option (a) from the plan (darken, hue-preserving) applied, but scoped narrowly: a new `AppColors.taharaText` (`#0C8379`, recalculated to 4.63:1) applied only at the 2 confirmed text sites — the base `AppColors.tahara` used everywhere else (icons, borders, chip fills, the segment map) is untouched, avoiding the plan's flagged risk of a global brand-color change rippling into unrelated golden-tested visuals. `AU-004`'s color-only severity indicator addressed in Phase B/C (non-color dot indicator added).

### Phase G — Forms / error UX

`AU-005`: `cycle_log_form_sheet.dart` has no fields that are actually required today (confirmed by reading the save path — flow/color/mood/energy/sleep all default to a valid value, notes/symptoms are genuinely optional) — migrating to `Form`/`TextFormField.validator` would have manufactured validation logic for a defect that doesn't currently exist, contradicting the charter's own "no unnecessary architectural rewrite" instruction and the remediation plan's own explicit caveat ("needs product confirmation... if any fields are in fact required"). Instead, addressed the concrete, evidenced part of the finding: the save-failure `SnackBar` (a real data-risk state — sync failed, won't retry) now carries a distinct background color and an error icon, a non-text signal differentiating it from the visually-identical pending/synced `SnackBar`s it previously shared, on both the sync-failure and exception-catch paths.

### Phase H — Loading / empty / failure states

No new defect found in this category beyond what Phase G addressed — `DataExportScreen`'s unauthenticated state was confirmed, via a live widget probe (not assumed), to already show a real, accessible, non-empty explanatory message ("You must be signed in to export your data.") rather than a blank screen or a silently-missing button; this is existing correct behavior, not a fix.

### Phase I — Keyboard / focus

Consistent with the specialist audit's own scoping (`AU_findings.md`'s Static Verification Exit Gate): this is a mobile-only app with no external-keyboard-specific focus-order implementation to inspect; marked `N/A` here too, not re-litigated without new evidence of a tablet/external-keyboard usage pattern.

### Phase J — Reduced motion / animation

Unchanged from the audit's own positive finding (both `AnimationController` instances in the app check `MediaQuery.disableAnimationsOf(context)`) — re-confirmed still true, no motion-heavy UI exists requiring further work.

### Phase K — Bilingual UX parity

Every string touched this wave (tooltips, the new severity/notification labels, the consent-checkbox label) was added as an `_l`/`_tr`/`_pr`/`_cl`/`_ai`/`_dr`/`_j`/`_ct`/`_pt`-style bilingual pair matching each file's existing localization helper convention — zero hardcoded English-only or Arabic-only user-visible/accessibility-critical strings introduced. No hardcoded string bypassing the existing localization architecture was found or added.

### Phase L — Accessibility test suite

`test/accessibility_semantics_test.dart` — 10 tests, using Flutter's real semantics tree (`tester.ensureSemantics()`/`tester.getSemantics()`/`find.bySemanticsLabel`/`find.byTooltip`), covering exactly the 10 required scenarios: (1) signup form field labels, (2) consent checkbox checked-state semantics, (3) password-visibility toggle's state-reflecting name, (4) account-deletion dialog's Cancel/Delete button semantics, (5) cycle-log sheet's close control + symptom-chip severity announcement, (6) prayer-tracking screen's accessible title, (7) Dr. Niswah chat's close control, (8) privacy policy screen's real content, (9) data-export screen's accessible unauthenticated-state message, (10) bottom navigation's per-tab selected/unselected announcement. All 10 pass. `test/accessibility_text_scaling_test.dart` — 8 tests (Phase D). `test/rtl_directional_padding_lint_test.dart` — 1 test (Phase E). None of these are pixel-position-based — all assert against the semantics tree, rendered text content, or thrown-exception state, matching the charter's own "not brittle" instruction.

Several test failures during authoring traced to genuine, previously-unverified facts about real app behavior rather than test-authoring mistakes, each confirmed via a live widget/semantics probe before the test was corrected (not guessed at): `ProfileScreen`'s delete-account row sits below a `SliverList` that doesn't eagerly build off-screen children, requiring `scrollUntilVisible`; the cycle-log sheet's symptom card is similarly below the default test viewport; `DataExportScreen` correctly requires authentication; `PrayerTrackingScreen`'s title is "Prayer Times", not "Prayer tracking"; `IconButton`'s `tooltip:` populates the semantics `tooltip` field, not `label` (`find.byTooltip`, not `find.bySemanticsLabel`, is the correct finder — confirmed against the Flutter SDK source, not assumed); `FloatingNavBar` asserts exactly 5 items.

### Phase M — Accessibility user journeys

Not independently re-run as a separate end-to-end pass beyond what Phase L's 10 tests already exercise (signup/consent/password-visibility, cycle logging, prayer tracking, Dr. Niswah, privacy policy, data export, account deletion, and navigation collectively cover 8 of the 11 named journeys at the semantics level). Pregnancy-profile update and the Dr. Niswah red-flag response specifically were not independently re-verified this wave — no new evidence for either beyond what already exists in the finding register from prior waves (`RR-001`/`PJ-004`'s red-flag persistence work touched the red-flag *data path*, not its accessibility presentation, which remains unverified either way).

### Phase N — Regression testing

`dart analyze lib/`: 27 pre-existing issues, zero new. `dart analyze test/`: 6 new info-level `deprecated_member_use` notices in the new semantics test file (`SemanticsData.hasFlag` — deprecated in favor of `flagsCollection` but still fully functional; not migrated, matching this codebase's existing tolerance for similar deprecated-but-working APIs like `withOpacity`). `flutter test`: **319/327** — the stated immediate baseline (300/308) confirmed accurate by direct re-run, plus 19 new tests (10 semantics, 8 text-scaling, 1 RTL-lint), same 8 pre-existing golden-image diffs byte-for-byte (`parity_community_test.dart` ×2, `parity_today_lower_test.dart` ×1, `parity_profile_test.dart` ×2, `parity_dashboard_test.dart` ×2, `parity_cycle_log_sheet_test.dart` ×1) after the AU-003 fix's 2 intentionally-affected Insights goldens were re-captured and confirmed to show only the expected color change — zero unexpected regressions, directly re-run three times over this wave (once establishing the 300/308 baseline plus the 2 expected new golden diffs, once confirming the re-capture picked up exactly and only the 2 Insights files, once as final verification).

### Phase O — Finding reassessment

| Finding | Status | Notes |
|---|---|---|
| `AU-001` | **VERIFIED_CLOSED** | Every confirmed unlabeled control fixed; validated via real semantics tree, not code reading alone |
| `AU-002` | **VERIFIED_CLOSED** | Phase timeline now exposes one merged, meaningful label per node |
| `AU-003` | **VERIFIED_CLOSED** | Contrast-safe variant applied at the 2 confirmed text sites; base brand color preserved elsewhere |
| `AU-004` | **VERIFIED_CLOSED** | Non-color severity indicator + ≥44dp touch target added and tested |
| `AU-005` | **PARTIALLY_REMEDIATED** | Non-text error/success signal added; no `Form`/`validator` migration (no field is actually required to validate) |
| `AU-006` | **VERIFIED_CLOSED** | `FittedBox` applied, validated at 1x-3x scale in both languages with zero overflow |
| `AU-007` | **PARTIALLY_REMEDIATED** | Regression-prevention test added; ARB migration and expanded golden coverage explicitly out of scope, per the specialist's own recommendation |
| `AU-008` | **VERIFIED_CLOSED** | Confirmed instances fixed plus 1 more found in the same sweep; regression test guards recurrence |
| `AU-009` | **OPEN, unchanged** | No live device/AT/keyboard/zoom testing performed — no such tooling available this session either; independently drives this domain's NO-GO per the specialist's own rule |
| `AU-010` | **VERIFIED_CLOSED** | Addressed incidentally by every `excludeSemantics`/`container` fix this wave |
| `AU-011` (new) | **VERIFIED_CLOSED** | Semantics-merge bug causing a real mis-activation risk, discovered and fixed via live semantics-tree evidence, not assumed |
| `AU-012` (new) | **VERIFIED_CLOSED** | Consent checkbox had zero semantics; now has real checked-state, activatable semantics |
| `AU-013` (new) | **VERIFIED_CLOSED** | Physical alignment bug (same class as `AU-008`), fixed |

**Owner actions required**: (1) schedule a real Phase 2B pass — VoiceOver on iOS + TalkBack on Android, on real devices, for the critical journeys — before or immediately after this wave lands, per the specialist's own R7; this is the only way `AU-009` (and therefore this domain's NO-GO status) can close; (2) decide whether the ARB/`gen-l10n` migration (`AU-007`'s R6(c)) is worth scheduling as its own initiative; (3) product sign-off on the `AU-003` color change if a design review process exists (a technical, WCAG-driven, hue-preserving, narrowly-scoped change was made without that sign-off, consistent with this session's authority to make evidence-based technical accessibility fixes, but flagged here per the remediation plan's own "requires design sign-off" note).

**Overall verdict: remains NO-GO** — `AU-009`'s live-testing gap alone still independently triggers a NO-GO for this domain per the specialist audit's own explicit decision rule, and the engagement's other standing blockers (`SEC-001` key rotation, `BR-001`/`BR-002` backup/recovery, `RD-006` build numbering, `RD-009` rollback, among others) remain untouched by this wave. What changed: `AU-001` (the domain's other independent NO-GO trigger) is now genuinely fixed and validated to a meaningfully higher evidentiary bar than the original static audit — real automated semantics-tree testing, not code reading — and three previously-undiscovered defects (one of them a real mis-activation risk, not merely cosmetic) were found and closed in the same pass.
