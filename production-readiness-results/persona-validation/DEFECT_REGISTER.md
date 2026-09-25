# Defect Register — Niswah UI Acceptance Testing, PR #4

Every defect below was found through live interaction with the real,
compiled app on the iOS Simulator (or via direct, independent database
verification of what a live interaction actually persisted) — never
inferred from reading code alone. Each was reproduced, fixed, covered
by a regression test, and re-verified.

## D-001 — P1 — "Unable to verify" shown for a woman's first-ever period

**Found via**: Persona B, live dashboard after Start Bleeding on a
fresh account.

**Symptom**: The dashboard's prayer-status card said "Unable to verify
your tracking data — your prayer obligation can't be confirmed right
now," with a "Try again" button that could never help. Nothing had
failed; there simply wasn't enough recorded history yet to compute a
Fiqh conclusion for a woman on day 1 of her first-ever episode.

**Root cause**: `_FiqhState.evidenceUnresolved` was overloaded to mean
both "a genuine read failure" and "not enough history yet" — two
different facts with the same UI treatment (verification-failure
copy, a retry button).

**Fix**: `lib/features/dashboard/presentation/screens/dashboard_screen.dart`
— new `_FiqhState.insufficientHistory`, with its own honest copy ("Not
enough history yet... keep logging, and ask a trusted scholar if you
need guidance today") and no "Try again" button (there is nothing to
retry).

**Regression test**: `test/parity_today_stepper_consistency_test.dart`
— extended the existing "genuinely insufficient canonical evidence"
test to assert the new copy and the absence of both the old
verification-failure text and the "Try again" button.

**Reverified**: live, Persona B run after the fix — dashboard correctly
shows "Bleeding recorded — Day 1 of this record — Learning your cycle"
and the honest insufficient-history copy, never the failure message.

**Status**: FIXED, committed, regression-tested, re-verified live.

---

## D-002 — P1 — A correction never reached the legacy `cycle_entries`
projection (cross-screen consistency)

**Found via**: Code investigation prompted by the charter's own
cross-screen consistency requirement, then confirmed and iterated live
in Persona E.

**Symptom (part 1, the original gap)**: `correction_sheet.dart` called
`repository.correctObservation(...)` but never called
`CycleEntriesProjection().project(...)` — unlike the Start/Daily-
checkin/Backfill sheets, which all mirror into `cycle_entries` on
success. A correction updated the canonical `bleeding_observations`
table correctly (new row, `supersedes_id` chain) but never touched
`cycle_entries` at all — so the bottom-nav Calendar tab and Insights
(both legacy `cycle_entries` readers) would keep showing the
PRE-correction flow value forever.

**Symptom (part 2, found live after the first fix)**: adding a plain
`project()` call fixed the "never updates" problem but created a new
one — since each observation projects under its OWN id, correcting an
observation left BOTH the original and the corrected row in
`cycle_entries` for the same calendar day, which any legacy consumer
would show as two independent same-day reports rather than one
corrected fact. Live verification (direct SQL against the disposable
test database) caught this: `cycle_entries` had two rows, both showing
the ORIGINAL "medium" value at one point during debugging (a false
alarm from querying the wrong column,`flow_intensity` instead of the
actual `flow` column — corrected once identified), but even after
fixing the query, the real issue — two rows for one logical day — was
confirmed.

**Root cause**: `CycleEntriesProjection` had no concept of "this
projection supersedes an earlier one" — `project()` alone is correct
for a genuinely new, independent fact (Persona C), but wrong for a
correction.

**Fix**:
- `lib/features/cycle_tracking/data/repositories/correction_sheet.dart`
  — corrections now call the projection after a successful save.
- `lib/features/cycle_tracking/data/repositories/cycle_entries_projection.dart`
  — new `projectCorrection(corrected, {required supersededObservationId})`:
  projects the new value, then deletes the superseded observation's own
  prior `cycle_entries` row (via the already-existing
  `CycleTrackingRepositoryImpl.deleteCycleLog`). Removes the row even
  when the correction itself is to "I'm not sure" (nothing new is
  projected, but the old definite value must not keep surfacing
  either).

