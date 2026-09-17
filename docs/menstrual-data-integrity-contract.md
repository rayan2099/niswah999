# Menstrual Data Integrity & Active Bleeding Journey — Canonical Contract

Status: **living architecture contract**. Established by the Menstrual Data
Integrity & Active Bleeding Journey charter (2026-09-17). Commits A and C
below are implemented and merged into this branch; the rest of this
document describes the target architecture for the commits that follow.
Future agents must treat this as the canonical reference — do not
reinvent the taxonomy, episode model, or provenance rules described here
without updating this document in the same change.

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
  `supabase/migrations/20260917090000_bleeding_episode_model.sql`). Every
  *new* write to the menstrual-data model should target these tables.
  `cycle_baselines` holds the separate, never-historical estimate class.
- **Existing, compatibility track**: `cycle_entries` — untouched schema,
  still read by every existing consumer (`CycleCalculationService`,
  `CycleStatusEngine`, the dashboard ring, `client_fiqh_state_provider`,
  notifications, data export). A new `data_provenance` column
  (`legacy_unverified` | `user_observed` | `user_reported_historical`)
  lets a consumer distinguish a row with no corresponding
  `bleeding_observations` backing (`legacy_unverified`) from one written
  through a provenance-aware path, without requiring every consumer to
  migrate in the same pass.

**Not yet built** (tracked as follow-up, not silently skipped): a
one-directional projection that mirrors every new `bleeding_observations`
write into a `cycle_entries` row, so `CycleCalculationService` and the
dashboard immediately reflect episodes created after onboarding (today,
onboarding's `BleedingEpisodeRepositoryImpl` writes only to the new
tables — see §7's Known Gaps). Until that projection exists, the two
tracks are not yet kept in sync automatically.

## 3. Episode lifecycle

`bleeding_episodes.status`: `active` | `ended` | `uncertain`.

- **Never auto-ended** just because an expected duration elapsed — only
  an explicit end-date report changes `active`/`uncertain` to `ended`.
- **One active episode per user**, enforced at the database level
  (`bleeding_episodes_one_active_per_user`, a partial unique index on
  `user_id WHERE status = 'active'`) — not just an application check.
- `uncertain` is a first-class terminal state for "I don't know whether
  it has ended," distinct from both `active` and `ended` — never forced
  into either.
- `start_date`/`end_date` are always the honest, factual calendar dates
  reported. The Fiqh evaluation layer (`MadhhabRuleEvaluator`) already
  consumes a raw duration without ever truncating or rewriting it — this
  model does not change that contract, it feeds it more honestly.

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

## 6. What's implemented today (Commits A & C)

- **Commit A** — `supabase/migrations/20260917090000_bleeding_episode_model.sql`:
  `bleeding_episodes`, `bleeding_observations`, `cycle_baselines` tables,
  full RLS, constraints, indexes; `cycle_entries.data_provenance` column
  (additive, backfilled `legacy_unverified`). Verified: applies cleanly
  against the canonical baseline, schema-contract checks all pass,
  idempotent on re-run (E3 — local reconstruction, not production).
  `CycleLog.fromJson` now throws `CycleLogParseException` on an
  invalid/missing `date` or `flow` instead of silently defaulting to
  `DateTime.now()`/`FlowLevel.light`; `SecureLocalStore.decodeJsonListSafely`
  and the repository's remote-row parsing quarantine one bad record
  instead of discarding an entire list.
- **Commit C** — `lib/features/onboarding/presentation/screens/onboarding_screen.dart`:
  removed the fabricated-daily-logs behavior entirely. A real calendar
  (`showDatePicker`) replaces the fixed 31-day grid; the Madhhab-based cap
  on the raw duration question is gone; a new active/ended/uncertain
  question replaces the assumption that a reported start implies a fixed-
  length period starting that day. A reported start (+ end, if given)
  becomes one `bleeding_episodes` row via `BleedingEpisodeRepositoryImpl`;
  the usual-duration/usual-cycle-length questions are optional estimates
  stored via `CycleBaselineRepositoryImpl` into `cycle_baselines`, never as
  observed history.

Evidence level for both: **E2 (automated: unit + widget tests, `flutter
analyze`, `dart format`)** and **E3 (integration: the migration was
verified against a real local Postgres reconstruction of the canonical
baseline + full migration chain, schema-contract-passing)**. Neither
commit has real owner/device (E4) verification — that remains outstanding
and is owner-only per the charter's own evidence-tier rule.

## 7. Known gaps / explicitly deferred (not silently dropped)

The charter's full scope (Commits B, D–H) was not attempted in this pass.
Recorded here so a future agent does not have to rediscover the shape of
the remaining work:

- **Commit B** (repositories/sync/revisions/legacy compatibility): no
  local-first/offline path exists yet for `bleeding_episodes`/
  `bleeding_observations` (they are server-only — see
  `BleedingEpisodeRepositoryImpl`'s doc comment); no code yet reads them
  back into the dashboard/calculation pipeline; the `cycle_entries`
  projection described in §2 does not exist yet.
- **Commit D** (active bleeding state machine + daily check-in UX): no
  "Bleeding started/stopped" action wired to the new episode model yet
  (the dashboard's existing `_endHaid` still targets `cycle_entries`
  only); no daily check-in journey; Section 15's "no response is not
  data" notification-silence handling is not yet built against this
  model.
- **Commit E** (notification journey): `NotificationRefreshCoordinator`'s
  existing per-type/idempotent-reschedule pattern (IDs 101–104) is
  confirmed directly extensible for a new `NotificationType.activeBleeding`
  (planned ID 105), but that type does not exist yet.
- **Commit F** (ring/calendar observed-vs-predicted): the dashboard's
  `_InsufficientCycleDataCard` all-or-nothing behavior (Section 25) is
  unchanged — an active-today episode with insufficient history for
  predictions still shows the same empty-ring card, not a factual "Day 1"
  state.
- **Commit G** (Fiqh integration boundary + invalidation): no
  provenance/invalidation model yet ties a cached Fiqh assessment to a
  specific observation version + Madhhab + ruleset version (Section 31).
  `MadhhabRuleEvaluator` itself is already architecturally correct
  (confirmed by direct code reading) — this gap is about tracking when a
  cached *result* goes stale, not about the evaluator's own logic.
- **Commit H** (full test matrices, Sections 52–57): only targeted unit/
  widget tests for the two implemented commits exist; the charter's much
  larger named scenario matrices (timezone/DST/leap-day, concurrent
  offline corrections, property/fuzz testing) were not built.
- The four required end-to-end proof chains (Section 68) are not
  producible yet — they depend on Commit D existing at all.

## 8. STOP conditions that did not trigger

None of Section 71's real stop conditions (destructive production
migration required, unreconstructable legacy provenance needing a product
decision beyond `legacy_unverified`, a schema conflict implying data loss,
a new religious/medical ruling required, production credentials needed)
were hit in this pass. The reason implementation stopped after Commits A
and C is scope/time, not a blocking condition — recorded honestly per the
charter's own quality bar (Section 72): tests passing and a migration
applying cleanly is not the same as the charter being complete.
