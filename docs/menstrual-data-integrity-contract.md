# Menstrual Data Integrity & Active Bleeding Journey — Canonical Contract

Status: **living architecture contract**. Established by the Menstrual Data
Integrity & Active Bleeding Journey charter (2026-09-17). Commits A, C, a
hostile-self-review fix pass, B, a Commit D slice, a PR #4 hardening
pass, completion-wave Fixes A–D, and new Hardenings 1–4 (below) are
implemented on `feat/menstrual-data-integrity` (pushed to origin, PR #4,
draft, unmerged); the rest of this document describes the target
architecture for the commits that follow. Future agents must treat this
as the canonical reference — do not reinvent the taxonomy, episode
model, or provenance rules described here without updating this document
in the same change.

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

## PR #4 completion wave — pre-completion fixes A–D (2026-09-18)

Required before continuing into Commits D–H. Each is its own commit
(`215a4b3` for A/C/D, `6c964f7` for B) with the full technical detail in
its own message.

| Fix | Status |
|---|---|
| A — one atomic, idempotent onboarding operation | **FIXED** — `record_onboarding_menstrual_history` RPC; verified live: episode-only, baseline-only, both together, 5 identical retries → exactly one of each, a CHECK-violating baseline value rolls back the *whole* operation (no orphan episode), future-date rejection, both open and ended variants |
| C — every canonical write path validated, not just start/end | **FIXED** — one trigger (`bleeding_observations_validate_insert`) covers every INSERT into `bleeding_observations` regardless of code path: ownership, ended-episode rejection (with the one precise closing-observation exception), future-date rejection, and correction-target validation (same user, same episode) — each verified live, including the cross-account and cross-episode cases |
| D — durable app-kill recovery | **FIXED** — `PendingBleedingOperationStore` persists an operation's id + replayable params *before* either RPC is sent, cleared on success; `reconcilePendingOperations` (wired into `main.dart`'s existing app-start/app-resume triggers) replays anything still pending through the same idempotent RPC. Verified: round-trip, replace-not-duplicate, and a replay that cannot succeed is correctly left pending. What is **not** and cannot be proven here: a real process kill on a real device (E4) |
| B — real IANA timezone identity | **DART-SIDE FIXED, NATIVE BUILD UNCONFIRMED** — `flutter_timezone` added and wired (`DeviceTimezone.currentId()`), captured for both live sheet actions; `utc_offset_minutes` remains the separate, reliable field all canonical date math is based on. `flutter analyze`/`dart format`/`flutter test` are clean. This session has no way to run a real Android or iOS native build — confirm this branch's own CI "Build Android (debug artifact)" and "Build iOS (no-codesign compile check)" jobs are green before treating Fix B as closed |

A genuine test-infrastructure bug was found and fixed while building Fix
B: under `testWidgets` (not a plain `test()`), an unmocked
`MethodChannel` call hangs indefinitely instead of throwing
`MissingPluginException` quickly. The first version of
`device_timezone_test.dart` used a plain `test()` and gave a false sense
the graceful-degradation path was covered; the real gap was only
surfaced by `start_bleeding_sheet_test.dart` timing out once the sheets
started calling `DeviceTimezone.currentId()`. Fixed with
`mockDeviceTimezoneForTest` (mirroring the existing
`resetSecureLocalStoreForTest` pattern).

## PR #4 completion wave — new hardenings 1–4 (2026-09-18)

CI run #62 confirmed native Android + iOS compile evidence for
`flutter_timezone`, closing Fix B's own open question. Before continuing
into the rest of Commit D and Commits E–H, four further structural gaps
were required to be closed.

