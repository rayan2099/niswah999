# PJ Journey Traces — End-to-End

Methodology note: every step below is a static code-path trace (file:line-level), not a live execution. Confidence symbols follow the template's key. Prior findings are cited by ID, not re-derived, except where this trace surfaces a mechanism a prior audit stated only abstractly (e.g. DI-004's "unknown") — those are called out explicitly and escalated to `PJ-xxx` in `PJ_findings.md` only when they add something none of the 90 existing findings already states.

---

## PJ-J1 — Onboarding → Account Creation

**Golden-rule trace:** Entry (sign-in screen) → consent checkbox → `AuthRepositoryImpl.signUpWithEmail/Phone` → Supabase Auth `signUp` → `auth.users` insert → `on_auth_user_created` trigger → `public.profiles` insert → session → root router → `NiswahHomeShell`/onboarding.

| Step | Code location | What happens |
|---|---|---|
| 1 | `lib/features/auth/presentation/screens/sign_in_screen.dart` `_SignInContentState._agreed` | A local `bool _agreed` checkbox toggles UI only. |
| 2 | same file, `_AuthSheetState._submit()` (lines 585–652) | Calls `repo.signUpWithEmail(...)` / `repo.signUpWithPhone(...)`. **`_agreed` is never read anywhere in `_submit()` or passed to the repository.** |
| 3 | `lib/features/auth/data/repositories/auth_repository_impl.dart:77-104` | `_client.auth.signUp(...)` — Supabase Auth call. On success, inserts into `auth.users` (Supabase-managed). |
| 4 | `supabase/migrations/20260820174500_niswah_production_schema_security.sql:77-87` | `on_auth_user_created` trigger fires `AFTER INSERT ON auth.users`, calling `handle_new_user()`, which inserts `(id, full_name, selected_madhhab)` into `public.profiles` only. |
| 5 | `AuthController.instance.markSignedUp()` (sign_in_screen.dart:641/665) → root router in `main.dart` | Routes to onboarding steps, then `NiswahHomeShell` once Supabase's own auth-state stream fires. |

### Reconciliation

- **UI state:** checkbox appears functional (fills red, shows check icon) — user believes they are gating account creation on consent.
- **Authoritative state:** the checkbox's `bool` is dead weight; `signUpWithEmail`/`signUpWithPhone` never inspect it, so account creation (and the ensuing collection of health/pregnancy/religious/location data across the other 5 journeys) proceeds identically whether `_agreed` is `true` or `false`. **Directly confirms PC-001** — traced here to the exact three lines (585, 616-621, 635) that would have needed a `if (!_agreed) return;` guard and don't have one.
- **`profiles` row:** confirmed created via a real, migrated trigger — this **partially resolves** the "does *a* user table get populated" half of DI-004/UNK-006's open question: yes, `public.profiles` reliably gets a row (assuming the migration was applied — itself covered by UNK-002/ASM-003, still open). **However**, this is not the whole story: `schema.sql` separately defines a second, distinct `public.users` table (not `profiles`) that 14+ other core tables' `user_id` columns FK to, and this audit's own grep of every `.from(...)` call site in `lib/` found **zero** writes to `users` — only to `profiles`. This is the more consequential half of DI-004/UNK-006 and remains genuinely unresolved; it is traced fully in PJ-J2 below and raised as `PJ-001` in `PJ_findings.md` because the *specific mechanism* (which tables it silently breaks, and which historical incident it plausibly already caused) had not been traced end-to-end by any single Wave 1–4 audit.
- **Cross-reference:** ROOT-009 already frames PC-001 as part of a systemic "consent is decoration" pattern (also covering PC-004, PC-005, RD-007) — this trace adds nothing new to that root cause, only confirms it at the code line.

### Verdict: **FAIL**

Consent gating does not exist as a functioning control (confirmed, not inferred) — this alone is launch-blocking per PC-001/ROOT-009 (already OPEN, already BLOCKER-class, correctly propagated). Downstream profile creation is at least traceable to a real trigger, but whether it — or any of the 7+ later migrations that assume a *different*, never-populated `users` table — actually executes successfully against the live project remains an open critical unknown (ASM-001/ASM-003, UNK-002/006/007).

---

## PJ-J2 — Daily Cycle/Haid Logging (core value proposition)

