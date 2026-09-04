> ⚠️ **PROPOSED — NOT IMPLEMENTED.** This is a design-only remediation plan. No dependency upgrades, config changes, lockfile edits, or code changes were made during this audit. Nothing below should be described as fixed until each item is separately implemented and revalidated.

# Dependencies & Configuration Audit — Remediation Plan (Phase 3)

## Root-Cause Map

| Finding | Symptom | Root cause | Confidence | Related findings | Remediation phase |
|---|---|---|---|---|---|
| DC-001 | Secrets compiled into every release binary | `.env` declared as a Flutter `assets:` entry instead of using a build-time injection mechanism (`--dart-define-from-file`) or a native secrets store | High | DC-002, DC-003, DC-004 | R1 |
| DC-002 | `APP_ENV` has no effect on behavior | Environment concept was scaffolded (loaded, validated, exposed) but never wired into any conditional logic — no flavors/build modes ever consumed it | High | DC-001 | R1 |
| DC-003 | `.env.example` incomplete/inaccurate vs actual code requirements | Likely AI-agent or manual drift: `GeminiService` was added/changed later and never reconciled with `AppEnvironment`'s AI-key scaffold or with `.env.example` | High | DC-001 | R1 |
| DC-004 | Missing config causes silent infinite splash hang instead of clear failure | Global `runZonedGuarded` catch-all added for an unrelated deep-link crash bug, but its blast radius was never scoped to exclude startup-critical config validation | High | DC-001 | R1 (urgent) |
| DC-005 | Release Android build would be signed with debug key | Flutter template placeholder never replaced with a real release signing config | High | DC-006, DC-010 | R1 (urgent) |
| DC-006 | No reproducible/automated build pipeline | No CI/CD ever set up for this repo | High | DC-005, DC-007, DC-010 | R2 |
| DC-007 | No enforced Flutter/Dart version | No FVM/version-pinning tool adopted | High | DC-006 | R2 |
| DC-008 | Orphaned Firebase config + credential in git | Leftover from an earlier/parallel Firebase-based prototype, never cleaned up after migrating to Supabase | Medium | — | R3 |
| DC-009 | Debug auth-bypass flag shipping in `main.dart` | Convenience flag added during onboarding-flow development, not gated behind a build-mode check | High | — | R3 |
| DC-010 | iOS release build has no pinned signing team | Same root cause class as DC-005, Automatic signing never replaced with a manual/CI-manageable config | High | DC-005, DC-006 | R1 (urgent) |
| DC-011 | Dependency deprecation status unverified | No network/pub.dev access available during this audit | N/A (procedural) | — | R2 |

---

## Remediation Principles Applied

- Fail early: config validation should actually stop the app, not be swallowed.
- Safe defaults: missing config must never silently degrade to a hang or an unsigned/mis-signed build.
- One source of truth: `.env.example` (or its replacement) must match what the code actually reads.
- Separate environments explicitly: dev/staging/prod need distinct build-time config, not one shared `.env`.
- Do not mass-upgrade dependencies as part of this remediation — DC-011 is a verification task, not an upgrade mandate.

---

## R1 — Urgent (pre-launch blockers: DC-001, DC-003, DC-004, DC-005, DC-010)

### R1.1 — Stop bundling `.env` as a compiled asset (closes DC-001, contributes to DC-003)
- **Current:** `pubspec.yaml` → `flutter: assets: - .env`
- **Proposed:** Remove `.env` from the `assets:` list. Replace with Flutter's `--dart-define-from-file=<env>.json` (compile-time, not bundled as a readable asset) for build-time values, or a proper secrets-injection step in a future CI pipeline (see R2).
- **Affected code:** `lib/core/config/app_environment.dart` would need to switch from `flutter_dotenv`/asset-loading to `String.fromEnvironment`/compile-time constants for values that must be baked in, or fetch non-sensitive config from Supabase at runtime instead.
- **Affected environments:** All (dev, any future staging, production).
- **Risk:** Medium — touches the app's core config-loading path; needs careful testing of the config-missing failure path (see R1.3) in tandem.
- **Rollback:** Revert `pubspec.yaml` asset entry; low risk to revert.
- **Validation:** Build a release artifact, unpack it, confirm no secret values are present in the extracted asset bundle.
- **Note:** This is a design proposal only; the actual mechanism choice (dart-define vs. runtime-fetched config vs. native secure storage) should be finalized jointly with the Security audit owner, since it has direct security implications.

