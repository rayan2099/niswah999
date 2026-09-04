# Dependencies & Configuration Audit — Phase 1: Discovery

| Field | Value |
|---|---|
| System | Niswah (Flutter mobile app) |
| Repository | `/Users/rynadalsabh/Niswah` |
| Branch | `main` |
| Commit / Version | `13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f` / pubspec version `1.0.0+1`, bundle `com.niswah.niswah` |
| Phase | Discovery |
| Audit date | 2026-09-04 |
| Package manager(s) | `pub` (Dart/Flutter) — primary; `npm` (reference-only `src/` web app, not in scope) |
| Runtime(s) | Dart SDK `^3.13.0`; Flutter (lockfile requires `>=3.44.0`, no upper bound) |
| Environment | Local / repo inspection only — no staging or production environment access |
| Build target | Android (`com.niswah.niswah`) + iOS Runner |
| Restrictions | Read-only audit. No `flutter pub get/upgrade`, no build executed, no secrets rotated, no config/lockfile modified. |
| Report created | `DC_discovery.md` |

---

## 7. Package Manager Inventory

| Ecosystem | Manifest | Lockfile | Package manager | Version pinned? | Used for |
|---|---|---|---|---|---|
| Dart/Flutter (pub) | `pubspec.yaml` | `pubspec.lock` (tracked in git — confirmed via `git ls-files`) | `pub`/`flutter pub` | NO (caret ranges `^x.y.z`) — but lockfile provides reproducibility | Shipping mobile app (release candidate) |
| npm | `package.json` | `package-lock.json` | `npm` | Mixed | Reference-only web app (`src/`) — NOT the release candidate, per CLAUDE.md memory instruction; noted briefly only |

No conflicting lockfiles found for either ecosystem (no `yarn.lock`/`pnpm-lock.yaml` alongside `package-lock.json`).

## 8. Runtime Inventory

| Runtime | Required version | Declared where | CI version | Production version | Match? |
|---|---|---|---|---|---|
| Dart SDK | `^3.13.0` | `pubspec.yaml` → `environment.sdk` | N/A — no CI exists | UNKNOWN — depends on developer machine | UNKNOWN |
| Flutter SDK | `>=3.44.0` (no upper bound) | `pubspec.lock` (`sdks:` block) | N/A — no CI exists | UNKNOWN — depends on developer machine | UNKNOWN |
| Android Gradle Plugin | `9.1.0` | `android/settings.gradle.kts` | N/A | UNKNOWN | UNKNOWN |
| Kotlin | `2.4.0` | `android/settings.gradle.kts` | N/A | UNKNOWN | UNKNOWN |
| Gradle wrapper | `9.3.1` (all distribution) | `android/gradle/wrapper/gradle-wrapper.properties` | N/A | UNKNOWN | UNKNOWN |
| Java | `17` (source/target compatibility) | `android/app/build.gradle.kts` | N/A | UNKNOWN | UNKNOWN |
| iOS deployment target | `15.0` | `ios/Runner.xcodeproj/project.pbxproj` (3 build configs) | N/A | UNKNOWN | UNKNOWN |

**No Flutter/Dart SDK pinning mechanism exists** — no `.fvmrc`, no FVM config, no `asdf`/`.tool-versions`. `.metadata` records the Flutter tool revision (`4cf24164269a5ebf0c16a028a00727d0e77bbb05`) used when the project was scaffolded/migrated, but this is a historical marker consumed only by `flutter migrate`, **not an enforced build constraint**. Build reproducibility for the Flutter/Dart toolchain itself depends entirely on "whatever Flutter version is installed on the machine running `flutter build`," subject only to the loose `>=3.44.0` floor.

Version numbers observed (Dart 3.13, Flutter 3.44, AGP 9.1.0, Kotlin 2.4.0, Gradle 9.3.1) are all beyond this auditor's training-data familiarity (training cutoff January 2026; system date is 2026-09-04). They are **not asserted to be invalid** — flagged as requiring live-toolchain verification only.

## 9–13. Dependency Inventory (direct, `dependencies:` block of `pubspec.yaml`)

See `DC_dependency_inventory.md` for the full table with resolved versions from `pubspec.lock`.

## 14. Configuration Source Inventory

