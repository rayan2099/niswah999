# Database & Data Integrity — Production Readiness Report

| Field | Value |
|---|---|
| System | Niswah |
| Repository | /Users/rynadalsabh/Niswah |
| Branch | main |
| Commit / Version | 13a9387 (HEAD at audit time) |
| Database engine | PostgreSQL (Supabase-managed) |
| Database version | UNKNOWN — not verified, no live access |
| Schema/migration baseline | `supabase/schema.sql` (507 lines) + 12 files in `supabase/migrations/` (`20260820174500` → `20260830140000`) |
| Phase | FINAL — Production Readiness |
| Audit date | 2026-09-04 |
| Environment | Static repository review only |
| Environment status | 🧪 Controlled (read-only; no database connection made or permitted) |
| Restrictions | No live DB inspection, no migration execution, no controlled/runtime validation (Phase 2B not performed), no data repair |
| Report created | DI_production_readiness_report.md |

---

## Executive Summary

### System
Niswah — Flutter mobile app with a Supabase (Postgres) backend, covering menstrual-cycle/fiqh tracking, pregnancy tracking, an AI chat assistant ("Dr. Niswah"), private messaging, and a community forum.

### Version / Commit
13a9387 (`docs: update README...`), on top of `6d59bfe` (`feat: initial clean commit for Niswah`).

### Database
PostgreSQL via Supabase. Version not verified (no live access).

### Schema/migration baseline
`supabase/schema.sql` (19 tables documented) + 12 tracked migration files. **These two sources do not agree and cannot be reconciled from the repository alone** — see Finding DI-001.

### Open findings
- **DI0 (Critical):** 0 confirmed open — but see "Critical unknowns" below; DI-004 could resolve to DI0.
- **DI1 (High):** 4 — DI-001 (schema/migration drift), DI-002 (systemic silent-failure pattern on core health data), DI-004 (unverified `users` FK-population path — pre-launch-blocking as an *unknown*), DI-005 (unguarded destructive migration).
- **DI2 (Medium):** 2 — DI-003 (private-conversation duplicate race), DI-011 (`cycle_entries` missing per-day uniqueness).
- **DI3 (Low):** 5 — DI-006, DI-007, DI-009, DI-010, DI-012.
- **DI4 (Observation):** 1 — DI-008 (dead schema/dead code).

### Critical integrity tests
0/0 executed. **Phase 2B (Controlled Validation) was not performed** — this audit is static/read-only only, per its mandate. Every finding above is backed by static evidence (schema/migration text, first-party migration-comment admissions of real production incidents, and application code), but no runtime test was executed against any database as part of this audit.

### Critical unknowns
1. **DI-004 (the most consequential unknown):** whether `public.users` — the declared FK target for 14+ tables — is actually populated for real user accounts. No tracked code path populates it. If it is not populated by some untracked mechanism, writes to most of the app's core tables would fail with foreign-key violations for every account, and — per DI-002 — this could be currently happening **silently**, with no operator visibility. This requires a single read-only live query to resolve and should be treated as the top-priority pre-launch action.
2. Whether the live database schema currently matches `schema.sql`, `migrations/`, both, or neither, in full (DI-001) — the historical pattern strongly suggests periodic, undocumented direct changes to the live schema; the *current* full state is unverified.
3. Whether the DI-002 silent-failure pattern has already caused unrecoverable historical data loss for real users (as opposed to the documented incident window that the reactive migrations addressed) — requires live data investigation, not available statically.

### Final recommendation
🔴 **NO-GO**

---

## Launch Decision Rationale

Per the audit template's launch rules (§68):

- **NO-GO is required if:** "Critical write behavior is unknown," "Core models and DB schema materially disagree," or "Orphaning/data loss is realistic."
- All three conditions are met here:
  - Critical write behavior for the majority of the schema is unknown (DI-004).
  - `schema.sql` and the tracked migration history materially disagree, and this has already caused real production write failures on core features at least twice (DI-001).
  - Data loss is not merely "realistic" — it is **confirmed to have already occurred** for cycle-tracking (haid/period logging) and community content, via first-party migration-comment admissions, and the systemic pattern that caused it (silent error-swallowing, DI-002) is still present in the current codebase for `cycle_entries`, `pregnancy_milestones`, and community writes.

