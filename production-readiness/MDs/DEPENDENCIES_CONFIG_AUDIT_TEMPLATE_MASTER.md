# Dependencies & Configuration Audit — Reusable Master Template

> **Purpose:** A reusable production-readiness audit for verifying that an application's dependencies, packages, environment variables, runtime configuration, build configuration, feature flags, and environment-specific settings are controlled, reproducible, intentional, and safe before launch.
>
> This template is designed for applications built manually or with AI coding agents. It is intentionally evidence-driven: **do not mark dependency/configuration readiness PASS because the app builds locally or because `.env.example` exists. Critical dependencies and production configuration must be verified against the actual build/runtime path and the exact release environment.**

---

# 0. Operating Rules

## 0.1 Audit objective

Determine whether the current dependency and configuration model is production-ready by verifying:

- All production dependencies are known and intentionally used.
- Dependency versions are reproducible.
- Lockfiles are present and authoritative where applicable.
- Critical dependencies are not unintentionally duplicated.
- Deprecated, abandoned, or incompatible dependencies are identified.
- Runtime versions match package/framework requirements.
- Build tooling versions are controlled.
- Environment variables are inventoried.
- Required configuration is validated.
- Missing critical configuration fails clearly.
- Secrets are referenced safely and never committed.
- Environment-specific values are separated from application logic.
- Production does not use development/test/mock configuration.
- Feature flags have clear ownership and defaults.
- Debug modes are disabled in production.
- Build-time and runtime configuration are not confused.
- Local, staging, and production behavior do not silently drift.
- Configuration has an explicit source of truth.
- AI-generated code has not introduced phantom environment variables, unused packages, unsupported versions, duplicate libraries, or conflicting config patterns.

## 0.2 Non-goals

This audit does **not** replace:

- Security audit.
- Code quality audit.
- API/backend audit.
- Infrastructure/DevOps audit.
- Performance audit.
- Software supply-chain security review by a specialist.
- License/legal review by counsel.

When a dependency/configuration issue overlaps those areas, cross-reference the appropriate audit.

---

# 1. Mandatory Methodology

Use these stages in order:

| Stage | Name | What happens | Required output |
|---|---|---|---|
| 1 | **Discovery** | Map package managers, manifests, lockfiles, runtimes, environment variables, config files, feature flags, build profiles, and deployment assumptions | Dependency/config map |
| 2A | **Static Verification** | Inspect dependency and configuration consistency, usage, drift, deprecation, and unsafe patterns | Evidence matrix |
| 2B | **Controlled Validation** | Execute safe install/build/config validation in an approved environment | PASS / FAIL / INCONCLUSIVE matrix |
| 3 | **Remediation Design** | Design controlled upgrades/config fixes — **design only unless separately authorized** | Remediation plan |
| Final | **Production Readiness Report** | Consolidate evidence and issue launch recommendation | GO / CONDITIONAL GO / NO-GO |

### Golden rule

**A local successful build does not prove production configuration correctness.**

Always distinguish:

`Declared dependency → Installed dependency → Imported dependency → Runtime-used dependency → Production-compatible dependency`

and:

`Documented config → Defined config → Loaded config → Validated config → Used config → Production value`

---

# 2. Report Header

Use this header in every phase report:

| Field | Value |
|---|---|
| System | `{SYSTEM_NAME}` |
| Repository | `{REPOSITORY_NAME}` |
| Branch | `{BRANCH}` |
| Commit / Version | `{COMMIT_OR_VERSION}` |
| Phase | `{PHASE_NAME}` |
| Audit date | `{DATE}` |
| Package manager(s) | `{npm / pnpm / yarn / pip / poetry / composer / gradle / etc.}` |
| Runtime(s) | `{NODE / PHP / PYTHON / DART / JVM / etc.}` |
| Environment | `{Local / Dev / Staging / Production}` |
| Build target | `{TARGET}` |
| Restrictions | `{WHAT_WAS_NOT_DONE}` |
| Report created | `{THIS_FILENAME}` |

---

# 3. Evidence and Confidence Key

| Symbol | Meaning |
|---|---|
| 🟥 **Confirmed by Execution / Installed State** | Proven by install/build/runtime/config validation |
| 🟧 **Confirmed by Manifest / Code / Config** | Proven from exact file, package declaration, import, or config usage |
| 🟨 **Likely** | Strong inference but not yet runtime-confirmed |
| 🟦 **Requires Controlled Validation** | Must be validated before conclusion |
| ⬜ **Not Applicable / False Positive** | Does not apply or was disproven |

