# Dependencies & Configuration Audit — Findings Register (Phase 2A: Static Verification)

| Field | Value |
|---|---|
| System | Niswah (Flutter mobile app) |
| Repository | `/Users/rynadalsabh/Niswah` |
| Branch | `main` |
| Commit | `13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f` |
| Phase | 2A — Static Verification |
| Audit date | 2026-09-04 |

Evidence key: 🟥 Confirmed by Execution · 🟧 Confirmed by Manifest/Code/Config · 🟨 Likely · 🟦 Requires Controlled Validation · ⬜ N/A / False positive

---

## DC-001 — `.env` bundled as a Flutter asset; single file used for all build targets, no environment separation

- **Category:** `CFG-01` / `BUILD-01`
- **Severity:** **DC0 — Critical**
- **Dependency/config item:** `pubspec.yaml` → `flutter: assets: - .env`
- **Manifest path:** `pubspec.yaml` lines ~78-80
- **Declared value:** `.env` listed as a Flutter asset alongside `assets/images/logo.png`
- **Actual usage:** `flutter_dotenv` loads this bundled asset at runtime (`AppEnvironment.load()`, `main.dart`). Whatever `.env` exists on the developer/CI machine at the moment `flutter build` runs is compiled **verbatim, byte-for-byte** into the release APK/AAB/IPA as a readable asset file.
- **Production impact:** All secrets in `.env` at build time — `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `APP_ENV`, and currently `GEMINI_API_KEY` — ship inside the binary and are extractable by anyone who unpacks the release build (trivial for APK). There is **no build-time/environment separation mechanism whatsoever**: no Flutter build flavors configured in `android/app/build.gradle.kts` or the iOS Xcode project, no `--dart-define`/`--dart-define-from-file` usage anywhere in the codebase (confirmed via `grep` — zero matches for `String.fromEnvironment`/`Platform.environment`). A developer building "for production" and a developer building "for local testing" both compile in whatever `.env` happens to be sitting in their working directory at that moment — there is no `.env.production` vs `.env.development` distinction, and none is possible with the current build wiring.
- **Evidence:** 🟧 Confirmed by manifest (`pubspec.yaml`) + code (`app_environment.dart`, `main.dart` both call `dotenv.load()`/`AppEnvironment.load()`) + absence-of-alternative (grep for flavors/dart-define returned nothing).
- **Launch-blocker status:** YES
- **Status:** OPEN
- **Cross-reference:** Security Audit (secret-in-binary exposure is that audit's primary lens; this finding is registered here from the configuration-management angle per the assigned scope).

---

## DC-002 — `APP_ENV` is loaded and validated but has zero effect on application behavior (dead configuration)

- **Category:** `UNUSED-01` / `CFG-02`
- **Severity:** **DC2 — Medium**
- **Dependency/config item:** `APP_ENV` / `AppEnvironment.appEnvironment`, `AppEnvironment.isProduction`
- **Manifest/config path:** `lib/core/config/app_environment.dart` lines 26, 76, 78
- **Declared value:** Read from `.env`, defaults to `'development'` if absent, exposed via `AppEnvironment.appEnvironment` (getter) and `AppEnvironment.isProduction` (bool getter, `== 'production'`)
- **Actual usage:** `grep -rn "isProduction\|appEnvironment\b" lib` (excluding the defining file itself) returns **zero results**. No code anywhere branches on environment (no conditional logging verbosity, no conditional API base URL, no conditional feature availability, no debug-tool gating).
- **Production impact:** The variable exists, is documented in `.env.example`, and is actively loaded/parsed at every app startup — giving the *appearance* of environment-aware configuration — but changing `APP_ENV` from `development` to `production` (or anything else) produces **no behavioral difference in the shipped app**. This confirms, independently, that the app has no real dev/staging/prod separation at the application-logic layer, compounding DC-001: even if build-time separation existed, nothing in the code would currently act on it.
- **Evidence:** 🟧 Confirmed by code (getter defined, zero call sites found by exhaustive grep of `lib/`).
- **Launch-blocker status:** NO (bounded — dead code, not unsafe on its own) but **directly informs DC0/DC1 risk assessment above**
- **Status:** OPEN

---

## DC-003 — `.env.example` does not document the actually-used AI key (`GEMINI_API_KEY`); documents three AI keys that are never consumed anywhere in the codebase

- **Category:** `ENV-01` / `AI-01` (AI-agent-specific config drift, template §42.8 "partial renames"/phantom-variable pattern)
- **Severity:** **DC1 — High**
- **Dependency/config item:** `.env.example` vs `lib/core/config/app_environment.dart` vs `lib/core/services/gemini_service.dart`
- **Manifest/config path:** `.env.example` (repo root), `lib/core/config/app_environment.dart` (lines 14-46, 62-74), `lib/core/services/gemini_service.dart` (line 45)
- **Declared value:** `.env.example` documents only `APP_ENV`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`.
- **Actual usage — two distinct drifts confirmed:**
  1. **Undocumented but required:** `GeminiService` (the class actually powering the AI Advisor and Dream Interpreter features per its file location and API surface) reads `GEMINI_API_KEY` directly via `dotenv.env['GEMINI_API_KEY']`, completely bypassing `AppEnvironment`. This key is required for those features to function (`isConfigured` gate, `StateError` if missing) but is **not mentioned anywhere in `.env.example`**.
  2. **Documented-adjacent but dead:** `AppEnvironment` loads, validates-if-present, and exposes getters for `OPENAI_API_KEY`, `NISWAH_AI_API_KEY`, and `DREAM_INTERPRETER_API_KEY` (plus `VITE_*` aliases) — none of which appear in `.env.example` either, and **none of which have any call site outside `app_environment.dart` itself** (confirmed by grep). These three getters use `_require()`, meaning *if anything ever called them* with the value absent, the app would throw — but nothing does, so this is currently inert dead code, not a live risk.