### R1.2 — Reconcile documented vs. actual AI configuration (closes DC-003)
- **Proposed:**
  1. Add `GEMINI_API_KEY` to `.env.example` with a placeholder value and a comment noting it's required for AI Advisor/Dream Interpreter.
  2. Either (a) remove the unused `OPENAI_API_KEY`/`NISWAH_AI_API_KEY`/`DREAM_INTERPRETER_API_KEY` scaffold from `app_environment.dart` if that integration path is truly dead, or (b) if it's planned future work, mark it clearly as such in code comments and exclude it from required-config validation until it's actually wired to a feature.
  3. Move `GeminiService`'s key-reading onto the same validated path as the rest of config (`AppEnvironment`) so it gets the same fail-fast treatment as `SUPABASE_URL`/`SUPABASE_ANON_KEY`, rather than silently degrading to `isConfigured == false` at first use.
- **Affected code:** `.env.example`, `lib/core/config/app_environment.dart`, `lib/core/services/gemini_service.dart`.
- **Risk:** Low — additive/documentation-focused, plus one refactor of where `GeminiService` reads its key from.
- **Validation:** Fresh clone + `.env` built strictly from `.env.example` → confirm AI features either work or fail with a clear, early, documented error — not a silent runtime `StateError` surfaced only inside a chat screen.