For every material finding include:

- Finding ID.
- Dependency/config item.
- Manifest/config path.
- Declared value/version.
- Actual usage.
- Production impact.
- Evidence.
- Severity.
- Launch-blocker status.
- Confidence.

---

# 4. Severity Model

| Level | Classification | Dependency/config meaning | Launch treatment |
|---|---|---|---|
| **DC0** | Critical | Production cannot build/start safely, critical dependency/config mismatch causes catastrophic behavior, or production uses clearly unsafe/test credentials/config | **Mandatory NO-GO** |
| **DC1** | High | Core runtime/configuration is materially inconsistent, missing, unsupported, or likely to fail in production | **Pre-launch blocker** |
| **DC2** | Medium | Important dependency/config debt with bounded operational impact | Explicit acceptance required |
| **DC3** | Low | Minor duplication, stale config, or cleanup issue | Backlog acceptable |
| **DC4** | Observation | Improvement opportunity | Backlog |

## 4.1 Severity factors

Evaluate:

- Production reachability.
- Build/startup impact.
- Runtime compatibility.
- Environment scope.
- Dependency criticality.
- Upgrade risk.
- Silent fallback behavior.
- Security implications.
- Reproducibility.
- Whether issue affects only dev tooling or live runtime.
- Whether failure is immediate or latent.

---

# 5. Environment Warning

When validating outside production:

| Dimension | Evaluation |
|---|---|
| Technical severity | Based on dependency/config defect |
| Current actual impact | Based on current environment |
| Production impact | State how defect would affect release/runtime |
| Procedural classification | Unresolved DC0/DC1 findings are **Pre-Launch Blockers** |

Do not rotate secrets, upgrade production dependencies, rewrite lockfiles, or change live configuration during audit unless separately authorized.

---

# PHASE 1 — DISCOVERY

# 6. Objective

Understand every dependency and configuration source before judging readiness.

### Mandatory restrictions

During discovery:

- Prefer read-only inspection.
- Do not run package upgrades.
- Do not delete lockfiles.
- Do not regenerate manifests.
- Do not alter `.env` files.
- Do not rotate secrets.
- Do not enable production debug mode.
- Do not change feature flags.
- Do not run auto-fix package commands.

---

# 7. Package Manager Inventory

Document all package ecosystems used:

| Ecosystem | Manifest | Lockfile | Package manager | Version pinned? | Used for |
|---|---|---|---|---|---|
| `{npm}` | `{package.json}` | `{lockfile}` | `{pnpm/npm/etc.}` | `{YES/NO}` | `{frontend/backend/tooling}` |

Flag:

- multiple lockfiles for same ecosystem,
- package manager mismatch,
- lockfile missing,
- lockfile ignored,
- local install instructions differing from CI.

---

# 8. Runtime Inventory

Document:

| Runtime | Required version | Declared where | CI version | Production version | Match? |
|---|---|---|---|---|---|
| `{Node}` | `{}` | `{}` | `{}` | `{}` | `{YES/NO/UNKNOWN}` |

Include:

- Node.js,
- PHP,
- Python,
- Java/JVM,
- Dart/Flutter,
- Ruby,
- Go,
- database client runtime,
- native/mobile SDK requirements.

---

# 9. Dependency Inventory

For every relevant production dependency:

| Dep ID | Package | Declared version | Installed/resolved version | Scope | Imported/used? | Criticality |
|---|---|---|---|---|---|---|
| `DEP-001` | `{PACKAGE}` | `{}` | `{}` | `{runtime/dev}` | `{YES/NO/UNKNOWN}` | `{}` |

Separate:

- runtime,
- development,
- build-time,
- test-only,
- optional/peer dependencies.

---

# 10. Direct vs Transitive Dependency Inventory

Identify:

- direct dependencies,
- transitive dependencies,
- critical transitive packages,
- packages pulled by multiple paths,
- conflicting major versions.

Do not treat all transitive duplication as a defect; focus on meaningful risk.

---

# 11. Dependency Usage Inventory

For direct dependencies classify:

- actively imported,
- configuration-only,
- CLI/build-only,
- test-only,
- legacy/unused,
- unclear.

Flag package declared but no usage found, subject to dynamic framework behavior.

---

# 12. Dependency Ownership Inventory

For critical libraries document:

- why chosen,
- what feature depends on it,
- replacement difficulty,
- maintainer health known?,
- official/internal wrapper?,
- upgrade owner.

---

