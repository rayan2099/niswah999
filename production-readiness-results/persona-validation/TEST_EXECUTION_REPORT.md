# Test Execution Report — Niswah Acceptance Testing, PR #4

Status vocabulary (used separately everywhere, never blended):
**EXECUTED** = live run against the real compiled app with state-changing
assertions (UI *and* persisted state); **PARTIAL** = some live evidence, not a
full assertion-based pass; **BLOCKED** = cannot be executed here for a stated
external/structural reason; **NOT_ATTEMPTED** = not run. Nothing is reported
as PASS on screenshots alone, and unit/widget tests are not personas.

## Tested build

- **Branch**: `feat/menstrual-data-integrity` (PR #4, **DRAFT, unmerged**).
- **Code SHA under test**: `6df0a20…` for the iOS suite (22 of 24 personas) and
  the Android suite; one later commit (`51b0616`) bounds the GPS wait and
  hardens the Android location runners, after which the affected personas
  were re-run (see below). Later commits touch only documentation.
- **Backend under test**: a disposable **local** Supabase
  (`127.0.0.1:54321`, or `10.0.2.2:54321` from the Android emulator),
  provisioned by `scripts/provision_local_test_backend.sh`. Never production:
  a three-layer kill switch (host script, `main()` before Supabase/Sentry
  init, persona harness) refuses production/unknown/malformed backends.
- **Devices**: iOS Simulator (iPhone, iOS 17.5, local); Android emulator
  Pixel_8, Android 15, hardware GPU (local); GitHub-hosted Android emulators
  (API 34, software GPU) via the sharded dispatcher probe.
- **Automation**: Flutter `integration_test` + `flutter drive`; results are
  structured JSON judged by `scripts/verify_acceptance_results.py`.

## Suite results (personas)

| Where | Result |
|---|---|
| iOS Simulator, local, full suite | **24/24 PASS** (plus `pR_reminder_time` run individually on both platforms: PASS — added after the full run) — 22 in the full run; 2 (`pBatch7`, `pH`) reported `MISSING_RESULT` for **infrastructure** reasons (the machine lost network during `pub get` for one; a stalled build hit the 1500 s bound for the other) and passed when re-run individually; `p0`, `pAR1`, `pB`, `pL1`, `pL2` were re-run on the final code (see next line). |
| iOS re-run on final code (`p0`, `pAR1`, `pB`, `pL1`, `pL2`) | see "Final re-runs" below |
| Android emulator, local, full suite | **24/24 PASS** — 22 in the full run; `pL1`/`pL2` failed there on Android-only harness problems (below), were fixed and re-run through the same suite runner: PASS |
| GitHub-hosted Android emulators, sharded (`workflow_dispatch` logic via a throwaway push probe, run **36114358622**, 21 personas at that SHA) | **21/21 PASS**, 4 shards + verify job, ~33 min wall |
| Regular CI on the PR head | Analyze & Test, Build Android, Build iOS, BR-002 migration reproducibility: **all green** |

Android-only harness findings (not app defects, but disclosed):
1. A merely *revoked* location permission makes Android raise a **native
   prompt** no Flutter test can answer -> the denied persona now uses the
   `USER_FIXED` ("don't allow, don't ask again") state.
2. `flutter drive` **uninstalls the app when it finishes**, so a runtime
   permission cannot be set on it afterwards -> the suite installs the APK
   explicitly before `pm grant`.
3. An emulator only delivers a fresh GPS fix when one is injected while the
   app is asking -> a fix is injected for the duration of the run. The wait
   itself is now bounded (20 s) in the app so a granted permission with no fix
   shows an honest error instead of spinning forever.
4. Long sessions wedged the local emulator and (separately) Docker Desktop on
   this machine (low free memory/disk); both were restarted, the local
   database volume was intact (verified: 133 accounts, 0 orphans), and the
   affected runs were repeated. No result was carried over from a wedged run.

## Coverage numerator/denominator (`COVERAGE_MATRIX.csv` is the source of truth)

| Status | Count | of 114 |
|---|---|---|
| **EXECUTED** | **78** | 68% |
| PARTIAL | 13 | 11% |
| BLOCKED | 16 | 14% |
| NOT_ATTEMPTED | 7 | 6% |

The denominator grew from 101 to **114** because executing Phases 3–4 added
rows the first inventory pass missed (Madhhab guided flow, Arabic/RTL and
accessibility, three system rows) and four features that have **no navigation
path** in the shipped app. They are counted as BLOCKED rather than dropped.

- **BLOCKED (16)**: phone OTP and Google sign-in (external providers); real AI
  answers/history/citations (need a model backend + qualified review; only
  transport/honest failure is claimed); prayer logging, guided journeys,
  resource library, Ghusl guide, Account/Settings screens (unreachable —
  `DEFECT_REGISTER.md` F-001); delete-conversation (not implemented — F-002).
- **PARTIAL (13)**: session restore across launches (harness limit), revision
  chips, fertility-window values, pregnancy progression,
  the five report/export surfaces (open with real content; figures not
  compared with an oracle), Nifas fasting status (prayer status is asserted),
  wellbeing reminder, screen-reader semantics
  (labels only; real VoiceOver/TalkBack is device-only).
- **NOT_ATTEMPTED (7)**: correction conflict resolution (needs two
  concurrent writers), notification-tap routing, timezone re-derivation,
  pregnancy report, pregnancy AI context, wellbeing history, malformed AI
  response.

## Persona results

See `PERSONA_CATALOG.md`. All charter personas A–J plus the six-surface
walkthrough, Phase 3 batches 1–8, location (L1/L2), Madhhab (M), outage (O)
and the live Arabic journey (AR1) pass on iOS and Android; AUTH-08 passes on
iOS (needs a confirmations-ON backend, outside the main suite).

## Defects found and fixed (`DEFECT_REGISTER.md`)

| ID | Sev | Summary | Status |
|---|---|---|---|
| D-001 | P1 | "Unable to verify" shown for a first-ever period | Fixed, re-verified |
| D-002 | P1 | Correction never reached the legacy projection | Fixed, re-verified |
| D-003 | P2 | Raw exception + host/port on sign-up network failure | Fixed |
| D-004 | P1 | Legacy Calendar/Insights said "no history" for an onboarding-reported period | Fixed, live (iOS+Android) |
| D-005 | P3 | `ai_rate_limit_counters` outlived a deleted account | Fixed, 0 orphans live |
| D-006 | P1 | Offline replay left Today stale / "Salah is obligatory" while bleeding | Fixed, live (iOS+Android) |
| D-007 | P2 | Messaging showed the other user's raw account id | Fixed, live |
| D-008 | P2 | Community leaked a raw exception + backend URL on failure | Fixed, live |
| D-009 | P3 | English pregnancy card showed Arabic text | Fixed, regression test |
| D-010 | P3 | Calendar legend stayed English after a live switch to Arabic | Fixed, regression test |
| — | — | GPS wait unbounded (spinner forever with no fix) | Hardened (20 s limit) |

Open product findings (no fix, need a decision): F-001 six unreachable
screens (prayer logging unreachable), F-002 no delete-conversation.
**Open operational item**: the one production test account
(`I.1790267697321@example.test`) is **still outstanding** — deletion needs a
founder-provided admin path (`PRODUCTION_TEST_ACCOUNT_CLEANUP.md`).

## Cross-screen consistency

See `CROSS_SCREEN_CONSISTENCY.md`: the six-surface walkthrough failed before
D-004 and passes after (iOS and Android); four contradictions were found and
fixed (D-002, D-004, D-006, D-010).

## Regression suite (full repo)

- `flutter analyze lib/`: no new issues vs the baseline of 25 pre-existing infos.
- `flutter test`: see "Final re-runs" (the 10 macOS-only golden/parity image
  failures are pre-existing and pass on the Linux CI runner).
- Notification continuity: 13 pinned clocks x 7 time zones, exact counts
  unchanged (the earlier red CI was a real-wall-clock dependency, fixed with a
  single controlled clock — not loosened, retried or excluded).

## Honest accounting of flakiness encountered and resolved this wave

This section exists because the charter explicitly asks that a
flaky/blocked test never be silently reported as PASS. Real problems
hit and how each was actually resolved, not glossed over:

1. **A stale-build issue**: an early test file had a compile error
   (`t.enterText` referencing an undefined name); `flutter drive`
   silently kept re-running the last successfully-built binary instead
   of failing loudly, producing confusing, non-reproducible-looking
   results for several iterations until a full `rm -rf build/` forced
   a real rebuild and surfaced the actual compile error. Fixed by
   correcting the reference; lesson applied for the rest of the wave
   (verify a real rebuild occurred, not just that `flutter drive`
   exited 0).
2. **Session-state leakage between test runs**: the simulator's app
   install persists its Supabase auth session (Keychain) across
   separate `flutter drive` invocations. Several early "new account"
   test runs silently reused a 2-day-old session instead of creating a
   fresh one, producing confusing account-state mismatches. Fixed by
   adopting `xcrun simctl uninstall` before every subsequent isolated
   persona run (now standard practice for the rest of this wave), and
   this is deliberately exploited (not fought) for Persona I's two-
   phase design, where session persistence across two `flutter drive`
   invocations is the intended mechanism.
3. **A failed `expect()` inside this specific `flutter_driver`-based
   `integration_test` setup was observed to cascade into a fatal
   `FlutterError.onError`-related binding assertion that aborted the
   entire test binary**, rather than cleanly failing just the one test
   and continuing (the behavior a plain `flutter test` run has). Fixed
   by converting every assertion inside live persona tests to a
   logged, non-throwing PASS/FAIL check, with the real verdict computed
   host-side afterward via independent SQL where applicable.
4. **`Process.run('docker', ...)` cannot be spawned from inside the
   compiled iOS app itself** (`ProcessException: Starting new processes
   is not supported on iOS`) — an early design mistake, assuming the
   `integration_test` Dart code ran with host process-spawning
   capability. Fixed by redesigning: the live test logs its own
   identifying values (the test account's email) via `h.note()`
   (forwarded to the host's own stdout through the VM service
   connection), and the actual database verification runs as a
   separate, host-side `docker exec` call after the `flutter drive`
   invocation completes.
5. **A live SQL-injection approach for Persona I's malformed row
   turned out to be blocked by the database's own CHECK constraints**,
   now covering every enum column on both `bleeding_episodes` and
   `bleeding_observations` — a stronger integrity guarantee than
   assumed, not a defect. Persona I's live-injection plan was
   abandoned rather than weakened to "insert a value the schema
   accepts but isn't really representative of the original bug" — see
   `PERSONA_CATALOG.md`'s own note.

Every one of these was root-caused and either fixed or the plan was
changed and disclosed — never silently retried until something looked
like a pass.

## Deferred / not attempted

Listed in the NOT_ATTEMPTED and BLOCKED bullets above. Additionally:

- A live paired-screenshot comparison against a running `main` build.
- iOS-in-CI: GitHub macOS runners have no Docker, so a local Supabase cannot
  run beside the iOS Simulator there; iOS evidence is local by design.
- E4 (physical device) — a separate gate, not claimed anywhere (`DEVICE_ONLY_GAPS.md`).
- Disclosure: commit `1686e43` also carries an unintended whitespace-only
  reformat of two unrelated files (no behavioural change).