| Hardening | Status |
|---|---|
| 1 — Onboarding idempotency must survive process death | **FIXED** — `PendingBleedingOperationStore` gained an `onboardingHistory` operation type; the onboarding screen persists its operation id + full replayable episode/baseline params *before* calling `record_onboarding_menstrual_history`, clears on success, and its own `initState` reuses (via the new `getPendingByType`) any operation id left over from a killed process instead of generating a fresh one. `reconcilePendingOperations` gained the matching replay branch, and — unlike the start/end branches — also marks onboarding completed on a successful replay, so a woman is never routed back through onboarding to re-answer data that already safely saved. Verified live against local Postgres: `record_onboarding_menstrual_history`'s own idempotent replay across all 6 required variants (ended historical episode, open+confirmed, open+uncertain, baseline-only, episode-only, both together) plus two explicit replay-with-different-params-still-returns-original-ids proofs, each confirming exactly one row per `client_operation_id`. What is **not** and cannot be proven here: a real device process-kill (E4) |
| 2 — Ended episodes must accept zero new observations | **FIXED** — the previous `flow='none' AND observed_date=end_date` exception in `bleeding_observations_validate_insert` was a real structural loophole (an owning caller could insert extra flow:none rows onto an ended episode) and has been removed entirely; an ended episode now rejects every new fact unconditionally except a genuine correction (`supersedes_id IS NOT NULL`). `end_bleeding_episode` was reordered to insert its own closing observation *before* flipping `lifecycle_status` to `ended`, so no exception was ever needed for its own write. A new, dedicated `correct_observation` RPC (not `SECURITY DEFINER`, so RLS/the validation trigger both still apply) is the only way to add a revision to an already-ended episode; it resolves the target episode from the observation being corrected rather than a caller-supplied parameter, so a correction can never be misdirected even by a malicious caller. Verified live: a direct extra `flow:none` insert on an ended episode is rejected; an arbitrary non-`none` observation on an ended episode is rejected; `correct_observation` succeeds against an already-ended episode's own closing observation; retrying the same `client_operation_id` returns the identical `observation_id`; a cross-account `supersedes_id` is rejected; `end_bleeding_episode`'s own atomicity and idempotent replay still hold after the reordering (fresh start+end → exactly one episode + one closing observation; replay → identical result) |
| 3 — Timezone must refresh | **FIXED** — `DeviceTimezone`'s cache is no longer permanent: `invalidateCache()` clears it (wired into `main.dart`'s app-resume handler, so a travel/manual zone change is detected the next time the app is foregrounded), and `currentId({forceRefresh: true})` lets a future timezone-sensitive scheduling path (Commit E) bypass the cache outright without depending on resume having already fired. `timezone_id_at_observation`/`utc_offset_minutes_at_observation` on already-recorded observations are untouched by any of this — this only ever affects the value used for *new* writes and *future* reminder computation. Verified: cache genuinely holds a stale value until invalidated/force-refreshed; `invalidateCache()` and `forceRefresh` each independently make the next call see a changed platform value |
| 4 — Pending operation model must expand with the product | **CONFIRMED, not newly built** — the per-user `SecureLocalStore` scoping is unchanged; the enum-based `PendingBleedingOperationType` pattern already proved itself extensible without disruption (start, end, and now onboarding history share one store/reconciliation loop). Daily-observation/backfill/correction pending-operation support is intentionally **not** added yet — no UI exists yet to generate those operations (see Commit D below) — but the pattern is already proven to extend cleanly when it does. Audited: `AppErrorReporter.report` calls in this repository only ever pass the opaque `operation.operationId`, never `operation.params` itself — no replay payload reaches Sentry/analytics/logs today |

## PR #4 final implementation wave — Hardening 5 + Commits D/E/F/G (2026-09-19)

A review found `correct_observation` was never actually the *sole*
correction authority: an ordinary authenticated client could still
satisfy `bleeding_observations_validate_insert`'s rules with a direct
table INSERT (any row with `supersedes_id` set passed the trigger the
same as a call through the RPC). Hardening 5 closed this and became the
foundation everything below is built on.

### Hardening 5 — one canonical mutation boundary

**FIXED.** `bleeding_episodes`/`bleeding_observations`/`cycle_baselines`
revoke every client-facing INSERT/UPDATE/DELETE grant entirely (SELECT
remains); every mutation now goes through a `SECURITY DEFINER` RPC.
`anon` had every grant revoked outright. Converted to `SECURITY DEFINER`
+ explicit `SET search_path`: `start_bleeding_episode`,
`end_bleeding_episode`, `record_onboarding_menstrual_history`,
`correct_observation` — each already derived ownership exclusively from
`auth.uid()`, never a caller-supplied user id, so bypassing RLS changed
nothing about their safety. New RPCs completing the required mutation
list: `record_bleeding_observation` (daily check-in + backfill — the
same underlying operation, distinguished only by which date/source the
caller passes), `set_continuation_uncertain`, `save_baseline_estimate`.