# 13. Framework / SDK Compatibility Inventory

Map compatibility among:

- framework version,
- language/runtime,
- plugin versions,
- SDKs,
- compiler/build tool,
- native platform SDK.

Example:

`Flutter ↔ Dart ↔ package versions ↔ Android Gradle Plugin ↔ Kotlin ↔ iOS deployment target`

Document known compatibility constraints.

---

# 14. Configuration Source Inventory

Identify all configuration sources:

- `.env`,
- `.env.local`,
- `.env.production`,
- config files,
- build profiles,
- JSON/YAML/TOML,
- runtime parameter store,
- secret manager,
- database-stored settings,
- feature flag provider,
- mobile build config,
- CI variables,
- deployment dashboard variables.

| Source | Environment | Purpose | Checked into repo? | Contains secrets? | Authoritative? |
|---|---|---|---|---|---|
| `{SOURCE}` | `{}` | `{}` | `{YES/NO}` | `{YES/NO}` | `{YES/NO}` |

---

# 15. Environment Variable Inventory

Use stable IDs:

- `ENV-001`, `ENV-002`, ...

| Env ID | Variable | Required? | Type | Used by | Default | Secret? | Environments |
|---|---|---|---|---|---|---|---|
| `ENV-001` | `{NAME}` | `{YES/NO}` | `{string/int/bool/url}` | `{MODULE}` | `{}` | `{YES/NO}` | `{}` |

Never include actual secret values.

---

# 16. Environment Variable Source-of-Truth Map

Compare:

- `.env.example`,
- README,
- config schema,
- CI,
- deployment platform,
- code usage.

Flag variable that exists in code but not documentation/configuration.

---

# 17. Build-Time vs Runtime Config Inventory

Classify every critical config value:

- compile/build-time,
- deploy-time,
- runtime,
- client-exposed,
- server-only.

Flag server secret accidentally embedded into client build.

Security implications cross-reference Security Audit.

---

# 18. Feature Flag Inventory

| Flag ID | Flag | Default | Environments | Owner | Expiry/removal date | Critical path? |
|---|---|---|---|---|---|---|
| `FLAG-001` | `{FLAG}` | `{}` | `{}` | `{}` | `{}` | `{YES/NO}` |

Flag:

- permanent temporary flags,
- conflicting defaults,
- flag read in one place but set elsewhere differently,
- dead flags,
- production experiments with unclear ownership.

---

# 19. Debug / Development Setting Inventory

Search for:

- debug mode,
- verbose errors,
- mock API,
- sandbox payments,
- dev auth bypass,
- seed mode,
- test endpoints,
- profiler,
- hot reload assumptions,
- fake notifications,
- localhost URLs.

---

# 20. Endpoint / URL Configuration Inventory

Document:

- API base URL,
- websocket URL,
- callback URLs,
- CDN,
- storage,
- payment provider,
- auth provider,
- analytics,
- AI service.

Flag hardcoded production/dev URLs in application code.

---

# 21. Secret Reference Inventory

Without exposing secret values, identify secret names and expected storage:

- DB URL,
- API keys,
- OAuth client secret,
- JWT secret/private key,
- payment key,
- webhook secret,
- SMTP credentials,
- storage key,
- AI provider key.

Flag secret expected from environment but hardcoded or missing.

---

# 22. Configuration Validation Inventory

Determine whether app validates config at:

- build,
- startup,
- first use,
- never.

Document:

- required fields,
- type checks,
- URL validation,
- enum validation,
- numeric range,
- mutually exclusive settings.

---

# 23. Environment Parity Inventory

Compare:

| Area | Local | Staging | Production | Drift risk |
|---|---|---|---|---|
| Runtime | `{}` | `{}` | `{}` | `{}` |
| DB engine/version | `{}` | `{}` | `{}` | `{}` |
| Feature flags | `{}` | `{}` | `{}` | `{}` |
| Storage | `{}` | `{}` | `{}` | `{}` |
| Integrations | `{}` | `{}` | `{}` | `{}` |

Flag material environment-only behavior.

---

# 24. Discovery Execution Log

### Fully reviewed
`{MANIFESTS / CONFIG / ENV SCHEMAS}`

### Partially reviewed
`{AREAS}`

### Structurally scanned only
`{AREAS}`

### Could not inspect
`{AREAS + REASON}`

### Actions performed
| Action | Purpose | Result |
|---|---|---|

### Actions deliberately avoided
| Action avoided | Reason |
|---|---|

---

# 25. Discovery Exit Gate

