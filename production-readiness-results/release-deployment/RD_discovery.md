# Release & Deployment Audit — Phase 1: Discovery

| Field | Value |
|---|---|
| System | Niswah (Flutter mobile app — iOS + Android) |
| Repository | `/Users/rynadalsabh/Niswah` |
| Branch | `main` |
| Commit / Version | `13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f` ("docs: update README") on `1.0.0+1` per `pubspec.yaml` |
| Phase | 1 — Discovery |
| Audit date | 2026-09-04 |
| CI/CD platform | **None found** |
| Hosting/deployment platform | Google Play (Android), Apple App Store (iOS); backend on Supabase (project ref not verified from repo) |
| Production environment | Single, undifferentiated — no `ENV-STG`/`ENV-DEV` distinction exists for the mobile release path |
| Release type | Mobile (iOS + Android) |
| Restrictions | Read-only inspection only. No build, sign, publish, deploy, DNS, or CI-secret action performed. |
| Report created | `RD_discovery.md` |

This audit builds directly on prior-wave findings **DC-005 / DC-006 / DC-007 / DC-010** (Dependencies/Config) and **SEC-003** (Security), which are the primary evidence base for the signing/CI/reproducibility portion of this report. Each was independently re-confirmed with one direct read during this pass (see §7 "Actions performed"); this report does not re-derive them from first principles, it formally adopts and owns them as `RD-xxx` release-readiness findings (§ see `RD_findings.md`).

---

## 1. Environment Inventory

| Environment | Purpose | URL/domain | DB | Integrations | Data type | Deployment method | Owner |
|---|---|---|---|---|---|---|---|
| `ENV-LOCAL` | Developer machine builds (`flutter run`, `flutter build`) | N/A (mobile) | Supabase project referenced by whatever `.env` is on disk | Supabase (Postgres + Edge Functions), Gemini API | Real/production Supabase project (only one found — see below) | Manual `flutter build` on developer machine | Unclear — no named owner in repo |
| `ENV-PROD` (implied) | The only Supabase target discoverable in the repo | Not present in repo (real value lives only in `.env`, not committed) | Same as above | Same as above | Real | N/A — no deploy pipeline | Unclear |

**Finding:** There is no `ENV-STG`/staging environment anywhere in the repo — no second `.env.*` file, no Flutter build flavor, no separate Supabase project reference, no `--dart-define` scheme. `APP_ENV` is loaded but (per DC-002, Dependencies/Config) has zero effect on behavior. This means "environment separation" as required by §36 of the master template is **not achieved at the release-process level**: a build made "for testing" and a build made "for the store" are byte-for-byte the same process using the same single `.env` file. This is the release-process framing of DC-001; see `RD_findings.md` RD-005.

---

## 2. Release Flow Map

Documented (actual) flow, as evidenced by the repo:

```
Developer (local machine)
   → (no branch/PR discipline enforced — repo has 2 commits total, both direct to main)
   → no CI trigger (none exists)
   → manual `flutter build apk|appbundle|ios` on developer machine
   → Android: signingConfig = signingConfigs.getByName("debug")  [confirmed, see RD-001/DC-005/SEC-003]
   → iOS: CODE_SIGN_STYLE = Automatic, no DEVELOPMENT_TEAM pinned [confirmed, see RD-002/DC-010]
   → no artifact storage/registry found
   → no approval gate
   → no automated migration step (Supabase migrations under supabase/migrations/ are presumably applied manually via Supabase CLI/dashboard — no script or CI step found that runs them)
   → no deploy step to a store (no Fastlane, no App Store Connect API config, no Play Console upload script)
   → no smoke test step
   → no monitoring/observability tie to release version (no crash reporter dependency in pubspec.yaml — confirmed absent)
   → no rollback mechanism (mobile stores don't support one for the app binary; no feature-flag system exists per master baseline)
```

Every step after "developer writes code" is **manual and undocumented** — there is no file anywhere in the repo (script, README section, Makefile, doc) that describes how a release build is actually produced, signed, or shipped. This absence is itself evidence, not an assumption.

---

## 3. Branch / Versioning Strategy Inventory

