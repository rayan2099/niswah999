# Cross-Screen Consistency Report — Niswah, PR #4

The charter named four/six surfaces that must never show contradictory
facts about the same real menstrual event: Today dashboard, dashboard
canonical calendar, the main bottom-nav Calendar tab, Insights, Fiqh/
prayer-status surfaces, and export/report surfaces. This report
documents each surface's actual data source (verified by reading the
code, not assumed) and what was found.

## The two data models in this codebase

| Model | Tables | Consumers |
|---|---|---|
| **Canonical** | `bleeding_episodes`, `bleeding_observations` | Today dashboard's ring/status cards, `CanonicalCalendarScreen` (the dashboard's own calendar icon), `CanonicalBleedingStatusResolver` |
| **Legacy** | `cycle_entries` | `CycleTrackingScreen` (bottom-nav "Calendar" tab), `CycleTrackingViewModel`, `InsightsScreen`, `CycleCalculationService` predictions, AI context assembly |

These are **not** two views of one table — they are two separate
tables. `CycleEntriesProjection` (`lib/features/cycle_tracking/data/
repositories/cycle_entries_projection.dart`) is a one-directional
compatibility bridge, documented in
`docs/menstrual-data-integrity-contract.md` §2: every canonical write
also mirrors into `cycle_entries` so the legacy screens keep working
without being rewritten this wave. `bleeding_episodes`/
`bleeding_observations` are the sole source of truth; `cycle_entries`
is a read-compatibility mirror, never independently authored.

## What was found

### 1. A genuine, confirmed defect (now fixed) — see DEFECT_REGISTER.md D-002

`correction_sheet.dart` was the one write path that never called the
projection at all. A correction updated the canonical tables correctly
but the legacy screens would show the pre-correction value forever.
**Fixed and re-verified live** this wave.

### 2. A second-order defect found while fixing the first (now fixed)

Naively projecting a correction under its own new observation id left
**two** `cycle_entries` rows for one logical day (the original and the
correction), which a legacy consumer would render as two independent
same-day reports rather than one corrected fact. Fixed by having a
correction's projection also delete the superseded observation's own
prior `cycle_entries` row. **Re-verified live**, via direct SQL against
a real database: exactly one row remains, showing the corrected value.

### 3. A disclosed, intentional divergence — NOT a defect, but worth
stating plainly

`CycleEntriesProjection.project()` never projects an
`ObservationFlow.uncertain` ("I'm not sure") answer — there is no
factual flow value to represent in the flat legacy model, and the
projection's own doc comment states this is deliberate: inventing a
default would be exactly the fabrication this charter's central
doctrine forbids.

**Consequence, stated as the charter asks**: for a day reported as
uncertain, the canonical Dashboard/Calendar will show "reported as
uncertain," while the legacy Calendar tab/Insights will show **nothing
at all** for that day (no entry). This is a real, live, user-visible
divergence between the two surfaces for the exact same day — it is
disclosed and intentional (documented in the source before this wave
began), not something this wave introduced or is asked to silently
paper over. Whether "nothing shown" vs. "shown as uncertain" is
acceptable for launch is a product decision, not an engineering defect;
it is reported here rather than left undiscovered.

### 4. `CanonicalCalendarScreen` deliberately does not depend on the
projection at all

Its own source comment (`canonical_calendar_screen.dart`, `_onDayTap`):
"A successful save must be visible in the calendar without relying on
the legacy projection — re-fetching canonical data directly is exactly
that guarantee." Confirmed correct by design: the canonical calendar
re-reads `bleeding_observations` directly after every save, so it is
never affected by a projection gap (including the one D-002 fixed) —
only the LEGACY screens were ever at risk.

## Live verification performed

| Check | Method | Result |
|---|---|---|
| Correction updates canonical revision chain | Live UI + direct SQL on `bleeding_observations` | PASS — original + correction rows, `supersedes_id` correctly linked |
| Correction updates legacy projection | Live UI + direct SQL on `cycle_entries` | PASS (after D-002 fix) — exactly one row, corrected value |
| Same-day multiple observations (Persona C) persist as genuinely independent rows | Live UI + direct SQL | PASS — two rows, two distinct flow values, no false "latest wins" collapse |
| **Six surfaces, one account, one shared history** (Today, canonical Calendar, legacy Calendar tab, Insights, Fiqh/prayer status, reports) | `pWalkthrough_six_surface_test` — asserts every surface against the same account | **FAIL before D-004, PASS after** (iOS and Android). Before the fix the legacy Calendar said "Log at least two cycle starts" and Insights said "No cycle history yet" for an account whose onboarding-reported period Today/canonical Calendar already showed. |
| Onboarding-reported period is visible on the legacy screens **without** making `cycle_entries` authoritative and **without** fabricating a daily observation | Widget tests (`cycle_calculation_canonical_episodes_test`, `legacy_screens_canonical_history_test`) + the live walkthrough | PASS — legacy screens read episode start/end dates only; the projection still never writes an `uncertain` flow |
| Offline start, replayed after reconnect, reaches every surface (Today, Fiqh card, legacy model) with no manual refresh | Persona F (iOS + Android) + host SQL | PASS after D-006. Before the fix Today stayed stale and the prayer card kept "Salah is obligatory" for a woman who was bleeding. |
| Account switch leaves no trace of the previous account | Persona J (iOS + Android) | PASS |
| Account deletion removes the account from every table | Batch 4 live deletion + a sweep of every public table with `user_id` | PASS — 0 orphan rows (D-005 fixed) |
| Private messaging: what the sender sees equals what the recipient sees, and a third account sees nothing | Batch 8 (two + one real accounts, RLS) | PASS |
| Language: a live switch English -> Arabic reaches every visible label | Arabic persona scanning each tab | Two leaks found and fixed: D-009 (Arabic in the English pregnancy card), D-010 (legend chips stayed English after a live switch) |

## Contradictions found (all fixed)

1. D-002 — correction not reaching the legacy projection.
2. D-004 — legacy Calendar/Insights denying history the canonical surfaces show.
3. D-006 — stale Today / wrong ruling after an offline replay.
4. D-010 — a live language switch not reaching const chips.

## What remains unverified

- Real-device timing (OS background delivery of reminders) and physical
  screen-reader behaviour — see `DEVICE_ONLY_GAPS.md`.
- Report/export **figures** were confirmed to render for an account with
  real data, but were not compared against an independent oracle.
- The `CycleEntriesProjection` deliberately still never projects an
  `uncertain` flow; the legacy Calendar therefore shows onboarding-reported
  periods as "Reported period" rows/timing, not as coloured daily flow.
  That is the intended, non-fabricating behaviour.