Phase 1 passes only when:

- [ ] Package managers identified.
- [ ] Runtime versions identified.
- [ ] Direct dependencies inventoried.
- [ ] Dependency usage understood.
- [ ] Config sources mapped.
- [ ] Environment variables inventoried.
- [ ] Build-time/runtime config separated.
- [ ] Feature flags inventoried.
- [ ] Debug/test config identified.
- [ ] Environment parity risks identified.
- [ ] Unknown areas explicitly listed.

---

# PHASE 2A — STATIC VERIFICATION

# 26. Objective

Inspect dependency and configuration quality without mutating the project.

Use stable prefixes:

| Prefix | Category |
|---|---|
| `PKG-xx` | Packages |
| `LOCK-xx` | Lockfiles |
| `VER-xx` | Versioning |
| `COMPAT-xx` | Compatibility |
| `DEPR-xx` | Deprecated/abandoned |
| `DUP-xx` | Duplicate dependency |
| `UNUSED-xx` | Unused dependency/config |
| `ENV-xx` | Environment variables |
| `CFG-xx` | Configuration |
| `SECRET-xx` | Secret reference |
| `FLAG-xx` | Feature flags |
| `DEBUG-xx` | Debug/test config |
| `URL-xx` | Endpoint/URL config |
| `PARITY-xx` | Environment parity |
| `BUILD-xx` | Build configuration |
| `AI-xx` | AI-agent-specific dependency/config defects |

---

# 27. Lockfile Audit

Verify:

- expected lockfile exists,
- only intended lockfile used,
- lockfile committed,
- lockfile matches manifest,
- CI uses frozen/immutable install where appropriate,
- package manager version consistent.

Flag:
- `package-lock.json` + `yarn.lock` + `pnpm-lock.yaml` all present for one app without intention,
- lockfile recreated frequently by different tools.

---

# 28. Dependency Version Audit

Inspect:

- exact vs range versions,
- major-version drift,
- peer dependency conflicts,
- framework/plugin compatibility,
- unsupported runtime versions.

Do not require exact pinning universally; evaluate reproducibility and ecosystem norms.

---

# 29. Deprecated / Abandoned Dependency Audit

Identify packages that are:

- deprecated by package manager,
- replaced by framework-native alternative,
- archived,
- no longer maintained,
- incompatible with current framework.

Do not classify as blocker solely because package is old. Assess actual support/impact.

---

# 30. Duplicate Dependency Audit

Inspect:

- multiple major versions of same library,
- overlapping libraries for same purpose,
- multiple date libraries,
- multiple HTTP clients,
- multiple logging libraries,
- duplicate UI libraries,
- duplicate validation libraries.

Flag when duplication increases bundle/runtime/config inconsistency.

---

# 31. Unused Dependency Audit

Classify direct dependencies:

- confirmed used,
- likely unused,
- dynamic/framework usage,
- CLI-only,
- test-only.

Do not delete during audit.

---

# 32. Runtime Compatibility Audit

Verify:

- runtime satisfies framework minimum/maximum,
- build tooling compatible,
- production runtime known,
- local/CI/prod aligned enough.

Flag production runtime unknown for critical app.

---

# 33. Environment Variable Audit

For each variable verify:

- declared,
- documented,
- loaded,
- validated,
- used,
- correct exposure level,
- no unsafe default.

Flag phantom variables: referenced but never configured.

---

# 34. Missing Config Failure Audit

Inspect what happens if critical variable is absent.

Preferred behavior for critical config:

- fail early,
- clear error,
- no secret value displayed.

Flag silent fallback to unsafe/default environment.

---

# 35. Default Value Audit

Inspect defaults for:

- API URLs,
- environment mode,
- payment sandbox/live mode,
- feature flags,
- authentication behavior,
- ports,
- timeouts.

Flag default that could silently point production to test or vice versa.

---

# 36. Client-Exposed Configuration Audit

Verify client-visible config contains only values safe for client exposure.

Cross-reference secrets with Security Audit.

---

# 37. Debug/Test Configuration Audit

Search for production-reachable:

- test account bypass,
- fake user,
- mock backend,
- sandbox payment,
- test feature flag,
- dev toolbar,
- verbose stack trace,
- profiler,
- localhost.

---

# 38. Feature Flag Audit

Verify:

- default defined,
- missing flag behavior safe,
- production state known,
- owner known,
- stale flags identified,
- rollout logic consistent.

Flag feature where backend and frontend interpret flag differently.

---

# 39. Environment Parity Audit