**Golden-rule trace:** Entry (cycle tracking screen, log-entry sheet) → `CycleTrackingViewModel.saveLog()` → `MadhhabRuleEvaluator.evaluate()` (fiqh-state, pure/local) → `CycleTrackingRepositoryImpl.saveCycleLog()` → local upsert (always succeeds) → remote `cycle_entries` upsert (may fail) → UI.

| Step | Code location | What happens |
|---|---|---|
| 1 | `lib/features/cycle_tracking/presentation/viewmodels/cycle_tracking_view_model.dart:91-106` | `saveLog()` builds a `CycleLog` and calls `_repository.saveCycleLog(log)`, then unconditionally calls `loadLogs()`. |
| 2 | `lib/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart:115-127` | `saveCycleLog()`: `await _localDataSource.upsert(log)` (always succeeds, on-device only) **then** `try { await upsertCycleLog(log); } on NetworkFailure catch (error) { debugPrint(...); }` — the remote failure is caught and only `debugPrint`'d. **No exception propagates to the caller under any remote-failure condition.** |
| 3 | same file, `upsertCycleLog()` (130-148) | `await client.from('cycle_entries').upsert(payload, onConflict: 'id')`. On `PostgrestException`, throws `NetworkFailure` — which step 2 immediately swallows. |
| 4 | `loadLogs()` (69-89) | Calls `_repository.getCycleLogs()`, which (lines 26-81) merges local + remote, and on any remote read failure **returns local-only silently** (`catch (_) { return localLogs; }`). The UI's list is repopulated from this merged/local set, so the just-saved entry always appears. |

### Where fiqh state is computed

`MadhhabRuleEvaluator.evaluate()` (`lib/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart`) is a pure function over already-known bleeding duration/history — it runs entirely client-side/in-memory and never touches the network. It cannot fail due to any backend issue; its output is only as good as the log history it's given, which is the merged local+remote set from step 4.

### The exact mechanism behind the documented incident (new evidence traced this wave)

- `cycle_entries` has **no `CREATE TABLE` anywhere in tracked migrations** (confirmed: only two `ALTER TABLE cycle_entries ...` migrations exist — `20260825210000` and `20260826090000` — never a `CREATE`). This directly matches DI-001's "10 of 19 tables have no CREATE TABLE."
- Migration `20260826090000_cycle_entries_app_columns.sql` contains a direct, dated admission: *"every real cloud write to cycle_entries has been failing with 'column does not exist' since before this table was ever successfully written to from the app. This is why logging a haid entry or tapping 'End Haid' on the dashboard silently fails."* This is the documented incident DI-002/RR-001/OB-006 all already reference — this trace locates its exact root cause (`flow`, `cycle_day`, `symptoms`, `sync_status` columns missing) and its purported fix (additive `ALTER TABLE` statements).
- **What the fix did not address:** `schema.sql`'s `cycle_entries` definition (the closest available approximation of the live table, per the same migration's own comment that "the live table only had the schema.sql-documented columns") declares `user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` — the bare `users` table, not `auth.users`, not `profiles`. Per PJ-J1's trace, no code path ever inserts into `users`. If this FK is live (plausible — nothing in the tracked migration history ever changes it), **every remote `cycle_entries` upsert still fails today**, for a different reason than the one the documented fix addressed, via the identical silent-swallow code path (step 2 above). OB-006's finding that "the exact DI-002 incident code path is unchanged since the documented incident" is corroborated and sharpened by this trace: the *symptom* (silent failure) is unchanged because remediation only ever touched one of at least two independent causes of it.

### Reconciliation