**A genuine defect was found and fixed during this pass**: `REVOKE ALL
ON FUNCTION ... FROM PUBLIC` alone did not actually block `anon` from
executing any of these functions — Supabase's own canonical baseline
runs `ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT
ALL ON FUNCTIONS TO anon`, which grants directly to the named role, not
via `PUBLIC`. Fixed by revoking from `anon` explicitly on every RPC;
verified live via `has_function_privilege('anon', ...)`. The identical
pattern exists in a pre-existing, already-deployed function
(`check_and_increment_ai_rate_limit`) — flagged, not touched, since
fixing it safely requires understanding what currently depends on
`anon` access to it (plausibly legitimate: pre-auth rate limiting).

Commit D7 (concurrent correction conflict) is implemented inside
`correct_observation`: it explicitly checks whether its target is still
the current revision-chain tip before inserting, raising a
distinguishable `ERRCODE = 'NW409'` (not a raw unique-violation) when
another correction already superseded it first. A new
`effective_observation_id` SQL function (one tested recursive-CTE
definition of "current tip") backs both this check and the revision-
history resolver.

Verified live against a full local Postgres reconstruction: direct
authenticated INSERT/UPDATE on any of the 3 tables rejected (including
the exact `supersedes_id` loophole); `anon` rejected outright, including
calling any RPC at all; every new/converted RPC succeeds as its owning
authenticated user; cross-account `end_bleeding_episode` rejected (the
does-not-exist / does-not-belong-to-caller messages are now unified to
avoid leaking whether an episode id that isn't the caller's own actually
exists); `record_bleeding_observation` rejects a non-open episode; the
D7 conflict correctly triggers on a second correction targeting the same
observation; `effective_observation_id` resolves a 3-deep correction
chain to its true tip; idempotent re-application of all touched/new
migration files confirmed; schema contract clean throughout.

### Commit D — complete active bleeding journey