- **Branch strategy:** Single branch (`main`). No `develop`, no release branches, no tags (`git tag` returns nothing — verified). Both existing commits (`6d59bfe`, `13a9387`) were committed directly to `main`.
- **Semantic versioning:** `pubspec.yaml` declares `version: 1.0.0+1`. Flutter convention: `1.0.0` → `versionName`/`CFBundleShortVersionString`; `1` (after the `+`) → Android `versionCode` / iOS `CFBundleVersion`.
- **Build-number increment process:** **None found.** No script, Makefile target, CI step, or documented manual procedure anywhere in the repo increments the `+N` build number. Confirmed by exhaustive search for `versionCode`, `CFBundleVersion`, `buildNumber`, `build-number` across `*.md`, `*.sh`, `*.yaml`, `*.yml` (excluding `node_modules`/`build`) — the only hits are `pubspec.yaml` itself and the master baseline report describing it. See `RD_findings.md` RD-006.
- **Deployed-source identifiability:** The exact commit that would correspond to any given build is **not embedded anywhere in the build artifact or app** — no build-info file, no `--dart-define=GIT_COMMIT=...`, no version-display screen confirmed wired to git metadata (not verified beyond grep; no evidence found of one).

---

## 4. Build Artifact Inventory

| Artifact ID | Artifact | Built from | Build command | Stored where | Immutable? | Versioned? |
|---|---|---|---|---|---|---|
| `ART-001` | Android APK/AAB | `13a9387e` (would-be) | Not documented anywhere in repo — inferred standard `flutter build apk`/`appbundle` | Not stored anywhere (no CI artifact store, no repo location) | N/A — none built/found | N/A |
| `ART-002` | iOS IPA/archive | `13a9387e` (would-be) | Not documented anywhere in repo — inferred standard `flutter build ipa` | Not stored anywhere | N/A — none built/found | N/A |

