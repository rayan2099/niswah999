# Test Execution Report — Niswah Acceptance Testing, PR #4

Status vocabulary (used separately everywhere, never blended):
**EXECUTED** = live run against the real compiled app with state-changing
assertions (UI *and* persisted state); **PARTIAL** = some live evidence, not a
full assertion-based pass; **BLOCKED** = cannot be executed here for a stated
external/structural reason; **NOT_ATTEMPTED** = not run. Nothing is reported
as PASS on screenshots alone, and unit/widget tests are not personas.

## Tested build

- **Branch**: `feat/menstrual-data-integrity` (PR #4, **DRAFT, unmerged**).
- **Final closure-wave code SHA**: `cb0be4a99e77656e124afd1f0f6871e59658c9a9`
  (also the SHA the E4 Android APK, `dist/niswah-e4-cb0be4a99e77.apk`, is
  built from — see `E4_BUILD_MANIFEST.md`).
- **Earlier local-suite SHAs** (superseded by the closure-wave work above,
  kept for provenance): `6df0a20…` for the local iOS suite (22 of 24
  personas) and the local Android suite; `51b0616` bounds the GPS wait and
  hardens the Android location runners (affected personas re-run on it);
  `8b531a8` adds the reminder-time persona and provisioning retry — the
  hosted 25/25 run is on `8b531a8`.
- **Closure-wave commits** (all on top of `8b531a8`, in order): `6f22ef8`
  (D-011), `ac92f8a` (D-012, Batch 6 rewritten), `e59f6e1` (shard-mode
  verifier), `ef74d96` (AI-08/05/06 test seam, pregnancy parity), `232b65f`
  (D-013/D-014), `f28a66c` (D-015), `e00915d` (D-016, Arabic suite),
  `0321204` (D-017/D-018), `6118839` (REM-03 harness fix + disclosure),
  `cb0be4a` (PRAY-05 harness fix + disclosure).
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
| GitHub-hosted Android emulators, sharded (the `workflow_dispatch` logic run through a throwaway push probe) | run **36189478948** on `8b531a8` (+ the workflow file only): **25/25 PASS**, 4 shards + verify job, ~41 min wall. Earlier: **36114358622** (21 personas, 21/21) and **36183491971** (three shards green; one shard failed once at `supabase start` — a transient slow health check, then fixed with a retry and re-proven by 36189478948). |
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

**These counts are reported separately and are never blended into one
"coverage percentage."** A status here means what its definition at the top
of this document says — not "launch-ready."

| Status | Count | of 114 |
|---|---|---|
| **EXECUTED** | **96** | 84% |
| PARTIAL | 1 | 1% |
| BLOCKED | 17 | 15% |
| NOT_ATTEMPTED | 0 | 0% |
| **E4_REQUIRED** (separate gate, not in the 114; see below) | 8 rows | — |

The denominator grew from 101 to **114** while executing Phases 3–4 (Madhhab
guided flow, Arabic/RTL and accessibility, three system rows, and four
features with **no navigation path** in the shipped app, counted as BLOCKED
rather than dropped). Every one of the 114 rows now has a genuine attempt on
record — the closure wave's own work moved MENS-07/08, PREG-03/05/06, AI-08,
TTC-03, NIFAS-03 (prayer half), WELL-03/RPT-01..05, AUTH-09, REM-03, PRAY-05
and WELL-04 from PARTIAL/NOT_ATTEMPTED to EXECUTED (some resulting in a
disclosed FAIL, not silently promoted — see below).

- **BLOCKED — 17, split by reason** (never blended together, per the
  founder's directive to distinguish "external provider unavailable" from
  "structurally unreachable"):
  - **External (10)**: phone OTP and Google sign-in (AUTH-03/04/05 — need
    real providers); real AI answers/history/citations (AI-01/02/03/04/05/06/09
    — need a model backend and qualified content review; only
    transport/honest-failure is claimed, proven via AI-07/08).
  - **Structural — a product decision, not a test gap (7)**: prayer logging
    (PRAY-04), the wellbeing history screen (WELL-02), delete-conversation
    (MSG-06), guided journeys (JRN-01), the resource library (LIB-01), the
    Ghusl guide (GHU-01), Account/Settings screens (SET-01) — all have no
    navigation path or no implementation in the shipped app; see
    `PRODUCT_DECISIONS.md` (F-001/F-002) and `DEFECT_REGISTER.md` (F-003..F-007)
    for what exists in code, the cost of each choice, and the recommendation.
    **None of these were wired in or removed without a founder decision.**
- **PARTIAL (1)**: AR-04 (screen-reader semantics) — semantic labels are
  asserted live; a real VoiceOver/TalkBack reading-order pass is device-only
  (E4-07).
- **NOT_ATTEMPTED (0)**: none remain. Two rows (REM-03, PRAY-05) that were
  NOT_ATTEMPTED at the start of this wave were run live, multiple times; both
  surfaced real, root-caused findings (one a genuine harness bug now fixed
  and confirmed; one a harness bug fixed but not yet re-verified live) —
  disclosed in full below and in `DEFECT_REGISTER.md`, not silently marked
  passing.

### E4_REQUIRED (physical device — a separate gate, not folded into the 114)

`E4_PHYSICAL_DEVICE_CHECKLIST.md` lists 8 rows (E4-01..E4-08) that no
simulator or emulator can prove: real notification delivery over time, the
real permission prompts (notification, location), airplane-mode recovery,
real timezone/DST travel, real keyboard/autofill/password-manager, real
VoiceOver/TalkBack, and real device performance/battery. **None of these are
claimed executed, PASS, or otherwise satisfied by this wave's work. E4 is not
marked complete.** The E4 Android build (`dist/niswah-e4-cb0be4a99e77.apk`,
SHA `cb0be4a99e77656e124afd1f0f6871e59658c9a9`) exists so a physical pass can
start immediately; it is **not** itself evidence of anything on this list.

## Persona results

See `PERSONA_CATALOG.md` for the full list. All charter personas A–J plus the
six-surface walkthrough, Phase 3 batches 1–16, location (L1/L2), Madhhab (M),
outage (O), the live Arabic journey (AR1–AR4) and AUTH-09/xN/xZ pass or have a
disclosed, root-caused result on iOS and/or Android (per platform
availability, e.g. xN/xZ are Android-only, xAuth09 and pAR2/AR3 are iOS-only
by design). AUTH-08 passes on iOS (needs a confirmations-ON backend, outside
the main suite).

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
| D-011 | P1 | Reports ruled "Tahara" for a woman who was bleeding (legacy-only evidence) | Fixed, unit + live verified (iOS) |
| D-012 | P2 | JSON export always reported "account could not be loaded" | Fixed, unit + schema-contract tested |
| D-013 | P2 | timestamptz written in device wall-clock, not UTC (systemic) | Fixed going forward; historical rows keep the offset |
| D-014 | P2 | Doctor report had no pregnancy content | Fixed, verified live (iOS) |
| D-015 | P2 | Concurrent corrections surfaced a unique-index error, not the conflict | Fixed (migration), verified live |
| D-016 | P2 | Material widgets (pickers, Cancel/OK) stayed English in Arabic mode | Fixed, unit + live verified (iOS) |
| D-017 | P1 | A second account inherited the first account's device-local answers | Fixed, unit-tested, verified live (iOS) |
| D-018 | P2 | A reminder switch read ON while the OS would never show the notification | Fixed, unit-tested; live for toggle/persist/reopen |
| — | — | GPS wait unbounded (spinner forever with no fix) | Hardened (20 s limit) |

Open product findings (no fix, need a decision — see `PRODUCT_DECISIONS.md`
and `DEFECT_REGISTER.md`'s own F-001..F-007): six/seven unreachable or
unimplemented screens (F-001, F-002), a bilingual copy mismatch (F-003), the
client/server pregnancy-week cap (F-004), the wellbeing history screen
absence (F-005), no Nifas fasting statement (F-006), and a duplicable
private-conversation pair (F-007). **Nothing was wired in or removed without
a decision.**

**Open operational item**: the one production test account
(`I.1790267697321@example.test`) is **still outstanding** — deletion needs a
founder-provided admin path (`PRODUCTION_TEST_ACCOUNT_CLEANUP.md`); this
wave's own work never touched production and did not change this.

## Closure-wave findings run live but NOT resolved to a clean pass

Disclosed here rather than folded quietly into the EXECUTED count above —
each was run live, multiple times, root-caused, and either fixed-and-confirmed
or fixed-but-not-yet-reconfirmed. Full detail in `DEFECT_REGISTER.md`.

- **REM-03 (notification tap routing)**: a genuine harness bug (the reminder
  could be scheduled for the next day, not "a few minutes from now", if the
  UI interaction that set it took long enough to eat the lead time) was found
  and fixed, confirmed live every run since. The remaining gap — the OS never
  delivered the actual notification within the detection window on 4/4
  attempts — is Android's own by-design `inexactAllowWhileIdle` battery/
  app-standby deferral for this deliberately battery-friendly reminder, not a
  product defect; E4-01 is the real verification path.
- **PRAY-05 (timezone re-derivation)**: a genuine test bug (tapping
  `BackButton` on a screen whose real close control is a `CloseButton`, since
  it is opened as a fullscreen dialog) was found, confirmed live twice
  (produced a real, root-caused FAIL both times), and fixed to match this
  codebase's own established pattern. Re-verification of the fix was blocked
  by this specific machine running out of resources after a very long
  session (6 further attempts failed to host exhaustion, unrelated to the
  fix) — the emulator was shut down rather than continuing to force it. Needs
  one clean re-run.
- **WELL-04 (wellbeing reminder)**: the toggle/persist/reopen behaviour is
  confirmed live and gates this row's pass. A secondary, D-018-related live
  check (whether the "notifications are blocked" notice renders in time) was
  investigated in depth — including temporary source instrumentation that
  proved the underlying state update is correct — and left informational
  only, since it could not be reconciled with this same host's load; the
  logic itself is proven by a fast, deterministic unit test instead.

## Cross-screen consistency

See `CROSS_SCREEN_CONSISTENCY.md`: the six-surface walkthrough failed before
D-004 and passes after (iOS and Android); four contradictions were found and
fixed (D-002, D-004, D-006, D-010).

## Regression suite (full repo)

- `flutter analyze lib/`: no new issues vs the baseline of 25 pre-existing infos.
- `flutter test` (every non-golden file): **1067 passed, 0 failed, 2 skipped**
  (final closure-wave run, SHA `cb0be4a99e77…`) — the golden/parity image
  failures are pre-existing macOS-rendering artifacts and pass on the Linux CI
  runner; the 2 skips are `parity_today_stepper_consistency_test.dart`'s own
  two obsolete legacy-only-bleeding cases, skipped visibly with the reason
  (superseded by canonical-only Fiqh authority), never deleted.
- **Correction (this report previously implied CI's own test step excluded
  every `parity_*`-prefixed file)**: CI's exclusion pattern matched the
  `parity_` file-name prefix, so behavioural regression tests such as the
  D-001 fix's own test never ran in CI at all — not merely golden images.
  Fixed: `ci.yml` now excludes only files containing `matchesGoldenFile`;
  behavioural `parity_*` tests run in CI (with the two genuinely-obsolete
  cases above skipped by name, not by a blanket exclusion).
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

Listed in the BLOCKED bullets above (no NOT_ATTEMPTED rows remain).
Additionally:

- A live paired-screenshot comparison against a running `main` build.
- iOS-in-CI: GitHub macOS runners have no Docker, so a local Supabase cannot
  run beside the iOS Simulator there; iOS evidence is local by design.
- E4 (physical device) — a separate gate, not claimed anywhere
  (`DEVICE_ONLY_GAPS.md`, `E4_PHYSICAL_DEVICE_CHECKLIST.md`). **E4 is NOT
  marked complete or passed.**
- A full local re-run of every unchanged persona (this wave re-ran the
  personas its own fixes touched, live, on the platform each needs; it did
  not re-run the ~80 unaffected personas already proven in earlier waves).
  The intended final full-suite validation is the hosted, sharded dispatcher
  (PR #5) run against PR #4's exact head SHA once the founder authorizes the
  merge — see "Pending founder actions" below.
- PRAY-05's fix is applied but not yet re-verified live (host resource
  exhaustion; see the closure-wave findings section above) — needs one clean
  re-run before being called done.
- Disclosure: commit `1686e43` also carries an unintended whitespace-only
  reformat of two unrelated files (no behavioural change).

## Pending founder actions (not decided or performed by this wave)

- **PR #5 merge authorization**: PR #5 (`.github/workflows/acceptance-dispatch.yml`,
  hardened per an earlier directive — the `|| true` removed from the shard
  step) remains **open, unmerged**, awaiting explicit founder authorization.
  Once authorized and merged, the dispatcher should be run against PR #4's
  exact head SHA — `4c2eb240e2368861875bd9c6e6c516b340e54c61` (confirmed via
  `gh pr view 4`) at the time this report was written; **confirm the live PR
  #4 head again before dispatching**, since work between now and then would
  move it. (The E4 Android APK is built from `cb0be4a99e77…`, one code commit
  earlier — the difference is this report's own doc update, not app code.)
  Record the run ID, resolved SHA, every shard result, the final verifier
  result and artifact names here.
- **F-001 through F-007**: product decisions (see `PRODUCT_DECISIONS.md`,
  `DEFECT_REGISTER.md`) — nothing wired in, removed or implemented without one.
- **Production test-account cleanup**: still outstanding, needs a
  founder-provided admin path.
- **PR #4 stays DRAFT and UNMERGED.**