| Item | Status |
|---|---|
| D1 — daily check-in (YES/NO/I'm not sure) | **BUILT** — `daily_checkin_sheet.dart`, wired into the dashboard's Quick Actions. YES calls `record_bleeding_observation`; NO calls the existing atomic `end_bleeding_episode`; I'M NOT SURE calls the new `set_continuation_uncertain` RPC. |
| D2 — same-day multiple observations | **PROVEN live** — 3 same-day `record_bleeding_observation` calls (spotting 08:00, medium 14:00, light 21:00) verified against local Postgres: all 3 rows persist distinctly with their real `observed_time`s, none collapsed. |
| D3 — missed check-in prompt | **BUILT** — `_MissedCheckinBanner` on the dashboard detects a real gap (at least one full local day since the open episode's most recent observation) and offers "Add it," never forces one; declining leaves the gap. |
| D4 — backfill | **BUILT** — `showBackfillObservationSheet`, reachable from Quick Actions and from the missed-check-in banner (pre-filled to the detected date). `observed_date`/`reported_at` kept genuinely distinct; `source` classified `user_reported_historical`. |
| D5 — correction (UI + RPC + revision chain + history read + effective-observation resolver) | **BUILT** — `correction_sheet.dart`; `correct_observation` RPC; `bleeding_observations_supersedes_once` (pre-existing); `getRevisionHistory`/`effectiveObservationId` repository methods calling the new `effective_observation_id` SQL function. Not yet wired into a calendar (Commit F has no month-grid UI to attach a "tap historical date" entry point to — see Commit F's own status). |
| D6 — correction-of-correction | **SUPPORTED BY DESIGN, not UI-exercised this wave** — `correct_observation` accepts any prior observation id as `supersedes_id` including an existing correction; `effective_observation_id`'s recursive-CTE walk was verified live against a real 3-deep chain (v1→v2→v3). The correction sheet itself always targets whatever `target` it's given, so calling it again with v2 as the target correctly produces v3 — proven at the RPC/resolver level, not yet driven end-to-end through two sequential UI taps in one test. |
| D7 — concurrent correction conflict | **BUILT** — `correct_observation`'s explicit tip-check (`ERRCODE = 'NW409'`) verified live; `CorrectionConflictException` on the Dart side; `correction_sheet.dart`'s conflict UI ("Current saved value" / "Your offline change" / Keep saved / Use my change — rebased onto the current tip, never a fork from the stale original). |
| D8 — local-first/outbox | **PARTIAL** — `PendingBleedingOperationStore` extended with `dailyOrBackfillObservation`/`correction`/`baselineEstimate` types, wired into every new sheet before its RPC call, with matching `reconcilePendingOperations` replay branches. **Not built**: the three user-facing SAVED+SYNCED / SAVED ON DEVICE-SYNCING / SYNC NEEDS ATTENTION states — no UI surface currently shows sync status at all (this predates this wave; disclosed, not fabricated). |
| D9 — process-death replay | **PROVEN at the RPC level, PARTIAL for full device replay** — reconciliation branches exist and are tested (leaves pending when replay cannot succeed, for every one of the 3 new operation types); a genuine defect was found and fixed in the same pass (see below). Live-Postgres idempotent-replay proof now exists for every write RPC in this model: `record_onboarding_menstrual_history`, `start_bleeding_episode`, `end_bleeding_episode`, `correct_observation`, and `record_bleeding_observation` (same `client_operation_id` retried with different field values still returns the original `observation_id`, exactly one row). Real device process-kill remains E4. |

**A genuine, separate defect was found and fixed while wiring D9**:
`endEpisode`/`recordObservation`/`correctObservation`/`saveBaseline` all
return `null` on failure (including an ordinary RPC error already caught
and reported internally) rather than throwing — but
`reconcilePendingOperations`'s switch statement did not check the
return value before falling through to `clearPending`, meaning a
genuine RPC failure during reconciliation would have been silently
treated as success and the pending operation dropped, losing the
retry entirely. Fixed by checking each nullable result and throwing a
`StateError` on `null`, routing it into the same "leave pending" path
every other failure in that loop already uses. This affected the
pre-existing `endEpisode` case too, not only the 3 new ones added this
wave.

### Commit E — active bleeding notification journey

| Item | Status |
|---|---|
| E1 — eligibility | **BUILT** — `ActiveBleedingReminderScheduler.isEligible`: open (confirmed or uncertain) is eligible, ended is not, no episode is not. Pure, unit-tested. |
| E2 — consent | **BUILT** — a contextual dialog after a new episode starts ("Would you like Niswah to remind you..."), gated by a persisted "already asked" flag so declining is honored permanently, never re-asked. Default preference is OFF (unlike every other notification type in this app). Reuses the existing generic notification-settings screen for the always-available toggle. |
| E3 — privacy | **BUILT** — default copy is "Niswah / Time for your daily check-in." — no flow, Madhhab, symptoms, or notes in the payload or the notification body. Unit-tested that the copy never contains "bleeding"/"flow"/"haid"/"fiqh". |
| E4 — timezone | **BUILT, recomputation verified; real-device DST NOT PROVEN (E4-hardware)** — the reminder is recomputed from scratch on every `NotificationRefreshCoordinator.refresh()` call (app start/resume), which already runs right after `DeviceTimezone.invalidateCache()` on resume (Hardening 3) — nothing here caches a stale offset across calls. |
| E5 — logical reminder identity | **BUILT** — a stable, explicitly-owned FNV-1a hash of `userId:episodeId:localDay` (deliberately not `String.hashCode`, which the language spec does not guarantee stable across SDK versions/reinstalls). Unit-tested: stable for repeat calls, differs per day/episode/user. |
| E6 — reminder satisfaction | **BUILT** — `planDailyCheckin` returns null once today already has an observation; the coordinator then explicitly cancels today's own id (covers the case where the reminder already fired before the check-in happened). A second manual observation later the same day remains fully allowed at the write-path level (Commit D2). |
| E7 — tap routing | **BUILT, real-device tap NOT PROVEN (E4-hardware)** — an opaque JSON payload (`type`/`userId`/`episodeId`/`localDate`) captured via `onDidReceiveNotificationResponse` and `getNotificationAppLaunchDetails` (terminated-launch case); consumed once the dashboard is reached (the one place guaranteed to know who is actually signed in) — a payload for a different or no signed-in user is silently discarded, never acted on; an episode that has since ended is not reopened. |
| E8 — event audit | **PARTIAL** — "scheduled" events are logged via the existing `NotificationLogController` (dedup'd by id, matching the pattern already used for cycle/pregnancy/wellbeing). **Not built**: separate "cancelled"/"opened"/"responded" event records. |
| E9 — end/reopen/signout | **PARTIAL** — ending an episode (from either the daily check-in's NO branch or the End Bleeding sheet) cancels that day's reminder id; signing out calls a new `NotificationService.cancelAll()`, wired into `AuthController`'s existing sign-out branch (the same place that already resets per-account Madhhab state) — covers every notification type, not just this one. **N/A**: "correction that legitimately reopens episode: recompute reminder" — the current data model has no concept of reopening an ended episode via a correction (corrections only ever touch `bleeding_observations`, never flip `bleeding_episodes.lifecycle_status` back to open), so this specific sub-item does not apply to the architecture as built. |

### Commit F — canonical dashboard/ring/calendar

The owner-reported failure this commit must make structurally
impossible — "saved, but no visible ring/state" — was traced to its
real cause: the dashboard's `isCurrentlyBleeding` signal and its
"insufficient history" card both derived *exclusively* from
`cycle_entries` (via `CycleTrackingViewModel`/`CycleCalculationService`),
which only ever learns about a canonical write through
`CycleEntriesProjection`'s best-effort mirror. If that mirror failed,
the dashboard would show nothing was wrong — the canonical row would
exist and be perfectly correct, just invisible.

| Item | Status |
|---|---|
| F1 — canonical factual read model | **FIXED for the ring's own state signal** — a new `CanonicalBleedingStatusResolver` reads `bleeding_episodes` directly (never `cycle_entries`, never the projection) and its result is unioned into `isCurrentlyBleeding` (can only ever add a true case the legacy signal missed, never remove one it had right) and used to select which card renders. Quick Actions (start/end/daily-check-in/backfill) and the missed-check-in banner are now reachable the moment a canonical open episode exists, regardless of legacy prediction-sufficiency — previously they were gated behind "sufficient history for a prediction," meaning a first-time user could never reach the daily check-in button at all. The *prediction* math itself (average cycle length, next-period forecast) still comes from the legacy engine — Fiqh conclusions are a separate layer above raw facts (Commit G's own G4 principle), not something this pass rewrites. |
| F2 — projection failure test | **PROVEN at the resolver level** — `canonical_bleeding_status_resolver_test.dart` documents and proves that `resolveFromEpisodes` has no code path connecting it to `cycle_entries`/the projection at all: a projection failure structurally cannot affect its result, because there is nothing to affect. A full dashboard-widget-level "deliberately break the projection, then check the rendered tree" integration test was not additionally built — the resolver being provably projection-independent is the actual guarantee; a widget-level re-proof would be testing the same fact through more indirection, not a materially stronger one. |
| F3 — explicit ring states | **BUILT** — `RingFactualState`: `noHistory` / `factualOpenEpisode` / `factualCompletedHistory` / `predictionEligibleHistory`, unit-tested (including that an open episode always wins over any completed count). |
| F4 — first observation | **BUILT** — `_FactualOpenEpisodeCard`: "Bleeding recorded / Day N of this record / Learning your cycle." — shown immediately, never gated on a second cycle. |
| F5 — first completed episode | **BUILT** — `_FactualCompletedHistoryCard`: shows that real history exists without fabricating an average, next-period, or fertile window; explicit copy that a second start is needed to learn the pattern. |
| F6 — prediction input policy | **PARTIAL, inherited** — `RingFactualState.predictionEligibleHistory` requires 2+ real canonical episodes before falling through to the legacy `_CycleOverview`/prediction UI at all. The finer-grained policy the charter asks for (explicitly distinguishing `USER_OBSERVED`/`USER_REPORTED_HISTORICAL`/`USER_REPORTED_ESTIMATE`/`LEGACY_UNVERIFIED` eligibility, and relabeling an estimate-derived output as "Based on the estimate you gave us" rather than "Your average") is **not built** — the legacy `CycleCalculationService` this still falls back to for the actual prediction math was not rewritten in this pass. |
| F7 — observed vs. predicted visual semantics | **NOT BUILT** — no new accessible, non-color-only visual distinction was added between observed/historical/estimated/predicted/legacy-unverified content this wave. |
| F8 — calendar actions | **NOT BUILT** — no calendar/month-grid screen exists in this app to attach "tap a historical date" actions to; building one was out of scope for this wave's remaining time. The underlying actions it would need (view observations, add backfill, correct, inspect revision history) all already exist as standalone, working entry points (`correction_sheet.dart`, `showBackfillObservationSheet`, `getObservationsForEpisode`, `getRevisionHistory`) — only the calendar surface to launch them from a specific date is missing. |

### Commit G — Fiqh evidence boundary (architecture/invalidation only — no Knowledge Base work performed)

Reviewed against the existing Fiqh pipeline (`CycleStatusEngine`,
`CycleCalculationService`, `MadhhabRuleEvaluator`) rather than rebuilt —
most of what this commit requires turned out to already hold by
construction from prior waves, verified rather than assumed:

| Item | Status |
|---|---|
| G1 — UNKNOWN Madhhab never blocks raw tracking | **VERIFIED, already true** — grepped every tracking write path added this wave (`start_bleeding_sheet.dart`, `daily_checkin_sheet.dart`, `correction_sheet.dart`, `bleeding_episode_repository_impl.dart`) and none reference `MadhhabController`/Madhhab at all; none of the SQL RPCs take a Madhhab parameter or condition any check on it. `CanonicalBleedingStatusResolver` (Commit F's ring signal) and `ActiveBleedingReminderScheduler` (Commit E's reminder eligibility) likewise take no Madhhab input — structurally incapable of gating on it. Daily reminders and the ring's factual states are therefore already unconditional on Madhhab; only the separate Fiqh *conclusion* (haid/tahara/istihadah label) depends on it, exactly as required. |
| G2 — assessment provenance | **N/A TODAY, documented as a forward contract** — there is no persisted or cached Fiqh assessment anywhere in this codebase; `CycleStatusEngine.evaluate()` is a pure function recomputed fresh on every dashboard build, never written to a table or local store. Provenance (user/episode/effective-revision-set/Madhhab/ruleset-version/evaluated_at/precision) has nothing to attach to today. **Binding requirement for whoever adds the first such cache** (e.g. an AI-generated report, a performance optimization): it MUST carry those fields from the day it is introduced — this is now the documented contract, not a retrofit to do later. |
| G3 — invalidation | **N/A TODAY, trivially satisfied** — with no cache, there is nothing to go stale; recomputing fresh on every access is the strongest possible form of "always reflects the latest evidence." The 6 listed invalidation triggers (observation added/corrected, backfill, episode end, episode correction/reopen, Madhhab change, ruleset version change) apply the moment a cache is introduced. |
| G4 — no raw evidence mutation | **VERIFIED** — grepped `cycle_status_engine.dart`, `cycle_calculation_service.dart`, `madhhab_rule_evaluator.dart` for `.insert(`/`.update(`/`.upsert(`/`.delete(`/`.rpc(`: zero matches. These are read-and-compute-only; Fiqh interpretation sits above evidence exactly as required, verified rather than assumed. |
| G5 — insufficient evidence -> unresolved, not guessed | **VERIFIED, already true (a prior wave's work)** — `FiqhCycleState.madhhabUnresolved`/`insufficientHistory` already exist and are "returned instead of guessing" per the engine's own doc comment; not rebuilt, not touched. |

No new religious rulings were introduced. No Knowledge Base work was
started.

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
- **An ended episode accepts zero new facts (Hardening 2).** Earlier
  drafts carved out a narrow exception (`flow='none' AND
  observed_date=end_date`) so `end_bleeding_episode` could insert its own
  closing observation after marking the episode ended — this was a real
  structural loophole (any owning caller could exploit the same
  exception to add extra rows to an already-ended episode). Fixed two
  ways together: `end_bleeding_episode` now inserts its closing
  observation *while the episode is still open*, before flipping
  `lifecycle_status`, so the exception was never actually needed; and the
  trigger's rule is now unconditional — `lifecycle_status = 'ended'`
  rejects every new row *unless* it carries a `supersedes_id` (a genuine
  correction). Corrections to an ended episode's history go through the
  dedicated `correct_observation` RPC, which resolves the target episode
  from the observation being corrected (never a caller-supplied
  parameter) — adding a new fact to an ended episode and correcting one
  that already exists are deliberately kept as two different operations,
  not one INSERT path with a growing set of exceptions.

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