No DI0 finding was *confirmed* in this static review, but DI-004 is an unresolved critical unknown that the template explicitly treats as NO-GO-triggering on its own, independent of whether it ultimately resolves to a real DI0. Given the additional confirmed DI1 findings (DI-001, DI-002, DI-005), a NO-GO is warranted even setting DI-004 aside.

**This is not a verdict that the app is broken today.** The reactive migrations (`20260825210000`, `20260826090000`, `20260830140000`) appear to have fixed the specific incidents they targeted. The verdict reflects that (a) the *process* that produced those incidents is still in place and unaddressed, (b) at least one equally severe unknown (DI-004) remains genuinely unverified and is squarely within the template's NO-GO criteria, and (c) the silent-failure pattern that hid the previous incidents from both users and operators is still live in the codebase today, meaning a recurrence would again go undetected.

---

## Launch Gate Table

| Gate | Requirement | Evidence | Status |
|---|---|---|---|
| LG-DI-01 | Zero open DI0 | No DI0 confirmed; DI-004 is an unresolved unknown with DI0 potential | **CONDITIONAL** (treat as FAIL until DI-004 is resolved) |
| LG-DI-02 | Zero launch-blocking DI1 | DI-001, DI-002, DI-005 open | **FAIL** |
| LG-DI-03 | Critical FKs/references safe | DI-004 unresolved | **FAIL** |
| LG-DI-04 | Critical uniqueness concurrency-safe | DI-003 (private conversations) | **FAIL** |
| LG-DI-05 | Critical transactions safe | No multi-step financial/booking transactions found in scope; single-table writes reviewed are simple upserts — N/A beyond DI-002's eventual-consistency concern | **PASS (with caveat — see DI-002)** |
| LG-DI-06 | Critical idempotency verified | `upsert(... onConflict: 'id')` patterns reviewed and consistent; no payment/webhook idempotency surface found in scope | **PASS (N/A — no idempotency-critical external callbacks found)** |
| LG-DI-07 | Critical concurrency verified | DI-003 concurrency gap confirmed by static logic analysis, not runtime-tested | **FAIL** |
| LG-DI-08 | Migration path validated | Not runtime-validated (Phase 2B not performed); statically, migrations cannot rebuild schema from scratch (DI-001) | **FAIL** |
| LG-DI-09 | Model/schema alignment verified | DI-001 confirms material, historically-costly disagreement | **FAIL** |
| LG-DI-10 | No critical orphan/data-loss path | DI-002 confirms a live, currently-present silent-data-loss pattern | **FAIL** |
| LG-DI-11 | Money/time handling verified | No money fields in scope; timestamps consistently `TIMESTAMPTZ`/UTC | **PASS** |
| LG-DI-12 | No critical unknowns | DI-004 (and the live-schema-state unknown underlying DI-001) remain open | **FAIL** |

**Result: 8 of 12 gates FAIL or CONDITIONAL. Mandatory FAIL — NO-GO confirmed by the gate table.**

---

## Residual Risk Register

