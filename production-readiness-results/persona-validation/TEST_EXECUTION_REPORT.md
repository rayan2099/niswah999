# Test Execution Report — Niswah Acceptance Testing, PR #4

## Tested build

- **Branch**: `feat/menstrual-data-integrity`
- **SHA tested against (session start)**: `8eaca1007de1fb3c21e2f648beec5157821ccca3`
- **`main` SHA (unrelated, frozen)**: `e4cc02e28c8df7220ed21090e3634311e1a3a28d`
- **Backend under test**: a disposable LOCAL Supabase instance
  (`http://127.0.0.1:54321`), provisioned by
  `scripts/provision_local_test_backend.sh` from the canonical baseline
  + every active migration — never production. The app's real `.env`
  was backed up before each session and restored immediately after;
  `git status .env` was confirmed clean (matches the committed/
  gitignored real config) before finishing.
- **Device**: iOS Simulator, iPhone 15 Pro, iOS 17.5. Android was NOT
  exercised this wave (see `DEVICE_ONLY_GAPS.md`).
- **Automation**: Flutter `integration_test` + `flutter_driver`
  (`flutter drive`), driving the real compiled app — never a test-only
  replacement widget. Maestro was not installed/used.

## Coverage numerator/denominator (see `COVERAGE_MATRIX.csv` for the
row-by-row source of truth)

| Metric | Count |
|---|---|
| Total inventoried features/journeys (`FEATURE_INVENTORY.md`) | **101** |
| EXECUTED (full live pass/fail evidence) | **21** |
| PARTIAL (some live evidence, not a full assertion-based pass) | **6** |
| NOT_ATTEMPTED | **74** |
| **Executed + Partial as a fraction of total** | **27 / 101 (≈27%)** |
| **Fully executed (excluding partial) as a fraction of total** | **21 / 101 (≈21%)** |

**This is not a claim of comprehensive coverage.** 74 of 101 inventoried
features were not attempted this wave. The 27 that were attempted were
chosen to prioritize, per the charter's own explicit instruction, the
incomplete menstrual personas (C, E, F, H, I, J) first, plus the
already-partially-covered ones (A, B, D, G) that this wave's earlier
work had established.

## Persona results

See `PERSONA_CATALOG.md` for the full table. Summary:

- **PASS, live-verified**: A, B, C, D, E, G, J (7 of 10 charter personas)
- **PASS, cited from existing automated suite, not re-run live this
  wave**: F, I (2 of 10)
- **NOT ATTEMPTED**: H (1 of 10)

No persona is reported as PASS on partial/flaky/blocked evidence — see
"Honest accounting of flakiness" below for what was discarded/redone
rather than reported as a false pass.

## Defects found and fixed (see `DEFECT_REGISTER.md` for full detail)

| ID | Severity | Summary | Status |
|---|---|---|---|
| D-001 | P1 | First-ever period showed "Unable to verify" (data-failure copy) instead of an honest "not enough history yet" | Fixed, regression-tested, re-verified live |
| D-002 | P1 | A correction never reached the legacy `cycle_entries` projection; fixing that naively then left two rows for one day | Fixed, regression-tested, re-verified live against a real database |
| D-003 | P2 | A network failure during sign-up showed the raw exception, including the backend's own host and port | Fixed, regression-tested |

No P0 defects found. No defect was worked around by narrowing what the
test checks for — see `DEFECT_REGISTER.md`'s own closing note.

## Cross-screen consistency (see `CROSS_SCREEN_CONSISTENCY.md`)

The write-path consistency question (does a correction/second
observation reach every table it should) was verified live via direct,
independent SQL checks — this is what D-002 was found and fixed
through. The full six-surface READ-side walkthrough (opening Today,
canonical calendar, legacy Calendar tab, Insights, Fiqh/prayer status,
and export/report screens in sequence for one shared synthetic history)
was **not** completed this wave.

## Regression suite (full repo)

- `dart format --set-exit-if-changed`: clean on every file this wave
  touched.
- `flutter analyze lib/`: 25 pre-existing infos, zero new issues, zero
  errors.
- `flutter test` (full suite, run after all fixes): **754 tests, 10
  failures** — the identical 10 golden/parity-image failures already
  on file from the true merge-base comparison in an earlier wave (see
  `docs/menstrual-data-integrity-contract.md` §11's own Fix 6). **Zero
  new regressions.**
- `scripts/validate_migrations.sh` (BR-002): not re-run locally this
  wave (no SQL/migrations touched); last confirmed passing in CI at
  the prior wave's SHA — see that wave's own report.

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

## Deferred / not attempted this wave

- Persona H (returning user, historical/predicted data).
- The full Section 4 broader-product sweep beyond Auth/Onboarding-
  default-path/Reminders (Prayer, TTC, Pregnancy, Nifas, Wellbeing, AI,
  Community, Messaging, Reports, most of Profile) — see
  `COVERAGE_MATRIX.csv`.
- Bilingual (Arabic) live re-verification of this wave's own journeys —
  see `DEVICE_ONLY_GAPS.md`.
- Android live execution — see `DEVICE_ONLY_GAPS.md`.
- The full six-surface cross-screen READ-side walkthrough with one
  shared synthetic history — see `CROSS_SCREEN_CONSISTENCY.md`.
- A live, paired-screenshot before/after comparison against a running
  `main` build — see `BEFORE_AFTER_COMPARISON.md` (the structural
  comparison was completed; the visual one was not).
- CI validation of the new `acceptance.yml` workflow — the file is
  real, runnable infrastructure, but has not itself been triggered and
  watched to completion in GitHub's own environment this wave.
