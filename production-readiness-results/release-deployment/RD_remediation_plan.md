# Release & Deployment Audit — Remediation Plan

> ⚠️ **This remediation plan is PROPOSED and NOT YET IMPLEMENTED.** No code, configuration, CI, signing, DNS, or store-console changes were made as part of this audit. Release pipeline, signing, and production-configuration changes require separate technical approval and execution before any part of this plan can be considered done. Nothing below should be described as release-ready until Phase 2B (Controlled Deployment Validation) is actually run and passes.

| Field | Value |
|---|---|
| System | Niswah (Flutter mobile app) |
| Repository | `/Users/rynadalsabh/Niswah` |
| Commit | `13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f` |
| Phase | 3 — Remediation Design |
| Audit date | 2026-09-04 |

---

## Root-Cause Map

| Finding | Release symptom | Root cause | Confidence | Related findings | Remediation phase |
|---|---|---|---|---|---|
| RD-001 | Android release build signed with debug key | Flutter-template placeholder never replaced; no release keystore was ever generated | High (verified) | RD-002, RD-003, RD-010 | R1 (urgent) |
| RD-002 | iOS build has no pinned signing identity | Same class as RD-001 — template default never replaced with an explicit team/manual profile | High (verified) | RD-001, RD-003 | R1 (urgent) |
| RD-003 | No CI/CD pipeline | Never set up for this repo at any point in its (short) history | High (verified) | RD-001, RD-002, RD-004, RD-006 | R2 |
| RD-004 | No SDK version pinning | No FVM/asdf/equivalent adopted | High (verified) | RD-003 | R2 |
| RD-005 | No environment/build separation | Config scaffolding (`APP_ENV`, flavors) never wired into build system or app logic | High (verified) | RD-001 remediation, DC-001/DC-002/DC-003 (owned by Dependencies/Config) | R1 |
| RD-006 | Static build number, no bump process | No process was ever designed because no release has ever shipped | High (verified) | RD-003 (CI is the natural place to automate this) | R1 |
| RD-007 | No changelog/metadata; dead privacy-policy link | Store-submission assets were never produced; UI text for "Privacy Policy"/"Terms of Use" was added as a placeholder and never wired to a real document/URL | High (verified) | Privacy/Compliance audit (document itself), RD-008 | R1 |
| RD-008 | 2-commit squashed git history | History appears to have been intentionally reset ("initial clean commit") for reasons not documented anywhere in the repo | Medium (the reset itself is certain; the *reason* is not confirmable from repo evidence alone) | RD-003, RD-009 | R3 (process, not a code fix) |
| RD-009 | No rollback path faster than store review | No feature-flag system or remote-config layer was ever built; the one working mitigation (disabling the `dr-niswah-chat` function) is an accidental byproduct of normal error handling, not a designed capability | High (verified) | RD-005 (a real config layer would also enable this), FLAG audit gap noted in master baseline | R2 |
| RD-010 | No key-custody plan | Moot until RD-001 is remediated — flagged so it isn't forgotten once a real key exists | N/A (forward-looking) | RD-001 | R1 (bundled into RD-001's remediation) |

---

## Remediation Principles Applied

Per master template §73:

- **Build once, identify exactly:** every remediation below aims to make the eventual artifact traceable to an exact commit + build number + toolchain version.
- **Separate environments:** RD-005's fix should be coordinated with Dependencies/Config's DC-001/DC-002/DC-003 remediation rather than duplicated — see cross-reference note below.
- **Fail pipeline on critical checks:** the proposed CI (R2.1) should block on test failure and on any signing-config regression (e.g., a CI check that fails the build if `signingConfig` resolves to `debug` for a `release` build type).
- **Roll back intentionally:** R2.2 below proposes the minimum viable emergency-mitigation layer given this is a mobile client with no rollback mechanism.
- **Automate repeatable steps:** build-number bumping (R1.3) and toolchain pinning (R2.3) are both mechanical and should not depend on human memory.

---

## R1 — Urgent (pre-launch blockers: RD-001, RD-002, RD-005, RD-006, RD-007, RD-010)

### R1.1 — Configure real Android release signing (closes RD-001, addresses RD-010)

- Generate a dedicated release keystore (`upload-keystore.jks`) via `keytool`, outside version control.
- Add `android/key.properties` (git-ignored) referencing the keystore path/passwords/alias.
- Update `android/app/build.gradle.kts`:
  ```kotlin
  val keystoreProperties = Properties()
  val keystorePropertiesFile = rootProject.file("key.properties")
  if (keystorePropertiesFile.exists()) {
      keystoreProperties.load(FileInputStream(keystorePropertiesFile))
  }

  signingConfigs {
      create("release") {
          keyAlias = keystoreProperties["keyAlias"] as String
          keyPassword = keystoreProperties["keyPassword"] as String
          storeFile = keystoreProperties["storeFile"]?.let { file(it) }
          storePassword = keystoreProperties["storePassword"] as String
      }
  }
  buildTypes {
      release {
          signingConfig = signingConfigs.getByName("release")
      }
  }
  ```