| Source | Environment | Purpose | Checked into repo? | Contains secrets? | Authoritative? |
|---|---|---|---|---|---|
| `.env` | All (single file, no per-environment variant) | Supabase URL/key, `APP_ENV`, `GEMINI_API_KEY` | NO — gitignored (`.env*` with `!.env.example` exception in `.gitignore`; confirmed not in `git ls-files`) | YES | YES — sole runtime config source |
| `.env.example` | Template/docs | Documents expected variable names | YES | NO (placeholder values only) | Documentation only, and incomplete (see DC-003) |
| `pubspec.yaml` → `flutter.assets` | Build-time | Bundles `.env` as a compiled asset | YES | Indirectly (see DC-001) | YES — determines what ships in the binary |
| `android/app/build.gradle.kts` | Build-time (Android) | App ID, SDK versions, release signing config | YES | NO | YES |
| `ios/Runner.xcodeproj/project.pbxproj` | Build-time (iOS) | Deployment target, code signing style | YES | NO | YES |
| `firebase-applet-config.json`, `firebase-blueprint.json`, `firestore.rules` | Unclear/orphaned | Appears to be a legacy/parallel Firebase prototype config | YES (tracked in git) | YES — contains a Firebase Web API key | NO — app does not use Firebase (see DC-008) |
| `.vercel/project.json` | Unclear | Vercel project linkage, likely for the `src/` reference web app, not the Flutter app | YES | NO (project/org IDs only, not secret) | Out of scope (web reference app) |

## 15. Environment Variable Inventory

| Env ID | Variable | Required? | Type | Used by | Default | Secret? | Environments |
|---|---|---|---|---|---|---|---|
| ENV-001 | `SUPABASE_URL` | YES (fails startup if empty) | url | `lib/core/config/app_environment.dart`, `lib/core/network/supabase_client.dart` | none — throws `FormatException` | NO (public project URL) | All (single `.env`) |
| ENV-002 | `SUPABASE_ANON_KEY` | YES (fails startup if empty) | string | same as above | none — throws | Client-safe by design (anon key); code explicitly rejects if it looks like a service-role/secret key | All |
| ENV-003 | `VITE_SUPABASE_URL` | NO (fallback only) | url | `app_environment.dart` `_read()` fallback for ENV-001 | — | NO | All |
| ENV-004 | `VITE_SUPABASE_ANON_KEY` | NO (fallback only) | string | `app_environment.dart` `_read()` fallback for ENV-002 | — | Same caveat as ENV-002 | All |
| ENV-005 | `APP_ENV` | NO | string | `app_environment.dart` (loaded, validated as a string, exposed via `appEnvironment`/`isProduction`) | `'development'` | NO | All — **but has zero effect on app behavior; see DC-002** |
| ENV-006 | `OPENAI_API_KEY` (+ `VITE_OPENAI_API_KEY` fallback) | Conditionally (throws only if a caller reads the getter, but **no caller exists**) | string | `app_environment.dart` only — getter `openAiApiKey` has zero call sites elsewhere in `lib/` | none | YES (should be) | All — dead/unused |
| ENV-007 | `NISWAH_AI_API_KEY` (+ `VITE_NISWAH_AI_API_KEY`) | Same as ENV-006 | string | Same — dead/unused | none | YES (should be) | All — dead/unused |
| ENV-008 | `DREAM_INTERPRETER_API_KEY` (+ `VITE_DREAM_INTERPRETER_API_KEY`) | Same as ENV-006 | string | Same — dead/unused | none | YES (should be) | All — dead/unused |
| ENV-009 | `GEMINI_API_KEY` | **Functionally required** for AI Advisor / Dream Interpreter (`GeminiService`), but **not validated at startup at all** — bypasses `AppEnvironment` entirely | string | `lib/core/services/gemini_service.dart` reads `dotenv.env['GEMINI_API_KEY']` directly | `''` → `isConfigured == false` → feature throws `StateError` only when a user opens the AI feature | YES | All — **undocumented in `.env.example`, see DC-003** |

## 16. Environment Variable Source-of-Truth Map

| Variable | In `.env.example`? | In code (`app_environment.dart`/`gemini_service.dart`)? | Actually used at runtime? | Drift |
|---|---|---|---|---|
| `APP_ENV` | YES | YES (loaded+exposed) | NO (dead getter) | Documented but functionally inert |
| `SUPABASE_URL` / `SUPABASE_ANON_KEY` | YES | YES | YES | None |
| `VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY` | YES | YES (fallback) | YES (as fallback) | None |
| `GEMINI_API_KEY` | **NO** | YES (`gemini_service.dart`, bypasses `AppEnvironment`) | **YES — this is the actual key the shipping AI features depend on** | **Confirmed drift — see DC-003** |
| `OPENAI_API_KEY`, `NISWAH_AI_API_KEY`, `DREAM_INTERPRETER_API_KEY` (+ `VITE_*` aliases) | **NO** | YES (`app_environment.dart` — loaded, validated-if-present, getters defined) | **NO — zero call sites for the getters anywhere in `lib/`** | Phantom/dead config, distinct from the `GEMINI_API_KEY` drift — see DC-003 |

## 17. Build-Time vs Runtime Config Inventory