Inspect material differences between staging and production:

- provider type,
- database engine,
- queue availability,
- runtime version,
- feature flags,
- storage,
- auth,
- build mode.

A staging environment that differs materially may not validate production behavior.

---

# 40. Build Configuration Audit

Inspect:

- production mode enabled,
- source maps policy,
- debug symbols,
- optimization flags,
- minification,
- tree-shaking,
- target platform,
- environment injection,
- build profile.

Do not treat optimization settings as a performance audit; focus on correctness/reproducibility.

---

# 41. CI / Local Dependency Consistency Audit

Compare:

- package manager,
- runtime,
- install command,
- build command,
- test command,
- environment loading.

Flag “works on local only” assumptions.

---

# 42. AI-Agent-Specific Dependencies & Configuration Audit

Mandatory when AI agents were used.

Actively search for:

## 42.1 Phantom environment variables

- code references variable not present anywhere else,
- agent invents new variable without adding deployment config.

## 42.2 Unused dependencies

- agent installs library for abandoned approach,
- dependency remains after refactor.

## 42.3 Competing libraries

- axios + fetch wrapper + another HTTP client,
- multiple validation/state/date/logging packages.

## 42.4 Unsupported APIs / versions

- agent writes code for newer library version than installed,
- package docs copied from different major version.

## 42.5 Localhost / temporary URLs

- `localhost`,
- `127.0.0.1`,
- ngrok/test domains,
- temporary Vercel/preview URLs.

## 42.6 Unsafe defaults

- missing env falls back to development,
- payment mode defaults to test silently,
- auth disabled when config missing.

## 42.7 Config duplication

- same value in `.env`, config file, hardcoded constant, deployment manifest.

## 42.8 Partial renames

- old and new env variable names both exist,
- frontend changed but backend did not,
- docs reference old name.

## 42.9 Test/debug leftovers

- mock flag,
- fake data mode,
- dev login,
- seed command run at startup.

## 42.10 Unnecessary dependency installation

- AI installs package instead of using existing framework/native capability,
- overlapping packages increase attack surface and maintenance burden.

---

# 43. Static Verification Matrix

| Check ID | Category | Scope | Expected condition | Evidence | Result |
|---|---|---|---|---|---|
| `{ID}` | `{}` | `{}` | `{}` | `{}` | `{PASS/FAIL/INCONCLUSIVE}` |

---

# 44. Static Verification Exit Gate

Phase 2A passes only when:

- [ ] Lockfiles reviewed.
- [ ] Versions/compatibility reviewed.
- [ ] Deprecated/abandoned dependencies reviewed.
- [ ] Duplicate/unused dependencies reviewed.
- [ ] Runtime compatibility reviewed.
- [ ] Environment variables reviewed.
- [ ] Config validation/defaults reviewed.
- [ ] Feature flags reviewed.
- [ ] Debug/test config reviewed.
- [ ] Environment parity reviewed.
- [ ] AI-generated dependency/config risks reviewed.
- [ ] DC0/DC1 candidates have evidence.

---

# PHASE 2B — CONTROLLED VALIDATION

# 45. Objective

Prove dependency/configuration reproducibility using safe commands in an approved environment.

### Mandatory restrictions

- Do not upgrade packages.
- Do not run `--fix`/auto-upgrade.
- Prefer frozen/immutable install.
- Do not expose secret values.
- Do not modify production config.
- Record exact runtime/package-manager versions.
- Use disposable/local/staging environment.

---

# 46. Validation Test Categories

| Prefix | Category |
|---|---|
| `DC-INSTALL-xx` | Dependency install |
| `DC-BUILD-xx` | Build |
| `DC-START-xx` | Startup |
| `DC-ENV-xx` | Environment validation |
| `DC-FLAG-xx` | Feature flags |
| `DC-PARITY-xx` | Environment parity |
| `DC-RUNTIME-xx` | Runtime compatibility |

---

# 47. Controlled Validation Matrix

| Test ID | Validation | Preconditions | Command/action | Expected result | Actual result | Evidence | Result |
|---|---|---|---|---|---|---|---|
| `{ID}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{PASS/FAIL/INCONCLUSIVE}` |

---

# 48. Clean Install Test

In a clean/disposable environment:

1. Use declared runtime.
2. Use declared package manager.
3. Use committed lockfile.
4. Install with frozen/immutable mode if supported.
5. Record warnings/errors.
6. Confirm no manual undocumented step required.

---

# 49. Production Build Test

Build exact production target.