- **Production impact:** A new developer or a fresh build machine following `.env.example` exactly would produce a build where:
  - The AI Advisor / Dream Interpreter features silently fail their `isConfigured` check (feature appears broken/unavailable to end users, discovered only when a user opens that screen, not at build or startup time — no fail-fast for this specific, real feature dependency).
  - Three unrelated, unused environment variables are validated in code for a feature path that does not exist in the current app (`OPENAI_API_KEY`/`NISWAH_AI_API_KEY`/`DREAM_INTERPRETER_API_KEY`), suggesting either a removed/replaced AI provider integration (drift from an earlier implementation) or an AI-agent-introduced scaffold that was never wired up or cleaned up.
- **Evidence:** 🟧 Confirmed by config (`.env.example` content) + code (both files read in full) + exhaustive grep for getter call sites.
- **Launch-blocker status:** YES (undocumented required config for a real, user-facing feature — build machines/new hires cannot reliably produce a working AI feature from documented instructions alone)
- **Status:** OPEN

---

## DC-004 — Startup config-validation failures are silently swallowed by a global `runZonedGuarded` handler; missing/invalid critical config produces a silent infinite hang instead of a clear failure

- **Category:** `CFG-03` (Missing Config Failure Audit, template §34)
- **Severity:** **DC0 — Critical**
- **Dependency/config item:** `main()` / `AppEnvironment.load()` interaction
- **Manifest/config path:** `lib/main.dart` lines 34-61 (`runZonedGuarded`), `lib/core/config/app_environment.dart` lines 94-129 (`_require`, `_validateClientConfig`)
- **Declared/intended behavior:** `AppEnvironment.load()` is explicitly designed to fail fast — `_require()` throws `FormatException` with a clear message ("Missing required environment value for SUPABASE_URL...") if `SUPABASE_URL`/`SUPABASE_ANON_KEY` are empty, and `_validateClientConfig` throws if a service-role/secret-looking value is detected.
- **Actual behavior:** `main()` calls `await AppEnvironment.load()` (and everything after it, including `runApp(...)`) **inside** a `runZonedGuarded` block whose error callback is:
  ```dart
  (error, stack) {
    debugPrint('Unhandled error: $error\n$stack');
  }
  ```
  This callback does not rethrow, does not call `exit()`, does not show any error UI, and does not call `runApp()` with a fallback error screen. If `AppEnvironment.load()` throws (missing/invalid Supabase config — the exact scenario the validation exists to catch), execution of the guarded function stops **before `runApp()` is ever reached**. The zone handler logs to `debugPrint`, which is a no-op / not visible to end users in a release build and not connected to any crash-reporting tool (none found in `pubspec.yaml`).
