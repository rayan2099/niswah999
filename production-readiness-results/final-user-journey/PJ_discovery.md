# PJ Discovery — Final Pre-Launch User Journey Audit

## Report Header

| Field | Value |
|---|---|
| System | Niswah — Flutter mobile app (iOS + Android), Supabase backend, Gemini AI |
| Release candidate | commit `13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f`, branch `main`, version `1.0.0+1`, bundle `com.niswah.niswah` |
| Build artifact | Not built for this audit — static source only (no `flutter build`/device/emulator access) |
| Environment | Source-code / migration static trace only. No staging, no live Supabase project access, no live Gemini call |
| Audit date | 2026-09-04 |
| Platforms tested | None executed live. Traced for iOS + Android from `lib/` |
| Roles tested | Single end-user role only (no admin/operator role exists in this app) |
| Languages tested | Traced statically for EN/AR (RTL) where the code path touches it; no live rendering check |
| Test data prefix | N/A — no live execution performed |
| Prior audit package | COMPLETE — Waves 1–4 (Security, Code Quality, Dependencies/Config, API/Backend, Database, Functional QA, Performance, Reliability, Observability, Backup/Recovery, Release/Deployment, Privacy, Accessibility, Analytics) all ingested from `production-readiness-results/master/00_04_MASTER_FINDING_REGISTER.md` |
| Restrictions | No live device/emulator/backend/network access of any kind. "Verification" in this audit means full static code-path tracing from UI event handler through every layer to its persisted/external effect, cross-referenced against prior specialists' findings — never re-derived from scratch. |

---

## 6. Specialist Audit Intake

| Audit | Report available? | Verdict | Open critical/high findings | Accepted residual risks | Notes |
|---|---|---|---|---|---|
| Security | YES | NO-GO | SEC-001, SEC-003, SEC-004 (BLOCKER-class) | None accepted | Client-bundled Gemini key, debug-signed release, messaging RLS gap |
| Functional QA | YES | CONDITIONAL GO | FQ-002 (MEDIUM) | — | Golden-test diffs (FQ-000) unresolved |
| Code Quality | YES | CONDITIONAL GO | CQ-003 (BLOCKER, low-effort), CQ-010 (pending ROOT-001) | — | Dead duplicate fiqh engine coexists with live one |
| Database & Data Integrity | YES | NO-GO | DI-001, DI-002, DI-004, DI-005 (BLOCKER-class) | None accepted | Schema/migration divergence; silent write-failure pattern; unresolved `users`-table population unknown |
| API/Backend | YES | NO-GO | AB-001, AB-002 (BLOCKER-class) | None accepted | Possible Gemini endpoint hallucination (ROOT-001); client-side AI calls uncapped |
| Performance | YES | CONDITIONAL GO | PF-001–PF-003 (MEDIUM) | — | Startup sequencing, PDF not isolate-offloaded |
| Reliability & Resilience | YES | NO-GO | RR-001, RR-002 (BLOCKER-class) | None accepted | No retry/backoff anywhere; app-wide silent async-error swallow |
| Observability | YES | NO-GO | OB-001–OB-004, OB-009, OB-010 (BLOCKER-class) | None accepted | No crash reporting anywhere; server-side audit-log insert unlogged and unguarded |
| Backup & Recovery | YES | NO-GO | BR-001, BR-002, BR-004 (BLOCKER-class) | None accepted | Schema cannot be rebuilt from repo; backup existence itself unverifiable |
| Release/Deployment | YES | NO-GO | RD-006, RD-007, RD-009 (BLOCKER-class) | None accepted | Static build number, no privacy-policy link, no rollback path |
| Privacy & Compliance | YES | NO-GO | PC-001, PC-002, PC-003, PC-004, PC-008 (BLOCKER-class) | None accepted | Cosmetic consent checkbox; no deletion path; no AI-disclosure; no DPA |
| Accessibility/UX | YES | NO-GO | AU-001, AU-009 (BLOCKER-class) | None accepted | 15/20 icon buttons unlabeled; no controlled interaction testing ever run |
| Dependencies/Config | YES | NO-GO | DC-001, DC-003, DC-004, DC-005, DC-006, DC-010 (BLOCKER-class) | None accepted | `.env` bundled as asset; debug keystore; no CI/CD |
| Analytics & Business Events | YES | N/A (independently confirmed) | AE-001 (non-blocking) | — | No telemetry SDK exists; dead paywall UI corroborates dormant premium-tier columns |

