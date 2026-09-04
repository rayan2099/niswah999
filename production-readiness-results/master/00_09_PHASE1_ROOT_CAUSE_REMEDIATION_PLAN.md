# 00_09 — Phase 1: Root-Cause Remediation Plan

> **PLANNING ONLY. NOTHING IN THIS DOCUMENT HAS BEEN IMPLEMENTED.** No code, configuration, migration, or production-database change has been made as part of this phase. This plan requires explicit review and approval before any execution wave begins. Per the remediation charter, this supersedes no specialist remediation plan (`SEC_remediation_plan.md`, `DI_remediation_plan.md`, etc.) — it sequences and gates them against each other and against the Phase 0 evidence in `00_05_UNKNOWN_ASSUMPTION_REGISTER.md`.

| Field | Value |
|---|---|
| Baseline | `1.0.0+1` / commit `13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f` |
| Precondition | Phase 0 complete — all 5 critical unknowns resolved (`00_05` §Phase 0 Resolution) |
| Status | PROPOSED — awaiting release-owner review and sequencing approval |

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

**Findings addressed:** `BR-001`, `BR-002`, `BR-003`, `BR-004`, `BR-005`, `BR-007`, `BR-008`, `DI-001`, `DI-005`, `DI-006`, `DI-004`/`PJ-001` (informing, already closed).
**Affected audits:** Database, Backup & Recovery, Final User Journey.
**Dependencies:** None — this is the root prerequisite. Nothing else with a DB-mutation tag may start before this wave's exit criteria (§4.10) are met.
**Production access required:** Yes throughout (read-only until step 4.9; one metadata-only write in 4.9).
**Regression risk:** None if sequenced as written — every DDL-authoring/testing step below happens against an isolated environment, never live, until the final ledger-repair step.

### Sequence

**4.1 — Establish a safe recovery point** *(OWNER ACTION REQUIRED — cannot be executed by this session)*
Enable Point-in-Time Recovery and/or trigger an immediate physical backup for the live project. Phase 0 confirmed `pitr_enabled: false` and `backups: []`. This is very likely a plan-tier/billing decision (Free tier typically has no physical backups) — a financial and account-level action outside what a remediation session can or should perform unilaterally. **This step blocks everything else in Wave 0 and, transitively, every DB-mutating item in every later wave.** Until this is done, the honest status of the whole plan is: *any* schema mistake, anywhere, for any reason, is permanently unrecoverable.
- DB mutation: No (infrastructure/billing config, not schema).
- Exit criterion: at least one restorable backup exists, confirmed via `supabase backups list`.

**4.2 — Capture the authoritative live schema** *(read-only, can start immediately/in parallel with 4.1)*
Extend Phase 0's partial capture (`public`, `auth` schemas only) to a complete, multi-schema, schema-only export: tables, columns, functions, triggers, **RLS policies** (`pg_policies` — not yet inventoried), **indexes** (`pg_indexes`), **constraints** (`information_schema.table_constraints`), and **extensions** (`pg_extension`) — none of which Phase 0's two targeted dumps covered in full. Store the result under a new, clearly-labeled path (e.g. `supabase/live_schema_capture/2026-09-04_baseline.sql`) — **not** overwriting `schema.sql` yet.
- DB mutation: No.

**4.3 — Inventory live-only objects**
Formalize what Phase 0 already found (partial list) plus whatever 4.2 adds: `chat_history` table, `create_user_profile()` function, `delete_my_account()` function, `auth_users_create_profile` trigger, naming divergences (`prayer_log` vs `prayer_entries`, `pregnancy_records` vs `pregnancy_milestones`, `secret_vault` vs `secret_vault_entries`), plus any policy/index/constraint that exists live but not in `schema.sql`/migrations. Produce a single ledger document.
- DB mutation: No.

**4.4 — Three-way comparison**
For every object found in 4.2/4.3: mark present/absent/matching across {live, `schema.sql`, tracked migrations}. This is the definitive "what is actually true" table that both `DI-001` and `BR-002` have been circling since Wave 1 of the original audit.
- DB mutation: No.

