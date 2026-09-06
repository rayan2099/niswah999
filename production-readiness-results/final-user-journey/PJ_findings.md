# PJ Findings — New Cross-Layer Observations Only

> **Status update (2026-09-06, most recently the Final Application Code Blockers wave):** This document is the frozen original audit (2026-09-04), preserved as-is for historical reference. Current status: `PJ-001` — **VERIFIED_CLOSED** (favorable — `public.users` is populated for every real account by an untracked-but-live trigger; the residual concern that this provisioning logic exists only in the live database is tracked separately under `DI-001`/`ROOT-007`). `PJ-002` — **PARTIALLY_REMEDIATED/OPEN**, narrowed to cross-device sync only (the silent-failure/no-warning half of this finding's original scope is closed). `PJ-003` — **VERIFIED_CLOSED** (Final Application Code Blockers wave, 2026-09-06 — the local red-flag fallback no longer rethrows after showing its banner, eliminating the simultaneous generic-error signal). `PJ-004` — **VERIFIED_CLOSED** (deployed to production as function version 8, live-verified via forced-failure testing, an authenticated production recheck, and a fresh live version check this same day). `PJ-005` — **VERIFIED_CLOSED** (Final Application Code Blockers wave, 2026-09-06 — `community_board_screen.dart`/`profile_screen.dart` no longer fall back to fabricated demo conversations on a dead/absent session; both now show an honest re-authentication prompt instead). `PJ-006` — **VERIFIED_CLOSED** (Doctor's Report Data Completeness + Truthfulness wave, 2026-09-06). Check `production-readiness-results/master/00_04_MASTER_FINDING_REGISTER.md`, not this file, for current status.

Per the assignment brief, this register contains **only** findings that emerge specifically from end-to-end reconciliation across two or more already-known issues, or that trace a mechanism a prior audit stated only as an abstract/unresolved unknown. It does not re-create SEC/DI/AB/OB/RR/CQ/PC/AU/BR/RD/DC findings that already exist — those are cited by ID in `PJ_journey_traces.md` and in the Cross-Reference column below.

---

## PJ-001 — Bare `public.users` table is the FK target for 7+ core feature tables and is never populated by any code path; the app's own migration history is internally inconsistent about which "users" table each table actually depends on

| Field | Value |
|---|---|
| Journey | PJ-J1 (Onboarding), PJ-J2 (Cycle logging), PJ-J3 (AI chat) |
| Role | ROLE-002 |
| Platform | iOS + Android (backend-side, platform-independent) |
| Step | Any INSERT into `cycle_entries`, `chat_threads`, `chat_messages`, `flagged_conversations`, `pregnancy_profile`, `wellbeing_logs`, `community_posts`, `community_comments`, `community_likes` |
| Expected outcome | Row inserts successfully against a populated FK target |
| Actual outcome | FK target (`public.users`) is plausibly always empty; confirmed by static trace that **zero** call site in `lib/` ever writes `.from('users')` |
| Cross-system impact | Compounds DI-004 (open critical unknown), DI-001 (schema/migration divergence), DI-002 (silent-swallow pattern), BR-002 (migration replay halts) — this is very likely the same event BR-002 already observed by direct replay, now identified by mechanism: `20260824115900_dr_niswah_chat_threads.sql` is the first tracked migration to `REFERENCES users(id)` against a table no migration ever creates |
| Evidence | `grep -rn "\.from('users')" lib/` → zero results. `supabase/schema.sql:7` defines `CREATE TABLE users (...)`, distinct from both `auth.users` and `public.profiles`. 7 migrations from `20260824115900` onward all FK to bare `users(id)`; earlier migrations (`20260820174500`, `20260822014500`, `20260822210000`) instead FK directly to `auth.users(id)` — the codebase itself is inconsistent about which target is correct, suggesting this was never resolved even by whoever wrote the migrations |
| Severity | **PJ0** — if confirmed live, this silently breaks the core write path of essentially the entire app's data model, permanently, for every user |
| Launch blocker | YES |
| Confidence | 🟨 Likely — cannot be elevated to 🟥 Confirmed without one live query (`SELECT count(*) FROM users`), same restriction as DI-004/UNK-006. This finding's value over DI-004 is that it identifies the *specific tables and mechanism* affected, not just that the question is open. |
| Status | OPEN |

---

## PJ-002 — Cycle/haid logging: local-first UI + silent remote-write failure + no cross-device sync = a full data-loss chain invisible until a device is lost, with no warning at any point in the chain

