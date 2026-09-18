# Menstrual Data Integrity & Active Bleeding Journey — Canonical Contract

Status: **living architecture contract**. Established by the Menstrual Data
Integrity & Active Bleeding Journey charter (2026-09-17). Commits A, C, a
hostile-self-review fix pass, B, a Commit D slice, and a PR #4 hardening
pass (below) are implemented on `feat/menstrual-data-integrity` (pushed
to origin, PR #4, draft, unmerged); the rest of this document describes
the target architecture for the commits that follow. Future agents must
treat this as the canonical reference — do not reinvent the taxonomy,
episode model, or provenance rules described here without updating this
document in the same change.

## PR #4 hardening pass — blocker status (2026-09-18)

A critical review found the schema/repository from Commits A/B, though
individually tested, had real architectural gaps once examined as a
whole. Each item below was fixed and verified live against a real local
Postgres reconstruction (inside real transactions, with authenticated-
role/JWT simulation, not superuser) unless noted otherwise. See
`69d7bfc`'s own commit message for the full technical detail of each.

| # | Blocker | Status |
|---|---|---|
| 1 | True idempotency (`client_operation_id`, not mere unique-violation) | **FIXED** — verified: 5 identical retries → 1 row each; different key while open → correct conflict |
| 2 | Atomic episode end (+ closing observation) | **FIXED** — new `end_bleeding_episode` RPC, own idempotency, verified live |
| 3 | Onboarding must not silently lose data on save failure | **FIXED** (explicit recoverable error + retry — the alternative the review itself offered, not the "preferred" local-first/outbox architecture, which remains open) |
| 4 | Provenance must reflect which date was reported, not which screen | **FIXED** — `ObservationSource.classify`, used everywhere a source is set |
| 5 | "Uncertain" must not vacate the one-open-episode slot | **FIXED** — `LifecycleStatus`/`ContinuationCertainty` split, verified live |
| 6 | No unsupported biological hard caps | **FIXED** — DB bounds widened to storage-only (1–365/1–1000), date pickers widened to 100 years, Slider replaced with numeric input |
| 7 | Real timezone identity | **PARTIAL** — `utc_offset_minutes` is now the only field any canonical date math uses (closes the correctness gap); true IANA capture would need a new platform plugin this pass could not verify against a real native build — left open, not claimed done |
| 8 | Episode start facts must not be freely mutable | **FIXED** — column-level `REVOKE`/`GRANT`, verified: direct `start_date` UPDATE returns "permission denied" |
| 9 | Baseline estimates need reproducibility | **FIXED** — append-only history, insert-only RLS |
| 10 | Future-date validation at the canonical write boundary | **FIXED for start/end** (the two RPCs); **not extended** to the plain `addObservation`/`createEpisode` INSERT paths (daily check-ins, onboarding), which remain client-validated only — disclosed gap, not silently assumed covered |
| 11 | End-date UI must know the episode start | **FIXED** — `episodeStartDate` threaded through, unreachable choices disabled not hidden, verified by a widget test |
| 12 | Canonical save must not depend on best-effort projection | **NOT FIXED as a durable outbox** — per the review's own explicit allowance, the PR stays draft and no claim is made that the user-visible save journey is complete until Commit F migrates the dashboard onto canonical data directly |

**A genuine security defect was found and fixed during this pass**, not
merely re-confirmed: `bleeding_observations_check_episode_owner`'s own
internal lookup was itself subject to RLS, which correctly hides another
user's episode from the caller — meaning a real cross-account attempt
evaluated `NEW.user_id <> NULL` (NULL, not TRUE) and silently succeeded.
This was only caught because this pass tested as a real `authenticated`
role rather than the Postgres superuser used to first verify the trigger
in the earlier hostile-review pass. Fixed with `SECURITY DEFINER` +
explicit `search_path`; re-verified live that the same attack now fails
while a legitimate same-owner insert still succeeds.

## Central doctrine (verbatim, non-negotiable)

```
NO FABRICATED HEALTH DATA.
NO SILENT ASSUMPTIONS.
UNKNOWN IS VALID DATA.
ABSENCE OF A RESPONSE IS NOT AN OBSERVATION.
CORRECTIONS MUST PRESERVE HISTORY.
PREDICTIONS MUST BE DISTINGUISHABLE FROM OBSERVATIONS.
FIQH CLASSIFICATION MUST BE DISTINGUISHABLE FROM HEALTH FACTS.
DERIVED VALUES MUST BE REPRODUCIBLE FROM THEIR INPUTS.
USER-SUPPLIED ESTIMATES MUST NEVER BECOME OBSERVED HISTORY.
```

Every decision below exists to satisfy this doctrine, not the other way
around.

## 1. The 7-class data taxonomy

These categories must never silently convert into each other. Provenance
is persisted wherever a value could otherwise be mistaken for a class it
isn't.

| Class | Meaning | Where it lives today |
|---|---|---|
| `USER_OBSERVED` | Reported live, at/near the real event | `bleeding_observations.source = 'user_observed'` (not yet written by any UI — see §7) |
| `USER_REPORTED_HISTORICAL` | Reported after the fact (backfill, onboarding, correction) | `bleeding_episodes`/`bleeding_observations.source = 'user_reported_historical'` — onboarding writes this today |
| `USER_REPORTED_ESTIMATE` | A stated usual duration/cycle length | `cycle_baselines` — never observed history, one row per user, always replaceable |
| `CALCULATED` | Derived from confirmed episodes (cycle length, day-of-cycle) | `CycleCalculationService` |
| `PREDICTED` | A forward projection (next period, fertile window) | `CycleTrackingController.predictNextPeriodStart`, gated by `hasSufficientHistory`/`hasPlausibleAverage` |
| `FIQH_DERIVED` | A Madhhab-specific ruling on top of a raw duration | `MadhhabRuleEvaluator` output (`FiqhCycleState`) |
| `UNKNOWN/UNOBSERVED` | No data, and that absence is itself meaningful | A `null`/`uncertain` value — never backfilled with a guess |

## 2. Source-of-truth architecture

Two tracks, deliberately kept simple rather than forcing a full-codebase
rewrite in one pass (permitted explicitly by the charter's own Section
35, "compatibility adapters ... one-directional/read-only where
practical"):

- **Canonical, forward-looking track**: `bleeding_episodes` and
  `bleeding_observations` (migration
  `supabase/migrations/20260917090000_bleeding_episode_model.sql`, plus
  the `start_bleeding_episode` atomic-start RPC in
  `20260917100000_start_bleeding_episode_rpc.sql`). Every *new* write to
  the menstrual-data model targets these tables — onboarding
  (`BleedingEpisodeRepositoryImpl.createEpisode`) and the dashboard's
  Start/End Bleeding actions (`startEpisode`/`endEpisode`, via
  `lib/.../presentation/widgets/start_bleeding_sheet.dart`) are both live
  today. `cycle_baselines` holds the separate, never-historical estimate
  class.
- **Existing, compatibility track**: `cycle_entries` — untouched schema,
  still read by every existing consumer (`CycleCalculationService`,
  `CycleStatusEngine`, the dashboard ring, `client_fiqh_state_provider`,
  notifications, data export). A `data_provenance` column
  (`legacy_unverified` | `user_observed` | `user_reported_historical`)
  lets a consumer distinguish a row with no corresponding
  `bleeding_observations` backing (`legacy_unverified`) from one written
  through a provenance-aware path.

**Now built**: `CycleEntriesProjection`
(`lib/features/cycle_tracking/data/repositories/cycle_entries_projection.dart`)
is the one-directional bridge — every concrete-flow observation created
through `BleedingEpisodeRepositoryImpl` (episode start, episode end's own
`flow: none` closing observation) is mirrored into a real `cycle_entries`
row with an honestly-derived `cycleDay`
(`CycleCalculationService.computeCycleDayForNewEntry`), tagged
`user_observed`/`user_reported_historical` as appropriate. An `uncertain`
("I'm not sure") observation is deliberately never projected — there is
no factual flow value to represent, and inventing one would itself be
the fabrication the charter forbids. This is what lets the still-
unmigrated `CycleCalculationService`/dashboard-ring engine correctly
reflect a new episode's start *and* end without those consumers having
been rewritten in this pass.

## 3. Episode lifecycle

Two orthogonal axes (PR #4 hardening, Blocker 5 — replacing an earlier
three-way `active`/`ended`/`uncertain` that conflated them, which let
marking uncertain silently vacate the one-active-episode slot):

- `bleeding_episodes.lifecycle_status`: `open` | `ended`. **Never
  auto-ended** just because an expected duration elapsed — only an
  explicit end (via `end_bleeding_episode`) closes it.
- `bleeding_episodes.continuation_certainty`: `confirmed` | `uncertain`,
  meaningful only while `open` (`NULL` once `ended`). "I'm not sure if
  it has ended" marks this `uncertain` — it never itself closes the
  episode.
- **One OPEN episode per user**, enforced at the database level
  (`bleeding_episodes_one_open_per_user`, a partial unique index on
  `user_id WHERE lifecycle_status = 'open'`) — covers both `confirmed`
  and `uncertain` continuation, so marking uncertain can never let a
  second, genuinely concurrent episode start.
- `start_date`/`end_date` are always the honest, factual calendar dates
  reported. The Fiqh evaluation layer (`MadhhabRuleEvaluator`) already
  consumes a raw duration without ever truncating or rewriting it — this
  model does not change that contract, it feeds it more honestly.
- `start_date`/`start_precision`/`start_source` are **immutable after
  creation** — enforced by column-level `REVOKE`/`GRANT`, not merely
  application discipline. All lifecycle transitions go through the
  `end_bleeding_episode` RPC or a plain UPDATE of only the columns that
  remain grantable (`lifecycle_status`, `continuation_certainty`, the
  `end_*` columns).
- Starting and ending are each atomic (episode + its first/closing
  observation, in one transaction) and independently idempotent via a
  client-generated `client_operation_id`/`end_client_operation_id` — a
  retried call returns the original result rather than erroring or
  duplicating.

## 4. Observation model

`bleeding_observations`: one immutable row per fact.

- `flow` includes `uncertain` (a daily check-in's "I'm not sure")
  distinct from `none` (an explicit "not bleeding today") — an unanswered
  check-in must never collapse into either.
- `precision`: `exact_time` | `approximate_time` | `date_only` — never
  silently promoted to a more exact class than what was actually
  reported.
- `observed_date` vs. `reported_at`: kept as two separate columns
  precisely so a backfilled report (observed Monday, reported Wednesday)
  never becomes indistinguishable from a live one. "Backfilled-ness" is
  derived from the gap between them, not a redundant stored flag that
  could contradict it.
- **Corrections never overwrite in place.** A correction is a new row
  whose `supersedes_id` points at the observation it replaces. A partial
  unique index (`bleeding_observations_supersedes_once`) ensures at most
  one row ever supersedes a given observation — one linear chain per
  fact, no forks, no cycles (a row can only ever reference a `id` that
  already exists, so a cycle is structurally impossible).
- **No future observations**: enforced at the application layer, not a
  DB `CHECK` — Postgres forbids non-immutable functions like `now()` in
  check constraints, and "future" depends on the reporter's own
  `timezone` column on the same row. Any code that inserts into this
  table must validate this before insert.

## 5. Legacy data policy (critical)

The 48 real rows currently in production `cycle_entries` may be genuine
manual logs, or may be leftover onboarding-fabricated days from before
this charter's Commit C fix — **the current schema has no way to
reliably tell them apart** (identical shape, no distinguishing field ever
existed). Per the charter's explicit instruction, every existing row is
classified `legacy_unverified`, not silently declared `user_observed`.

Consumption policy for `legacy_unverified` data (§44 of the charter):
usable for basic day-tallies/history (matching what `CycleCalculationService`
already honestly does — it was never over-claiming certainty from these
rows), but must **not** be treated as authoritative for a new Fiqh
conclusion or a high-confidence prediction unless a user re-confirms it or
provenance is otherwise proven. No destructive reclassification, deletion,
or "trust everything" migration was performed or is planned — the column
is additive and the data is preserved exactly as-is.

## 6. What's implemented today (Commits A, C, B, and a Commit D slice)

- **Commit A** — `supabase/migrations/20260917090000_bleeding_episode_model.sql`:
  `bleeding_episodes`, `bleeding_observations`, `cycle_baselines` tables,
  full RLS, constraints, indexes; `cycle_entries.data_provenance` column
  (additive, backfilled `legacy_unverified`). A hostile self-review pass
  (still Commit A, separate commit) then found and fixed: the original
  RLS policies had no `FOR` clause (defaults to `FOR ALL`), silently
  permitting UPDATE/DELETE on the supposedly-immutable
  `bleeding_observations` — split into SELECT/INSERT-only policies,
  verified inside real transactions; no trigger tied an observation's
  `user_id` to its episode's true owner — added a `BEFORE INSERT`
  trigger, verified it rejects a cross-account attempt; `end_precision`/
  `end_source` had no relationship to `end_date` — added a consistency
  `CHECK`; no self-reference guard on `superseded_by`/`supersedes_id`;
  `updated_at` had no trigger to bump it on a real UPDATE — reused the
  existing `public.set_updated_at()`. `CycleLog.fromJson` now throws
  `CycleLogParseException` on an invalid/missing `date` or `flow` instead
  of silently defaulting; list-decoding quarantines one bad record
  instead of discarding an entire list.
- **Commit C** — `lib/features/onboarding/presentation/screens/onboarding_screen.dart`:
  removed the fabricated-daily-logs behavior entirely. A real calendar
  (`showDatePicker`) replaces the fixed 31-day grid; the Madhhab-based cap
  on the raw duration question is gone; a new active/ended/uncertain
  question replaces the assumption that a reported start implies a fixed-
  length period starting that day. A reported start (+ end, if given)
  becomes one `bleeding_episodes` row; the usual-duration/usual-cycle-
  length questions are optional estimates in `cycle_baselines`. A
  double-tap guard on the completion button was added during the hostile
  review (an ended/uncertain episode has no DB uniqueness guard the way
  an active one does).
- **Commit B** — `start_bleeding_episode` RPC + `BleedingEpisodeRepositoryImpl`
  (`startEpisode`/`endEpisode`/`markEpisodeUncertain`/`addObservation`/
  `getObservationsForEpisode`) + `CycleEntriesProjection`: the canonical
  write path, and the one-directional compatibility bridge described in
  §2. The RPC's atomicity and double-tap safety were verified directly
  against a real local Postgres reconstruction — a genuine double-tap
  (two separate RPC calls) leaves exactly one episode and one observation,
  never an orphan of either.
- **Commit D (start/end lifecycle slice only)** —
  `lib/features/cycle_tracking/presentation/widgets/start_bleeding_sheet.dart`,
  wired into the dashboard's `_InsufficientCycleDataCard` (first-ever
  bleeding) and `_QuickActions` (Start/End buttons), replacing the old
  direct `cycle_entries` writes (`_endHaid` removed). Asks only Section
  6's two factual questions; a failed save reports honestly rather than
  silently succeeding. **Not yet built**: the daily check-in journey,
  backfill, and correction UX — see §7.

Evidence level throughout: **E2 (automated: unit + widget tests, `flutter
analyze`, `dart format` — 553 passing / 10 failing, the 10 confirmed
identical against clean `main`)** and **E3 (integration: every migration
and the RPC's atomicity were verified against a real local Postgres
reconstruction of the canonical baseline + full migration chain, inside
real transactions with real RLS role/JWT simulation)**. No commit has
real owner/device (E4) verification — that remains outstanding and is
owner-only per the charter's own evidence-tier rule.

## 7. Known gaps / explicitly deferred (not silently dropped)

Recorded here so a future agent does not have to rediscover the shape of
the remaining work:

- **Commit D (remainder)**: no daily check-in journey (Sections 8–11 —
  "are you still bleeding today?" while an episode is active); no
  backfill UX distinguishing `observed_date` from `reported_at`; no
  correction/revision UI (the DB model and `addObservation`'s
  `supersedesId` support it, but nothing in the UI creates one yet); no
  conflict handling for offline concurrent corrections (Section 13); no
  local-first/offline path for `bleeding_episodes`/`bleeding_observations`
  (server-only — see `BleedingEpisodeRepositoryImpl`'s doc comment).
- **Commit E** (notification journey): `NotificationRefreshCoordinator`'s
  existing per-type/idempotent-reschedule pattern (IDs 101–104) is
  confirmed directly extensible for a new `NotificationType.activeBleeding`
  (planned ID 105), but that type does not exist yet — no active-bleeding
  reminder, no consent prompt, no tap-routing, no event log.
  `showEndBleedingSheet`'s success path does not yet cancel any reminder
  because none is scheduled yet.
- **Commit F** (ring/calendar observed-vs-predicted): the dashboard's
  `_InsufficientCycleDataCard` all-or-nothing behavior (Section 25) is
  unchanged — an active-today episode with insufficient history for
  predictions still shows the same empty-ring card (though it is now
  reachable via a truthful Start-Bleeding flow rather than the old direct
  log sheet), not a factual "Day 1" state. No calendar UI reads
  `bleeding_observations` directly yet.
- **Commit G** (Fiqh integration boundary + invalidation): no
  provenance/invalidation model yet ties a cached Fiqh assessment to a
  specific observation version + Madhhab + ruleset version (Section 31).
  `MadhhabRuleEvaluator` itself is already architecturally correct
  (confirmed by direct code reading) — this gap is about tracking when a
  cached *result* goes stale, not about the evaluator's own logic.
- **Commit H** (full test matrices, Sections 52–57): targeted unit/widget
  tests exist for every implemented piece (entities, repository
  null-client paths, the projection, the sheets, the RPC verified live
  against Postgres); the charter's much larger named scenario matrices
  (timezone/DST/leap-day, concurrent offline corrections, property/fuzz
  testing) were not built.
- Proof chains 2–4 (daily check-in, episode closure -> reminder
  cancellation, correction -> invalidation) are not producible yet — they
  depend on Commit D's remainder and Commits E/G. Proof chain 1 (start
  bleeding -> persistence -> factual dashboard state -> ...) is real as
  far as persistence and dashboard-reload go; the "-> reminder" leg
  depends on Commit E, which does not exist yet.

## 8. STOP conditions that did not trigger

None of Section 71's real stop conditions (destructive production
migration required, unreconstructable legacy provenance needing a product
decision beyond `legacy_unverified`, a schema conflict implying data loss,
a new religious/medical ruling required, production credentials needed)
were hit in this pass. The reason implementation stopped after Commits A
and C is scope/time, not a blocking condition — recorded honestly per the
charter's own quality bar (Section 72): tests passing and a migration
applying cleanly is not the same as the charter being complete.