- **Production impact:** If required config is missing or invalid at build time (a very plausible failure mode given DC-001 — one `.env` for all builds, easy to build with a stale/incomplete file), the shipped app does not crash and does not show an error — it **hangs indefinitely on the native splash screen**, because `runApp()` is never invoked. This is operationally almost the worst-case outcome: indistinguishable in the field from a generic "app won't load" bug, with no diagnostic signal reaching the user, support team, or (absent a crash reporter) even the developer. It directly defeats the "fail early, clear error, no secret displayed" principle the codebase's own validation logic was written to satisfy.
- **Evidence:** 🟧 Confirmed by code — both files read in full; control flow traced line-by-line.
- **Launch-blocker status:** YES — matches template NO-GO criterion "Critical config is missing or silently defaults unsafely" (the failure mode here is silent-hang rather than silent-default, arguably worse for diagnosability).
- **Status:** OPEN
- **Cross-reference:** Reliability/Observability audits (no crash reporting exists to surface this even if instrumented) — flag for those auditors too.

---

## DC-005 — Android release build is explicitly signed with the debug keystore; no release signing configuration exists anywhere

- **Category:** `BUILD-02`
- **Severity:** **DC0 — Critical**
- **Dependency/config item:** Android release signing config
- **Manifest/config path:** `android/app/build.gradle.kts`, lines ~30-35
- **Declared value:**
  ```kotlin
  buildTypes {
      release {
          // TODO: Add your own signing config for the release build.
          // Signing with the debug keys for now, so `flutter run --release` works.
          signingConfig = signingConfigs.getByName("debug")
      }
  }
  ```
  This is the **unmodified Flutter template placeholder** — the `TODO` comment is the stock text `flutter create` generates.
- **Actual usage:** Confirmed no `android/key.properties` file exists anywhere in the repo (`find` returned nothing), no keystore file was found, and no alternate `signingConfigs` block defines a `release` identity anywhere in `android/app/build.gradle.kts` or `android/build.gradle.kts`.
- **Production impact:** Running `flutter build appbundle --release` (or `apk --release`) today produces an artifact **signed with the Android debug key**. This artifact cannot be uploaded to Google Play (Play Console rejects debug-signed uploads for production/internal tracks requiring app signing) and, more broadly, there is currently **no reproducible, externalized release-signing mechanism** — the moment someone does wire one up ad hoc on their own machine, the keystore/`key.properties` location, storage, and rotation process are entirely undocumented and unverifiable from the repo.
- **Evidence:** 🟧 Confirmed by manifest (`build.gradle.kts` read in full) + confirmed absence of `key.properties`/keystore via `find`.
- **Launch-blocker status:** YES — matches template NO-GO criterion directly ("production build cannot be reproduced" / release cannot be legitimately distributed).
- **Status:** OPEN
- **Cross-reference:** Release/Deployment audit (primary owner of the actual signing/distribution process) — this finding should be treated as shared with that audit.

---

## DC-006 — No CI/CD pipeline exists; all build/release steps depend entirely on local developer machine state

- **Category:** `BUILD-03` / `PARITY-01`
- **Severity:** **DC1 — High**
- **Dependency/config item:** Build/release reproducibility
- **Manifest/config path:** N/A (absence confirmed — no `.github/workflows/`, no `.gitlab-ci.yml`, `bitrise.yml`, `codemagic.yaml`, `azure-pipelines.yml`, or any other CI config found anywhere in the repository, consistent with the pre-confirmed statement in the audit brief)
- **Declared value:** N/A
- **Actual usage:** N/A — there is no automated pipeline of any kind for install, build, test, or release.
- **Production impact:** Every release build depends on: the exact Flutter/Dart SDK version installed on that developer's machine (unpinned, see DC-007), the exact contents of that developer's local `.env` (see DC-001), and — currently — a nonexistent release signing keystore (see DC-005). None of these are automated, verified, or reproducible outside a single person's laptop. There is no automated test gate before release, no frozen/immutable install step, and no record of what toolchain/config actually produced any given shipped artifact.
- **Evidence:** 🟧 Confirmed by exhaustive filesystem search (absence).
- **Launch-blocker status:** YES — matches template NO-GO criterion "Required env variables exist only locally and not in deployment" and general reproducibility requirements for GO/CONDITIONAL GO.
- **Status:** OPEN
- **Cross-reference:** Release/Deployment audit (primary), Reliability audit.

---

## DC-007 — No Flutter/Dart SDK version pinning mechanism