### Intake rule application

Per template §201–204: **every mandatory specialist audit above that has already run is NO-GO** (9 of 14 domains: Security, Database, API/Backend, Reliability, Observability, Backup/Recovery, Release/Deployment, Privacy, Accessibility). None of these blocking conditions has been remediated or retested. Per the template's explicit rule, **this alone makes a GO or CONDITIONAL GO impossible for this final audit**, independent of anything found in this wave. This journey audit's job is not to relitigate that verdict, but to determine — by tracing actual execution paths end-to-end — *how* those already-known defects manifest concretely inside the six critical journeys, and whether the act of tracing surfaces genuinely new compound failure modes invisible to any single-domain audit.

---

## 7. Release Candidate Integrity Check

| Check | Expected | Actual | Evidence | Result |
|---|---|---|---|---|
| Commit | `13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f` | `git log` HEAD matches assignment brief | `git status` clean, branch `main` | PASS |
| Build | Flutter release build from this commit | Not built (no build tooling run in this audit) | N/A | INCONCLUSIVE — no build artifact produced or verified |
| Schema/migrations | Live Supabase schema matches `supabase/migrations/` + `supabase/schema.sql` | Cannot verify — no live DB access. Static comparison shows migrations and `schema.sql` themselves materially diverge (DI-001, confirmed again in this wave, see `PJ_journey_traces.md` §2/§3) | `supabase/schema.sql`, `supabase/migrations/*.sql` | FAIL — divergence directly observed |
| Config | `.env`/build config matches candidate | `.env` bundled as Flutter asset (DC-001); `.env.example` omits `GEMINI_API_KEY` (DC-003) | Master register | FAIL (cited, not re-derived) |

---

## 8. Launch Assumption Register

| Assumption ID | Assumption | Owner | Evidence | Risk if false |
|---|---|---|---|---|
| `ASM-001` | The live Supabase project's `public.users` table exists and is populated for every account, matching `schema.sql`'s FK design | Unknown/unassigned | Static trace (this audit): **zero** code path anywhere in `lib/` ever writes to `.from('users')` — only `.from('profiles')` is populated (via `AuthRepositoryImpl` and the `handle_new_user()` trigger in `20260820174500_niswah_production_schema_security.sql`, which inserts only into `profiles`). Master register: DI-004 (open), UNK-006 (open) | If false: every INSERT into `cycle_entries`, `chat_threads`, `chat_messages`, `flagged_conversations`, `pregnancy_profile`, `wellbeing_logs`, `community_posts/comments/likes` — i.e. essentially every core write in the app — fails on a FK violation, for every user, permanently. See `PJ_findings.md` PJ-001. |
| `ASM-002` | Gemini endpoint shape (`v1beta/interactions`) used identically in `supabase/functions/dr-niswah-chat/index.ts` and `lib/core/services/gemini_service.dart` is a real, working Google API | Unknown/unassigned | Confirmed present verbatim in both places by this audit's own read of `index.ts` line 21 (`GEMINI_ENDPOINT = '.../v1beta/interactions'`). Cross-references ROOT-001/UNK-001 (open) | If false: 100% of AI features (Dr. Niswah chat, AI Advisor, Dream Interpreter) are dead in production, with no error surfaced anywhere except a same-request failure the user might mistake for a network blip |
| `ASM-003` | The tracked migration sequence in `supabase/migrations/` was actually applied, in order, to the live project | Unknown/unassigned | Cross-references UNK-002 (open); BR-002 already proved by direct replay that this sequence halts partway through against an empty DB. This audit additionally confirms (see `PJ_journey_traces.md` §2) that migration `20260824115900` is itself the most likely literal halt point, since it is the first migration to reference a bare `users(id)` FK target that no tracked migration ever creates | If false in either direction, every downstream conclusion about "what the live schema looks like" is unverifiable from source alone |
| `ASM-004` | `NiswahSupabase.clientOrNull` stays non-null for the app's lifetime once `Supabase.initialize()` succeeds once at startup (confirmed by reading `lib/core/network/supabase_client.dart`) | N/A — verified by this audit | Static read, see `PJ_journey_traces.md` §4 | Governs which demo-mode fallback branches are reachable in practice (see PJ-002) |

Unknown critical assumptions ASM-001–ASM-003 remain open and, per template §241, **block GO on their own**.

---

## 9. User Role Inventory

