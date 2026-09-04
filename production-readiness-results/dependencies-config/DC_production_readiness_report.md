# Dependencies & Configuration — Production Readiness Report (Final)

| Field | Value |
|---|---|
| System | Niswah (Flutter mobile app) |
| Repository | `/Users/rynadalsabh/Niswah` |
| Branch | `main` |
| Commit / Version | `13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f` — pubspec `1.0.0+1`, bundle `com.niswah.niswah` |
| Phase | Final — Production Readiness |
| Audit date | 2026-09-04 |
| Package manager(s) | `pub` (Dart/Flutter) — primary/in-scope; `npm` — reference-only web app, out of primary scope |
| Runtime(s) | Dart `^3.13.0`, Flutter `>=3.44.0` (no upper bound, unpinned) |
| Environment | Local repository inspection only — no CI, staging, or production environment exists to validate against |
| Build target | Android (`com.niswah.niswah`) + iOS Runner |
| Restrictions | Auditor-only mandate: no dependency changes, no lockfile changes, no config/`.env` changes, no builds executed. Phase 2B (Controlled Validation) was **not executed** — no `flutter build`/install was run, per the read-only scope of this pass. |
| Report created | `DC_production_readiness_report.md` |

---

## 69. Executive Summary

### System
Niswah — Flutter mobile app (women's health/cycle-tracking + Islamic prayer-time companion), Supabase backend.

### Version / Commit
`1.0.0+1` / `13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f`

### Runtime(s)
Dart SDK `^3.13.0`; Flutter SDK `>=3.44.0` (unpinned, no version-manager config found)

### Package manager(s)
`pub`/`flutter pub`, with `pubspec.lock` committed to git (reproducibility gate for package resolution: PASS)

### Production build
**NOT RUN.** No `flutter build` was executed during this audit (read-only mandate). Build success/failure is therefore **UNKNOWN**, not PASS.

### Open findings
- DC0 (Critical): **3** — DC-001, DC-004, DC-005
- DC1 (High): **3** — DC-003, DC-006, DC-010
- DC2 (Medium): **2** — DC-002, DC-007
- DC3 (Low): **2** — DC-008, DC-009
- DC4 (Observation): **1** — DC-011
- Closed/N-A: **1** — DC-012 (Podfile absence, verified false positive)

Full detail: `DC_findings.md`.

### Critical unknowns
1. **Whether a `flutter build --release` currently succeeds at all** — not executed in this audit.
2. **Live pub.dev deprecation/advisory status** for `flutter_local_notifications` (22.3.0), `supabase_flutter` (2.17.2), `geolocator` (14.0.3), `adhan_dart` (2.0.1), and related toolchain versions (Flutter ≥3.44, AGP 9.1.0, Kotlin 2.4.0) — versions beyond this auditor's training-data familiarity; not confirmable offline.
3. **Actual production Supabase project configuration** (what `.env` values a real release build would use) — not accessible/in scope for this repo-only audit.
4. **Whether any release build has ever been produced and distributed**, and if so, what it was signed with, given DC-005/DC-010 show no working release-signing configuration currently exists in the repo.

### Final recommendation
🔴 **NO-GO**

---

## 70/71. Launch Gate Table

| Gate | Requirement | Evidence | Status |
|---|---|---|---|
| LG-DC-01 | Zero open DC0 | DC-001, DC-004, DC-005 open — `DC_findings.md` | **FAIL** |
| LG-DC-02 | Zero launch-blocking DC1 | DC-003, DC-006, DC-010 open, all marked launch-blocker YES | **FAIL** |
| LG-DC-03 | Reproducible clean install | Not executed (Phase 2B skipped); `pubspec.lock` committed (necessary but not sufficient — install itself unverified) | **FAIL** (INCONCLUSIVE treated as FAIL for gate purposes per template's evidence-driven standard) |
| LG-DC-04 | Production build passes | Not run | **FAIL** (NOT RUN, cannot be marked PASS) |
| LG-DC-05 | Runtime compatibility verified | Versions declared and internally consistent-looking, but no live compatibility matrix check possible; no CI to confirm | **FAIL** (UNKNOWN, treated conservatively) |
| LG-DC-06 | Lockfile/package-manager consistent | Single lockfile per ecosystem, `pubspec.lock` committed, no conflicting lockfiles | **PASS** |
| LG-DC-07 | Critical config inventoried/validated | Inventoried fully (`DC_discovery.md` §15-17); validation exists in code but is defeated by DC-004; `GEMINI_API_KEY` has no startup validation (DC-003) | **FAIL** |
| LG-DC-08 | No production debug/mock config | `kDebugSkipSignup` present but currently `false` (DC-009, low severity); no mock/sandbox/localhost found | **PASS** (with DC3 noted, not blocking) |
| LG-DC-09 | Feature flag defaults safe | Only flag found (`kDebugSkipSignup`) defaults safely to `false` | **PASS** |
| LG-DC-10 | Environment parity acceptable | No staging environment exists at all; single `.env` used for all targets (DC-001/DC-002) means "parity" is trivially true only because there is no differentiation to begin with — this is itself the defect | **FAIL** |
| LG-DC-11 | No critical AI config/dependency drift | DC-003 confirms real drift (undocumented required key, three unused dead keys) | **FAIL** |
| LG-DC-12 | No critical unknowns | Four critical unknowns listed above remain | **FAIL** |

**9 of 12 mandatory gates FAIL.** Per template §70, any mandatory FAIL prevents GO, and the NO-GO criteria are unambiguously met (open DC0 findings; production build not reproduced/verified; critical config missing safe fail-fast behavior; release signing absent on both platforms; required env variables exist only locally).

---

## 72. Residual Risk Register

| Risk ID | Finding | Severity | Probability | Production impact | Mitigation | Owner | Required before launch? |
|---|---|---|---|---|---|---|---|
| RISK-DC-001 | DC-001 | DC0 | HIGH (certain, given current build wiring) | Secrets (Supabase keys, Gemini key) compiled into every shipped binary, extractable | Remove `.env` from `flutter: assets:`; use `--dart-define-from-file` or runtime-fetched config | Release owner / mobile lead | YES |
| RISK-DC-002 | DC-004 | DC0 | MEDIUM (triggers only if config is missing/invalid at build time, which is plausible given DC-001's single-file-for-all-builds pattern) | Silent infinite splash-screen hang in the field, no diagnostic signal | Scope `runZonedGuarded` so config failures surface visibly | Mobile lead | YES |
| RISK-DC-003 | DC-005 | DC0 | CERTAIN (verified by direct code inspection — not probabilistic) | Cannot legitimately publish to Google Play; if force-published via unofficial channel, users receive a debug-signed, non-upgradeable-in-place app | Configure real release keystore + signing config | Release/Deployment owner | YES |
| RISK-DC-004 | DC-010 | DC1 | CERTAIN (verified) | Cannot reproducibly build a distributable iOS release outside one specific developer's machine | Set explicit `DEVELOPMENT_TEAM`/manual signing | Release/Deployment owner | YES |
| RISK-DC-005 | DC-006 | DC1 | CERTAIN (verified — no CI exists) | No reproducible/auditable build process for any release, ever | Stand up minimal CI (build + test on pinned toolchain) | Engineering lead | YES (or explicit owner acceptance for CONDITIONAL GO, not applicable here given DC0s remain) |
| RISK-DC-006 | DC-003 | DC1 | HIGH | New developers/build machines produce builds where AI Advisor/Dream Interpreter silently don't work; no clear signal why | Document `GEMINI_API_KEY`; reconcile dead AI-key scaffold | Mobile lead | YES |
| RISK-DC-007 | DC-002, DC-007 | DC2 | N/A (already realized) | No real dev/staging/prod behavioral separation; toolchain drift risk between machines | See remediation plan R2.2, R3.1 | Mobile lead | NO (acceptable as bounded debt once DC0/DC1 items are closed) |
| RISK-DC-008 | DC-008, DC-009 | DC3 | LOW | Repo hygiene / minor residual credential exposure from an unused backend | Cleanup per R3.2/R3.3 | Mobile lead | NO |
| RISK-DC-009 | DC-011 | DC4 | UNKNOWN | Unverified dependency currency/deprecation | Run `flutter pub outdated` with network access | Mobile lead | NO (but recommended before GO is revisited) |

---

## 73. Out-of-Scope / Not Verified

- **Production/staging environment variables** — no deployment platform exists for the Flutter app to inspect; entirely UNVERIFIED.
- **Actual `flutter build` execution** (Phase 2B Controlled Validation) — deliberately not run in this pass; this audit is Discovery + Static Verification (Phases 1 and 2A) only. A Controlled Validation pass in a disposable environment is recommended as the immediate next step and would directly test DC-001/DC-004/DC-005's real-world manifestation.
- **Live pub.dev advisory/deprecation data** — no network verification tool was available/authorized during this audit; all deprecation calls are marked UNKNOWN per DC-011.
- **Android/iOS native SDK compatibility matrix** for the specific versions found (Flutter ≥3.44, AGP 9.1.0, Kotlin 2.4.0, Gradle 9.3.1, iOS 15.0 deployment target) — beyond this auditor's verifiable training knowledge; not asserted incompatible, just unconfirmed.
- **License/legal compatibility review** — not performed; delegate to counsel per template's non-goals.
- **Package vulnerability/CVE assessment** — delegated to Security Audit per template's non-goals; this audit only flagged deprecation-status uncertainty, not specific CVEs.
- **`src/` (React/Vite reference web app)** — reviewed only superficially (existence of `package.json`/`package-lock.json`, no conflicting lockfiles found); per task scope and the user's standing instruction that `src/` is a design-reference app only, it was not audited to the same depth as the Flutter app and none of its findings (if any) are reflected in the gate table above.
- **CI provider / secrets manager selection** — no opinion formed on which specific CI platform or secrets manager to adopt; the remediation plan intentionally leaves this open for the release owner's infrastructure preference.

---

## 74. Final One-Sentence Recommendation

> Dependencies & Configuration recommendation: **NO-GO** for `1.0.0+1` (commit `13a9387e`) until findings **DC-001, DC-004, and DC-005** (and, before the next release-readiness review, **DC-003, DC-006, and DC-010**) are remediated and the associated clean-install, missing-config-failure, and production-build/signing validations pass — the release cannot currently be reproducibly built, safely configured, or legitimately signed for distribution on either platform.
