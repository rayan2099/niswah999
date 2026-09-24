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

## Summary

| ID | Severity | Area | Status |
|---|---|---|---|
| D-001 | P1 | Menstrual / Fiqh status | Fixed, regression-tested, re-verified live |
| D-002 | P1 | Cross-screen consistency (correction projection) | Fixed, regression-tested, re-verified live against a real database |
| D-003 | P2 | Auth error handling | Fixed, regression-tested |

No P0 defects found. No defects were left open, deferred, or worked
around by narrowing the test oracle.

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