- **Bundled with this action (RD-010):** document who holds the keystore + passwords, where an encrypted backup lives (e.g., a password manager or secrets vault, not another repo), and what happens if the sole key-holder is unavailable — before the key is first used for a real store submission, not after.
- **Risk if not done:** cannot legitimately publish to Google Play at all.
- **Rollback of this change:** N/A — this only adds a signing path; it does not remove the ability to build debug/local variants.
- **Retest:** produce a clean release AAB from a fresh checkout and verify (via `apksigner`/Play Console pre-launch report) it is signed with the new key, not the debug key.

### R1.2 — Configure real iOS release signing (closes RD-002)

- Set an explicit `DEVELOPMENT_TEAM` in `project.pbxproj` for the Release (and, if CI is later added, Profile) configuration, tied to the organization's actual Apple Developer Team ID.
- Decide and document whether `CODE_SIGN_STYLE` stays `Automatic` (acceptable for a single trusted developer machine, with the team ID pinned) or moves to `Manual` with an explicit provisioning profile (preferred once CI is introduced, per R2.1).
- **Risk if not done:** IPA builds are non-reproducible across machines/developers; App Store Connect uploads depend on whichever account is logged in at build time.
- **Retest:** produce a clean release IPA from a fresh checkout on a second machine/account and confirm identical signing identity.

### R1.3 — Establish a build-number increment process (closes RD-006)

- Minimum viable fix (no CI required): add a documented step to a release checklist requiring `pubspec.yaml`'s `+N` to be manually incremented before every build, verified against the last value submitted to each store.
- Preferred fix (pairs with R2.1): have CI compute the build number automatically (e.g., from a monotonic counter, timestamp, or the CI run number) and pass it via `flutter build ... --build-number=$N`, so no human step is required.
- **Risk if not done:** every release after the first is rejected outright at the store-upload step.
- **Retest:** simulate two successive builds and confirm the second has a strictly higher `versionCode`/`CFBundleVersion` than the first.

### R1.4 — Produce store-submission assets and fix the privacy-policy link (closes RD-007)