| Role ID | Role | Key permissions | Critical journeys | Operational importance |
|---|---|---|---|---|
| `ROLE-001` | Guest / unauthenticated visitor | Browse sign-in screen only; demo-mode fallback data in messaging/community if reached without a session | Onboarding entry | Low |
| `ROLE-002` | End user (signed-in woman tracking her cycle/pregnancy) | Full app: cycle logging, chat, messaging, reports, prayer tracking | All 6 journeys below | Highest — the only real user role this app has |

No admin, staff, moderator, or operator role/console exists anywhere in the codebase (confirmed by the absence of any admin screen, role field beyond `auth.uid()`-scoped RLS, or operations dashboard in `lib/`). This itself is material to Phase 4 §18 (Operational Handoff Matrix): **there is no operational/admin state for any journey to hand off to** — a red-flagged conversation, once logged to `flagged_conversations`, has no in-app consumer; it exists purely as a raw DB row for a manual, out-of-app process. This is consistent with, not contradictory to, the existing register (no separate finding needed).

---

## 10. Critical Journey Inventory

| Journey ID | Journey | Role | Business outcome | Criticality | Systems involved |
|---|---|---|---|---|---|
| `PJ-J1` | Onboarding → account creation | ROLE-001→002 | New account created, consented, initial profile row exists | Critical | Supabase Auth, `profiles` trigger, RLS |
| `PJ-J2` | Daily cycle/haid logging | ROLE-002 | Fiqh state (tahara/haid/needs-advisory) computed and persisted | Critical (core value prop) | `MadhhabRuleEvaluator`, local storage, `cycle_entries`, RLS |
| `PJ-J3` | Dr. Niswah AI chat — red-flag message | ROLE-002 | Urgent banner shown; message + audit log persisted; Gemini reply returned | Critical (safety) | Edge function `dr-niswah-chat`, Gemini, `chat_messages`, `flagged_conversations` |
| `PJ-J4` | Private messaging | ROLE-002 | Message delivered, read-state correct, no cross-user leakage | High | `private_conversations`, `private_messages`, RLS |
| `PJ-J5` | Doctor/husband PDF report export | ROLE-002 | Accurate, complete PDF generated and shareable | High | Cycle/pregnancy/wellbeing repos, `flagged_conversations` read, `printing` package |
| `PJ-J6` | Prayer time tracking with location | ROLE-002 | Correct prayer times shown; reminder notifications fire | High | `Geolocator`, `adhan_dart`, `flutter_local_notifications` |

---

## 12–18. Entry-state / Data-state / Platform / Locale / Integration / Notification / Operational matrices

These are **not separately tabulated as blank template scaffolding** here — each is answered inline, per journey, inside `PJ_journey_traces.md`, because every cell would otherwise either restate a prior specialist finding (which the template instructs to cite, not duplicate) or require live execution this audit does not have (in which case the correct entry is "🟦 Requires Controlled E2E Test — not executed", not a fabricated PASS). The Entry-State, Integration, and Notification content that *can* be established from source is folded into each journey's step-by-step trace.

Explicitly unresolved / not executed for every journey:
- Live device or emulator interaction (no journey received live click-through testing).
- Screen-reader/keyboard navigation execution (cross-references AU-009, already an open BLOCKER — not re-tested here).
- RTL layout inspection at runtime (only source-level `_tr()`/Arabic-string presence confirmed where read).
- Any live network call to Supabase or Gemini.

---

## 19. Journey Discovery Exit Gate

- [x] All critical roles identified (2 — no admin role exists in this app).
- [x] All critical journeys identified (6, per assignment brief's minimum set; no additional journey met the bar for inclusion beyond these six — messaging, chat, cycle logging, onboarding, reporting, and prayer tracking exhaust the app's other top-level `NiswahHomeShell` destinations at a comparable criticality level).
- [x] Journey steps mapped (see `PJ_journey_traces.md`).
- [x] Entry states identified where traceable from source.
- [ ] Platform matrix defined — **not executed**; no live iOS/Android divergence traced beyond what's visible in shared Dart source (out of scope without device access).
- [x] Locale/RTL requirements identified where visible in source; **not** visually verified.
- [x] Integrations mapped (Supabase Auth/Postgres/RLS, Gemini, `flutter_local_notifications`, `Geolocator`, `printing`).
- [x] Notifications mapped (see PJ-J3, PJ-J6 traces).
- [x] Operational handoffs mapped — **there are none**; documented above.
- [x] Critical unknown journeys documented — none identified beyond the six in scope.