### R1.3 — Fix the silent-hang startup failure mode (closes DC-004)
- **Proposed:** Narrow the scope of `runZonedGuarded`'s error handling so that a config-validation failure during `AppEnvironment.load()` is caught explicitly (e.g., a dedicated `try/catch` around just that call) and results in `runApp()` being called with a visible, minimal error screen (or at minimum, an explicit `FlutterError.reportError` + a deliberate early return that doesn't leave the user on an indefinite native splash). The broader `runZonedGuarded` handler can remain for genuinely unexpected async errors elsewhere (its original purpose per the code comment — swallowing a Supabase deep-link exception), but startup-critical config validation should not share that same silent fate.
- **Affected code:** `lib/main.dart`.
- **Risk:** Low — purely additive error handling; does not change the happy path.
- **Validation:** Manually clear/corrupt required `.env` values in a disposable local build and confirm the app shows a clear error instead of hanging on the splash screen (this is exactly template §50's "Missing Critical Config Test" — recommended as the first Phase 2B test once a disposable build environment is available).

### R1.4 — Configure real Android release signing (closes DC-005)
- **Proposed:** Generate/obtain a production keystore, store it outside the repo, add a `key.properties`-style file (gitignored) referencing it, and wire `android/app/build.gradle.kts`'s `release` build type to that `signingConfigs` entry instead of `signingConfigs.getByName("debug")`. Document the keystore's secure storage location (secrets manager / CI secret store once R2 lands) — never commit it.
- **Affected environments:** Production release builds only.
- **Risk:** Medium — signing key management is sensitive; losing the release key after first Play Store upload is unrecoverable for that app listing, so this must be done carefully with proper backup.
- **Rollback:** N/A once a release is signed and published with a given key — this is a one-way door, hence "Medium" risk despite being conceptually simple.
- **Validation:** `flutter build appbundle --release`, verify signature with `jarsigner`/`apksigner` shows the release key, not the debug key.

### R1.5 — Configure real iOS release signing (closes DC-010)
- **Proposed:** Set an explicit `DEVELOPMENT_TEAM` in the Xcode project (or move to manual signing with a checked-in-safely provisioning profile reference), decoupling release builds from whichever developer's Xcode happens to be running.
- **Affected environments:** Production release builds only.
- **Risk:** Low-Medium — standard iOS release engineering task, but requires Apple Developer account access this audit did not have.
- **Validation:** Archive/export an IPA and confirm the signing identity matches the intended distribution certificate, not an ad hoc developer identity.

---

## R2 — Pre-launch strongly recommended (DC-006, DC-007, DC-011)

### R2.1 — Stand up a minimal CI pipeline (closes DC-006)
- **Proposed:** At minimum, a single automated workflow that runs `flutter pub get --enforce-lockfile` (or equivalent frozen-install flag), `flutter analyze`, `flutter test`, and a release build, on every push/PR, using a pinned Flutter version.
- **Risk:** Low — additive, does not touch app code.
- **Validation:** A clean CI run succeeding is itself the validation.

### R2.2 — Pin the Flutter/Dart toolchain (closes DC-007)
- **Proposed:** Adopt FVM (or Flutter's built-in version management) and commit `.fvmrc`, or at minimum document the exact required Flutter version in the README and enforce it in the new CI pipeline (R2.1).
- **Risk:** Low.
- **Validation:** CI and local builds both resolve to the identical Flutter version.

### R2.3 — Verify dependency deprecation status live (closes DC-011)
- **Proposed:** Run `flutter pub outdated` and check each direct dependency (especially `flutter_local_notifications`, `supabase_flutter`, `geolocator`, `adhan_dart`) against pub.dev's current listing and any deprecation notices, once network access is available/authorized.
- **Risk:** None (read-only verification) — but any resulting upgrades should be scoped as a **separate, deliberate task**, not bundled into this remediation, per template guidance against generic mass-upgrades.

---

## R3 — Backlog-acceptable cleanup (DC-002, DC-008, DC-009)

### R3.1 — Remove or wire up dead `APP_ENV` logic (closes DC-002)
- Either remove `isProduction`/`appEnvironment` if genuinely unneeded, or use them for something real (e.g., gate `kDebugSkipSignup`, gate verbose logging) — whichever the team decides. Low risk either way.

### R3.2 — Remove orphaned Firebase artifacts (closes DC-008)
- Delete `firebase-applet-config.json`, `firebase-blueprint.json`, `firestore.rules` from the repo (or move to an `archive/` directory clearly marked as historical) once confirmed with the team that no other system depends on them. Coordinate with Security audit before deletion in case the exposed key needs separate rotation/reporting first.

### R3.3 — Gate or remove `kDebugSkipSignup` (closes DC-009)
- Replace the manual `const bool` with a check against `kDebugMode` (from `package:flutter/foundation.dart`) so it can never be `true` in a release build regardless of a forgotten manual edit, or remove it entirely if no longer needed for onboarding-flow development.

---

## Remediation Phase Table

| # | Action | Findings closed | Dependencies/config | Environments affected | Risk | Rollback | Validation |
|---|---|---|---|---|---|---|---|
| R1.1 | Replace bundled `.env` asset with build-time injection | DC-001 | `pubspec.yaml`, `app_environment.dart` | All | Medium | Easy (revert file) | Unpack release build, confirm no secrets present |
| R1.2 | Reconcile AI key docs/code drift | DC-003 | `.env.example`, `app_environment.dart`, `gemini_service.dart` | All | Low | Easy | Fresh-clone build from `.env.example` produces working or clearly-failing AI features |
| R1.3 | Scope startup error handling so config failures are visible | DC-004 | `main.dart` | All | Low | Easy | Missing-config test shows clear failure, not a hang |
| R1.4 | Real Android release signing | DC-005 | `android/app/build.gradle.kts` + new `key.properties` (gitignored) | Production | Medium (one-way once published) | N/A after first publish | Verify signature on built AAB |
| R1.5 | Real iOS release signing | DC-010 | `ios/Runner.xcodeproj` | Production | Low-Medium | Easy pre-publish | Verify signing identity on archived IPA |
| R2.1 | Minimal CI pipeline | DC-006 | New `.github/workflows/*.yml` (or equivalent) | All | Low | Easy | Green CI run |
| R2.2 | Pin Flutter/Dart version | DC-007 | New `.fvmrc` or README + CI enforcement | All | Low | Easy | CI/local version match |
| R2.3 | Live dependency deprecation check | DC-011 | N/A (verification only) | N/A | None | N/A | `flutter pub outdated` output reviewed |
| R3.1 | Remove/wire up `APP_ENV` dead code | DC-002 | `app_environment.dart` | All | Low | Easy | Code review |
| R3.2 | Remove orphaned Firebase files | DC-008 | Repo root files | All | Low | Easy (git revert) | Confirm no references break |
| R3.3 | Gate `kDebugSkipSignup` behind `kDebugMode` | DC-009 | `main.dart` | All | Low | Easy | Release build confirms flag inert |

---

## Remediation Exit Gate

- [x] Root cause documented for every open finding.
- [x] Upgrade/removal rationale explicit (no dependency version upgrades proposed — DC-011 is verification-only).
- [ ] Compatibility reviewed — NOT YET (would require implementing R1.1's chosen mechanism and testing).
- [x] Environment impact known for each item.
- [x] Rollback documented for each item (noting DC-005/DC-010's one-way nature post-publish).
- [x] Build/test validation defined for each item.
- [x] No broad unnecessary upgrade proposed.
- [x] Secret/config changes (R1.1, R1.4) separated from ordinary code changes in this plan.

This plan is **implementation-ready in design** but **no item has been implemented or validated**. Each item requires a separate, explicitly-authorized implementation pass followed by Phase 2B Controlled Validation before it can be marked Verified Closed.