**4.5 — Canonical migration baseline strategy (design decision, authored but not applied to live in this step)**
Author **one** new, idempotent (`IF NOT EXISTS`-guarded) baseline migration that captures the *current live reality exactly as it is* — including `chat_history`, both provisioning triggers/functions, and every live-only object under its **live** name (`prayer_log`, not the never-applied `prayer_entries` rename). Mark all 12 existing migration files "SUPERSEDED — historical, do not replay" per `DI` plan's R6 append-only convention (do not delete them — `DI-006`). Regenerate `schema.sql` *from* this baseline so it becomes a generated artifact, not a hand-maintained one (per `DI` plan R1.4).
- **Explicitly separate from this baseline:** any *behavioral* change (e.g. `DI-004` R4's original idea of retargeting FKs from `users` to `profiles`) is a later, deliberate, product-reviewed decision — not bundled into "capture what exists today."
- DB mutation: No (this authors a new file in the repository; it is not yet applied anywhere).

**4.6 — Preserve production data**
Independent of the schema baseline, take a full **data**-only export (`supabase db dump --linked --data-only`) as a point-in-time artifact. This contains real health/religious/message data — **must not be committed to git**; store in owner-managed, encrypted, access-controlled storage only.
- DB mutation: No.

**4.7 — Preserve `auth.users` integration verbatim**
Both triggers (`on_auth_user_created`→`handle_new_user()`, `auth_users_create_profile`→`create_user_profile()`) and both function bodies go into the baseline migration byte-for-byte as captured live. No consolidation, dedup, or "cleanup" in this step — reality first, improvement later (improvement is a Wave 1c decision, see §7).
- DB mutation: No (part of 4.5's authored file).

**4.8 — Preserve `delete_my_account()` verbatim**
Same treatment. Flag in the baseline migration's comments that its exact cascade/anonymization behavior needs Privacy-audit verification (Wave 5, §7) before the client is wired to call it.
- DB mutation: No.

**4.9 — Clean rebuild test against a brand-new isolated environment** *(hard gate — must pass)*
Using a fresh Supabase local stack or disposable Postgres (the method already proven in Phase 0), apply **only** the new baseline migration (4.5) end-to-end against an empty database. Then run a schema diff between this freshly-rebuilt environment and the 4.2 live capture. **Exit criterion: zero diff.** This is the literal proof — not an assertion — that a fresh environment reproduces the required schema and behavior, satisfying the charter's explicit "do not fix this by marking the database as migrated without demonstrating reproducibility."
- DB mutation: No (isolated test environment only).

**4.10 — Restore/recovery test** (requires 4.1 complete)
Once a real backup exists, restore it into an isolated, non-production project or local instance (never live) and validate: schema present, representative record counts, key FK relationships resolve (e.g. a `cycle_entries.user_id` correctly resolves to `public.users`). This satisfies `BR-008`'s Golden Rule (an unexercised backup is unverified).
- DB mutation: No to live; yes to the disposable restore target only.

**4.11 — Register the live database as migrated** *(the one live-touching step in this wave)*
Only after 4.9 passes with zero diff: use `supabase migration repair` to mark the new baseline version as `applied` against the live project's migration ledger, and mark the 12 superseded migrations `reverted` in that ledger (they never actually ran there, per Phase 0's `migration list` finding). This is a metadata-only write to Supabase's internal tracking table — it does **not** execute any DDL against `public`/`auth` (the baseline is `IF NOT EXISTS`-guarded and live already has these objects).
- DB mutation: **Yes** (metadata only, zero schema DDL against live) — requires 4.1 (recovery point) to be satisfied first, per the blanket rule in §1.
- Rollback: `supabase migration repair --status reverted <version>` restores the ledger to its current state. Zero risk beyond the ledger itself — no DDL was ever run against live in this wave.

### 4.12 — Wave 0 Exit Criteria (all required before any later wave's DB-mutating item may proceed)
- [ ] 4.1: at least one real, restorable backup exists (or PITR enabled)
- [ ] 4.2–4.4: complete live-vs-repo comparison ledger produced and reviewed
- [ ] 4.5, 4.7, 4.8: baseline migration authored, capturing all live-only objects verbatim
- [ ] 4.6: data preserved in owner-managed secure storage (not git)
- [ ] 4.9: clean rebuild test passes with **zero** schema diff against live capture
- [ ] 4.10: at least one real restore test demonstrated
- [ ] 4.11: live migration ledger repaired to reflect reality

---

## 5. Root-Cause Table (dependency-aware, all finding IDs preserved)

| Root cause | Finding IDs | Affected audits | Dependencies | Proposed remediation | Production risk | Rollback | Tests required | E2E journeys |
|---|---|---|---|---|---|---|---|---|
| **P0 — DB not reproducible / no backup** | `BR-001,002,003,004,005,007,008`, `DI-001,005,006` (`DI-004`/`PJ-001` inform, closed) | Database, Backup/Recovery, Final User Journey | None (root prerequisite) | Wave 0, §4 | High if skipped/rushed; near-zero if sequenced as written (all DDL tested in isolation first) | `migration repair --status reverted`; no live DDL was run | Zero-diff rebuild test (4.9); restore test (4.10) | None required for the capture itself; all journeys re-verified after any later schema change |
| **P1a — Silent failure / write-path durability** | `DC-004`, `CQ-009`, `AB-010`, `DI-002`, `RR-001,002`, `FQ-002`, `OB-001–006,009,010`, `BR-005`, `PJ-002,004,006` (`ROOT-005`) | Database, Reliability, Observability, Backup/Recovery, Final User Journey, Functional QA | None blocking; app-code only, runs parallel to Wave 0 | Repository-layer error surfacing + retry/backoff + UI "sync failed" state + crash/error reporting (coordinated with P3) | Medium — touches every core repository's error contract; UI states may need new design | Per-repository revert (each is an independent commit per `DI`/`OB` plans) | Simulated remote-failure test per repository; red-flag chat failure-injection test (`PJ-004` regression) | Cycle logging, pregnancy tracking, community, Dr. Niswah chat (red-flag path), private messaging |
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
| **1a** | P1a | `DC-004,CQ-009,AB-010,DI-002,RR-001,002,FQ-002,OB-001-006,009,010,BR-005,PJ-002,004,006` | Repository impls, `main.dart`, `dr-niswah-chat/index.ts`, `failures.dart` | No (app/edge-function code only) | No | Not required — may start immediately | Failure-injection per repository | Reliability, Database, Observability, Final User Journey | Cycle logging, pregnancy tracking, community, Dr. Niswah chat, private messaging | Per-commit revert |
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