- **Category:** `VER-01` / `COMPAT-01`
- **Severity:** **DC2 — Medium**
- **Dependency/config item:** Flutter/Dart toolchain version
- **Manifest/config path:** `pubspec.yaml` (`environment.sdk: ^3.13.0`), `pubspec.lock` (`sdks: flutter: ">=3.44.0"`), absence of `.fvmrc`/FVM config/`.tool-versions`
- **Declared value:** Only a lower bound is enforced (`^3.13.0` Dart, `>=3.44.0` Flutter) — no upper bound, no exact pin, no version-manager config.
- **Actual usage:** Build depends on "whatever Flutter version happens to be active on the machine running the build," subject only to the floor constraint. `.metadata`'s `revision` field is a historical scaffold marker, not an enforced constraint (not consumed by `flutter build`).
- **Production impact:** Two developers (or a developer and a future CI system) with different Flutter versions ≥3.44.0 could produce meaningfully different builds (different Dart language features available, different generated Gradle/Xcode wiring, different plugin API compatibility), with no mechanism to detect or prevent the drift. Compounds DC-006.
- **Evidence:** 🟧 Confirmed by manifest inspection + confirmed absence of `.fvmrc`/equivalent via `find`.
- **Launch-blocker status:** NO on its own (bounded debt), but **contributes to the reproducibility gate failure driving DC-006's severity**.
- **Status:** OPEN

---

## DC-008 — Orphaned Firebase configuration artifacts committed to the repository, including a live-looking API key, unrelated to the app's actual Supabase backend

- **Category:** `UNUSED-02` / `SECRET-01`
- **Severity:** **DC3 — Low** (from a config-management angle; escalate to Security Audit for credential-exposure severity)
- **Dependency/config item:** `firebase-applet-config.json`, `firebase-blueprint.json`, `firestore.rules`
- **Manifest/config path:** Repo root; all three confirmed tracked via `git ls-files`
- **Declared value:** `firebase-applet-config.json` contains a `projectId` (`gen-lang-client-0587133184`), `appId`, and an `apiKey` field with a populated value in Firebase's standard `AIzaSy...` web-API-key format.
- **Actual usage:** `pubspec.yaml` declares **no** Firebase packages (`firebase_core`, `cloud_firestore`, etc.), and `grep -rln "firebase" lib` returns **zero matches**. The app's only backend integration is `supabase_flutter`. These files appear to be leftovers from an earlier or parallel prototyping effort (the repo's `MANIFEST.md` references a "Live web reference: AI Studio URL," consistent with a Firebase/AI-Studio-based scaffold that predates or parallels the current Supabase-backed Flutter app).
- **Production impact:** From a pure configuration-management standpoint: these are dead, unreferenced configuration sources committed to the repo, creating ambiguity about which backend is authoritative for a reader unfamiliar with the project history, and representing config clutter that should be resolved (removed, or clearly marked archival) before or shortly after launch. The credential-exposure angle (a real-looking API key sitting in git history) is flagged here but its actual risk/blast-radius assessment belongs to the Security Audit.
- **Evidence:** 🟧 Confirmed by file content (header read) + confirmed absence of Firebase packages/imports in the shipping app.
- **Launch-blocker status:** NO (config-hygiene only) — but flag for Security Audit escalation review.
- **Status:** OPEN
- **Cross-reference:** Security Audit (credential exposure).

---

## DC-009 — Hardcoded auth-bypass debug flag present in shipping `main.dart`

- **Category:** `DEBUG-01`
- **Severity:** **DC3 — Low** (currently safe default; flagged as a debug-leftover pattern)
- **Dependency/config item:** `kDebugSkipSignup`
- **Manifest/config path:** `lib/main.dart` line 32
- **Declared value:** `const bool kDebugSkipSignup = false;` — comment explicitly labels it "TEMPORARY DEBUG FLAG — set to true only for local preview of the onboarding flow."
- **Actual usage:** `lib/main.dart` line 112, gates `MaterialApp.home` — when `true`, skips the sign-in screen entirely and opens onboarding at step 4.
- **Production impact:** Currently `false`, so no active risk in the audited commit. However, it is a manually-toggled compile-time constant with no environment/flavor/build-config gating whatsoever — its safety depends entirely on a developer remembering to leave it `false` (or catching it in review) before every release build. This is exactly the pattern template §42.9 ("test/debug leftovers... dev login") warns about.
- **Evidence:** 🟧 Confirmed by code (both definition and use site read).
- **Launch-blocker status:** NO (currently safe) — recommend removal or gating behind a real debug-build check (e.g., `kDebugMode`) before next release cycle.
- **Status:** OPEN

---

## DC-010 — iOS release code signing has no pinned team/identity; relies entirely on local Xcode/Apple ID state