**Regression tests**:
- `test/cycle_entries_projection_test.dart` — two new tests: a
  correction leaves exactly one row (the corrected value, correct id);
  a correction to "uncertain" removes the superseded row with nothing
  fabricated in its place.
- Live: Persona E re-run end to end after the fix, with independent SQL
  verification (not the app's own read path) confirming exactly one
  `cycle_entries` row for the day, showing "heavy" (the corrected
  value), while `bleeding_observations` correctly retains both the
  original and the correction with the `supersedes_id` chain intact.

**Status**: FIXED, committed, regression-tested, re-verified live
against a real database.

---

## D-003 — P2 — Raw exception (with server host/port) shown to the user
on a network failure during sign-up/sign-in

**Found via**: Persona B/X1, live sign-up attempt against the
disposable local backend before it had finished provisioning.

**Symptom**: The sign-up screen showed the literal exception string,
including the backend's own host and port:
`ClientException with SocketConnection refused (OS Error: Connection
refused, errno = 61), address = 127.0.0.1, port = 55281, uri=
http://127.0.0.1:54321/auth/v1/signup?redirect_to=...`

**Root cause**: `sign_in_screen.dart`'s four `catch (error)` blocks
displayed `error.toString()` verbatim for every failure type, with no
distinction between a genuine server/validation answer (wrong
password, already registered — useful to show as-is) and a pure
connectivity failure (never useful to a user, and here leaking
internal infrastructure detail).

**Fix**: new `lib/core/errors/network_failure.dart` —
`isNetworkFailure(Object error)` classifies connectivity failures
(socket/timeout exceptions and their common string markers) separately
from server/validation responses. All four catch sites in
`sign_in_screen.dart` now show a plain-language, recoverable message
("Couldn't reach Niswah. Check your connection and try again — what
you typed is still here.") for a genuine network failure, and the
original server-message behavior unchanged for everything else.

**Regression test**: `test/network_failure_test.dart` — the exact
string this defect produced, plus typed `SocketException`/
`TimeoutException`, are classified as network failures; real
server/validation strings ("Invalid login credentials", "User already
registered", "Password too short") are not.

**Status**: FIXED, committed, regression-tested.

---

## D-004 — P1 — Calendar/Insights said "no history" for an onboarding-reported period (cross-screen contradiction)

**Found via**: the six-surface acceptance walkthrough (one account, one
shared history), live on iOS.

**Symptom**: canonical surfaces (Today, the canonical Calendar, the
episode history) knew the returning woman's reported period, while the
bottom-nav Calendar said "Log at least two cycle starts" and Insights
said "No cycle history yet" for the same account.

**Root cause**: `record_onboarding_menstrual_history` persists a canonical
episode whose start observation is `flow=uncertain` (flow is never asked in
onboarding) plus a closing `flow=none`. `CycleEntriesProjection` correctly
never projects an uncertain flow, so the legacy `cycle_entries` model had
nothing, and both legacy screens read only that model.

**Fix** (canonical stays authoritative; no fabricated daily row):
`CycleCalculationService.calculate` accepts `CanonicalEpisodeTiming`
(episode start/end **dates** only), merged with log-derived starts (dedupe
within a day, log-derived wins); the legacy Calendar and Insights pass the
canonical episodes in; Insights lists them as "Reported period" rows.
Commit `1686e43`.

**Regression tests**: `test/cycle_calculation_canonical_episodes_test.dart`,
`test/legacy_screens_canonical_history_test.dart`.

**Reverified**: live, six-surface walkthrough (iOS and Android): all six
surfaces agree.

**Status**: FIXED.

---

## D-005 — P3 — `ai_rate_limit_counters` outlived a deleted account (retention/erasure)

**Found via**: the production test-account cleanup analysis, then confirmed
in a local behavioural test.

**Root cause**: `ai_rate_limit_counters.user_id` had no foreign key to
`auth.users`, so `delete_my_account()` (which deletes the auth user and
relies on 27 cascading tables) left the user's counter rows behind.

**Fix**: migration `20260925100000_ai_rate_limit_counters_deleted_with_user.sql`
(trigger on `auth.users` + a one-time orphan cleanup). Commit `1c84e6f`.

**Regression test**: `scripts/check_account_deletion_cascade.sh` (also run
by `scripts/validate_migrations.sh` in CI) + a row in
`scripts/verify_schema_contract.sql`. Live: Batch 4 deletes a real account
in the app; a sweep over every public table with `user_id` finds **0
orphan rows**.

**Status**: FIXED. (The one production test account is a separate,
still-OUTSTANDING operational item — see
`PRODUCTION_TEST_ACCOUNT_CLEANUP.md`.)

---

## D-006 — P1 — After an offline start replayed, Today stayed stale and showed "Salah is obligatory" while bleeding

**Found via**: Persona F executed end to end live (offline save -> pending
-> reconnect -> replay).

**Symptom**: the canonical episode existed after replay, but the dashboard
never refreshed: Today showed no episode and the prayer card kept "Salah is
obligatory" for a woman who was bleeding (a Fiqh-relevant stale window);
the legacy `cycle_entries` model never received the replayed observation
(interactive saves do); a still-open "Saved on device - syncing." sheet
stayed stale.

**Fix**: `reconcilePendingOperations` projects every replayed observation
into the legacy model exactly like the interactive paths and announces
completion via `reconcileCompletions`; the dashboard and the queued
sheets listen. Commit `b9be07d`.

**Regression tests**: `test/bleeding_reconcile_signal_test.dart` + the live
Persona F (asserts pending -> 0, exactly one episode + one observation via
the app's repository **and** independent host SQL, no "Salah is
obligatory", Today synced).

**Status**: FIXED, re-verified live on iOS **and on Android**.

---

## D-007 — P2 — Private-message inbox and chat header displayed the other person's raw account id

**Found via**: Batch 8, two real accounts exchanging messages (live,
Android).

**Symptom**: the conversation title was the other participant's UUID
(e.g. `c68ec844-4381-…`), in both the inbox and the chat header.

**Fix**: `conversationTitle()` shows only a display name the other person
already publishes on a non-anonymous community post
(`fetchDisplayNames`), otherwise a neutral "Private conversation" label —
never an id. Anonymous authors therefore stay anonymous.

**Regression tests**: `test/private_messaging_test.dart` (no id shown; name
shown when published) + live Batch 8 asserts no UUID in inbox/thread.

**Status**: FIXED, re-verified live on Android.

---

## D-008 — P2 — Community composer/feed leaked a raw exception and the backend URL on failure

**Found via**: the real-outage persona (COMM-10), live on iOS.

**Symptom**: a failed publish rendered `ClientException: Connection reset
by peer, uri=http://…/rest/v1/community_posts?select=%2A` inside the
composer (internal URL, table and driver detail shown to the user).

**Fix**: the community view models report the exception through
`AppErrorReporter` and show a localized friendly message
(`communityErrorMessage`).

**Regression test**: `test/community_repository_idempotency_test.dart`
("a failed publish shows a friendly message, not the exception/URL") +
live persona O (no raw leak; retry publishes exactly one post).

**Status**: FIXED, re-verified live on iOS.

---

## Summary

| ID | Severity | Area | Status |
|---|---|---|---|
| D-001 | P1 | Menstrual / Fiqh status | Fixed, regression-tested, re-verified live |
| D-002 | P1 | Cross-screen consistency (correction projection) | Fixed, regression-tested, re-verified live against a real database |
| D-003 | P2 | Auth error handling | Fixed, regression-tested |
| D-004 | P1 | Cross-screen: legacy Calendar/Insights vs onboarding history | Fixed, regression-tested, re-verified live (iOS + Android) |
| D-005 | P3 | Account-deletion retention (`ai_rate_limit_counters`) | Fixed, regression-tested, verified live (0 orphans) |
| D-006 | P1 | Offline replay left Today stale / wrong ruling / legacy unprojected | Fixed, regression-tested, re-verified live (iOS + Android) |
| D-007 | P2 | Messaging: raw account id shown as conversation title | Fixed, regression-tested, re-verified live |
| D-008 | P2 | Community: raw exception + backend URL shown on failure | Fixed, regression-tested, re-verified live |

No P0 defects found. No defect was worked around by narrowing the test
oracle. Open items are **not defects in a fixed sense** but product
findings that need a founder decision — see "Open findings" below.

## Findings that are NOT defects (disclosed, not fixed)

- **`cycle_entries.flow_intensity` always reads 'medium'.** Investigated
  as a possible fourth defect; it is a separate, legacy, always-default
  column distinct from the actively-written `flow` column on the same
  table. Every consumer in this codebase reads `flow`, never
  `flow_intensity` — confirmed via `CycleLog.toJson()`/`.fromJson()`
  and a direct grep. Not user-facing, not touched by this wave. Worth a
  cleanup migration someday, not an acceptance defect.
- **Every enum column on `bleeding_episodes`/`bleeding_observations` is
  now fully CHECK-constrained at the database layer** (`flow`,
  `precision`, `source`, `lifecycle_status`, `continuation_certainty`,
  etc.) — confirmed while attempting to construct a live
  degraded-evidence test case for Persona I. This is a genuinely
  stronger data-integrity guarantee than assumed going into this wave,
  not a gap — but it means Persona I's live-injection approach could
  not produce a real malformed row against this schema; see
  `PERSONA_CATALOG.md`'s own note on Persona I.

## Open findings (need a product decision — NOT fixed, NOT hidden)

- **F-001 (P2) — features that exist in code but cannot be reached by any
  user.** Reference analysis of `lib/` shows no navigation path to:
  `GuidedJourneysScreen`, `ResourceLibraryScreen`, `GhuslGuideScreen`,
  `AccountSettingsScreen`, `settings_screen.dart`, and
  `PrayerTrackingScreen`. Consequence: **prayer logging (PRAY-04,
  `togglePrayerStatus`) is not reachable from the running app**, and the
  Ghusl guide/library/journeys cannot be opened. They are recorded as
  BLOCKED/unreachable (not PASS, not "untested"). Decision needed: wire
  them in or remove them.
- **F-002 (P3) — MSG-06 has no implementation.** There is no delete-
  conversation UI or repository method. Recorded NOT IMPLEMENTED.

## Test-infrastructure findings (not product defects; fixed in the harness)

- The notification continuity test read the real wall clock (18:00 lead
  time + 21:00 catch-up cutoff), so 9 assertions failed depending on the
  hour CI ran. Fixed with one controlled clock (`AppClock.now`), 13 pinned
  local-clock scenarios and a 7-timezone matrix; expected counts unchanged.
- A persona's hard `expect()` crashes the whole binary (use logged
  booleans + `reportResult`); `pumpAndSettle` can hang; paused/hidden
  lifecycle disables frames (dispatch the lifecycle chain back-to-back);
  Android needs one `convertFlutterSurfaceToImage()` per process and a
  GPU-accelerated emulator; a native permission dialog cannot be tapped
  (set OS permission from the host); `.order()` in supabase-dart defaults
  to **descending** (a test bug, not an app bug).
- Disclosure: the D-004 commit (`1686e43`) also contains an unintended,
  whitespace-only reformat of `cycle_segment_planner.dart` and
  `cycle_symptom_decoder.dart`. No behavioural change.
