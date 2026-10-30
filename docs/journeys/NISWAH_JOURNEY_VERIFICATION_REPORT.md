# Niswah 300-journey verification report

As of 2026-10-29. Generated counts come from
`python3 scripts/journey_register.py`, which builds
`docs/journeys/NISWAH_JOURNEY_COVERAGE.csv` from the source register and
fails if any NJ id is missing, if a row claims automated evidence without
naming it, or if a row is VERIFIED without every required dimension passing.

A green test suite does not verify every journey. Each journey records
automated, staging, signed-iPhone, signed-Android and specialist evidence
separately.

## Status

| Status | Journeys |
|---|---|
| VERIFIED | 0 |
| IMPLEMENTED — UNVERIFIED | 181 |
| IMPLEMENTATION REQUIRED | 24 |
| BLOCKED — EXTERNAL EVIDENCE REQUIRED | 94 |
| NOT ASSESSED | 0 |
| OUT OF SCOPE — EXPLICIT DECISION | 1 |

**67 of 300** journeys have their outcome demonstrated by a named automated
test. None is VERIFIED, because 170 journeys also need a signed iPhone and
signed Android run, and none has been recorded.

## Evidence by dimension

| Dimension | Pass | Partial | Required, not run | Blocked |
|---|---|---|---|---|
| Automated | 67 | 94 | 107 (none yet) | – |
| Staging integration | 12 | 7 | 1 | – |
| Signed iPhone | 0 | – | 170 | – |
| Signed Android | 0 | – | 170 | – |
| Specialist (medical / fiqh) | 0 | – | – | 40 |

Every one of the 300 journeys is now assessed (2026-10-30). The last 30
were features that do not exist (AI record changes, attachments, import,
history search, a predictions-off setting), which are recorded as
launch-scope decisions rather than built, and a few gaps that are now
IMPLEMENTATION REQUIRED (time capture, notification grouping, recent
authentication before deletion, storage-full saves, export snapshot).

## Critical and high gaps (Included scope)

| Journey | Gap |
|---|---|
| NJ-183, NJ-184 (Critical) | Community has no block or report. rayan decided community ships (2026-10-29); block, report and moderation are being built in a separate thread. |
| NJ-018, NJ-126 | Approximate dates need a clinical prediction policy (PT-003). |
| NJ-147 | No remote fiqh kill switch (PT-196). |
| NJ-237 | Account deletion has no recent-authentication step; policy decision needed. |

Closed in open branches (automated evidence only): NJ-069 confirmation
auto-advance (PR #63); NJ-074 recovery names the account and refuses a save
after an account change, and NJ-232 export discarded on an account switch
including A→B→A (draft PR #65). Screens, sheets and
dialogs opened over home now close on sign-out or account switch. NJ-013:
an unsaved day-log entry is kept for its account and offered back (draft PR #66).

## Sign-up email confirmation (NJ-003..NJ-006, NJ-061, NJ-062, NJ-065, NJ-066)

Implemented on `feat/signup-email-guidance`: the destination address is
shown, the Spam folder is named («البريد غير المرغوب فيه (Spam)»), Resend is
paced by a cooldown and Auth's own rate limit, a wrong address can be
corrected, common domain typos are suggested and never applied silently.
Nothing says the email was delivered; the app only knows the request was
accepted. Real delivery to Gmail, Outlook and iCloud inboxes is an external
check that has not been run.

## Period-tracking register (PT-001..PT-200)

50 VERIFIED, 85 IMPLEMENTED — UNVERIFIED, 32 IMPLEMENTATION REQUIRED,
33 BLOCKED. See `docs/period-tracking/PERIOD_TRACKING_VERIFICATION_REPORT.md`.

## External blockers

- Launch-scope decisions: see `NISWAH_LAUNCH_SCOPE.md`.
- Signed iPhone and Android runs of the device journeys.
- Medical and fiqh specialist review (39 journeys).
- Staging: migration `20261029130000` (PT-002) is not installed; the SQL is
  ready in the staging kit for rayan to run.
