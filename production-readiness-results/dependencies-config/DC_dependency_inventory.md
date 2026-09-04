# Dependencies & Configuration Audit — Dependency Inventory (Supporting)

Source: `pubspec.yaml` (declared) cross-checked against `pubspec.lock` (resolved). Commit `13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f`.

## Direct runtime dependencies

| Dep ID | Package | Declared (pubspec.yaml) | Resolved (pubspec.lock) | Scope | Imported/used? | Criticality | Deprecation status |
|---|---|---|---|---|---|---|---|
| DEP-001 | `cupertino_icons` | `^1.0.8` | `1.0.9` | runtime | YES (icon font) | Low | UNKNOWN/NOT VERIFIED |
| DEP-002 | `collection` | `^1.19.1` | `1.19.1` | runtime | YES | Low | Actively maintained (Dart team package) |
| DEP-003 | `equatable` | `^2.0.7` | `2.1.0` | runtime | YES | Medium | UNKNOWN/NOT VERIFIED — widely used, no known deprecation as of training data |
| DEP-004 | `flutter_dotenv` | `^5.2.1` | `5.2.1` | runtime | YES — sole env-loading mechanism | **Critical** (all config flows through this) | UNKNOWN/NOT VERIFIED |
| DEP-005 | `http` | `^1.2.2` | `1.6.0` | runtime | YES (`GeminiService`, likely elsewhere) | Medium | Dart-team maintained; no deprecation known |
| DEP-006 | `url_launcher` | `^6.3.1` | `6.3.2` | runtime | YES (imported; not grep-verified per-callsite in this audit) | Low-Medium | No deprecation known |
| DEP-007 | `shared_preferences` | `^2.3.3` | `2.5.5` | runtime | YES (used by several `*_controller.dart` preference classes per file listing) | Medium | Flutter-team maintained |
| DEP-008 | `supabase_flutter` | `^2.8.1` | `2.17.2` | runtime | YES — backend client, used in `lib/core/network/supabase_client.dart` | **Critical** (entire backend integration) | UNKNOWN/NOT VERIFIED — resolved version (2.17.2) is beyond this auditor's training-data familiarity; verify against live pub.dev |
| DEP-009 | `uuid` | `^4.6.0` | `4.6.0` | runtime | YES (likely) | Low | No deprecation known |
| DEP-010 | `pdf` | `^3.13.0` | `3.13.0` (exact match to declared floor) | runtime | YES (used with `printing`, likely for cycle-tracking report export) | Medium | No deprecation known |
| DEP-011 | `printing` | `^5.15.0` | `5.15.0` (exact match) | runtime | YES | Medium | No deprecation known |
| DEP-012 | `flutter_local_notifications` | `^22.3.0` | `22.3.0` (exact match) | runtime | YES — `lib/core/services/notification_service.dart` | **Critical** (prayer/cycle notification feature) | UNKNOWN/NOT VERIFIED — major version 22 is beyond this auditor's training-data familiarity; verify against live pub.dev before treating as current/non-deprecated |
| DEP-013 | `timezone` | `^0.11.1` | `0.11.1` (exact match) | runtime | YES (pairs with notifications scheduling) | Medium | No deprecation known |
| DEP-014 | `geolocator` | `^14.0.3` | `14.0.3` (exact match) | runtime | YES — prayer-time/location features | **Critical** (location permission-gated feature) | UNKNOWN/NOT VERIFIED — version 14.x beyond training-data familiarity |
| DEP-015 | `adhan_dart` | `^2.0.1` | `2.0.1` (exact match) | runtime | YES — Islamic prayer time calculation, core to app identity | **Critical** (core domain logic) | UNKNOWN/NOT VERIFIED — small/niche package; maintainer health not assessable from training data, flag for live verification |

## Direct dev dependencies

| Dep ID | Package | Declared | Resolved | Scope | Criticality |
|---|---|---|---|---|---|
| DEP-016 | `flutter_lints` | `^6.0.0` | `6.0.0` | dev-only | Low (code quality gate only, no production impact) |
| DEP-017 | `flutter_test` (SDK) | `sdk: flutter` | bundled with Flutter SDK | dev/test-only | Low |

## Notable transitive dependencies (critical path)

| Package | Resolved version | Pulled by | Note |
|---|---|---|---|
| `gotrue`, `postgrest`, `realtime_client`, `storage_client`, `functions_client`, `supabase`, `supabase_common` | Various | `supabase_flutter` | Full Supabase client stack — all transitive, all critical to backend connectivity; not independently version-pinned in `pubspec.yaml` (acceptable, standard for a wrapper package) |
| `dart_jsonwebtoken` | `3.4.1` | (transitive, likely via `supabase`/`gotrue` for JWT decoding) | Security-relevant transitive dependency; not directly declared/controlled |
| `geolocator_android`, `geolocator_apple`, `geolocator_linux/web/windows` | Various | `geolocator` | Platform federated-plugin pattern — normal, not a duplication concern |
| `flutter_local_notifications_linux/web/windows` + `_platform_interface` | Various | `flutter_local_notifications` | Same federated pattern — normal |
| `path_provider_linux/windows` + `_platform_interface` | Various | Likely transitive via `printing`/`shared_preferences` | Desktop-platform plugin stubs present even though this is a mobile-only app per bundle ID — not a defect, standard federated plugin resolution |

No duplicate/competing libraries found for the same purpose (single HTTP client `http`, single local-storage mechanism `shared_preferences`, no competing date/logging/validation libraries, no second Supabase/backend client). **DUP-xx: no findings.**

No direct dependency was found declared-but-unused by import search — all 15 direct runtime packages have at least one plausible consumer in `lib/` based on the file/module structure reviewed. `flutter_dotenv` and `supabase_flutter` were directly verified by import/usage grep; the remainder are inferred from package purpose matching observed feature modules (cycle tracking, notifications, prayer times, community/PDF export) and were not individually grep-verified line-by-line in this pass — **flag as `UNUSED-xx: INCONCLUSIVE` for DEP-001, DEP-003, DEP-006, DEP-009, DEP-010, DEP-011, DEP-013 pending a full per-package import grep**, though risk is low given the app's evident feature surface.

## Framework/SDK Compatibility Snapshot

`Flutter (>=3.44.0) ↔ Dart (^3.13.0) ↔ Android Gradle Plugin (9.1.0) ↔ Kotlin (2.4.0) ↔ Gradle (9.3.1) ↔ iOS deployment target (15.0)`

All version numbers are internally plausible (no obvious mismatch such as an AGP version requiring a newer Gradle than declared), but **none could be cross-checked against an authoritative compatibility matrix** — this auditor's training data does not extend to confirm compatibility for Flutter 3.44/AGP 9.1/Kotlin 2.4 combinations. Mark **UNKNOWN / REQUIRES LIVE VERIFICATION**.

## Lockfile Audit Summary

- Single lockfile per ecosystem: `pubspec.lock` for Dart (committed), `package-lock.json` for the reference npm app (committed, out of primary scope).
- `pubspec.lock` is tracked in git (`git ls-files` confirms) — **PASS** on lockfile-committed gate.
- No evidence of multiple/conflicting Dart lockfiles.
- No `flutter pub get`/install was executed during this audit, so **lockfile-matches-manifest** and **clean install succeeds** are **NOT VERIFIED** (Phase 2B Controlled Validation was not executed — see `DC_production_readiness_report.md` Out-of-Scope section).
