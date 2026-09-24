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

## Live verification performed this wave

| Check | Method | Result |
|---|---|---|
| Correction updates canonical revision chain | Live UI + direct SQL on `bleeding_observations` | PASS — original + correction rows, `supersedes_id` correctly linked |
| Correction updates legacy projection | Live UI + direct SQL on `cycle_entries` | PASS (after D-002 fix) — exactly one row, corrected value |
| Same-day multiple observations (Persona C) persist as genuinely independent rows | Live UI + direct SQL | PASS — two rows, two distinct flow values, no false "latest wins" collapse |
| Dashboard "Today" ring reflects the same episode a fresh Insights/Calendar-tab visit would see | **Not executed this wave** | Insights and the Calendar tab were never opened live this wave (see `COVERAGE_MATRIX.csv`, MENS-10/MENS-11) — this specific pairwise comparison is a real gap, not a claimed PASS |

## What remains unverified

The charter's own six-surface list (Today, canonical calendar, legacy
Calendar tab, Insights, Fiqh/prayer-status, export/report surfaces) was
**not** fully walked live with one shared synthetic history this wave.
What was verified live is the **write path** consistency (does a
correction/second observation reach every table it should) via direct
database checks — which is the mechanism that would cause any
cross-screen contradiction in the first place. The **read-side**
walkthrough (opening all six screens in sequence for one account and
screenshotting/asserting each) was not completed and should be treated
as the next step, not as done.