| Risk ID | Finding | Severity | Probability | Production impact | Mitigation | Owner | Required before launch? |
|---|---|---|---|---|---|---|---|
| RISK-DI-001 | DI-001 | DI1 | High (has already occurred twice) | Silent write failures on core features, discovered only by chance/user reports | R1 (schema reconciliation + process change) | Backend/DB owner | **YES** |
| RISK-DI-002 | DI-002 | DI1 | Medium-High | Undetectable, permanent loss of health-tracking data on remote-sync failure | R2 (surface failures, add retry/telemetry) | App/Backend owner | **YES** |
| RISK-DI-003 | DI-003 | DI2 | Low-Medium (requires near-simultaneous mutual message-initiation) | Duplicate/fragmented conversation threads | R3 (normalize pair + fix constraint) | Backend owner | Recommended, not strictly mandatory |
| RISK-DI-004 | DI-004 | Unknown (up to DI0) | Unknown — must be measured | Possible total write failure across 14+ tables for some/all accounts | R4 (live verification, then FK retarget/backfill) | Backend/DB owner | **YES — top priority** |
| RISK-DI-005 | DI-005 | DI1 | Low (specific historical instance likely safe) but file remains a landmine | Irreversible community data loss if replayed against populated environment | R5 (add guard, document as historical) | Backend/DB owner | **YES** (process fix, low effort) |
| RISK-DI-006 | DI-006 | DI3 | N/A | Reduced auditability of schema history | R6 (append-only policy) | Backend owner | No |
| RISK-DI-007 | DI-007 | DI3 | Medium | Stale `updated_at` on missed writes | R7 (DB trigger) | Backend owner | No |
| RISK-DI-008 | DI-008 | DI4 | Low | Confusion risk / accidental future re-wiring to dead table | R8 (deprecate/remove) | Backend owner | No |
| RISK-DI-009 | DI-009 | DI3 | N/A | No server-side audit trail for religious/fiqh determinations | R9 (product decision) | Product + Backend | No (product sign-off recommended) |
| RISK-DI-010 | DI-010 | DI3 | Low | Logically inconsistent pregnancy data displayed | R10 (CHECK constraints) | Backend owner | No |
| RISK-DI-011 | DI-011 | DI2 | Medium | Duplicate/contradictory cycle-day records affecting fiqh display | R11 (UNIQUE constraint + merge-key fix) | Backend owner | Recommended |
| RISK-DI-012 | DI-012 | DI3 | N/A | Unintended message loss on account deletion (if not product-intended) | R12 (product sign-off) | Product + Privacy | No (sign-off recommended) |

---

## Out-of-Scope / Not Verified

- **Live Supabase project / database was not accessed.** No credentials were available or used; this audit is static/read-only by mandate. Every claim about "the live schema" in this report is an inference from migration and code text, explicitly labeled as such.
- **Actual current row counts** for any table — not verified.
- **Whether all 12 tracked migrations have actually been applied, in order, to the current production project** — not verified; inferred only from migration comments describing incidents that were apparently later fixed.
- **Database engine/version** (e.g., exact Postgres version, Supabase project tier) — not verified.
- **RLS policies as actually deployed** (vs. as written in migration text) — a `DROP POLICY IF EXISTS` + `CREATE POLICY` pair could theoretically have been applied out of order or partially; not independently verifiable without live introspection. (Note: RLS access-control correctness itself is primarily the parallel Security audit's angle; this audit's RLS review was limited to data-integrity-relevant scoping — e.g., whether a user could write a row under another user's `user_id`. All reviewed `INSERT`/`UPDATE` policies consistently use `auth.uid() = user_id`-style checks, which — as written — correctly prevent cross-user writes; no gap of that specific kind was found in the policy text reviewed.)
- **Index usage / query performance** — out of scope for this audit (cross-reference Performance audit); an index inventory was captured in DI_discovery.md but not evaluated for adequacy under load.
- **Backup/restore capability and disaster-recovery drill** — out of scope (cross-reference Backup & Recovery audit); this audit only notes that DI-001's findings make a from-scratch environment rebuild via tracked migrations currently impossible, which is directly relevant to disaster-recovery readiness and should be flagged to that audit.
- **Controlled/runtime validation (Phase 2B of the template)** — not performed. No test data was created, no concurrency test was executed, no migration was actually replayed. All findings are Phase 1 (Discovery) + Phase 2A (Static Verification) only.
- **`supabase/functions/dr-niswah-chat/index.ts` business logic** — file existence and its role as the sole writer to `flagged_conversations` (via service role, bypassing RLS) were confirmed; the function's internal logic was not fully read (more relevant to Security/API audits).
- **Client-side validation depth** in `lib/features/*/domain/entities/*.dart` (e.g., exact `CycleLog.toJson()`/`fromJson()` behavior, form-level validation in presentation code) was not exhaustively reviewed field-by-field beyond what was needed to support the findings above; cross-reference Functional QA / Code Quality audits for full client-validation coverage.

Do not read any of the above as PASS — they are explicitly unverified.

---

## Final One-Sentence Recommendation

> Database & Data Integrity recommendation: **NO-GO** for the current commit until findings **DI-001, DI-002, DI-004, and DI-005** are resolved — schema/migration drift has already caused confirmed silent production data loss on core health-tracking and community features via a still-present error-swallowing pattern, and the foreign-key population path for the majority of the app's tables (`users`) is an unverified critical unknown that must be checked against the live database before launch.