- **Build-time / compiled-into-binary:** the entire `.env` file, because `pubspec.yaml` declares it under `flutter: assets: - .env`. Flutter asset bundling copies the file byte-for-byte into the release app bundle (APK/AAB/IPA) at build time. There is **no `--dart-define`/`--dart-define-from-file` usage anywhere** (`grep` for `String.fromEnvironment`/`Platform.environment` returned no matches) and **no Flutter build flavors** configured in `android/app/build.gradle.kts` or the iOS Xcode project. One `.env`, whatever it contains on the build machine, ships in every build regardless of target (dev/staging/prod are not distinguished at the build-tooling level at all).
- **Runtime (read from the bundled asset at app start):** `flutter_dotenv` loads the bundled `.env` asset in `AppEnvironment.load()` (also duplicated in `main.dart` — `dotenv.load()` is called twice: once directly in `main()`, once inside `AppEnvironment.load()`).
- **Client-exposed:** `SUPABASE_URL`/`SUPABASE_ANON_KEY` are intentionally client-safe (anon key). `GEMINI_API_KEY` and the three unused AI keys, if populated, would be compiled into the client binary and are extractable — cross-reference Security Audit.

## 18. Feature Flag Inventory

| Flag ID | Flag | Default | Environments | Owner | Expiry/removal date | Critical path? |
|---|---|---|---|---|---|---|
| FLAG-001 | `kDebugSkipSignup` (`lib/main.dart:32`) | `false` (compile-time const) | All builds — no environment/flavor gating | UNKNOWN | None set — comment says "TEMPORARY DEBUG FLAG" | NO (currently `false`, bypasses signup/login and jumps to onboarding step 4 if flipped `true`) |

No other feature-flag mechanism (remote config, flag provider, `.env`-driven flags) exists in the codebase.

## 19. Debug / Development Setting Inventory

- `kDebugSkipSignup` (see FLAG-001) — auth bypass toggle, currently disabled, hardcoded in shipping `main.dart`.
- `debugShowCheckedModeBanner: false` set explicitly in `MaterialApp` (correct for production polish, not a defect).
- `main.dart` wraps the entire startup sequence in `runZonedGuarded`, whose error handler is `debugPrint('Unhandled error: ...')` only — see DC-004. `debugPrint` output is not visible to end users or typically captured in production without a crash-reporting integration (none found in `pubspec.yaml`).
- No mock API / sandbox payment / seed mode / fake notification / localhost URL references found anywhere in `lib/` (`grep -rniE "localhost|127.0.0.1|ngrok"` returned no matches).

## 20. Endpoint / URL Configuration Inventory

