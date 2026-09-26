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

## 9. PR #4 Data-Integrity Closure Wave + Final Closure and Adversarial
## Validation wave (2026-09-19)

Two further charters landed on this same branch after Section 8 above
was written. Recorded here rather than rewriting the sections above, to
keep this document's own history honest rather than silently
retconning earlier status tables.

### Closure Wave — 17 named blockers

PASS (real, tested, several live-verified against a full local Postgres
reconstruction): typed read-failure model (`LoadResult<T>` — success/
degraded/unavailable, never conflated with verified-empty); canonical
episode lifecycle as the sole factual "is she bleeding right now"
signal (`hasOpenEpisode`, structurally independent of the legacy Fiqh
display label); `CanonicalFiqhEvidenceAdapter` (canonical, effective,
post-correction evidence bridged into the legacy `CycleLog` shape,
never inventing a `FlowLevel` for an `uncertain` day); server-side
provenance derivation on every canonical write RPC (a client can no
longer claim `user_observed` for a past date); DB + RPC-level
precision/timestamp consistency; real IANA timezone application
(`tz.setLocalLocation`, previously a no-op); a real, persisted,
user-choosable active-bleeding reminder time; contextual (not
cold-start) notification consent; background/foreground/terminated
notification tap routing via a live `NotificationService.onTap` stream;
correction-conflict resolution that actually clears the stale pending
outbox entry; `PendingBleedingOperationStore.loadPending` hardened
against malformed JSON/wrong shape/one-bad-item without losing the
rest; a structural notification event audit trail (scheduled/
cancelled/opened/responded) separate from the display feed; trust-based
prediction eligibility (a degraded read can never become
`predictionEligibleHistory`); degraded-read propagation into the UI.

PARTIAL/NOT BUILT at the time that wave's own report was delivered:
the third sync state ("SYNC NEEDS ATTENTION") was not yet built; F7
(observed/reported/estimated/predicted visual semantics) and F8 (a
canonical calendar screen) were not started at all — no calendar/
month-grid UI exists in this app yet to attach date-tap actions to.