- Write and host an actual privacy-policy document at a stable, public URL (coordinate content with the Privacy/Compliance audit's findings — do not draft this in isolation from that audit).
- Wire the "Privacy Policy" and "Terms of Use" `TextSpan`s in `sign_in_screen.dart` to real, functioning links (add `TapGestureRecognizer` calling `url_launcher`'s `launchUrl`, or navigate to an in-app WebView/screen rendering the policy).
- Create a `CHANGELOG.md` (or equivalent) and start recording entries starting with the first real release; prepare minimal store-listing metadata (description, screenshots) ahead of first submission.
- **Risk if not done:** near-certain store-submission rejection for a health-data app lacking a reachable privacy policy; no prepared "what's new" content for submission.
- **Retest:** tap the link in a debug build and confirm it opens the live policy document; confirm the URL is what gets entered in both store consoles.

### R1.5 — Coordinate environment/build separation fix with Dependencies/Config (addresses RD-005)

- This finding's underlying root cause (`.env` bundled as a compiled asset, `APP_ENV` inert) is already owned and remediated in detail by `DC_remediation_plan.md` R1.1/R1.2 (stop bundling `.env` as an asset; adopt `--dart-define-from-file` or a runtime-fetched config; reconcile `.env.example`). This plan does not duplicate that design — it requires that remediation to also produce, as a release-process deliverable, at least two distinct build configurations (e.g., `internal-test` and `production`) with genuinely different backing Supabase projects/keys, so a broken build can be tested against a non-production backend before it ever reaches a store.
- **Risk if not done:** every "test" build is actually a production build; there's no safe place to validate a risky change against real infrastructure without touching production data.

---

## R2 — Pre-launch strongly recommended (RD-003, RD-004, RD-009)

### R2.1 — Stand up a minimal CI pipeline (closes RD-003)

- Add a CI workflow (GitHub Actions is the natural fit given the repo already lives on a git remote) that, at minimum, on every push/PR:
  1. Checks out at a pinned Flutter/Dart version (see R2.2).
  2. Runs `flutter pub get` from `pubspec.lock` (no upgrade).
  3. Runs `flutter analyze` and the full `test/` suite, failing the build on any failure.
  4. Optionally, on tagged releases only: builds the release Android/iOS artifacts using the R1.1/R1.2 signing configuration, and fails explicitly if `signingConfig` resolves to `debug`.
- **Risk if not done:** no build is ever automatically verified; the existing test suite provides no protective value at release time.
- **Retest:** deliberately introduce a failing test and a debug-signing regression on a branch; confirm CI fails on both.

### R2.2 — Pin the Flutter/Dart toolchain (closes RD-004)

- Adopt FVM (`fvm use <version>`, commit `.fvmrc`) or an equivalent pinning mechanism, matching (or deliberately upgrading from) the revision recorded in `.metadata`.
- Wire the CI pipeline (R2.1) to install and use this exact pinned version.
- **Risk if not done:** builds drift silently across machines/time.
- **Retest:** confirm `flutter --version` matches the pin on a freshly provisioned CI runner.

### R2.3 — Design a minimal emergency-mitigation layer (addresses RD-009)

- Do not attempt a full feature-flag platform as a pre-launch requirement — that is disproportionate to this app's current stage. Instead:
  1. Formally document the one verified mitigation lever (disabling/altering the `dr-niswah-chat` Supabase Edge Function) as a runbook: who has dashboard access, what the disable procedure is, and what the user-visible degraded state looks like (confirmed in this audit: a caught error, not a crash, for that one path).
  2. Audit each other Supabase-backed feature (cycle tracking, community board, private messaging, pregnancy tracking) for the same graceful-degradation property, and fix any that would crash rather than degrade if their backend call failed — this closes the "not exhaustively verified" gap noted in RD-009.
  3. Once R1.5's environment-separation fix (a real runtime-config layer) exists, evaluate whether a lightweight remote-config flag (even a single Supabase table read at startup) is worth adding for the highest-risk features, as a formal, tested kill switch rather than an accidental one.
- **Risk if not done:** a bad release remains unmitigatable faster than a full store review cycle for anything except the one already-checked path.
- **Retest:** in a non-production environment, disable the Edge Function and confirm each audited feature degrades visibly rather than crashing.

---

## R3 — Process / longer-term (RD-008)

### R3.1 — Establish incremental commit/review discipline going forward

- This is not a code fix — RD-008 cannot be "remediated" retroactively (the missing history cannot be recovered), only prevented going forward.
- Recommend: feature-branch + PR workflow (even a lightweight one, without requiring another human reviewer if the team is a single developer) so future changes are traceable, and so that a future incident review can answer "what changed and when" without relying on memory.
- If the squashed history was deliberate (e.g., to remove a leaked secret or reset an early prototype), document that decision explicitly in the repo (e.g., a note in `README.md` or a `HISTORY.md`) so future reviewers don't have to guess.
- **Risk if not done:** every future release-readiness audit will face the same provenance gap, compounding over time.

---

## Remediation Phase Table

| # | Action | Findings closed | Release component | Environments affected | Risk | Rollback | Retest |
|---|---|---|---|---|---|---|---|
| R1.1 | Real Android release signing + key custody plan | RD-001, RD-010 | Android build | Build/signing only | Low (additive) | N/A | Clean AAB build, verify signature |
| R1.2 | Real iOS signing identity | RD-002 | iOS build | Build/signing only | Low (additive) | N/A | Clean IPA build on 2nd machine |
| R1.3 | Build-number increment process | RD-006 | Versioning | All | Low | N/A | Two successive builds, compare versionCode |
| R1.4 | Store assets + fix privacy-policy link | RD-007 | Store submission, app UI | Production | Low | Revert link change if needed | Tap link in build, confirm resolves |
| R1.5 | Environment/build separation (coordinated with DC remediation) | RD-005 | Build config | Dev/test/prod | Medium (touches config loading) | Revert to single `.env` if broken | Build both flavors, confirm distinct config |
| R2.1 | Minimal CI pipeline | RD-003 | Whole pipeline | All | Low | Disable workflow if broken | Introduce deliberate failure, confirm CI catches it |
| R2.2 | Toolchain pinning | RD-004 | Build | All | Low | Remove pin if it blocks urgent work | Confirm `flutter --version` on fresh runner |
| R2.3 | Emergency-mitigation runbook + per-feature degradation audit | RD-009 | Backend/rollback | Production | Low (documentation + defensive coding) | N/A | Disable function in non-prod, confirm graceful degradation per feature |
| R3.1 | Incremental commit/review discipline | RD-008 | Process | All future work | N/A (process only) | N/A | N/A — observe over next several changes |

---

## Remediation Exit Gate

- [x] Root cause documented for every open finding (see Root-Cause Map above)
- [x] Pipeline/config change explicit for each R1/R2 action
- [ ] Migration impact reviewed — N/A for this plan (no migration-sequencing findings were raised by this audit; deferred to Database Integrity audit)
- [x] Environment impact known (R1.5, R2.1 both note affected environments)
- [x] Rollback defined where applicable (additive changes noted as low-risk/no-rollback-needed; R1.4/R1.5 note explicit revert paths)
- [x] Smoke test / retest defined for every action
- [ ] Observability/release tagging defined — **not designed in this plan**; cross-referenced to Observability audit, which should define how a release is identified in logs/crash reports once R2.1 (CI) exists
- [x] No undocumented manual dependency remains unaddressed for the critical release path — every manual step identified in `RD_discovery.md` §24 has a corresponding remediation action above (R1.1-R1.5, R2.1-R2.3)

**This plan is design-only. None of the above has been implemented, tested, or verified as part of this audit.**