No build artifact was found in the repository (a stray `build/` directory exists locally with intermediate Dart/Flutter tooling caches — `build/ios`, `build/native_assets`, `build/test_cache`, `build/unit_test_assets` — but no `.apk`/`.aab`/`.ipa` release artifact). No build was executed during this audit (per the master template's mandatory restrictions).

---

## 5. Build Provenance Inventory

Per template §11 — can a reviewer answer:

| Question | Answer |
|---|---|
| Which commit produced this artifact? | **Cannot be determined** — no artifact exists to inspect, and no mechanism to embed commit SHA into a build was found. |
| Which dependencies/lockfile were used? | `pubspec.lock` exists and is committed — this part is traceable *if* a build is made from a clean checkout of this exact commit. |
| Which environment/build profile was used? | **Cannot be determined** — no build profile concept exists (see §1 above). |
| Which CI run produced it? | N/A — no CI exists. |
| Which build number/version is inside it? | Whatever `pubspec.yaml` declares at build time — `1.0.0+1`, static, unless manually edited (§3). |

---

## 6. CI Pipeline Inventory

| Pipeline | Trigger | Stages | Required? | Production capable? | Owner |
|---|---|---|---|---|---|
| — | — | — | — | — | — |

**None exist.** Confirmed by directory search: no `.github/workflows`, no `.gitlab-ci.yml`, no `Jenkinsfile`, no `bitrise.yml`, no `codemagic.yaml`, no `.circleci` anywhere in the repo (search performed to depth 4, excluding `node_modules`). This is the release-process framing of **DC-006**; see `RD_findings.md` RD-003.

---

## 7. Required Pre-Deploy Checks Inventory

No pre-deploy checks are enforced by any automated mechanism because no CI/pipeline exists to enforce them. Test files exist under `test/` (a substantial suite — unit, widget, golden, parity tests), which is positive evidence that *some* verification discipline was practiced during development, but nothing in the repo requires these tests to pass before a release build is produced or shipped — running them is entirely at the discretion of whoever builds the release, with no gate.

---

## 8. Deployment Target Inventory

- **Mobile:** Google Play Store (Android, `com.niswah.niswah`), Apple App Store (iOS, bundle presumed to match `com.niswah.niswah` — not independently re-verified in this pass beyond the Android `namespace`/`applicationId`; iOS bundle ID not explicitly grepped in this pass, inherited from DC/SEC prior findings which did not flag a mismatch).
- **Backend:** Supabase (Postgres DB, Auth, Edge Functions — `dr-niswah-chat`). Deployment of Supabase migrations/functions is **not automated** — no `supabase/config.toml` with linked project ref found, no CI step, no deploy script. Presumed manual via Supabase CLI or dashboard, unverified (**UNKNOWN — NOT VERIFIED**, would require Supabase CLI/dashboard access).
- **No CDN, no custom domain, no DNS records relevant to this app were found** — the mobile app talks directly to Supabase's platform-managed domain. DNS/TLS/CDN sections of the master template are therefore largely **N/A** for this release type, beyond noting that Supabase's own TLS/cert management is out of this repo's control and not independently auditable from the codebase.

---

## 9. Deployment Script Inventory

None found. No shell scripts, Makefiles, Fastlane (`fastlane/` directory, `Fastfile`, `Appfile`), Gradle deploy tasks beyond the stock Flutter template, or Xcode build automation/schemes beyond the stock `Runner.xcscheme` were found anywhere in the repo.

---

## 10. Environment Variable / Secret Injection Inventory

Production values enter the build via a single, locally-present `.env` file (not committed — `.gitignore` excludes `.env*`), loaded at build time as a bundled Flutter asset (`pubspec.yaml` → `flutter: assets: - .env`) and read at runtime via `flutter_dotenv`. There is no CI secret store, no deployment-platform variable injection, and no secret manager involved anywhere in the pipeline — because there is no pipeline. This is the release-process framing of **DC-001**; see `RD_findings.md` RD-005. Actual secret *values* were not recorded in this report per template instruction.

---

## 11. Database Migration Release Inventory

- 15 migration files exist under `supabase/migrations/`, most recent timestamp `20260830140000_community_schema_reset.sql`.
- No script, CI job, or documented procedure was found that applies these migrations automatically at release time. Presumed manual (Supabase CLI `db push` or dashboard SQL editor), **UNKNOWN / NOT VERIFIED**.
- `supabase/schema.sql` (507 lines) exists as a separate consolidated schema snapshot; its relationship to the migrations directory (source of truth vs. generated dump) was already flagged **UNKNOWN** by the master baseline and assigned to the Database Integrity audit — not re-litigated here, cross-referenced only.
- No evidence of migration/app-version compatibility planning (expand-contract pattern, etc.) — not directly assessable without more context on release cadence, which does not exist yet (no releases have shipped per the git history, §14).

---

## 12. Release / Migration Sequencing Inventory

Not applicable in practice — no release has ever shipped (2-commit git history, no build artifact, no CI). There is therefore no sequencing to document beyond noting that none has ever been exercised even once.

---

## 13. Feature Flag Release Inventory

Confirmed absent, consistent with the master baseline: no LaunchDarkly, Firebase Remote Config, Supabase-config-driven flag, or custom flag service found anywhere in `lib/`. This directly limits rollback/mitigation options — see §15 below and `RD_findings.md` RD-009.

---

## 14. Rollback Inventory

| Component | Rollback method | Time estimate known? | Data rollback required? | Tested? |
|---|---|---|---|---|
| Mobile app binary (Android/iOS) | **None formal.** Only path is a new store submission with a higher build number, subject to full app-store review latency (hours to days, provider-controlled, not owner-controlled) | NO | N/A (client-only rollback) | NO — never exercised, no release has ever shipped |
| Backend — Supabase Edge Function (`dr-niswah-chat`) | **Ad hoc, partial:** the function could be disabled or its Gemini-calling logic short-circuited via the Supabase dashboard without a client release. Client code (`DrNiswahBackendService.send()` in `lib/features/ai_assistant/data/services/dr_niswah_backend_service.dart`) throws a `StateError` on any non-200/malformed response, and the caller (`chat_view_model.dart` `_sendViaDrNiswahBackend`, wrapped in `try`) catches it rather than crashing the app — so disabling the function server-side degrades this one feature to a visible error state instead of taking down the whole app. This is a genuine, if informal, partial kill-switch. | NO (no documented procedure, no formal flag, no tested runbook) | N/A | NO — not exercised; assessed from code reading only |
| Backend — RLS policy change | Theoretically, an RLS policy could be tightened to block writes/reads for a specific table if a bad release corrupted data flow through that table, mitigating (not reversing) the blast radius. No such runbook exists. | NO | Possibly (existing rows unaffected by a policy change) | NO |
| Database schema/migration | No forward-fix or rollback migration convention observed (migration filenames are additive/date-stamped only; no down-migrations found) | NO | Would require manual SQL, unverified who owns this | NO |
| Config (`.env` values, e.g., rotating a leaked key) | Possible in principle (edit `.env`, rebuild) but requires a **full rebuild and re-release** of the mobile app since config is baked into the binary at build time (per DC-001) — this is not a fast operation for a mobile client | NO | N/A | NO |

**Bottom line:** for the mobile client itself, there is no rollback faster than a full app-store review cycle. The only faster mitigation lever that exists today is disabling/altering the Supabase-side `dr-niswah-chat` Edge Function or an RLS policy — and that only helps for backend-dependent features that already fail gracefully in the client (confirmed for the AI chat path; not verified for every other Supabase-backed feature in the app, e.g., cycle tracking, community board, private messaging — each would need the same catch-and-degrade pattern individually verified to rely on this as a mitigation, which was **not exhaustively checked** here and should not be assumed for other features without that check).

---

## 15. Domain / DNS Inventory

Not applicable — no custom domain, DNS records, or CDN configuration found for this mobile release. Supabase's own domain/TLS is a third-party managed concern outside this repo's control and not independently auditable from the codebase (**UNKNOWN / NOT VERIFIED** — would require Supabase dashboard access).

## 16. TLS / Certificate Inventory

N/A for the same reason — no repo-controlled certificates. Mobile app uses standard OS trust store against Supabase's TLS endpoint; no certificate pinning found in `lib/` (not independently exhaustively re-verified in this pass — Security audit is authoritative on this point if it examined pinning).

## 17. CDN / Cache Release Inventory

N/A — no CDN in this release's architecture as discovered.

---

## 18. Mobile Release Inventory

| Item | Value |
|---|---|
| Bundle/package ID | `com.niswah.niswah` (Android `namespace`/`applicationId` confirmed in `android/app/build.gradle.kts`) |
| Signing keys (Android) | **Debug keystore**, hardcoded via `signingConfig = signingConfigs.getByName("debug")`; no `key.properties`, no `.jks`/`.keystore` file found anywhere in repo (confirmed by search) — see RD-001 |
| Signing identity (iOS) | `CODE_SIGN_STYLE = Automatic`, no `DEVELOPMENT_TEAM` set in any of the 3 build configs in `project.pbxproj` (Debug/Release/Profile) — see RD-002 |
| Version/build number | `1.0.0+1`, static, no increment process (see §3, RD-006) |
| App-store account | **UNKNOWN / NOT VERIFIED** — requires App Store Connect / Google Play Console access, out of scope for this repo-based audit |
| Review requirements | Not assessed — no submission has occurred |
| Phased release | Not configured/assessable — no CI or store config found |
| Minimum supported OS | Not independently re-verified in this pass; `ios/Flutter/AppFrameworkInfo.plist` / `Info.plist` and `android/app/build.gradle.kts` `minSdk = flutter.minSdkVersion` (inherited from Flutter tooling default, not explicitly overridden) |
| Store metadata (screenshots, descriptions, privacy-policy URL) | **None found in repo** — see §19 below and RD-007 |
| Privacy labels/disclosures | Not present in repo; would be configured in-console (App Store Connect "App Privacy" / Play Console "Data safety") — **UNKNOWN / NOT VERIFIED** |
| Deep links/universal links | Not assessed in this pass — out of the DC-005/006/007/010 evidence base and not part of the explicitly assigned new-ground checklist; flagged as unexamined |

---

## 19. Store-Listing Readiness (new ground)

Searched exhaustively (excluding `node_modules`/`build`) for:

- `CHANGELOG*` — **none found**.
- `*release-notes*` — **none found**.
- `fastlane/`, `metadata/`, `*store-listing*` directories — **none found**.
- Privacy-policy URL reference (grep for `privacy.polic`/`privacypolicy` across `.md`/`.dart`/`.json`/`.plist`/`.xml`) — the only in-app hit is a **decorative, non-functional** "Privacy Policy" label in the sign-in consent checkbox (`lib/features/auth/presentation/screens/sign_in_screen.dart` lines ~351, ~359: `TextSpan(text: _tr('Privacy Policy', ...))` and `TextSpan(text: _tr('Terms of Use', ...))`). Both are plain styled `TextSpan`s with **no `TapGestureRecognizer`, no `onTap`, no `url_launcher` call** — confirmed by reading the surrounding widget tree. They render as colored text but are not tappable links to any document. No privacy-policy document, URL, or asset was found anywhere in the repo. See RD-007.

Both Apple App Store Connect and Google Play Console **require** a live, reachable privacy-policy URL to be entered at submission time for any app that collects personal/health data (this app tracks menstrual/pregnancy health data and uses Supabase Auth) — this is a hard submission blocker independent of anything else in this report, and is currently unmet by anything discoverable in this repository.

---

## 20. Release Approval Inventory

No approval process, CODEOWNERS file, branch protection config, or documented release-sign-off procedure was found. Git history shows both commits authored by the same single author (`rayan2099`) with no PR/review trail (repo has no `.github/` at all, so no PR templates or required-review settings could exist here even if GitHub branch protection were configured server-side — that server-side config is **UNKNOWN / NOT VERIFIED**, outside repo inspection).

---

## 21. Post-Deploy Verification Inventory

No smoke-test script, health-check endpoint, or documented post-deploy verification procedure was found. No crash-reporting or analytics SDK was found in `pubspec.yaml` dependencies (consistent with the master baseline's Observability findings) — meaning even if a release shipped, there would be no automated signal that it is healthy.

## 22. Release Monitoring Inventory

None — no crash reporter, no release-tagging in logs/error tracking (none exists), cross-referenced to Observability audit as authoritative.

## 23. Hotfix / Emergency Release Inventory

No documented hotfix process exists. The realistic emergency path for a mobile-app-only bug is: fix code → manually bump `+N` build number (no tooling enforces or reminds of this) → manually re-sign (blocked today by RD-001/RD-002) → resubmit to both stores → wait through review. No expedited-review process or emergency runbook is documented anywhere in the repo.

---

## 24. Manual Step Inventory

| Step | Why manual | Owner | Failure risk | Can automate? |
|---|---|---|---|---|
| Bumping `pubspec.yaml` build number before each release | No tooling/CI exists to do it automatically | Unclear/undocumented | High — a forgotten bump causes both stores to reject the upload outright (RD-006) | YES |
| Producing the release build (`flutter build ...`) | No CI exists | Unclear/undocumented | Medium — non-reproducible, developer-machine-dependent (also DC-006/DC-007) | YES |
| Signing the Android/iOS build | No CI or documented signing procedure exists; currently would use the debug key (Android) or whatever Xcode account is logged in (iOS) | Unclear/undocumented | **Critical** — RD-001 blocks legitimate Play Store publication outright; RD-002 makes iOS builds non-reproducible across machines | YES |
| Applying Supabase migrations | No CI/deploy script found | Unclear/undocumented | High — migration/app version could drift out of sync with no automated guard | YES |
| Uploading to App Store Connect / Play Console | No Fastlane/CI upload step found | Unclear/undocumented | Medium — human error in selecting build/track | YES (partially — stores still require review) |
| Writing/publishing release notes | No changelog file or template found | Unclear/undocumented | Low-Medium — store listings could be submitted with stale/missing notes | YES |

---

## 25. Discovery Execution Log

### Fully reviewed
- `android/app/build.gradle.kts` (signing config)
- `ios/Runner.xcodeproj/project.pbxproj` (code-signing keys, all 3 build configs)
- `pubspec.yaml` (version, assets, dependencies)
- `.env` / `.env.example` (keys only, values redacted in this report)
- Full repo-root directory listing and `.metadata`
- `git log --stat` (full, both commits) and `git log --graph --oneline --all`
- `lib/features/ai_assistant/data/services/dr_niswah_backend_service.dart`, `chat_repository_impl.dart`, `chat_view_model.dart` (error-handling around the Supabase Edge Function call, for the rollback/kill-switch assessment)
- `lib/features/auth/presentation/screens/sign_in_screen.dart` (privacy-policy link verification)
- `supabase/migrations/20260820174500_niswah_production_schema_security.sql` (RLS pattern sample)
- Prior-wave `DC_discovery.md`, `DC_findings.md`, `DC_remediation_plan.md`, `DC_production_readiness_report.md`, and `SEC_findings.md` / `SEC_production_readiness_report.md` (for cross-reference and re-confirmation)

### Partially reviewed
- `supabase/functions/dr-niswah-chat/` (structure and client-facing contract only, not full server-side logic — out of Release/Deployment scope)
- `production-readiness-results/master/00_01_RELEASE_CANDIDATE_BASELINE.md` (relevant excerpts only)

### Structurally scanned only
- Full repo tree (`find` to depth 2) to confirm absence of CI config, Fastlane, changelog, store-metadata directories

### Could not inspect
- App Store Connect / Google Play Console state (no credentials/access — out of scope per template §5, marked UNKNOWN/NOT VERIFIED throughout)
- Supabase dashboard/project configuration (function deployment state, RLS live state, project linkage) — no CLI session or dashboard access available
- Any actual build/signing outcome (mandatory restriction — no build was executed)

### Actions performed

| Action | Purpose | Result |
|---|---|---|
| `grep`/`find` for CI config across common platforms | Confirm DC-006 (no CI) still holds | Confirmed — none found |
| Read `android/app/build.gradle.kts` | Confirm DC-005/SEC-003 (debug signing) still holds | Confirmed verbatim, TODO comment still present |
| `grep` for `CODE_SIGN_STYLE`/`DEVELOPMENT_TEAM` in `project.pbxproj` | Confirm DC-010 still holds | Confirmed — 3 `Automatic` hits, 0 `DEVELOPMENT_TEAM` hits |
| `find` for `.fvmrc`/`.tool-versions`/`.fvm` | Confirm DC-007 (no SDK pinning) still holds | Confirmed — none found; only `.metadata` (auto-generated, not a pinning mechanism) |
| `find`/`grep` for CHANGELOG, release-notes, fastlane, store metadata | New-ground check for store-listing readiness | Confirmed absent |
| `grep` for privacy-policy references | New-ground check for privacy-policy URL | Found only a non-functional UI label, no real link/document |
| `git log --stat` / `git log --graph` | Assess git history depth for release-provenance auditability | Confirmed exactly 2 commits, single author, no PR trail |
| Read `dr_niswah_backend_service.dart`, `chat_repository_impl.dart`, `chat_view_model.dart` | Assess whether Supabase-side changes could serve as an ad hoc kill switch | Confirmed graceful degradation (try/catch) for this one feature path only |

### Actions deliberately avoided

| Action avoided | Reason |
|---|---|
| Running `flutter build` (any target) | Mandatory Phase 1 restriction — no builds during discovery |
| Any Supabase CLI command that could alter project state | Mandatory restriction — read-only inspection only |
| Any git tag/branch creation | Mandatory restriction |
| Attempting store-console access | No credentials provided; out of scope for a repo-based audit |

---

## 26. Discovery Exit Gate

- [x] Environments mapped (single, undifferentiated environment — explicitly documented as a gap, not left blank)
- [x] Release flow mapped (fully manual, no automated stage exists past `git commit`)
- [x] Versioning/build provenance understood (static `1.0.0+1`, no increment mechanism, no commit-to-artifact traceability)
- [x] CI pipeline identified (confirmed: none exists)
- [x] Pre-deploy checks identified (tests exist but are not gated by anything)
- [x] Deployment targets/scripts identified (Play Store / App Store / Supabase; no scripts exist)
- [x] Production config injection understood (single `.env`, no separation — DC-001 inherited)
- [x] Migration sequencing understood (manual, unverified, no automation)
- [x] Rollback mapped (no formal rollback for mobile binary; partial ad hoc Supabase-side mitigation identified and evidenced)
- [x] DNS/TLS/CDN mapped where applicable (N/A for this architecture, documented as such)
- [x] Mobile release process mapped where applicable (signing, versioning, store metadata all mapped — all deficient)
- [x] Approvals/ownership identified (confirmed: none exist)
- [x] Post-deploy verification defined (confirmed: none exists)
- [x] Manual steps listed (§24)
- [x] Unknown release areas explicitly listed (store-console state, Supabase dashboard state — both flagged UNKNOWN/NOT VERIFIED throughout)