A genuine regression was introduced and then found and fixed within
that same wave: `_canonicalStatus == null` (no session yet, or the
first canonical fetch simply hadn't resolved) was briefly treated
identically to a genuine read failure, wrongly showing "couldn't
verify" instead of the honest empty state — this was also the root
cause of most of that wave's own `accessibility_text_scaling_test.dart`
failures.

### Final Closure and Adversarial Validation wave

Four items, each verified against the real baseline commit
(`1d56a6e`) rather than assumed:

1. **Three honest sync states — COMPLETE.** `PendingBleedingOperation`
   gained durable `retryCount`/`lastFailureCategory`/`lastAttemptAt`
   tracking; `SyncState` (`savedSynced`/`savedSyncing`/
   `needsAttention`) is computed from real, persisted history, never a
   fourth silent "failed" state. Failure categorization
   (network/auth/validation/correctionConflict/unknown) determines
   whether automatic reconciliation keeps retrying forever
   (network/auth/unknown — genuinely never dead-lettered) or stops
   after the first failure and waits for a deliberate manual retry
   (validation/correctionConflict — "do not retry invalid operations
   indefinitely"). A real dashboard banner (`_SyncStatusBanner`)
   surfaces `needsAttention` items with a category-honest recovery
   action — a real "Retry now" where retrying can help, an honest
   "needs your review" note (no false retry button) where it can't.

2. **Multi-day notification continuity — COMPLETE.**
   `ActiveBleedingReminderScheduler.planRollingDailyCheckins` plans a
   bounded (7-day) rolling window of independently-scheduled,
   independently-cancellable reminders every refresh, reusing the
   existing per-day logical identity rather than an OS recurring-alarm
   primitive that can't selectively skip one satisfied day. A single
   refresh (proven via both a pure-scheduler test and a real
   `NotificationRefreshCoordinator` integration test using the actual
   `flutter_local_notifications` platform channel) leaves a full
   week's genuine, distinct reminder ids scheduled — an episode is
   never left silent again purely because the app wasn't reopened
   daily. Bounded deliberately (iOS's own hard, OS-wide 64-pending-
   notification ceiling, shared across every notification type this
   app uses) — a continuous absence longer than the window, or a
   check-in completed on a different device while this one stays
   offline, is the explicitly disclosed limit of what a client-only
   scheduler can guarantee; cross-device instantaneous cancellation is
   never claimed. Also fixed, found while building this: the same-day
   "catch-up" time used to be `now + 1 minute`, recomputed later on
   every repeated refresh — now a fixed buffer derived only from the
   preferred time itself, stable across repeated same-day refreshes.

3. **Canonical-only Fiqh authority — COMPLETE.** `_canonicalFiqhLogs ??
   _viewModel.logs` was removed outright — the Fiqh ruling now comes
   exclusively from canonical evidence, never a legacy fallback. A new
   `_FiqhState.evidenceUnresolved` (with its own retry-capable UI —
   `_FiqhEvidenceUnresolvedCard` in place of the ring, honest copy in
   the Salah banner and — the most safety-critical consumer —
   `_PrayerStatusCard`, which previously would have confidently
   asserted "Salah is obligatory" from evidence that could not
   actually be verified) takes priority over every other signal,
   including her own manual Istihadah toggle, whenever the observations
   read genuinely fails, is degraded by a quarantined row, or an
   excluded `uncertain`-flow day (`CanonicalFiqhEvidenceAdapter.
   excludedUncertainDates`, new) falls within the currently open
   episode's own date range. One directly caused, honestly disclosed
   test casualty: `parity_today_stepper_consistency_test.dart`'s
   "manual istihadah mode still shows a real day count" test relied on
   legacy-only fixture data with no canonical session at all — now
   correctly insufficient to compute a day count, exactly as this
   finding required.

4. **Notification scheduling audit integrity — COMPLETE.**
   `NotificationService.scheduleAt`/`scheduleDaily` now return a
   `NotificationSchedulingOutcome` (`accepted`/`failed`/
   `permissionUnavailable`/`uninitialized`) instead of `void`;
   `cancel` returns a plain `bool`. `NotificationRefreshCoordinator`
   only records a "scheduled" audit event (or the display-feed entry)
   once the OS has actually acknowledged the call, and only records
   "cancelled" when cancellation genuinely succeeded. Verified against
   the real `flutter_local_notifications` platform channel (mocked at
   the method-channel level, not a hand-rolled stand-in): a genuine
   injected platform rejection returns `failed`; a real Android
   `areNotificationsEnabled() == false` returns `permissionUnavailable`
   before ever attempting the call; iOS has no non-prompting permission
   query in the installed plugin version, so an iOS permission-caused
   failure is honestly reported as the less-precise `failed` rather
   than a fabricated distinction.

**Not built in this wave** (disclosed, not silently dropped): F7
(observed/reported/estimated/predicted/legacy-unverified visual
semantics) and F8 (a canonical calendar screen) remain exactly as
un-started as the prior wave left them — both are substantial new-UI
efforts (F8 in particular needs an entirely new month-grid screen this
app does not have yet), not something addressable as an incremental
patch. The broader per-audit-area findings registers under
`production-readiness-results/`, the traceability matrix, the founder
launch-confidence dashboard, and the owner launch checklist were not
updated this wave — only this contract document was, as the one
directly and specifically governing this charter's own architecture;
updating the other ~20 documents is disclosed here as a remaining,
separate task, not claimed done.

All four CI jobs (Analyze & Test, Build Android, Build iOS, BR-002
migration reproducibility) were green on this wave's own final pushed
SHA. PR #4 remains draft and unmerged throughout.

## 10. "Finish the Product Contract" wave (2026-09-19, same branch)

Picks up exactly where Section 9 left off: F7 and F8, left un-started
there, are built and tested in this wave; the manual-Istihadah test
regression Section 9 disclosed as a "directly caused" casualty is
properly resolved (not merely re-skipped); notification continuity
beyond the 7-day rolling window received the explicit design review
this wave's charter required; and the remaining widget-test gaps
Section 9's own text implicitly left open are closed. PR #4 stays
**draft, unmerged**; nothing here claims `E4` (owner device) evidence
or an overall launch decision.

### F7 — evidence provenance, built

`EvidenceProvenance` (`lib/features/cycle_tracking/domain/entities/
evidence_provenance.dart`) is the shared six-class taxonomy this
charter's Section 1 requires: `userObserved`, `userReportedHistorical`,
`userReportedEstimate`, `predicted`, `legacyUnverified`,
`missingUncertain`. Each carries its own icon, short/long label pair
(English + Arabic), and an `isTentative` flag so a predicted value can
never share a confirmed observation's own confident visual treatment.
`ProvenanceBadge` is the one reusable widget every consumer renders
from — icon + text always, never color alone, with the long-form
sentence reaching a screen reader via `Semantics.label` even where the
visible chip only shows the short text, and `FittedBox`-wrapped to
survive 200% text scale. Wired into the new canonical calendar's day
cells and legend (predicted days additionally get a distinct dashed
border, painted by a small `CustomPainter`, never the same solid fill
real bleeding gets).

A real, pre-existing accessibility gap was found and fixed while
building this: the legacy `CycleCalendar` widget's day-cell `Semantics`
label always announced the marker's internal English constant (e.g.
"Expected Haid") regardless of the active locale — a screen reader in
Arabic mode was announcing English. Fixed via a new `localizedLabel`
getter on `_DayMarker`, mirroring the pairing the visible legend text
already showed sighted users.

Test coverage: `provenance_badge_test.dart`, 16 tests — every class's
icon+text, every class's Semantics long-form label, the
never-tentative-false invariant for `predicted`, the honest
`legacyUnverified` wording, Arabic labels, and 200% text scale.

### F8 — canonical calendar, built

`CanonicalCalendarScreen` (new) is the production month-grid screen
this charter's Section 2 explicitly required rather than accepting as
out of scope. Reads `bleeding_episodes`/effective
`bleeding_observations` directly — `cycle_entries` is never read.
Supports month/year navigation (prev/next plus a tap-to-pick month
picker), and tapping any date opens `observation_detail_sheet.dart`,
which:

- shows every observation reported for that day (Commit D2's
  multiple-same-day-observations feature is fully preserved, never
  collapsed to one row);
- marks which one is the effective (current) value versus a
  superseded revision, in oldest-first order — a genuine, visible
  revision history, since a correction never changes which calendar
  day a fact is about, grouping by date already reconstructs the full
  chain with no extra network round trip;
- offers "Correct this entry" (opens the existing, already-hardened
  `showCorrectObservationSheet`) for a day with an effective value, or
  "Add missing entry" (`showBackfillObservationSheet`) for an empty day
  that falls within an existing episode's own range;
- for a day with no episode covering it at all, shows honest guidance
  ("use Start Bleeding") rather than a fabricated action — see the
  disclosed scope limit below;
- refreshes the calendar from canonical data directly on return from
  any action — never relies on the legacy projection to reflect a
  save.

A bounded, disclosed forward projection (2+ real completed episodes,
plausible 15-90 day gap) marks predicted days, and explicitly never
projects across an already-open episode's own real data — the
"fabricate bleeding between two reported observations" failure mode
this charter prohibits.

**Disclosed scope limit, not silently narrowed**: adding a fully
separate historical episode (both start and end already in the past,
unconnected to today) has no write path anywhere in this app outside
the one-time onboarding history flow (`recordOnboardingHistory`, which
this codebase's own server-side design ties to account setup, not
repeated ad-hoc entry). "Add missing entry" therefore covers
backfilling within an *existing* episode's own date range, matching
this codebase's own established Commit D4 "backfill" scope — building
a second, general-purpose historical-episode-creation RPC and UI is a
real, separate feature, not something this wave silently declined to
disclose.

A real bug was found and fixed while wiring this up: `episodeForDay`'s
range check (used to decide whether "Add missing entry" should be
offered) treated an *open* episode's range as unbounded into the
future (it has no `endDate` to bound it), which would have offered
backfill on a future date and then handed that date straight to
`showBackfillObservationSheet`'s own date picker as its `initialDate`
— outside that picker's own `lastDate: now` bound, an assertion
failure. Fixed by clamping the eligibility check to never extend past
"today," closing the future-date-rejection requirement structurally
rather than only inside the sheet.

Test coverage: `canonical_calendar_screen_test.dart`, 10 tests — a real
bleeding day from canonical evidence, a full multi-observation revision
chain (current vs. superseded, both visible), the backfill entry point
opening the real backfill sheet, an empty day with no episode offering
no fabricated action, the future-date-rejection edge case above, month
navigation, a leap day (2028-02-29), an honest unavailable-read card
(never fabricated data), predicted-day distinct dashed styling, and
Arabic RTL.

**What this does NOT cover, matching this codebase's own established
scope boundary** (`correction_sheet_test.dart`'s identical note): a
full write round trip (save → server → refreshed calendar) requires a
real, signed-in Supabase session, which a plain widget test cannot
provide. Not tried on a real device.

### Canonical Fiqh regression — resolved properly, not re-skipped

Section 9 disclosed the manual-Istihadah test as a casualty of Commit
G4's legacy-fallback removal. Resolved per the charter's explicit
5-step instruction — no legacy fallback restored, no alternate one
introduced:

1. The test's real intended behavior (manual Istihadah still shows a
   real, grounded day count, never blank/crashed) is preserved by
   giving `DashboardScreen` genuine test-injection points
   (`canonicalRepositoryOverride`/`canonicalUserIdOverride`, mirroring
   its own established `viewModel` pattern) so the fixture can supply
   real canonical evidence instead of a legacy-log fallback.
2. A second, real, safety-critical bug was found in the process: the
   `insufficientEvidenceWhileFactuallyBleeding` guard (added in the
   prior wave to stop `_PrayerStatusCard` from asserting "Salah is
   obligatory" for a factually-open episode with unsynced evidence)
   checked `snapshot.state == FiqhCycleState.insufficientHistory` — an
   enum value the fallback snapshot that triggers exactly this
   situation never actually produces (it is hardcoded to
   `FiqhCycleState.tahara`). The guard never fired. Fixed to check
   `!fiqhCalculation.hasSufficientHistory` directly, the same condition
   that selects that fallback in the first place.
3. Two new tests prove the required negative space: unavailable
   canonical evidence produces the explicit unresolved state (never a
   confident Haid/Tahara/Istihadah ruling), and a factually open
   episode with genuinely insufficient evidence (none synced yet, not
   "unavailable") is never shown as confirmed Tahara.
4. No separate religious rule was needed or invented — the gap was a
   test-fixture/engineering defect (a legacy fallback the fixture had
   relied on being removed), not a genuine Fiqh product-rule question.

Verified against the true baseline (`915af02`, via a `git worktree`
comparison) rather than assumed: two of the four originally-failing
tests in `parity_today_stepper_consistency_test.dart` are pre-existing,
unrelated ring/statistical-placement bugs (present at baseline,
untouched by this fix); the manual-Istihadah test and the two new
tests all pass. Zero newly-failing tests.

### Notification continuity beyond 7 days — design review + build

The charter asked for an explicit review of extending the existing
7-day rolling window, not merely enlarging it. `NotificationService.
scheduleDaily` already used an OS-native RECURRING trigger
(`matchDateTimeComponents: DateTimeComponents.time`) for the wellbeing
reminder — this is the "genuinely-supported background scheduling
mechanism" the charter asked to be considered, now also applied to the
active-bleeding reminder as a second tier:

- **Tier 1 (unchanged)**: the existing 7-day rolling window — exact,
  per-day identity, E6 satisfaction-aware, precise tap-routing to a
  specific date.
- **Tier 2 (new)**: `activeBleedingRecurringFallbackId`, one OS-native
  recurring registration that fires daily at the same preferred time
  indefinitely, consuming exactly one of iOS's shared 64-pending slots
  regardless of episode length, and re-derives the correct local fire
  time from the device's *current* timezone/DST on every firing — no
  app reopen needed, unlike Tier 1's own absolute-instant scheduling.

Honestly disclosed, not claimed as full continuity: Tier 2 cannot
consult app state, so it may occasionally repeat on a day already
checked in, and its payload (`recurringFallbackType`, deliberately no
`localDate`) cannot pre-encode which day it will fire on — a tap on it
always means "whatever today genuinely is," resolved at tap time, not
read from a stale embedded date. **Exact supported horizon, stated
plainly**: 7 days of precise, per-day-aware reminders without
reopening; beyond that, an indefinite but coarser daily nudge — never
described as indefinite exact daily tracking.

A second, real, independently-found gap was fixed alongside this: both
`start_bleeding_sheet.dart`'s and `daily_checkin_sheet.dart`'s
end-episode paths (Commit E9) previously cancelled only *today's* own
rolling-window id, leaving days 2-7 of an already-scheduled window live
to fire for an episode that no longer exists. Both now cancel the
entire window (`ActiveBleedingReminderScheduler.rollingWindowReminderIds`)
plus the new recurring fallback.

**iOS pending-notification budget, worst case, every type enabled
simultaneously**: cycle (1) + pregnancy (1) + nifas (1) + wellbeing (1)
+ active-bleeding rolling window (7) + active-bleeding recurring
fallback (1) = **12 of 64** — audited as its own explicit test, not
merely asserted.

Test coverage: `notification_scheduler_test.dart` (+5 — rolling-window
id enumeration, a 15-day-episode gap demonstration showing the rolling
window alone does not reach days 8-15, DST-spanning id stability
across the real 2027-03-14 transition, the recurring payload's shape,
the budget audit above), `notification_multi_day_continuity_test.dart`
(+3 — the recurring fallback scheduled/cancelled correctly against a
real mocked `flutter_local_notifications` plugin channel), and a new
`dashboard_notification_tap_stream_test.dart` (5 — the live `onTap`
subscription while the dashboard is already mounted, for both payload
types plus malformed/foreign/rapid-fire inputs; simulates a real tap by
invoking the plugin's own native-to-Dart `didReceiveNotificationResponse`
callback through the mocked channel, not a hand-rolled shortcut).

**Not tried on a real device**: real timezone/DST change, real OS
notification delivery/permission grant-deny, and real tap-through
remain E2 (automated) only.

### Remaining widget-test gaps — closed

Two structural gaps this wave found, both closed against the real
`DashboardScreen` and its real `BleedingEpisodeRepositoryImpl`-shaped
injection points, never a decorative stand-in — new
`dashboard_canonical_degraded_evidence_test.dart`, 5 tests:

- `_CanonicalStatusUnavailableCard` after a genuine episodes-read
  failure, including a full retry round trip (the fake repository
  itself changes behavior on the second call — a real state
  transition).
- Degraded canonical evidence (`LoadDegraded`, both the
  quarantined-row and the materially-excluded-uncertain-day
  sub-cases) correctly restricts the Fiqh conclusion via
  `_PrayerStatusCard`, and — the necessary negative case — an
  excluded uncertain day from already-concluded, months-old history
  does *not* restrict a conclusion about the present.

A real bug surfaced while writing the second test: `_FiqhEvidenceUnresolvedCard`'s
English copy overflowed its fixed 280×280 circle by ~10px at real
device width (the Arabic translation is more compact and never
triggered it) — fixed with a `FittedBox`, which also covers 200%
text-scale for this card.

### Documents updated this wave

This contract document (own section, above); `00_12_TRACEABILITY_MATRIX.md`
(F7/F8 rows updated from `MISSING` to `REMEDIATED —
E2_AUTOMATED_VERIFIED`, new rows for the Fiqh regression fix,
notification continuity, and the remaining widget-test coverage); the
founder launch-confidence dashboard (`docs/founder-launch-confidence-dashboard.md`,
same-day follow-on paragraph, plain language, no overclaiming); a new
portable owner E4 script, `docs/owner-e4-menstrual-journey.md`,
committed to the repository (superseding the prior wave's failed
`vscode-webview://` artifact link). **Preserved, not touched**: every
existing finding ID and evidence status in the master finding
register/requirements ledger — this wave's work is scoped entirely to
this charter, not a re-litigation of unrelated findings. **`E4` is not
marked passed for anything in this section, and no overall launch GO
is declared anywhere in this wave's documentation updates.**

All changes on this same branch, PR #4, still **draft and unmerged**.

## 11. Independent Review Fixes wave (2026-09-20, same branch)

An independent review of Section 10's own work found seven real issues.
All seven are addressed here; none required restoring any legacy Fiqh
fallback.

**Fix 1 — eliminate duplicate daily notifications.** Section 10's own
two-tier notification design (a 7-day exact rolling window plus an
OS-native recurring fallback layered on top, both active simultaneously
for the same days) was reviewed against the installed
`flutter_local_notifications` plugin's actual native source rather than
assumed reliable cross-platform: Android's `zonedScheduleNotification`
genuinely delays a recurring schedule's first fire to a future
`scheduledDate`, but iOS's `buildUserNotificationCalendarTrigger`
(`ios/.../FlutterLocalNotificationsPlugin.m`) builds its
`NSDateComponents` for a time-only match from **only hour/minute/second
— year/month/day are discarded** before ever reaching
`UNCalendarNotificationTrigger`. Per Apple's own calendar-trigger
semantics, this fires at the *next* occurrence of that clock time
regardless of which future date was requested — meaning the "delay the
fallback until day 8" design would, on iOS specifically, have started
firing on day 1, genuinely duplicating every day the rolling window
already covered. This is a real, verified platform inconsistency, not a
theoretical risk.

Per that finding's own explicit instruction ("if the platform cannot
reliably support the intended hybrid, choose one predictable,
documented scheduling architecture instead of allowing duplicates"):
the recurring fallback is removed entirely.
`ActiveBleedingReminderScheduler.defaultRollingWindowDays` is widened
from 7 to **30** — using the exact same one-off, per-day-exact
`zonedSchedule` call the window already used (verified reliable on
both platforms: the same iOS function's non-time-only branch builds its
`NSDateComponents` from the *full* date, never discarding it). Single
mechanism, single owner, no overlap possible by construction. 30 was
chosen, not left arbitrary: it is a full month (comfortably covers any
realistic gap between app opens) and, audited as its own test, leaves
34 of iOS's shared 64-pending-notification budget free for
cycle/pregnancy/nifas/wellbeing plus future headroom, even with the
entire window scheduled at once.

A second, real, independently-found gap surfaced by this same
investigation: both `start_bleeding_sheet.dart`'s and
`daily_checkin_sheet.dart`'s end-episode paths already looped over
`ActiveBleedingReminderScheduler.rollingWindowReminderIds` to cancel
the *whole* window (not only today's id) — that loop now correctly
covers the new, larger 30-day size automatically, since both reference
the one shared constant.

New coordinator-level tests prove, against a real mocked plugin
channel: exactly one `zonedSchedule` call per reminder id across a full
30-day window (never twice for the same id); at least 15 consecutive
days present, spanning the old 7-day boundary; and zero
`matchDateTimeComponents`-based registrations for this reminder type at
all. `E4` (real device behavior) remains explicitly not claimed — this
is the honest limit of what a mocked-plugin-channel test can prove.

**Fix 2 — correct calendar uncertainty semantics.** The canonical
calendar's day-cell Semantics announcement collapsed two genuinely
different facts into the same phrase: a day with *no report at all*
and a day with an *explicit "I'm not sure"* observation were both
announced as "No recorded bleeding" — silently treating a real,
present answer as if nothing had been recorded. Now four distinct,
tested announcements: no entry recorded / reported as uncertain /
reported: no bleeding / reported: bleeding (with its provenance
appended). The already-correct *visual* distinction (a muted tint plus
a small question-mark icon for uncertain days) is untouched — this fix
is specifically the audible/semantic side.

**Fix 3 — detect actual corrections via `supersedes_id`, never same-day
observation count.** `isCorrected` was computed as
`rawForDay.length > 1` — meaning three genuinely independent same-day
observations (no revision relationship between them at all) were
incorrectly flagged as "corrected" purely because there happened to be
several of them. Now computed as
`rawForDay.any((o) => o.supersedesId != null)` — the same canonical
revision-chain fact the effective-value resolver itself already relies
on. Four scenarios directly tested: three independent observations
(no correction indicator); one observation plus one real correction
(indicator present); a correction-of-correction (full history
retained, effective tip correct); and multiple independent
observations where only one is corrected (accurate combined display,
indicator present for the real correction, unaffected by the unrelated
independent one).

**Fix 4 — make degraded calendar data explicit.** `LoadDegraded`
(a partially-successful read with at least one quarantined row) was
previously indistinguishable from a clean `LoadSuccess` — folded
silently into "the data," with no notice shown and no restriction on
computing a forward prediction from it. Now tracked as its own state
(`_episodesDegraded`/`_observationsDegraded`), surfacing the same
distinct, non-alarming, retryable notice a degraded observations read
already showed, and explicitly suppressing the forward projection
whenever either read is degraded — a prediction is never computed from
evidence known to have a gap. Four scenarios tested separately: clean
empty, fully unavailable, degraded, and complete.

**Fix 5 — prove actual F7 category coverage, not a legend-only claim.**
An audit of all six `EvidenceProvenance` categories against real
production data sources and real UI surfaces found that two of the six
— `legacyUnverified` and `userReportedEstimate` — appeared only in the
calendar's own legend, with zero code path ever attaching either to an
actually-rendered record. Both now have a real, tested surface:

- `legacyUnverified`: the *legacy* `CycleCalendar` widget (Section
  10's own F7 fix already touched its Semantics localization) is the
  one place such a record can genuinely exist — the new canonical
  calendar deliberately never reads `cycle_entries` at all. A day
  whose `CycleLog.dataProvenance` is `legacyUnverified` now shows a
  small, additional icon and an extended Semantics disclosure, reusing
  the already-written (but previously uncalled) `provenanceForCycleLog`
  mapping — the day's own haid/tahara marker logic is untouched; this
  is purely an honest, additive visibility flag, never a claim the row
  is now a canonical observation.
- `userReportedEstimate`: `CycleBaselineRepositoryImpl.getBaseline`
  already existed, written once during onboarding, but was never
  called from anywhere in the app — the estimate had nowhere to be
  displayed. Now shown as its own labeled summary line on the
  canonical calendar, explicitly badged as an estimate, and — the
  charter's own explicit prohibition — never attached to any specific
  calendar day (an estimate is a stated generalization, not an
  observation of a particular date; a dedicated test confirms a real
  observed day's own Semantics label never mentions the estimate).

**Fix 6 — correct the regression-baseline report.** Section 10's own
baseline comparison used `915af02` — a checkpoint on this same PR
branch, not the actual merge base. Re-verified via a fresh `git
worktree` at the true merge base, `e4cc02e28c8df7220ed21090e3634311e1a3a28d`:
all 10 of the previously-reported "pre-existing" failures are
confirmed genuinely present there too — none was a false attribution.
The one test that did *not* reproduce at the merge base,
`notification_multi_day_continuity_test.dart`, was introduced within
this PR itself and had a real flakiness of its own: it independently
re-derived its expected reminder ids via a second, separate real-clock
read, racing (astronomically rarely, but genuinely) against
`BleedingEpisodeRepositoryImpl.localToday`'s own internal real-clock
read inside `NotificationRefreshCoordinator.refresh()`.
`localToday` is deliberately real-wall-clock-only by design (see its
own dedicated test and PR #4 hardening Blocker 7 doc comment) — not a
bug to "fix" by making it `AppClock`-injectable. The correct fix was in
the test: compute "today" once, the same way the production code
derives it, and reuse that single value throughout, rather than
re-deriving it independently. Verified clean across 5 consecutive
runs. `NotificationRefreshCoordinator.refresh()`'s own `now` was
additionally switched from raw `DateTime.now()` to `AppClock.now()`
for general consistency with this codebase's established time-
injection pattern elsewhere (harmless — `AppClock.now()` defaults to
real `DateTime.now()` in production, and no other test exercises
`refresh()` directly).

Final count after all six code fixes: **739 tests, 10 failures — all
10 confirmed identical to the true merge-base baseline. Zero PR-
introduced regressions remain.**

**Fix 7 — validate the owner E4 script.** The prior wave's step 10
("Notification delivery — multi-day, and tap in all three app states")
chained a 5-day uninterrupted no-reopen delivery test together with a
same-run notification tap — but tapping a notification reopens the
app, which changes the very conditions the 5-day test was supposed to
be measuring. Split into two independent steps: step 10 (five real
days, delivery only, explicitly "do not tap anything") and a new step
11 (tap in each of the three app states, as its own separate, later
run using fresh notifications). All subsequent steps renumbered
(12-15). Step 10's own stale "Failure signal" text (describing the
now-removed two-tier hybrid) was also corrected to match Fix 1's new
single-window architecture. The rest of the script's own constraint —
every step is a real user-facing interaction with a plain pass/fail
criterion, never asking the owner to inspect a server row count or
diagnose a race condition — was already satisfied and is unchanged.

All changes on this same branch, PR #4, still **draft and unmerged**.
No `E4` (real device) evidence is claimed for any of these seven fixes.

## 12. Notification Cancellation Closure wave (2026-09-20, same branch)

Section 11's Fix 1 established the single 30-day exact-window
architecture. This wave closes three real gaps in when that window
actually gets *cancelled*, not merely stopped from growing further.

**Finding 1 — disabling the preference did not cancel what was already
scheduled.** `_refreshActiveBleeding`'s `!enabled` branch previously
just returned — correct for a fresh session that never scheduled
anything, silently wrong for the far more common case of an
already-scheduled window from *before* she turned the reminder off. A
new `_cancelStaleActiveBleedingWindows` helper now runs on that branch:
it reads the user's own episodes (`getEpisodesForUser`, already-loaded
data, no new persisted state), bounds the sweep to episodes whose date
range could still plausibly overlap a previously-scheduled window
(`today - 30 days` cutoff, so an old account's ancient episodes are
never swept), and cancels each id in range — recording a `cancelled`
audit event **only** when the platform genuinely acknowledges the
cancel call, never on a rejected one. Separately,
`NotificationSettingsViewModel.updatePreference` now calls
`NotificationRefreshCoordinator.refresh()` immediately after a
successful `savePreferences`, instead of waiting for the next app
start/resume — mirroring the exact "schedule immediately" pattern the
dashboard's own contextual-consent flow already established.

**Finding 2 — a remotely-ended episode left local reminders active.**
The `isEligible(episode)` false branch (a canonical refresh
*verifying* no open episode remains) now runs the same
`_cancelStaleActiveBleedingWindows` sweep. Closure Blocker 1 discipline
is preserved throughout: a genuine read failure
(`LoadUnavailable<BleedingEpisode?>`) returns immediately, before this
branch is ever reached, and triggers no cancellation — only a
*verified* absence (a real `LoadSuccess`/`LoadDegraded` with no
eligible episode) counts. Account-switch leakage was found to already
be handled by an existing mechanism (`AuthController`'s
`cancelAll()` at sign-out, `lib/core/auth/auth_controller.dart:253`) —
this wave adds test coverage for it, not new production code.

**Finding 3 — reminder-time and timezone changes could leave stale
ids.** Two additions: (a) every refresh of an eligible episode now also
sweeps ids for days strictly before `today` within that episode's own
range (covers both ordinary day-forward progression and
timezone-shift-induced staleness, with no new persisted "last
scheduled window" cache needed); (b) `refreshLocalTimezone(forceRefresh:
true)` moved from being each caller's own responsibility into
`NotificationRefreshCoordinator.refresh()` itself, so every call site —
`main.dart`'s app-resume handler, the dashboard's contextual-consent
flow, and this wave's new Settings-toggle call site — picks up a
genuinely current device zone before any rescheduling, rather than
relying on each remembering it separately (the dashboard call site had
this exact gap before this wave; it is fixed as a side effect of
centralizing the call, not fixed separately). Historical observation
timestamps are never touched by any of this — only future scheduling.

Eight new coordinator-level integration tests, against the real
coordinator with an injected/mocked notification platform channel,
cover exactly the required scenarios: (1) schedule a full 30-day
window, then disable — zero outstanding active-bleeding ids; (2)
disable then re-enable — exactly one valid, freshly-scheduled reminder
per eligible day, not a permanently-cancelled one; (3) change the
preferred time — outstanding reminders reflect the new time (asserted
as a delta between two scheduled calls, not a hardcoded absolute hour,
since this test file's `tz.local` falls back to UTC in the absence of
`mockDeviceTimezoneForTest()`); (4) an episode verified ended remotely
is cancelled on this device's next successful refresh; (5) a read
failure produces zero false cancellations; (6) account switch reaches
the platform's `cancelAll` and the new account schedules independently
afterward; (7) a platform-rejected cancel call is never recorded as a
false `cancelled` audit event, and a later successful call still
succeeds; (8) cycle/pregnancy/nifas/wellbeing scheduling is untouched
by the active-bleeding cancellation sweep.

Full-repo verification after this wave: `dart format` and `flutter
analyze` clean on every file this wave touched (a pre-existing,
unrelated repo-wide formatting drift across ~67 other files was left
untouched — out of this wave's scope); **747 tests, 10 failures — the
same 10 golden/parity-image failures already confirmed present at the
true merge base in Section 11's Fix 6, zero new regressions**; BR-002
migration reproducibility (`scripts/validate_migrations.sh`) reconfirmed
passing (unaffected — no SQL touched this wave).

As with every prior wave, `E4` (real device) delivery/cancellation
timing is not claimed here — a mocked plugin channel proves the
coordinator's own logic is correct, not that a real OS actually honors
a `cancel` call within any particular latency. Cross-device
cancellation is, and remains, bounded by "this device's next
successful refresh" — never instantaneous, and never claimed while a
device is offline or the app never reopens.

## 13. Local Notification Reconciliation Closure wave (2026-09-21, same branch)

Section 12's own cancellation sweeps (`_cancelStaleActiveBleedingWindows`)
still depended on `getEpisodesForUser` — a Supabase read — to decide what
to cancel. This meant an explicit local opt-out (Settings → reminders off)
could silently fail to take effect while offline, mid-outage, or with an
expired/refreshing session: the exact scenario a *local* notification
toggle must never depend on a network round trip to honor.

**Architecture change.** `NotificationService` gained
`pendingActiveBleedingReminders()` — a thin wrapper over
`flutter_local_notifications`' own `pendingNotificationRequests()` API
(confirmed via direct source inspection, v22.3.0: returns
`id`/`title`/`body`/`payload` per pending request), purely local, never
touching Supabase. It decodes each request's own opaque Commit E7 payload
(`type`/`userId`/`episodeId`/`localDate` — never flow/Madhhab/notes/Fiqh
content) and returns only well-formed `activeBleedingCheckin` entries — a
different type, a payload that isn't valid JSON, or one missing a
required field is silently excluded, never crashes the sweep. Returns a
clean structural type (`PendingActiveBleedingReminder`), never the
plugin's own request object (which also carries raw title/body text), so
no caller outside this one file ever touches plugin internals.

`NotificationRefreshCoordinator` now reconciles against this actual OS
set instead of inferring from episode history:

- **Disable, or a verified "no open episode"**: cancels every pending
  request the payload attributes to the current signed-in user — no
  `getEpisodesForUser` call anywhere in either path. Account isolation is
  enforced structurally (`payload.userId == currentUserId`), never by
  trusting which reminder id happens to look "recent."
- **An eligible open episode**: `desiredIds` is exactly the current
  30-day plan's own ids (E6-aware — today's id is already absent when
  satisfied); `actualOwnedPendingIds - desiredIds` (scoped to this
  user+episode) is cancelled, and every desired id is (re)scheduled
  regardless (an idempotent replace for one already correct). This one
  pass subsumes Section 12's separate today's-id and stale-day sweeps,
  and correctly handles a shifted window from ANY cause — timezone
  change, ordinary day-forward progression, or a preferred-time change —
  without needing `episode.startDate` as a bound.

A rejected platform `cancel` call is still never recorded as a successful
`cancelled` audit event, and never stops the rest of the sweep from being
attempted — unchanged discipline from Section 12, re-verified against
the new architecture.

**Twelve integration tests** against the real coordinator with a mocked
plugin channel, extended to simulate the OS's own live pending-request
state (populated on `zonedSchedule`, removed on an accepted
`cancel`/`cancelAll`): (1) 30 scheduled, then Supabase fully unavailable
(both reads), then disabled — zero owned ids remain, zero
`getEpisodesForUser` calls; (2) Supabase unavailable while enabled — no
false episode-end inference; (3) a verified clean `getOpenEpisode(null)`
cancels local pending requests with zero `getEpisodesForUser` calls; (4)
(5) a simulated day-boundary shift backward/forward (via `AppClock`,
since the plugin's own `pendingNotificationRequests`/`zonedSchedule`
validate against the real wall clock, not an injectable one — a genuine
device timezone change itself remains E4-only) proves the old
out-of-window edge is cancelled and the new edge is added; (6) a
preferred-time change reschedules the same logical days with no stale
duplicates; (7) a malformed pending payload is ignored safely; (8) another
user's own pending request survives this user's disable; (9)
cycle/pregnancy/nifas/wellbeing untouched; (10) one rejected cancellation
never aborts the rest, never falsely audited, recovery still possible;
(11)/(12) re-enable and account-switch regression coverage carried
forward from Section 12.

Full-repo verification: `dart format`/`flutter analyze` clean on every
file this wave touched; **751 tests, 10 failures — the same 10
golden/parity-image failures already confirmed identical to the true
merge-base baseline, zero new regressions** (net +4 tests versus Section
12's 747, reflecting 12 new tests replacing the prior 8). BR-002
migration reproducibility (`scripts/validate_migrations.sh`) could not be
re-run to a clean pass this wave: three consecutive genuine attempts each
timed out identically at `supabase start`'s own container health-check
stage (analytics/vector/realtime/storage/pg_meta/studio all reported
"not ready: unhealthy"), before the script's own schema-validation logic
ever ran — an environment/docker resource constraint in this sandbox, not
a code issue: this wave touched zero SQL/migration files (confirmed via
`git diff --stat -- supabase/`), so the schema-contract itself is
unaffected and expected to still pass in a healthier environment or in
CI's own dedicated runner.

As with Section 12, `E4` (real device) evidence is not claimed: a mocked
plugin channel proves the reconciliation logic is correct, not that a
real OS actually honors a `cancel`/`pendingNotificationRequests` call
within any particular latency, nor that a real device timezone change is
picked up correctly (only a same-process day-boundary simulation is
exercised here).

All changes on this same branch, PR #4, still **draft and unmerged**.