| Field | Value |
|---|---|
| Journey | PJ-J2 |
| Role | ROLE-002 |
| Step | `CycleTrackingRepositoryImpl.saveCycleLog()` → `getCycleLogs()` on a second device/reinstall |
| Expected outcome | Haid history persists durably and is available on any device the user signs into |
| Actual outcome | History is plausibly local-device-only (per PJ-001's FK mechanism layered onto DI-002's confirmed pattern); a reinstall, device change, or app-storage clear loses it entirely, with **no warning surfaced at logging time, at reinstall time, or ever** |
| Cross-system impact | Chains DI-002 (silent swallow, confirmed) + RR-001 (no retry, confirmed) + PJ-001 (plausible FK cause) + the complete absence of any "your data isn't backed up to the cloud" messaging anywhere in the UI (cross-references BR-006, on-device data has no deliberate backup design) |
| Evidence | `cycle_tracking_repository_impl.dart:115-127` (swallow), `:20-81` (local-fallback read), migration comment in `20260826090000` confirming the historical incident |
| Severity | **PJ0** — core value proposition of the app (haid/cycle tracking) is not durably persisted, for a health-tracking app whose entire purpose is this data |
| Launch blocker | YES |
| Confidence | 🟧 Confirmed by specialist evidence (DI-002, RR-001) + 🟨 Likely for the specific FK mechanism (PJ-001) |
| Status | OPEN |

---

## PJ-003 — Dr. Niswah chat: a correctly-firing safety banner can render simultaneously with a generic error state on the same screen, for the same failed request

| Field | Value |
|---|---|
| Journey | PJ-J3 |
| Role | ROLE-002 |
| Step | `ChatViewModel._sendViaDrNiswahBackend()` catch block (line 252) → `sendMessage()` outer catch (line 213) |
| Expected outcome | One coherent signal to the user about what happened to her urgent message |
| Actual outcome | `messages` list gets an appended urgent-banner `ChatMessage` (reassuring), while `errorMessage` is independently set on the same view model via `rethrow` (alarming/confusing) — both are live simultaneously; how the screen renders both together was not verifiable without live execution, but the view-model-level contradiction is confirmed by source |
| Cross-system impact | Net-new: neither AB (client behavior on server failure) nor OB (logging) traced this specific dual-state outcome; it only becomes visible by tracing the full urgent-message path end-to-end as this audit's mandate requires |
| Evidence | `lib/features/ai_assistant/presentation/viewmodels/chat_view_model.dart:252-268` (banner + rethrow) and `:213-214` (errorMessage set from the same rethrown error) |
| Severity | **PJ2** — bounded UX confusion, not a data-loss or safety-message-suppression risk (the reassuring banner does still show) |
| Launch blocker | NO (does not independently block; compounds PJ-004 below, which does) |
| Confidence | 🟧 Confirmed by specialist evidence (static code read) — 🟦 would require a live device to confirm the actual rendered screen state |
| Status | OPEN |

---

## PJ-004 — Dr. Niswah chat: when the backend call fails for a red-flag message, neither the clinical audit-log entry NOR the user's own urgent message NOR the reassuring banner shown to her is ever persisted anywhere — the entire safety-relevant exchange vanishes on next load

