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
| IMPLEMENTED — UNVERIFIED | 171 |
| IMPLEMENTATION REQUIRED | 23 |
| BLOCKED — EXTERNAL EVIDENCE REQUIRED | 77 |
| NOT ASSESSED | 29 |
| OUT OF SCOPE — EXPLICIT DECISION | 0 |

**61 of 300** journeys have their outcome demonstrated by a named automated
test. None is VERIFIED, because 159 journeys also need a signed iPhone and
signed Android run, and none has been recorded.

## Evidence by dimension

| Dimension | Pass | Partial | Required, not run | Blocked |
|---|---|---|---|---|
| Automated | 61 | 94 | 130 (none yet) | – |
| Staging integration | 12 | 7 | 1 | – |
| Signed iPhone | 0 | – | 159 | – |
| Signed Android | 0 | – | 159 | – |
| Specialist (medical / fiqh) | 0 | – | – | 39 |

## Critical and high gaps (Included scope)

| Journey | Gap |
|---|---|
| NJ-183, NJ-184 (Critical) | Community has no block or report. Conditional on the launch-scope decision. |
| NJ-013 | No recovery of an in-progress entry after session expiry. |
| NJ-018, NJ-126 | Approximate dates need a clinical prediction policy (PT-003). |
| NJ-074 | Recovery link opened while another account is signed in. |
| NJ-232 | No account check on a running export. |
| NJ-147 | No remote fiqh kill switch (PT-196). |

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