| Endpoint | Source | Hardcoded? |
|---|---|---|
| Supabase URL | `.env` → `SUPABASE_URL` | NO (env-driven) |
| Gemini API | `https://generativelanguage.googleapis.com/v1beta/interactions` | YES — hardcoded constant in `gemini_service.dart` (acceptable; it's a fixed third-party API endpoint, not an environment-varying one) |

No localhost/dev/staging URLs found hardcoded in `lib/`.

## 21. Secret Reference Inventory (names only, no values exposed)

- `SUPABASE_ANON_KEY` — client-safe by design; code has an explicit guard rejecting service-role-looking values.
- `GEMINI_API_KEY` — expected from `.env`, actually used, not validated at startup, not documented in `.env.example`.
- `OPENAI_API_KEY`, `NISWAH_AI_API_KEY`, `DREAM_INTERPRETER_API_KEY` — expected from `.env` per `app_environment.dart`, validated-if-present, but unused by any code path found.
- Firebase Web API key found **hardcoded in a tracked JSON file** (`firebase-applet-config.json`) — not part of the Flutter app's dependency/config path, but a committed credential; primarily a Security Audit item, noted here for config-hygiene (orphaned config source, see DC-008).

## 22. Configuration Validation Inventory

- `AppEnvironment.load()` validates `SUPABASE_URL`/`SUPABASE_ANON_KEY` as required (throws `FormatException` if empty) and rejects values that look like service-role/secret keys — validated at **app startup**.
- The three unused AI keys are validated **only if present** (format check for accidentally-leaked secret material) — not required.
- `GEMINI_API_KEY` has **no startup validation at all** — its only check (`isConfigured`) runs lazily, at first use, inside `GeminiService`.
- **Critical gap:** the `FormatException`s thrown by `AppEnvironment.load()` are swallowed by the `runZonedGuarded` error handler in `main.dart`, which only logs via `debugPrint` and does not rethrow, show an error screen, or halt startup visibly — see DC-004. This defeats the fail-fast design intent.

## 23. Environment Parity Inventory

| Area | Local | Staging | Production | Drift risk |
|---|---|---|---|---|
| Runtime (Flutter/Dart) | Whatever is installed locally, ≥3.44.0/≥3.13.0 | N/A — no staging environment found | UNKNOWN — no deployment pipeline exists | HIGH — no pinning, no CI |
| Config source | Single local `.env` | N/A | Whatever `.env` exists on the build machine at build time | HIGH — no environment-specific config file/flavor exists at all |
| Signing (Android) | Debug key (explicit in `build.gradle.kts`) | N/A | UNKNOWN — no release keystore/`key.properties` found anywhere | CRITICAL — see DC-005 |
| Signing (iOS) | Automatic, tied to local Xcode/Apple ID (no `DEVELOPMENT_TEAM` pinned) | N/A | UNKNOWN | HIGH — see DC-013 |
| CI/CD | None | None | None | Confirmed — no `.github/workflows`, no other CI config anywhere in repo |

---

## 24. Discovery Execution Log

### Fully reviewed
`pubspec.yaml`, `pubspec.lock`, `.env` (names/structure only, values redacted from this report), `.env.example`, `.gitignore`, `.metadata`, `lib/core/config/app_environment.dart`, `lib/core/services/gemini_service.dart`, `lib/main.dart`, `android/app/build.gradle.kts`, `android/build.gradle.kts`, `android/settings.gradle.kts`, `android/gradle/wrapper/gradle-wrapper.properties`, `ios/Runner.xcodeproj/project.pbxproj` (signing-relevant keys), `ios/.gitignore`, `ios/Runner/Info.plist` (ATS check).

### Partially reviewed
`MANIFEST.md`, `docs/` (titles only), `firebase-applet-config.json` (header only, to identify orphan status — not the app's actual secrets), `package.json` (existence/scope only — reference app, out of primary scope).

### Structurally scanned only
Full `lib/` tree via `grep` for: `dotenv.env[`, `Platform.environment`, `String.fromEnvironment`, `localhost`/`127.0.0.1`/`ngrok`, `AppEnvironment.` call sites, `kDebugSkipSignup` call sites.

### Could not inspect
- Production/staging environment variables — no deployment platform exists to inspect (confirmed: no CI, no hosting dashboard reference for the Flutter app).
- Actual `flutter build`/`flutter pub get` execution — not run, per audit's read-only mandate and to avoid mutating `pubspec.lock`/toolchain state.
- Live `pub.dev` package status (deprecation/advisory data) — no network tool available/authorized for this; all deprecation assessments below are marked UNKNOWN/NOT VERIFIED.
- `android/key.properties` or equivalent release keystore file — confirmed **absent** via `find`, not merely unreviewed.
- iOS `Podfile` — confirmed **absent**, investigated and attributed to Swift Package Manager usage (evidence: `ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift` present), not treated as a defect.

### Actions performed

| Action | Purpose | Result |
|---|---|---|
| `cat`/`grep` on `pubspec.yaml`, `pubspec.lock` | Inventory dependencies & versions | Complete — see `DC_dependency_inventory.md` |
| `git ls-files` / `git check-ignore` on `.env`, `pubspec.lock` | Verify what's committed vs gitignored | `.env` correctly ignored; `pubspec.lock` correctly committed |
| `find` for `key.properties`, `google-services.json`, `GoogleService-Info.plist`, `.fvmrc`, `Podfile` | Confirm presence/absence of native signing/version-pinning artifacts | All absent (Podfile absence explained by SPM) |
| `grep` for `dotenv.env[`, env-var call sites, `kDebugSkipSignup`, `localhost` | Trace actual runtime usage vs declaration | Completed — findings above |

### Actions deliberately avoided
| Action avoided | Reason |
|---|---|
| `flutter pub get`/`flutter pub outdated`/`flutter pub upgrade` | Template mandates no package installs/upgrades during audit |
| `flutter build` (any target) | Template mandates read-only inspection in Discovery; no approved controlled-validation environment was set up for Phase 2B in this pass |
| Reading full `.env` values into this report | Secrets must never be included in audit output; values were redacted before display |
| Modifying `.gitignore`, `pubspec.yaml`, or any config file | Auditor-only mandate — findings only, no remediation performed |

---

## 25. Discovery Exit Gate

- [x] Package managers identified.
- [x] Runtime versions identified (declared values; live/production values UNKNOWN).
- [x] Direct dependencies inventoried.
- [x] Dependency usage understood (all direct deps are imported; none found declared-but-unused).
- [x] Config sources mapped.
- [x] Environment variables inventoried.
- [x] Build-time/runtime config separated.
- [x] Feature flags inventoried.
- [x] Debug/test config identified.
- [x] Environment parity risks identified.
- [x] Unknown areas explicitly listed.

Phase 1 (Discovery) complete.
