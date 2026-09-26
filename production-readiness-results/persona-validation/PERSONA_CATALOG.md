# Persona Catalog — Niswah Acceptance Testing

Every persona is a Flutter `integration_test` run against the **real compiled
app** and a **disposable local Supabase** (never production — the kill switch
refuses anything else), reporting one structured `PASS/FAIL/BLOCKED/SKIPPED`
result that `scripts/verify_acceptance_results.py` judges. "PASS" requires
state-changing assertions (UI **and** persisted state), not screenshots.
A unit or widget test is not a persona and is not counted here.

Platforms: **iOS** = iOS Simulator (local); **Android** = Pixel_8 emulator
(local, hardware GPU) and GitHub-hosted API-34 emulators (sharded run
36114358622, 21/21 PASS). A persona marked iOS-only has not been run on
Android yet.

## Menstrual-data personas (charter A–J)

| ID | Persona | iOS | Android | Notes |
|---|---|---|---|---|
| A | New user, unknown Madhhab, zero history | PASS | PASS | (P0/B setup path) |
| B | First bleeding episode, one observation | PASS | PASS | D-001 found + fixed |
| C | Active episode, multiple same-day observations | PASS | PASS | real DB rows verified |
| D | Missed check-ins, later backfill | PASS | PASS | real date picker |
| E | Incorrect entry, correction, revision history | PASS | PASS | D-002 found + fixed |
| F | Offline save -> pending -> reconnect -> replay | PASS | PASS | real backend outage; exactly 1 episode + 1 observation (repo AND host SQL); D-006 found + fixed |
| G | Changing/disabling daily reminders | PASS | PASS | toggle only; time change = REM-02 PARTIAL |
| H | Returning user with real historical data | PASS | PASS | real dates + baseline values |
| I | Degraded/uncertain evidence | PASS | PASS | `flow=uncertain` daily check-in (the schema CHECK-constrains every enum, so a malformed row cannot be injected — a stronger guarantee than assumed) |
| J | Switching between two accounts | PASS | PASS | no trace of account 1 |
| W | Six-surface walkthrough (one account, one shared history) | PASS | PASS | FAILED before D-004 |

## Phase 3 breadth personas

| ID | Covers | iOS | Android |
|---|---|---|---|
| P0 | Build identity / backend banner | PASS | PASS |
| Batch1 | Auth error paths (AUTH-02/06), MENS-03, PRAY-01, PROF-04, PREG-01/02 | PASS | PASS |
| Batch2 | Explicit onboarding answers: Madhhab, married, city, still-bleeding, Anonymous Mode | PASS | PASS |
| Batch3 | TTC (unmarried restriction, married chance, off), pregnancy, birth -> Nifas, Nifas end | PASS | PASS |
| Batch4 | Anonymous Mode, Privacy Policy, **account deletion** (server rejects credentials; 0 orphans) | PASS | PASS |
| Batch5 | Community: create, anonymous/named, search, like, detail, delete own post (server rows) | PASS | PASS |
| Batch6 | Wellbeing check-in (+server row), Fiqh/Doctor/Wellbeing/Husband reports, JSON export | PASS | PASS |
| Batch7 | AI assistants degrade honestly with the AI backend unreachable | PASS | PASS |
| Batch8 | Author preview, private messaging between two accounts, unread -> read, history, RLS vs a third account | (runs in suite) | PASS |
| L1 / L2 | Location permission granted / denied (host sets the OS permission) | PASS | (in suite; emulator geo-fix path) |
| M | Guided Madhhab suggestion never assumed (confirm stores it; decline stores nothing) | PASS | (in suite) |
| O | Real outage: onboarding save retry (ONB-12) + community failure (COMM-10) | PASS | (in suite) |
| R2 | Change the reminder time in the real time picker; persists after reopening (REM-02) | PASS | PASS |
| AR1 | **Live Arabic RTL journey** incl. 200% text scale, RTL controls, no English leaks | PASS | PASS |
| AUTH08 | Email confirmation (outside the main suite: needs a confirmations-ON backend; `scripts/run_auth08_confirmations.sh`) | PASS | — |

"(in suite)" = part of the current full-suite run recorded in
`TEST_EXECUTION_REPORT.md`; that report states which final results exist.

## Not personas (recorded so nothing is silently skipped)

- Phone OTP / Google sign-in: BLOCKED — need real providers.
- Real AI answers / citations / history: BLOCKED — need a model backend and
  qualified content review; only transport + honest failure is claimed.
- Physical-device gaps: see `DEVICE_ONLY_GAPS.md` (separate E4 gate).
- Unreachable features (no navigation path): see `DEFECT_REGISTER.md` F-001.