| Field | Value |
|---|---|
| Journey | PJ-J3 |
| Role | ROLE-002 |
| Step | Full trace: `dr-niswah-chat/index.ts` red-flag insert (line 246-254, throws on FK violation per PJ-001) → function exits before the user-message insert (line 256) ever runs → client catch shows a local, in-memory-only banner (`chat_view_model.dart:252-268`) that is never sent through `_repository.sendMessage()` (unlike the direct-Gemini fallback path's fire-and-forget persistence at lines 306-319, which this backend path has no equivalent of) |
| Expected outcome | Per OB-004, the audit log insert failing is already known/OPEN. The assignment brief specifically asks what the *full, honest, end-to-end* behavior is when this compounds with a simultaneous Gemini failure |
| Actual outcome | Full answer, newly traced: **three separate persistence failures stack**, not one. (1) `flagged_conversations` — zero row (OB-004's finding). (2) The user's own original urgent message — zero row in `chat_messages`, because the function throws before reaching that insert (not previously stated by any audit — OB-004 discussed the log insert's blast radius only implicitly). (3) The reassuring banner itself, uniquely on this code path, is never written anywhere, even locally-persistently — it is a `ChatMessage` object that exists only in the current `ChangeNotifier`'s in-memory list. On next `loadMessages()` (thread reopen, app restart), the entire exchange — user's cry for help and the app's reassurance both — is gone with zero trace, client or server |
| Cross-system impact | Directly reconciles and extends OB-004 (server-side) with a client-side persistence gap OB never examined for this path, and reconciles AB's positive-control note (banner fires) with the fact that "fires" and "persists" are not the same guarantee |
| Evidence | `supabase/functions/dr-niswah-chat/index.ts:246-262` (insert order + shared unguarded block); `lib/features/ai_assistant/presentation/viewmodels/chat_view_model.dart:252-268` (no persistence attempt on this path, contrast with `:306-319` on the direct-model path which does attempt one) |
| Severity | **PJ0** — for a pregnancy-safety feature, a red-flag report that self-erases from all records (including the user's own chat history) the moment she reopens the app is a critical, dangerous, and clinically consequential gap |
| Launch blocker | YES |
| Confidence | 🟧 Confirmed by specialist evidence for the persistence-gap mechanism (direct code read); 🟨 Likely that the FK violation is what actually triggers it in production (depends on PJ-001) |
| Status | OPEN |

---

## PJ-005 — Private messaging demo-mode fallback is checked live, per screen-open, against current session state — not once at startup — so an active user with a silently-expired session is dropped into fabricated data with zero warning, repeatedly, for the rest of that session

| Field | Value |
|---|---|
| Journey | PJ-J4 |
| Role | ROLE-002 |
| Step | `community_board_screen.dart:99-103` / `profile_screen.dart:417-421`, `_messagingRepository` getter |
| Expected outcome | CQ-007 (already open) frames this generally as "including an unexpected session drop" |
| Actual outcome | This trace establishes the *specific* mechanism: the check is `NiswahSupabase.clientOrNull?.auth.currentUser?.id == null`, re-evaluated fresh every time either screen's Messages entry point is tapped — not a one-time app-start check. Because `clientOrNull` itself never goes null again post-init (`supabase_client.dart:19-27`), the only way into demo mode after a successful sign-in is a genuine, live `auth.currentUser` becoming null — i.e. an actual session death mid-use (refresh-token expiry/revocation, compounded by RR-001's absent retry) — and it will keep silently re-triggering on every subsequent visit until the user manually re-authenticates, which nothing in this flow ever prompts her to do |
| Cross-system impact | Sharpens CQ-007 with the exact trigger condition and its repeatability; compounds RR-001 (no recovery) and the app-wide absence of any session-expiry UX (template §25 — not implemented anywhere in this journey) |
| Evidence | `lib/features/community/presentation/screens/community_board_screen.dart:99-103`, `lib/features/auth/presentation/screens/profile_screen.dart:417-421`, `lib/core/network/supabase_client.dart:19-27` |
| Severity | **PJ1** — no financial/data-loss risk, but a materially deceptive UX state (fabricated conversations indistinguishable from real ones) with no safe workaround visible to the user |
| Launch blocker | YES (pre-launch blocker per PJ1 classification — no safe workaround exists in-product) |
| Confidence | 🟧 Confirmed by specialist evidence (direct code read of both call sites and the locator) |
| Status | OPEN |

---

## PJ-006 — Doctor's Report red-flag section is not merely sometimes incomplete — it is architecturally guaranteed to always read "no concerns flagged," because its data source (`flagged_conversations`) is populated by the exact insert this audit traces as plausibly always failing, and an empty read is indistinguishable from a successful one

| Field | Value |
|---|---|
| Journey | PJ-J5 |
| Role | ROLE-002 |
| Step | `DoctorReportScreen._generate()` → `FlaggedConversationsRepository.getRecent()` → `DoctorReportInsightsEngine.analyze(recentFlags: ...)` |
| Expected outcome | A doctor's report specifically built to surface safety-relevant red-flag chat history does so when that history exists |
| Actual outcome | `getRecent()` returns an empty list both when there is genuinely nothing to report AND when every insert into `flagged_conversations` has been silently failing (per PJ-001/PJ-004) — these two states are **structurally indistinguishable** to this code, by design (its own doc comment: "a signed-out user is a normal, silent empty result, not an error" — that reasoning was written for the signed-out case but the same code path also silently absorbs the FK-failure case) |
| Cross-system impact | Directly compounds PJ-001 (FK gap) + PJ-004 (chat-side persistence gap) into the one artifact this app produces specifically for a real doctor to read and potentially act on clinically — the single highest real-world-harm compounding finding in this audit |
| Evidence | `lib/features/doctor_report/data/repositories/flagged_conversations_repository.dart:23-47`; `lib/features/doctor_report/presentation/screens/doctor_report_screen.dart:88-90,103-111` |
| Severity | **PJ0** — a clinical document silently omitting safety-relevant history it was specifically designed to surface, with no way for the user or a reviewing doctor to know it's incomplete, is a critical, irreversible-in-effect defect (the doctor cannot know what she wasn't told) |
| Launch blocker | YES |
| Confidence | 🟨 Likely (depends on PJ-001's live-unverified FK premise) for the "always empty" claim; 🟥 Confirmed for the "0 rows and a genuine failure are indistinguishable by this code" architectural claim, which holds regardless of whether PJ-001 turns out to be true |
| Status | OPEN |

---

## Findings Register Summary

| Finding ID | Journey | Severity | Launch blocker? | Status |
|---|---|---|---|---|
| PJ-001 | PJ-J1/J2/J3 | PJ0 | YES | OPEN |
| PJ-002 | PJ-J2 | PJ0 | YES | OPEN |
| PJ-003 | PJ-J3 | PJ2 | NO | OPEN |
| PJ-004 | PJ-J3 | PJ0 | YES | OPEN |
| PJ-005 | PJ-J4 | PJ1 | YES | OPEN |
| PJ-006 | PJ-J5 | PJ0 | YES | OPEN |

4 × PJ0, 1 × PJ1, 1 × PJ2. Zero PJ3/PJ4.

## Root-Cause Ownership (template §56)

| Finding | Likely specialist owner |
|---|---|
| PJ-001 | Database |
| PJ-002 | Database, Reliability |
| PJ-003 | API/Backend, Code Quality |
| PJ-004 | API/Backend, Observability |
| PJ-005 | Code Quality, Reliability |
| PJ-006 | Database, Privacy (clinical-data-integrity angle) |