Verify:

- build succeeds,
- correct environment selected,
- no development/mock values injected,
- no missing config,
- no incompatible dependency error.

---

# 50. Missing Critical Config Test

Remove/omit one required synthetic config value in controlled environment.

Verify startup/build fails clearly when appropriate.

Do not use real secret values in test output.

---

# 51. Invalid Config Type Test

Where config schema exists:

- invalid URL,
- invalid number,
- invalid enum,
- invalid boolean.

Verify clear rejection.

---

# 52. Feature Flag Default Test

Test missing/unavailable flag provider where safe.

Verify default behavior is intentional and safe.

---

# 53. Runtime Version Test

Execute build/start with intended production runtime.

Verify no hidden local-version dependency.

---

# 54. Environment Parity Validation

Compare known key configuration dimensions:

- runtime,
- package manager,
- DB engine,
- critical providers,
- feature flags,
- build mode.

Record differences that invalidate staging evidence.

---

# 55. Controlled Validation Summary

| Metric | Count |
|---|---:|
| Validation tests planned | `{}` |
| Executed | `{}` |
| PASS | `{}` |
| FAIL | `{}` |
| INCONCLUSIVE | `{}` |
| DC0 findings | `{}` |
| DC1 findings | `{}` |
| DC2 findings | `{}` |

---

# 56. Controlled Validation Exit Gate

Phase 2B passes only when:

- [ ] Clean install succeeds or blocker documented.
- [ ] Production build succeeds.
- [ ] Intended runtime verified.
- [ ] Critical config validation verified.
- [ ] Missing critical config fails safely where applicable.
- [ ] Feature flag defaults verified where applicable.
- [ ] Material environment parity differences documented.
- [ ] Every FAIL has finding ID.
- [ ] No validation command silently upgraded dependencies or rewrote config.

---

# 57. Finding Register

| Finding ID | Category | Severity | Dependency / Config | Summary | Evidence | Production impact | Launch blocker? | Status |
|---|---|---|---|---|---|---|---|---|
| `DC-001` | `{}` | `{DC0-DC4}` | `{}` | `{}` | `{}` | `{}` | `{YES/NO}` | `OPEN` |

---

# PHASE 3 — REMEDIATION DESIGN

# 58. Mandatory Notice

> ⚠️ **This remediation plan is proposed and not yet implemented.** Dependency upgrades and production configuration changes can introduce regressions and require a separate implementation/release decision. Nothing below should be described as fixed until controlled validation passes.

---

# 59. Objective

Design controlled fixes that improve reproducibility and reduce configuration ambiguity.

Prefer:

- one package manager,
- authoritative lockfile,
- explicit runtime versions,
- validated configuration,
- minimal dependency set,
- centralized config,
- safe feature-flag defaults,
- explicit environment separation.

---

# 60. Root-Cause Map

| Finding | Symptom | Root cause | Confidence | Related findings | Remediation phase |
|---|---|---|---|---|---|
| `DC-001` | `{}` | `{}` | `{}` | `{}` | `R1` |

---

# 61. Remediation Principles

| Principle | Application |
|---|---|
| Reproducible installs | Lock dependencies and tool versions appropriately |
| One source of truth | Avoid duplicated config |
| Fail early | Critical config validated at startup/build |
| Safe defaults | Missing config must not silently create dangerous mode |
| Upgrade intentionally | Do not mass-upgrade during launch prep |
| Remove dead dependencies | Reduce maintenance/supply-chain surface |
| Separate environments | Dev/test/prod behavior explicit |
| Verify exact release | Rebuild/restart after config changes |

---

# 62. Dependency Upgrade Requirements

For each upgrade:

- current version,
- target version,
- reason,
- breaking changes,
- migration guide,
- affected code,
- affected tests,
- rollback,
- compatibility,
- release notes reviewed?,
- security reason if applicable.

Never propose “upgrade everything to latest” as a generic remediation.

---

# 63. Dependency Removal Requirements

Before removing:

- confirm no runtime use,
- confirm no dynamic/plugin usage,
- confirm build/test scripts do not require it,
- rebuild,
- rerun tests.

---

# 64. Config Remediation Requirements

For config change document:

- variable/key,
- old behavior,
- new behavior,
- affected environments,
- deployment action,
- secret-manager change if any,
- rollback,
- startup validation,
- client exposure risk.

---

# 65. Feature Flag Cleanup Requirements

For each stale flag:

- owner,
- final desired state,
- code paths affected,
- data/backward compatibility,
- removal sequence,
- rollback.

