# Persona Catalog — Niswah Acceptance Testing

Personas A–J are the charter-mandated menstrual-tracking personas.
Personas K+ extend into the broader product surface, added this wave to
begin (not complete) the Section 4 sweep. Each entry states what was
actually executed, on what evidence level, and what remains.

| ID | Persona | Executed? | Evidence level | Result |
|---|---|---|---|---|
| A | New user, unknown Madhhab, zero history | Yes | E2 live (iOS Simulator, real screens) | **PASS** |
| B | First bleeding episode, one observation | Yes | E2 live | **PASS** (1 defect found+fixed — see DEFECT_REGISTER.md D-001) |
| C | Active episode, multiple same-day observations | Yes | E2 live + real DB verification | **PASS** |
| D | Missed check-ins, later backfill | Yes | E2 live (real Material date picker, keyboard-entry mode) | **PASS** |
| E | Incorrect entry, correction, revision history | Yes | E2 live + real DB verification | **PASS** (1 defect found+fixed — see D-002) |
| F | Offline user, pending observation, recovery | Not re-run live this wave | E2/E3 — cited from existing `test/pending_bleeding_operation_store_test.dart` (28 tests, all 4 operation types, passing) | **PASS (existing suite)** — no NEW live-device airplane-mode run this wave |
| G | Changing/disabling daily reminders | Yes | E2 live (real Notification Settings screen, real toggle) | **PASS** |
| H | Returning user, historical/estimated/predicted data | **Not attempted** | — | **NOT ATTEMPTED** |
| I | Unavailable/degraded canonical evidence | Attempted, blocked; cited from existing suite | E2 — cited from `test/dashboard_canonical_degraded_evidence_test.dart` (F5(B)/F5(C), passing) | **BLOCKED live / PASS (existing suite)** — see below |
| J | Switching between two accounts | Yes | E2 live + real DB verification | **PASS** |

**Persona I note**: the original plan was to insert a row with a
deliberately unparseable `source` value directly via SQL against the
disposable local database, forcing a live `LoadDegraded` read. On
execution, the live database rejected it —
`bleeding_observations_source_check` (and equivalent CHECK constraints
on every other enum column, confirmed via `\d bleeding_observations`)
reject any value outside the exact set the Dart client also accepts.
This is a genuinely stronger data-integrity guarantee than assumed
going in, not a defect — but it means the live-injection approach
cannot produce a real malformed row against this schema. Live
verification for Persona I was not completed this wave; the existing
widget-level coverage (a mocked repository returning `LoadDegraded`/
`LoadUnavailable`, already passing) is the evidence on file.

## Extended (Section 4) personas — first pass only, not a full sweep

| ID | Area | Executed? | Result |
|---|---|---|---|
| K | Auth: sign-up (email) | Yes, as part of every menstrual persona's setup | **PASS** |
| L | Auth: sign-out | Yes (Persona J) | **PASS** |
| M | Auth: network failure during sign-up | Yes (found live, in Persona B's own run) | **PASS (after fix — D-003)** |
| N | Reminders: enable/disable, change time | Yes (Persona G) | **PASS** |

Every other Section 4 area (Onboarding sub-flows beyond the default
path, Prayer/location, TTC, Pregnancy, Nifas, Wellbeing, AI, Community,
Messaging, Reports, Profile/privacy beyond notification settings) is
**NOT ATTEMPTED** this wave. See `COVERAGE_MATRIX.csv` for the
feature-by-feature breakdown and `TEST_EXECUTION_REPORT.md` for the
honest numerator/denominator.