- **UI state:** Always "success." The log appears in the list immediately (local echo), the fiqh-state badge updates correctly (pure computation), no error, no retry prompt, no indication that a network operation happened or failed at all.
- **Authoritative downstream state (`cycle_entries` table):** Unverifiable without live DB access (per this audit's restriction) but plausibly still failing 100% of the time for the FK reason above, on top of RR-001's independently-confirmed absence of any retry/backoff. If the FK issue is real, this is not a transient/occasional failure — it is systemic and permanent for every remote write, exactly matching the master register's characterization of DI-002 as "silent write failures... already caused real production incidents."
- **Data-loss consequence:** because the *local* device is authoritative for the UI, a user who reinstalls the app, changes phones, or clears app storage loses her entire haid history with no warning at any point in that chain — not at logging time, not at reinstall time. This exact compounding (silent-write + local-only source of truth + no cross-device sync + no warning anywhere) had not been traced as a single continuous failure chain by any Wave 1–4 audit individually; it is raised as `PJ-002`.

### Verdict: **FAIL**

The journey does not reach its authoritative downstream state reliably (per direct migration-comment evidence of the original incident, and per this trace's static argument that a second, independent FK-based cause of the same failure is very likely still live). The UI's apparent success is not evidence of a completed journey — this is exactly the condition the template's Golden Rule exists to catch.

---

## PJ-J3 — Dr. Niswah AI Chat (red-flag / urgent message)

**Golden-rule trace:** Entry (chat screen, send) → client-side red-flag check (independent) → `ChatViewModel.sendMessage()` → `DrNiswahBackendService.send()` → edge function `dr-niswah-chat` → server-side red-flag check → `flagged_conversations` insert (service role) → `chat_messages` user insert (RLS) → Gemini call → `chat_messages` assistant insert → response → client banner/notification.

### Server side (`supabase/functions/dr-niswah-chat/index.ts`)

Order of operations inside the single `Deno.serve` handler (lines 200-309), **all inside one try/catch with an unlogged `catch (error)` at the very bottom returning HTTP 500** (confirms OB-004's exact framing):

1. Auth check (401 if missing/invalid).
2. `detectRedFlags(content)` — server-side keyword match, independent of Gemini (line 241-242).
3. **If urgent:** `serviceClient.from('flagged_conversations').insert({...})` (lines 246-254) — uses the **service role**, bypassing RLS, but the table's own FK is `user_id UUID NOT NULL REFERENCES users(id)` (confirmed in `20260824120000_dr_niswah_flagged_conversations.sql:8`). Per PJ-J1/PJ-J2's finding that `users` is never populated by any code path, **this insert plausibly fails with an FK violation on every single urgent message, for every user** — and because nothing here is individually try/caught, that exception propagates straight to the function's outer catch, producing an unlogged 500 **before the user's own message or the Gemini call ever happen.**
4. `userClient.from('chat_messages').insert(...)` for the user's own message (line 256) — also FKs to `users(id)` (`20260824115900_dr_niswah_chat_threads.sql:33`) — same plausible failure mode, reached only if step 3 didn't already throw.
5. `callGemini(...)` (line 270) — hits `GEMINI_ENDPOINT = 'https://generativelanguage.googleapis.com/v1beta/interactions'` with a custom `{model, input, system_instruction}` body shape. This is the literal code ROOT-001/AB-001/CQ-010 already flag as a likely-hallucinated, non-standard Gemini REST shape — cited, not re-derived. On failure, `reply` becomes an empty string or a generic Arabic "couldn't get a reply" string (line 271-275) — this failure path *is* individually try/caught (unlike steps 3-4) so a Gemini-only failure does not 500 the whole function.
6. `chat_messages` assistant-message insert (line 283-293) — same FK dependency as step 4.

### Client side (`lib/features/ai_assistant/presentation/viewmodels/chat_view_model.dart:224-269`)

- `isRedFlagLocally = DrNiswahRedFlags.matches(content)` is computed **before** calling the backend, entirely client-side, independent of network/DB state. This is the "positive control" the assignment brief references, confirmed exactly: **if `DrNiswahBackendService.send()` throws for any reason** (network error, Gemini failure, or — per this trace — a `flagged_conversations`/`chat_messages` FK violation surfacing as the edge function's unlogged 500), the `catch (error)` block at line 252 checks `isRedFlagLocally`; if true, it appends a local, ephemeral urgent-banner `ChatMessage` to the in-memory `messages` list and fires `_notifyUrgent()` (a real local push notification + a `NotificationLogController` feed entry, lines 38-66) — then `rethrow`s, which the outer `sendMessage()` catch (line 213) turns into a set `errorMessage`.

### Reconciliation — "what actually happens if Gemini is broken AND the DB insert fails simultaneously" (the assignment brief's exact question)

1. User sends a message containing a red-flag keyword (e.g. "نزيف" / "bleeding").
2. Server: red-flag detected → `flagged_conversations` insert attempted → **fails on FK violation** (per the traced mechanism above) → function throws → unlogged 500 returned. **No `chat_messages` row for the user's message was ever written either**, because the function threw before reaching that insert.
3. Client: `DrNiswahBackendService.send()` sees `response.status != 200`, throws `StateError`. `_sendViaDrNiswahBackend`'s catch fires: `isRedFlagLocally == true` → **the user sees the urgent banner appear in the chat, and a local push notification fires.** From the user's point of view, the safety-critical path worked — she got a clear, immediate "contact your doctor now" message and a notification.
4. Simultaneously, `errorMessage` is also set on the view model (line 214, reached via `rethrow`) — depending on how the chat screen renders `errorMessage` (a banner, a snackbar, etc.), the user may see a *second*, contradictory signal (a generic error) layered on top of the reassuring urgent banner in the same screen at the same time. This specific UI-state contradiction — a correctly-firing safety banner rendered simultaneously with a generic "something went wrong" error from the same failed request — was not identified by any prior single-domain audit and is raised as `PJ-003`.
5. **Authoritative state:** `flagged_conversations` has **zero** row for this event (audit trail — the entire reason this table exists — completely absent). `chat_messages` has **zero** row for either the user's original urgent message or the local banner (the banner was `messages = [...messages, bannerMessage]` in-memory only — it is never sent through `_repository.sendMessage()`, unlike the direct-Gemini fallback path, which *does* attempt to persist its banner in a fire-and-forget `unawaited(...)` block at lines 306-319). **If the user closes and reopens the thread, or reinstalls, the entire urgent exchange — including the fact that she reported a red-flag symptom at all — vanishes with no trace anywhere**, client or server. This directly reconciles and sharpens OB-004 (which correctly identified the *audit-log insert* as unguarded and unlogged, but did not trace that the same failure mode also silently discards the user's *own message content*, not just the log entry) and is raised as `PJ-004`.

### Reconciliation of ROOT-001 specifically

If ROOT-001 is confirmed true live (Gemini endpoint shape is wrong), step 5 above (`callGemini`) fails on every single call, for every feature. Because that failure *is* individually caught inside `callGemini`'s caller, a non-urgent ordinary message still gets a generic Arabic fallback string persisted as the assistant reply (line 271-275) rather than a hard failure — meaning **the AI chat feature would appear to work today** (every message gets *some* reply) even if 100% of Gemini calls are failing, exactly matching OB-003's finding that this would be invisible in any log/dashboard. This is the master register's own conclusion; this trace confirms the specific line of code that produces the misleadingly-benign fallback text.

### Verdict: **FAIL**

For the specific safety-critical scenario in the assignment brief (Gemini broken AND DB insert failing together), the client-side positive control (AB's finding) genuinely works and the user is not left without a warning — but the two things this journey exists to guarantee for a health/pregnancy app — a durable clinical audit trail and a persisted, retrievable message history — both silently fail with zero server-side logging (OB-004, confirmed) and, per this trace, zero client-side persistence fallback either (new: PJ-004).

---

## PJ-J4 — Private Messaging

**Golden-rule trace:** Entry (community/profile → "Messages") → repository resolution (real vs. mock) → `getOrCreateConversation` → `sendMessage` (RLS INSERT) → `markMessagesAsRead` (RLS UPDATE, SEC-004 gap) → Realtime subscription.

### Repository resolution — the exact CQ-007 trigger mechanism

Unlike what the locator (`lib/features/private_messaging/private_messaging_locator.dart`) alone would suggest (it only checks `NiswahSupabase.clientOrNull == null`, i.e. whether the SDK itself ever initialized), the **actual call sites** re-derive the fallback condition independently and more dynamically:

- `lib/features/community/presentation/screens/community_board_screen.dart:99-103`: `if (_currentUserId == null) return MockPrivateMessagingRepository(currentUserId: 'You');`
- `lib/features/auth/presentation/screens/profile_screen.dart:417-421`: `final userId = NiswahSupabase.clientOrNull?.auth.currentUser?.id; if (userId == null) return MockPrivateMessagingRepository(...);`

Both re-check `auth.currentUser?.id` **live, at the moment the Messages screen is opened** — not once at app start. `lib/core/network/supabase_client.dart:19-27` confirms `clientOrNull` itself stays non-null for the app's lifetime once `Supabase.initialize()` succeeds once; it is `auth.currentUser` — the live session state — that can independently become null later (token refresh failure, revoked refresh token, manual sign-out elsewhere) without `clientOrNull` ever changing.

### Reconciliation — "under what realistic condition would a user hit demo-mode unexpectedly" (assignment brief's exact question)

A fully signed-in, actively-using user whose Supabase session's refresh token silently fails or expires (e.g. device offline long enough that `autoRefreshToken` cannot renew before expiry, or the refresh token was revoked — none of RR-001's retry/backoff exists to recover this) will have `auth.currentUser` become `null` at the SDK level. The **next time** she opens Messages, both call sites above see `userId == null` and **silently substitute `MockPrivateMessagingRepository`** — a fully-functional-looking UI populated with fabricated demo conversations, with **no error, no "you've been signed out" prompt, and no visual distinction from her real inbox**. Any message she "sends" in this state goes nowhere (mock repository, in-memory only) and any real messages waiting for her are invisible. This concrete trigger condition — a *live*, per-screen-open session check, not a static init-time one — is more specific than CQ-007's original framing ("session drop... not just deliberate guest browsing") and is raised as `PJ-005`.

### RLS / SEC-004 trace

`supabase/migrations/20260822210000_private_messaging.sql:85-91`:
```sql
CREATE POLICY "Recipients can mark messages as read" ON private_messages
  FOR UPDATE USING (is_conversation_participant(conversation_id) AND auth.uid() <> sender_id)
  WITH CHECK (is_conversation_participant(conversation_id) AND auth.uid() <> sender_id);
```
Confirmed row-scoped, not column-scoped: any recipient satisfying the `USING`/`WITH CHECK` predicate may `UPDATE ... SET content = '...', sender_id = '...'` on that row via a direct PostgREST call, not just `is_read`. The app's own client code (`lib/features/private_messaging/data/repositories/private_messaging_repository.dart:129-145`) only ever sends `{'is_read': true}` — the app itself never exploits this — but the RLS policy provides no defense against a modified client or direct API call. Confirms SEC-004 exactly at the policy definition.

### DI-003 (TOCTOU) trace

`private_conversations` has `CONSTRAINT unique_pair UNIQUE (participant_one, participant_two)` (ordered-pair unique) — `getOrCreateConversation` (`private_messaging_repository.dart:65-98`) does a `SELECT ... OR (and(...),and(...))` read-then-insert with **no transaction/upsert atomicity**; two near-simultaneous "start conversation" taps by the same pair of users (client A initiates while client B, independently, also opens the same target user's profile and taps "message") can both pass the `existing == null` check before either INSERT commits, producing two separate conversation rows for the same pair with messages split across both. Confirms DI-003 at the exact repository method.

### Verdict: **PARTIAL**

Core send/read logic reconciles correctly when a session is genuinely active (auth-scoped RLS, correctly-participant-checked policies for read/insert). But: (a) the demo-mode fallback can trigger silently and repeatedly during normal use, not just for guests (new: PJ-005); (b) SEC-004's RLS gap and DI-003's race are both real and unremediated (cited, not re-derived); (c) there is no session-expiry UX anywhere in this journey (template §25's Session Expiry Test) — the user is never told her session died, she is just silently shown fake data.

---

## PJ-J5 — Doctor/Husband PDF Report Generation & Export

**Golden-rule trace:** Entry (profile → "Doctor's Report") → parallel repository reads (cycle, pregnancy, wellbeing, flagged conversations) → `DoctorReportInsightsEngine.analyze()` (pure) → `DoctorReportPdfBuilder.build()` (pure, main isolate) → `PdfPreview` widget → OS share sheet.

| Step | Code location | What happens |
|---|---|---|
| 1 | `lib/features/doctor_report/presentation/screens/doctor_report_screen.dart:73-118` | `_generate()` awaits, sequentially: `_cycleRepository.getCycleLogs(limit: 1000)`, `_pregnancyRepository.getForUser(userId)`, `_wellbeingRepository.getLogs(...)`, `_flaggedConversationsRepository.getRecent(since: ...)`. |
| 2 | `lib/features/doctor_report/domain/services/doctor_report_insights_engine.dart` | Pure composition of `FiqhReportInsightsEngine`, `WellbeingInsightsEngine`, `CycleSymptomDecoder` — no I/O, cannot itself fail from a backend issue. |
| 3 | `lib/features/doctor_report/presentation/pdf/doctor_report_pdf_builder.dart` (via `printing` package) | Runs on the **main isolate** (PF-003, cited not re-derived) — blocks the UI thread during generation, mitigated only by the existing loading state. |
| 4 | `PdfPreview` widget → OS share sheet | User exports/shares the finished PDF. |

### Reconciliation — does this journey depend on already-broken pieces?

- **Cycle data (step 1a):** `getCycleLogs()` is the exact method traced in PJ-J2 that silently degrades to **local-device-only** data on any remote failure. A report generated from a fresh install, a different device than where entries were logged, or after any of PJ-J2's plausible FK-violation failures, will **silently omit cycle history that the user believes was saved** — the PDF looks complete and professionally formatted with no indication anything is missing. This is a direct, mechanical compounding of DI-002/PJ-002 into a document a real doctor will read and may act on.
- **Flagged conversations (step 1d):** `FlaggedConversationsRepository.getRecent()` (`lib/features/doctor_report/data/repositories/flagged_conversations_repository.dart:23-47`) treats "0 rows" as a normal, successful, silent result (by design — its own doc comment says "a signed-out user is a normal, silent empty result, not an error"). Per PJ-J3's trace, if `flagged_conversations` inserts are failing on the `users(id)` FK, this table is **permanently empty for every user regardless of how many real red-flag messages were sent** — the report's red-flag section is not just occasionally incomplete, it is **structurally guaranteed to always read as "no concerns flagged,"** with a query that returns successfully (0 rows is valid), so no exception, no error state, nothing for `_generate()` to catch even if it tried. This is the single most consequential compound finding of this audit and is raised as `PJ-006` — a doctor's report specifically designed to surface safety-relevant red-flag history is not merely occasionally wrong, it is architecturally incapable of ever containing that data given the current, plausible FK-population gap.
- **AI-derived content:** No Gemini-generated text reaches this report anywhere — `recentFlags` carries only keyword-matched category labels and a raw message excerpt (server-side, deterministic keyword match, not an LLM output) and the rest of the report is entirely computed from structured data via pure, already-unit-tested engines. **ROOT-001 does not directly affect this journey's content correctness** — a useful negative finding, since the assignment brief specifically asked this to be checked.

### Verdict: **FAIL**

The report-generation mechanics themselves (steps 2-4) work correctly and deterministically off whatever data they're handed. The journey fails at the reconciliation the template's Golden Rule demands: the document's two safety-relevant sections (cycle/haid history, red-flag concerns) are silently sourced from data that this audit's own tracing shows is plausibly never reliably persisted server-side, with **zero** indication anywhere in the generated PDF, the loading UI, or any log that the report may be incomplete.

---

## PJ-J6 — Prayer Time Tracking with Location

**Golden-rule trace:** Entry (prayer tracking screen) → `PrayerLocationController` (permission → GPS fix → persist) → `adhan_dart` calculation (pure, local) → display → `NotificationService` scheduling (may silently no-op).

### Location (positive control, confirmed)

`lib/core/preferences/prayer_location_controller.dart:111-133` — `useDeviceLocation()` checks `Geolocator.isLocationServiceEnabled()`, requests permission if needed, throws typed `LocationServiceDisabled`/`LocationPermissionDenied` exceptions rather than failing silently (explicitly documented in the source as replacing an earlier silent-no-op bug), persists the resolved coordinates to `SharedPreferences`, and exposes a safe `resolved` getter that never returns null (defaults to Mecca). This is exactly the well-designed pattern the assignment brief flags as a positive control — confirmed at the code level, no gaps found.

### Calculation

Prayer times are computed via `adhan_dart` from the resolved coordinates — entirely local/offline, no backend dependency, cannot fail due to any Supabase/Gemini issue traced elsewhere in this audit. Displayed times are reliable given a correct location.

### Notification scheduling — where it actually breaks

`lib/core/services/notification_service.dart`:
- `initialize()` (26-62) sets `_initialized = true` **only if every step above it completes without throwing** — and nothing in this method is wrapped in its own try/catch.
- `scheduleAt()` (112-127), `scheduleDaily()` (131-162), `cancel()` (164-167) **all** begin with `if (!_initialized) return;` — a silent no-op, confirmed exactly as RR-003 describes, at every one of the three public scheduling methods.
- `main.dart` calls `await NotificationService.instance.initialize();` inside the app's top-level `runZonedGuarded` block (RR-002/OB-002, cited not re-derived). If `initialize()` throws for any reason (a platform-channel exception, a plugin registration failure — plausible on either iOS or Android across the diversity of real devices) that exception is swallowed by the app-wide handler via `debugPrint` only, `_initialized` never becomes `true`, and **every subsequent call to `scheduleAt`/`scheduleDaily` for the rest of the app's process lifetime becomes a permanent, silent no-op** — with no error surfaced at the point of scheduling, no error surfaced at startup, and no way for the user or the team to ever know.

### Reconciliation

- **UI state:** Prayer location setup completes successfully and is confirmed persisted; prayer times display correctly and immediately.
- **Authoritative downstream state (whether a notification will actually fire at prayer time):** entirely contingent on whether `NotificationService.initialize()` happened to succeed at this specific app launch, which is never re-checked, never retried, and never surfaced to the user in any way — she has no way to know, from anywhere in the app, whether her prayer reminders are live or permanently dead. This directly reconciles the assignment brief's exact question: **the well-designed location layer and the silently-failing notification layer are two independent subsystems chained together with no verification between them** — a correct location does not imply a working reminder, and the app gives no signal either way.

### Verdict: **PARTIAL**

Location resolution and time calculation are reliable (positive control confirmed). Notification delivery is not verifiably reliable — it depends on an unretried, unlogged, silently-failable one-time init flag with no user-facing or team-facing signal of its state, exactly as RR-003 already describes, now traced to the specific three call sites where the silent no-op occurs.

---

## Cross-Journey Reconciliation Summary

| Journey | UI | Backend/DB (authoritative) | External integration | Notification | Observability of failure | Verdict |
|---|---|---|---|---|---|---|
| PJ-J1 Onboarding | Success shown | `profiles` likely populated (trigger confirmed); `users` (schema.sql's FK target for everything else) never populated by any code path | Supabase Auth | N/A | None (PC-001 consent gap invisible by design) | **FAIL** |
| PJ-J2 Cycle logging | Always success (local echo) | Plausibly 100% remote-write failure (FK-to-empty-`users`), silently swallowed | N/A | N/A | None — OB-006 confirmed unchanged | **FAIL** |
| PJ-J3 Dr. Niswah chat (urgent) | Urgent banner + notification fire correctly (positive control) | `flagged_conversations` + `chat_messages` plausibly never persist the urgent exchange at all | Gemini (ROOT-001 unresolved) | Local notification fires correctly | Zero server-side logging (OB-004); zero client-side persistence of the banner itself (new) | **FAIL** |
| PJ-J4 Private messaging | Looks identical whether real or demo data | Real path: correctly RLS-scoped but SEC-004 column-gap and DI-003 race both live | N/A | Realtime subscription (untested live) | Silent demo-mode substitution on session death, no error | **PARTIAL** |
| PJ-J5 PDF report | Always renders a complete-looking document | Silently sourced from possibly-incomplete cycle data and a structurally-always-empty flagged-conversations section | None (no AI content in this journey) | N/A | None — 0 rows reads as "no concerns," not as an error | **FAIL** |
| PJ-J6 Prayer tracking | Location/times always correct | Notification scheduling silently no-ops if init failed, unretried | `adhan_dart` (local, reliable) | Unverifiable — may never fire | None (RR-003 confirmed unchanged) | **PARTIAL** |

**0 of 6** critical journeys reach a verified PASS. 4 FAIL, 2 PARTIAL, 0 PASS, 0 UNKNOWN (every journey was traceable to a definite code-level conclusion even without live execution, though several conclusions are appropriately flagged 🟨 Likely rather than 🟥 Confirmed pending live DB/network verification per ASM-001/ASM-002/ASM-003).