- **Category:** `BUILD-04`
- **Severity:** **DC1 — High**
- **Dependency/config item:** iOS code signing configuration
- **Manifest/config path:** `ios/Runner.xcodeproj/project.pbxproj`
- **Declared value:** `CODE_SIGN_STYLE = Automatic;` across all three build configurations, with `"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "iPhone Developer";` (generic placeholder). No `DEVELOPMENT_TEAM` key found anywhere in the project file (`grep` returned zero matches).
- **Actual usage:** Automatic signing requires Xcode to resolve a team/provisioning profile from whatever Apple Developer account is logged into the building machine's Xcode installation at build time.
- **Production impact:** Mirrors DC-005/DC-006 for iOS — there is no externalized, CI-manageable, reproducible signing configuration. A release IPA can currently only be produced on a specific developer's machine with their personal/team Apple ID configured in Xcode, and that dependency is invisible from the repo alone.
- **Evidence:** 🟧 Confirmed by manifest inspection (`project.pbxproj` grepped for all signing-relevant keys).
- **Launch-blocker status:** YES (same class of issue as DC-005, applied to the other platform)
- **Status:** OPEN
- **Cross-reference:** Release/Deployment audit.

---

## DC-011 — Multiple dependency versions and toolchain versions could not be checked against live deprecation/advisory data

- **Category:** `DEPR-01`
- **Severity:** **DC4 — Observation** (procedural — not asserting any of these ARE deprecated)
- **Dependency/config item:** `flutter_local_notifications` (22.3.0), `supabase_flutter` (2.17.2), `geolocator` (14.0.3), `adhan_dart` (2.0.1), `timezone` (0.11.1), `dart_jsonwebtoken` (3.4.1, transitive), Flutter SDK (≥3.44.0), Dart SDK (^3.13.0), Android Gradle Plugin (9.1.0), Kotlin (2.4.0), Gradle (9.3.1)
- **Manifest/config path:** `pubspec.lock`, `android/settings.gradle.kts`, `android/gradle/wrapper/gradle-wrapper.properties`
- **Declared value:** See `DC_dependency_inventory.md` for full resolved-version table.
- **Actual usage:** All are actively imported/used per Discovery.
- **Production impact:** UNKNOWN. This auditor's training data has a cutoff predating several of these resolved versions (system date is 2026-09-04); none can be confidently asserted as current, deprecated, or advisory-flagged from training knowledge alone.
- **Evidence:** 🟦 Requires controlled/live validation (a `flutter pub outdated` run and/or manual pub.dev lookups against network access not available in this audit environment).
- **Launch-blocker status:** NOT DETERMINED — explicitly mark UNKNOWN rather than PASS or FAIL, per template instruction not to convert lack of access into a verdict.
- **Status:** OPEN — requires live verification before final sign-off if the release owner wants deprecation risk fully closed.

---

## DC-012 — iOS `Podfile` absence investigated — verified false positive, not a defect

- **Category:** `BUILD-05` (verification note, not a defect)
- **Severity:** **⬜ N/A / False positive**
- **Dependency/config item:** `ios/Podfile`
- **Manifest/config path:** N/A (absence)
- **Finding:** No `Podfile` exists in `ios/`, which would ordinarily be flagged as broken/incomplete native iOS config for a Flutter app with native plugins (this app has many: `geolocator`, `flutter_local_notifications`, `printing`, `shared_preferences`, `supabase_flutter`, etc.). Investigation found `ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift` present, indicating the project uses **Swift Package Manager** for iOS plugin integration rather than CocoaPods — a supported alternative in newer Flutter tooling. Absence of `Podfile` is therefore **expected**, not a defect, given this toolchain configuration.
- **Evidence:** 🟧 Confirmed by presence of SPM-generated manifest.
- **Launch-blocker status:** NO
- **Status:** CLOSED (documented as verified non-issue)

---

## Findings Summary

| Severity | Count | IDs |
|---|---:|---|
| DC0 — Critical | 3 | DC-001, DC-004, DC-005 |
| DC1 — High | 3 | DC-003, DC-006, DC-010 |
| DC2 — Medium | 2 | DC-002, DC-007 |
| DC3 — Low | 2 | DC-008, DC-009 |
| DC4 — Observation | 1 | DC-011 |
| N/A / Closed | 1 | DC-012 |

DC-007 (no Flutter/Dart SDK pinning) is bounded on its own but directly compounds DC-006's reproducibility risk — see the final report's Root-Cause discussion.

Total open findings requiring launch-decision input: **10** (DC-001 through DC-011 minus DC-012).