---

# 66. Remediation Phase Table

| # | Action | Findings closed | Dependencies/config | Environments affected | Risk | Rollback | Validation |
|---|---|---|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` |

---

# 67. Remediation Exit Gate

Implementation-ready only when:

- [ ] Root cause documented.
- [ ] Upgrade/removal rationale explicit.
- [ ] Compatibility reviewed.
- [ ] Environment impact known.
- [ ] Rollback exists.
- [ ] Build/test validation defined.
- [ ] No broad unnecessary upgrade proposed.
- [ ] Secret/config changes separated from code where appropriate.

---

# FINAL — DEPENDENCIES & CONFIGURATION PRODUCTION READINESS REPORT

# 68. Objective

Produce one release decision for the exact audited dependency/configuration state.

---

# 69. Executive Summary

### System
`{SYSTEM_NAME}`

### Version / Commit
`{VERSION}`

### Runtime(s)
`{RUNTIMES}`

### Package manager(s)
`{PACKAGE_MANAGERS}`

### Production build
`{PASS / FAIL / NOT RUN}`

### Open findings
- DC0: `{COUNT}`
- DC1: `{COUNT}`
- DC2: `{COUNT}`
- DC3: `{COUNT}`

### Critical unknowns
`{COUNT + SUMMARY}`

### Final recommendation
`{🟢 GO / 🟡 CONDITIONAL GO / 🔴 NO-GO}`

---

# 70. Launch Decision Rules

## 🟢 GO

Use **GO** only when:

- Zero open DC0.
- Zero open DC1.
- Clean reproducible install succeeds.
- Production build succeeds.
- Runtime versions are known and compatible.
- Authoritative lockfiles exist where applicable.
- Critical environment variables are known.
- Critical config is validated.
- No production debug/mock/test mode remains.
- Feature flag defaults are safe.
- No critical environment parity mismatch remains.
- No critical phantom/unused/conflicting AI-generated config remains.
- No critical unknown remains.

## 🟡 CONDITIONAL GO

Use only when:

- Zero DC0.
- Zero launch-blocking DC1.
- Build/install/runtime are reproducible.
- Remaining issues are bounded DC2 debt.
- Production config is known.
- Release owner accepts residual risk.
- No critical unknown remains.

## 🔴 NO-GO

Use if:

- Any DC0 remains.
- Production build cannot be reproduced.
- Runtime version is incompatible/unknown.
- Critical config is missing or silently defaults unsafely.
- Production uses test/mock/debug settings.
- Lockfile/package-manager state is materially inconsistent.
- Critical dependency is incompatible with framework/runtime.
- Required env variables exist only locally and not in deployment.
- Client build exposes server-only secret.
- Critical environment parity is too different to trust validation.
- Critical configuration behavior remains unknown.

---

# 71. Launch Gate Table

| Gate | Requirement | Evidence | Status |
|---|---|---|---|
| `LG-DC-01` | Zero open DC0 | `{REGISTER}` | `{PASS/FAIL}` |
| `LG-DC-02` | Zero launch-blocking DC1 | `{REGISTER}` | `{PASS/FAIL}` |
| `LG-DC-03` | Reproducible clean install | `{TEST}` | `{PASS/FAIL}` |
| `LG-DC-04` | Production build passes | `{TEST}` | `{PASS/FAIL}` |
| `LG-DC-05` | Runtime compatibility verified | `{EVIDENCE}` | `{PASS/FAIL}` |
| `LG-DC-06` | Lockfile/package-manager consistent | `{EVIDENCE}` | `{PASS/FAIL}` |
| `LG-DC-07` | Critical config inventoried/validated | `{TESTS}` | `{PASS/FAIL}` |
| `LG-DC-08` | No production debug/mock config | `{EVIDENCE}` | `{PASS/FAIL}` |
| `LG-DC-09` | Feature flag defaults safe | `{TESTS}` | `{PASS/FAIL/N/A}` |
| `LG-DC-10` | Environment parity acceptable | `{MATRIX}` | `{PASS/FAIL}` |
| `LG-DC-11` | No critical AI config/dependency drift | `{EVIDENCE}` | `{PASS/FAIL}` |
| `LG-DC-12` | No critical unknowns | `{OPEN ITEMS}` | `{PASS/FAIL}` |

Any mandatory FAIL prevents GO.

---

# 72. Residual Risk Register

| Risk ID | Finding | Severity | Probability | Production impact | Mitigation | Owner | Required before launch? |
|---|---|---|---|---|---|---|---|
| `RISK-DC-001` | `{REF}` | `{DC}` | `{LOW/MED/HIGH}` | `{}` | `{}` | `{}` | `{YES/NO}` |

---

# 73. Out-of-Scope / Not Verified

Explicitly list:

- production environment variables unavailable,
- deployment platform config unavailable,
- proprietary package registry unavailable,
- certain lockfile ecosystem not analyzed,
- license/legal compatibility not reviewed,
- package vulnerability assessment delegated to Security Audit,
- native build environment unavailable,
- production runtime version not accessible,
- feature flag dashboard unavailable,
- anything intentionally excluded.

Do not convert lack of access into PASS or FAIL.

---

# 74. Final One-Sentence Recommendation

### GO example

> Dependencies & Configuration recommendation: **GO for production** for `{VERSION}` because all mandatory dependency/configuration launch gates passed and the exact release can be reproducibly installed, built, configured, and started without unresolved critical drift.

### CONDITIONAL GO example

> Dependencies & Configuration recommendation: **CONDITIONAL GO** for `{VERSION}`, subject to explicit acceptance of the documented DC2 residual debt; all critical runtime, dependency, build, and configuration guarantees are verified.

### NO-GO example

> Dependencies & Configuration recommendation: **NO-GO** for `{VERSION}` until findings `{DC-xxx...}` are remediated and the associated clean-install, runtime, configuration, and production-build validations pass.

---

# 75. Required Deliverables

A complete Dependencies & Configuration Audit should produce:

1. `01_DEPENDENCIES_CONFIG_DISCOVERY_REPORT.md`
2. `02_DEPENDENCIES_CONFIG_STATIC_VERIFICATION_REPORT.md`
3. `03_DEPENDENCIES_CONFIG_VALIDATION_REPORT.md`
4. `04_DEPENDENCIES_CONFIG_REMEDIATION_PLAN.md`
5. `05_DEPENDENCIES_CONFIG_PRODUCTION_READINESS_REPORT.md`

Optional supporting files:

- `DEPENDENCY_INVENTORY.md`
- `ENVIRONMENT_VARIABLE_INVENTORY.md`
- `FEATURE_FLAG_INVENTORY.md`
- `ENVIRONMENT_PARITY_MATRIX.md`
- `DEPRECATED_UNUSED_DEPENDENCIES.md`
- `DEPENDENCIES_CONFIG_FINDINGS.csv`

---

# 76. Instructions to the AI Auditor

When this template is supplied to an AI coding agent:

1. Read this template completely before starting.
2. Do not upgrade dependencies during Discovery or Verification.
3. Do not rewrite lockfiles.
4. Do not rotate or print secrets.
5. Do not change production configuration.
6. Do not assume `.env.example` matches actual code usage.
7. Do not assume dependency is used because it is declared.
8. Do not assume dependency is unused solely because simple text search finds nothing.
9. Verify dynamic/plugin/framework use where relevant.
10. Do not assume local runtime matches production.
11. Inspect multiple lockfiles/package managers.
12. Inspect phantom environment variables.
13. Inspect hardcoded URLs and localhost references.
14. Inspect debug/mock/test flags.
15. Inspect feature flag defaults.
16. Inspect framework/library version compatibility.
17. Inspect AI-introduced duplicate packages and config names.
18. Do not propose mass upgrades without specific reason.
19. Cite exact manifests/config paths.
20. Preserve stable finding IDs.
21. Cross-reference Security, Code Quality, Performance, API, and Release/Deployment audits where relevant.
22. Revalidate after dependency/config changes before marking findings Verified Closed.
23. End with exactly one recommendation: **GO, CONDITIONAL GO, or NO-GO**.

---

# 77. Completion Standard

This audit is complete only when an independent reviewer could answer:

- Which package managers are used?
- Are installs reproducible?
- Which runtimes are required?
- Which dependencies are production-critical?
- Are any critical dependencies deprecated/incompatible?
- Are duplicate/unused dependencies controlled?
- What configuration sources exist?
- What environment variables are required?
- Which values are build-time vs runtime?
- Are critical values validated?
- Can missing config fail safely?
- Are feature flags controlled?
- Is production free of debug/mock/test configuration?
- Are staging and production sufficiently comparable?
- What validation was actually executed?
- What remains unknown?
- What remediation is proposed versus verified?
- Can this exact version be reproducibly installed, configured, built, and started in production?

If those questions cannot be answered from the audit outputs, the audit is not complete.
