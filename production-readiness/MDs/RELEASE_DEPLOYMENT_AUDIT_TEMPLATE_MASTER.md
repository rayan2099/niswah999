# Release & Deployment Audit — Reusable Master Template

> **Purpose:** A reusable production-readiness audit for verifying that an application can be released, deployed, rolled back, and operated safely and reproducibly in its intended production environment.
>
> This template is designed for applications built manually or with AI coding agents. It is intentionally evidence-driven: **do not mark release readiness PASS because the application deploys once, because CI is green, or because production currently loads. The exact release process, environment configuration, migration sequencing, rollback path, release provenance, and post-deploy verification must be demonstrably controlled.**

---

# 0. Operating Rules

## 0.1 Audit objective

Determine whether the current release/deployment process is production-ready by verifying:

- Production releases are reproducible.
- The exact source commit/version being deployed is identifiable.
- Build artifacts can be traced back to source.
- CI/CD pipelines are defined and understood.
- Required checks run before deployment.
- Environment separation is intentional.
- Production configuration is not mixed with development/staging configuration.
- Build-time and runtime variables are handled correctly.
- Database migrations are sequenced safely with application releases.
- Breaking schema changes have a compatibility plan.
- Feature flags are used safely where needed.
- Deployment can be rolled back.
- Rollback limitations are understood.
- Failed migrations have a recovery plan.
- DNS, TLS/SSL, domains, certificates, CDN, and routing are production-ready where applicable.
- Mobile/app-store release requirements are controlled where applicable.
- Release approvals/ownership are clear.
- Post-deploy smoke checks exist.
- Production health can be verified after release.
- Observability can distinguish releases.
- Release notes/changelog exist at an appropriate level.
- Emergency deployment/hotfix procedures are controlled.
- Manual deployment steps are documented and minimized.
- AI-generated code has not introduced preview URLs, test credentials, temporary deployment steps, divergent build scripts, or undocumented environment dependencies.

## 0.2 Non-goals

This audit does **not** replace:

- Security audit.
- Dependency/configuration audit.
- Backup/recovery audit.
- Database integrity audit.
- Reliability/resilience audit.
- Observability audit.
- Infrastructure penetration testing.
- Formal change-management certification.

Cross-reference those audits where relevant.

---

# 1. Mandatory Methodology

Use these stages in order:

| Stage | Name | What happens | Required output |
|---|---|---|---|
| 1 | **Discovery** | Map release pipeline, environments, artifacts, deployment targets, migrations, approvals, domains, rollback, and post-deploy checks | Release architecture map |
| 2A | **Static Verification** | Inspect CI/CD, deployment config, scripts, environment separation, versioning, migration order, rollback, and release safeguards | Release evidence matrix |
| 2B | **Controlled Deployment Validation** | Execute safe build/deploy/rollback/smoke tests in an approved environment | PASS / FAIL / INCONCLUSIVE matrix |
| 3 | **Remediation Design** | Design release-process fixes — **design only unless separately authorized** | Remediation plan |
| Final | **Production Readiness Report** | Consolidate evidence and issue launch recommendation | GO / CONDITIONAL GO / NO-GO |

### Golden rule

**A successful deployment is not proof of a safe deployment process.**

Always distinguish:

`Source commit → Build inputs → Build artifact → Deployment target → Migration state → Runtime config → Smoke verification → Rollback capability`

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
| CI/CD platform | `{GITHUB ACTIONS / GITLAB / VERCEL / etc.}` |
| Hosting/deployment platform | `{PLATFORM}` |
| Production environment | `{ENV_NAME}` |
| Release type | `{Web / Backend / Mobile / Desktop / Mixed}` |
| Restrictions | `{WHAT_WAS_NOT_DONE}` |
| Report created | `{THIS_FILENAME}` |

---

# 3. Evidence and Confidence Key

| Symbol | Meaning |
|---|---|
| 🟥 **Confirmed by Deployment / Rollback Test** | Proven through controlled release execution |
| 🟧 **Confirmed by Pipeline / Config / Script** | Proven from CI/CD, deployment config, scripts, manifests, or provider config |
| 🟨 **Likely** | Strong inference but runtime release behavior not fully proven |
| 🟦 **Requires Controlled Deployment Test** | Must be tested before conclusion |
| ⬜ **Not Applicable / False Positive** | Does not apply or was disproven |

For every important finding include:

- Finding ID.
- Release stage.
- Environment.
- Script/config/pipeline.
- Expected behavior.
- Actual/configured behavior.
- Evidence.
- Severity.
- Launch-blocker status.
- Confidence.

---

# 4. Severity Model

| Level | Classification | Release/deployment meaning | Launch treatment |
|---|---|---|---|
| **RD0** | Critical | Production release can corrupt data, deploy wrong code/config, become unrecoverable, or cannot be rolled back/recovered from a realistic failure | **Mandatory NO-GO** |
| **RD1** | High | Core release process is materially unreliable, non-reproducible, or depends on undocumented/manual assumptions | **Pre-launch blocker** |
| **RD2** | Medium | Important release-process weakness with bounded impact/workaround | Explicit acceptance required |
| **RD3** | Low | Minor process/documentation inconsistency | Backlog acceptable |
| **RD4** | Observation | Improvement opportunity | Backlog |

## 4.1 Severity factors

Evaluate:

- Blast radius.
- Data impact.
- Ability to detect failure.
- Rollback capability.
- Human error exposure.
- Environment ambiguity.
- Frequency of deployment.
- Complexity of migration.
- Multi-client compatibility.
- Whether production can be restored quickly.
- Whether wrong artifact/config can be deployed silently.

---

# 5. Environment Warning

When validating outside production:

| Dimension | Evaluation |
|---|---|
| Technical severity | Based on release defect itself |
| Current actual impact | Based on test/staging environment |
| Production impact | State realistic release consequence |
| Procedural classification | Unresolved RD0/RD1 findings are **Pre-Launch Blockers** |

Do not deploy to production, modify DNS, rotate production certificates, run destructive migrations, or publish app-store builds without explicit authorization.

---

# PHASE 1 — DISCOVERY

# 6. Objective

Understand exactly how code becomes a production release.

### Mandatory restrictions

During discovery:

- Prefer read-only inspection.
- Do not trigger production deploys.
- Do not rerun migrations.
- Do not alter release branches/tags.
- Do not change environment variables.
- Do not change DNS/certificates.
- Do not publish mobile builds.
- Do not modify CI secrets.

---

# 7. Environment Inventory

Use stable IDs:

- `ENV-DEV`
- `ENV-STG`
- `ENV-PROD`
- etc.

| Environment | Purpose | URL/domain | DB | Integrations | Data type | Deployment method | Owner |
|---|---|---|---|---|---|---|---|
| `{ENV}` | `{}` | `{}` | `{}` | `{}` | `{Synthetic/Real}` | `{}` | `{}` |

Flag:

- shared DB between staging and production,
- test integrations in production,
- production credentials in dev,
- undefined environment ownership.

---

# 8. Release Flow Map

Document full path:

`Developer → Branch → PR → CI → Build → Artifact → Approval → Migration → Deploy → Smoke Test → Monitoring → Rollback`

Identify every manual step.

---

# 9. Branch / Versioning Strategy Inventory

Document:

- main/master,
- develop,
- release branches,
- tags,
- semantic versioning,
- build numbers,
- mobile version code/build number,
- backend version,
- frontend version.

Flag inability to identify deployed source.

---

# 10. Build Artifact Inventory

| Artifact ID | Artifact | Built from | Build command | Stored where | Immutable? | Versioned? |
|---|---|---|---|---|---|---|
| `ART-001` | `{}` | `{COMMIT}` | `{}` | `{}` | `{YES/NO}` | `{YES/NO}` |

Examples:

- Docker image,
- static frontend bundle,
- server package,
- mobile APK/AAB,
- iOS archive,
- desktop installer.

---

# 11. Build Provenance Inventory

Determine whether reviewer can answer:

- Which commit produced this artifact?
- Which dependencies/lockfile were used?
- Which environment/build profile was used?
- Which CI run produced it?
- Which build number/version is inside it?

---

# 12. CI Pipeline Inventory

| Pipeline | Trigger | Stages | Required? | Production capable? | Owner |
|---|---|---|---|---|---|
| `{PIPELINE}` | `{}` | `{lint/test/build/deploy}` | `{YES/NO}` | `{YES/NO}` | `{}` |

---

# 13. Required Pre-Deploy Checks Inventory

Possible checks:

- lint,
- type-check,
- unit tests,
- integration tests,
- security checks,
- migrations validation,
- build,
- dependency audit,
- smoke tests,
- artifact signing.

Document which are mandatory vs advisory.

---

# 14. Deployment Target Inventory

Document:

- cloud provider,
- container runtime,
- serverless platform,
- static host,
- app store,
- CDN,
- edge network,
- managed DB,
- storage.

---

# 15. Deployment Script Inventory

Identify:

- shell scripts,
- make targets,
- Dockerfiles,
- compose files,
- Helm charts,
- Terraform,
- platform config,
- Vercel/Netlify config,
- Firebase config,
- Fastlane,
- Gradle/Xcode build automation.

---

# 16. Environment Variable / Secret Injection Inventory

Map how production values enter release:

- CI secret store,
- deployment platform variables,
- secret manager,
- build-time injection,
- runtime injection.

Never record secret values.

---

# 17. Database Migration Release Inventory

Document:

- when migrations run,
- who runs them,
- automatically/manual,
- before deploy/after deploy,
- transactional behavior,
- zero-downtime assumptions,
- compatibility with old/new app versions.

---

# 18. Release / Migration Sequencing Inventory

For each critical release identify sequence:

1. backup/checkpoint,
2. additive migration,
3. application deploy,
4. backfill,
5. feature flag switch,
6. cleanup migration.

Flag one-step breaking changes.

---

# 19. Feature Flag Release Inventory

Document flags used for:

- staged rollout,
- risky feature enablement,
- emergency disable,
- migration cutover,
- experimentation.

---

# 20. Rollback Inventory

| Component | Rollback method | Time estimate known? | Data rollback required? | Tested? |
|---|---|---|---|---|
| `{Frontend}` | `{}` | `{}` | `{YES/NO}` | `{YES/NO}` |

Include:

- frontend,
- backend,
- DB migration,
- mobile app,
- feature flag,
- config,
- infrastructure.

---

# 21. Domain / DNS Inventory

Where applicable document:

- production domain,
- subdomains,
- DNS provider,
- records,
- TTL,
- CDN/proxy,
- redirect rules,
- www/non-www behavior,
- API domain.

---

# 22. TLS / Certificate Inventory

Document:

- certificate provider,
- auto-renewal,
- expiration,
- custom certificates,
- wildcard certs,
- mobile pinning if applicable,
- staging vs production certificates.

---

# 23. CDN / Cache Release Inventory

Document:

- cache invalidation,
- static asset versioning,
- HTML cache,
- API cache,
- stale content risk,
- rollback cache behavior.

---

# 24. Mobile Release Inventory

Where applicable:

- bundle ID/package name,
- signing keys,
- certificates,
- provisioning profiles,
- version/build number,
- app-store account,
- review requirements,
- phased release,
- minimum supported OS,
- store metadata,
- privacy labels/disclosures,
- deep links/universal links.

---

# 25. Release Approval Inventory

Document:

- who can approve production,
- who can deploy,
- who can rollback,
- separation of duties if required,
- emergency override.

---

# 26. Post-Deploy Verification Inventory

Define required smoke checks:

- homepage/app launch,
- login,
- critical API,
- DB read/write,
- payment sandbox/live status check without real charge where possible,
- queue/worker,
- key integration,
- health/readiness,
- error tracking release tag.

---

# 27. Release Monitoring Inventory

Document post-release monitoring window and signals:

- error rate,
- latency,
- crash rate,
- payment failures,
- queue depth,
- DB health,
- critical business event rate.

Do not invent monitoring duration if owner has not defined it.

---

# 28. Hotfix / Emergency Release Inventory

Document:

- trigger,
- branch strategy,
- approval,
- testing minimum,
- deploy method,
- rollback,
- postmortem requirement if applicable.

---

# 29. Manual Step Inventory

List every manual release action.

| Step | Why manual | Owner | Failure risk | Can automate? |
|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{YES/NO}` |

Manual is not automatically bad; undocumented manual is high risk.

---

# 30. Discovery Execution Log

### Fully reviewed
`{PIPELINES / CONFIG / RELEASE SCRIPTS}`

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

# 31. Discovery Exit Gate

Phase 1 passes only when:

- [ ] Environments mapped.
- [ ] Release flow mapped.
- [ ] Versioning/build provenance understood.
- [ ] CI pipeline identified.
- [ ] Pre-deploy checks identified.
- [ ] Deployment targets/scripts identified.
- [ ] Production config injection understood.
- [ ] Migration sequencing understood.
- [ ] Rollback mapped.
- [ ] DNS/TLS/CDN mapped where applicable.
- [ ] Mobile release process mapped where applicable.
- [ ] Approvals/ownership identified.
- [ ] Post-deploy verification defined.
- [ ] Manual steps listed.
- [ ] Unknown release areas explicitly listed.

---

# PHASE 2A — STATIC VERIFICATION

# 32. Objective

Inspect release/deployment implementation for unsafe or non-reproducible behavior.

Use stable prefixes:

| Prefix | Category |
|---|---|
| `CI-xx` | CI/CD |
| `BUILD-xx` | Build |
| `ART-xx` | Artifact/provenance |
| `ENV-xx` | Environment separation |
| `CFG-xx` | Release config |
| `MIG-xx` | Migration sequencing |
| `FLAG-xx` | Feature flags |
| `ROLL-xx` | Rollback |
| `DNS-xx` | DNS |
| `TLS-xx` | TLS/certificates |
| `CDN-xx` | CDN/cache |
| `MOB-xx` | Mobile release |
| `APPROVE-xx` | Approval |
| `SMOKE-xx` | Post-deploy validation |
| `HOTFIX-xx` | Emergency release |
| `MANUAL-xx` | Manual steps |
| `AI-xx` | AI-agent-specific release defects |

---

# 33. CI Trigger Audit

Verify:

- production deploy trigger explicit,
- accidental branch push cannot deploy unexpectedly,
- PR checks run before merge where intended,
- production/manual approval exists where required.

---

# 34. Build Reproducibility Audit

Verify:

- clean checkout builds,
- lockfile used,
- runtime version defined,
- build command documented,
- no developer-machine dependency,
- deterministic enough for release.

---

# 35. Artifact Provenance Audit

Verify artifact includes/links:

- commit,
- version,
- build number,
- CI run.

Flag manual artifact upload with unknown source.

---

# 36. Environment Separation Audit

Inspect for:

- prod/staging URL confusion,
- shared secrets,
- shared database,
- environment-specific feature flags,
- incorrect build profile,
- test payment mode.

---

# 37. Production Configuration Audit

Verify:

- production variables known,
- required values present,
- no local fallback,
- no preview URL,
- no development flags,
- no sandbox key where live required,
- no live key where sandbox required for staging.

---

# 38. Migration Sequencing Audit

For each release with schema changes verify:

- old app works with new schema during transition where necessary,
- migration timing explicit,
- rollback limitation understood,
- backup/recovery available,
- backfill not assumed instant,
- destructive cleanup delayed until safe.

---

# 39. Zero-Downtime / Compatibility Audit

Where continuous availability matters:

- expand-and-contract pattern,
- backward-compatible API/schema,
- graceful process replacement,
- connection draining,
- worker version compatibility.

Do not require zero downtime where product does not need it; require intentional downtime plan instead.

---

# 40. Rollback Audit

Verify:

- previous artifact available,
- rollback command/process known,
- config rollback known,
- migration rollback/forward-fix known,
- mobile rollback limitations understood.

Flag “rollback” that reverts code but leaves incompatible schema.

---

# 41. Feature Flag Audit

Verify:

- risky functionality can remain off until deployment verified,
- missing flag provider has safe default,
- emergency disable possible where needed,
- stale flags identified.

---

# 42. DNS Audit

Verify:

- intended records,
- canonical domain,
- API domain,
- redirect behavior,
- TTL suitable for planned migration/cutover,
- no stale preview/test records.

---

# 43. TLS Audit

Verify:

- certificate valid,
- correct hostnames,
- auto-renewal configured,
- expiry observable,
- HTTP redirects to HTTPS where intended.

Security details cross-reference Security Audit.

---

# 44. CDN / Cache Audit

Verify:

- hashed/versioned assets,
- cache invalidation strategy,
- HTML/API cache behavior,
- rollback does not serve mismatched assets,
- stale release issue understood.

---

# 45. Mobile Release Audit

Verify:

- correct package/bundle ID,
- production API endpoint,
- production signing identity,
- unique build number,
- version correct,
- environment profile correct,
- store build not using debug mode,
- app links/deep links configured.

---

# 46. Release Approval Audit

Verify:

- production deploy permission controlled,
- accidental self-deploy path understood,
- owner known,
- emergency path documented.

Do not invent governance requirements not needed by project.

---

# 47. Smoke Test Audit

Verify smoke plan covers:

- service start,
- health,
- auth,
- critical read,
- critical write where safe,
- queue/job,
- integration,
- release tag.

---

# 48. Release Monitoring Audit

Verify release can be identified in:

- logs,
- error tracking,
- metrics,
- crash reporting.

Cross-reference Observability Audit.

---

# 49. Hotfix Audit

Verify hotfix process does not bypass all critical controls.

Minimum safe controls should be explicitly defined by owner.

---

# 50. Manual Step Audit

Flag steps that:

- exist only in developer memory,
- require copy/paste secrets,
- require editing production file manually,
- lack verification,
- lack rollback.

---

# 51. AI-Agent-Specific Release & Deployment Audit

Mandatory when AI agents were used.

Actively search for:

## 51.1 Preview/test URL leakage

- Vercel preview domain,
- localhost,
- ngrok,
- temporary backend endpoint,
- dev CDN.

## 51.2 Duplicate deployment config

- multiple Dockerfiles,
- old and new platform configs,
- duplicate CI workflows,
- competing release scripts.

## 51.3 Undocumented manual steps

- agent instructions say “run this once in console,”
- manual DB change not in migration,
- manual provider setup missing from repo docs.

## 51.4 Wrong environment assumptions

- build reads `.env.local` in production,
- staging key hardcoded,
- production branch assumes local config.

## 51.5 Fake green pipeline

- CI checks only build one package,
- failing test ignored,
- `continue-on-error`,
- deploy runs even if validation step fails.

## 51.6 Unsafe migration deployment

- migration auto-runs on startup on every instance,
- destructive migration bundled with app deploy,
- no backup/recovery prerequisite.

## 51.7 Version drift

- frontend, backend, mobile use unrelated versioning,
- deployed artifact cannot be traced to commit.

## 51.8 Temporary bypass

- debug auth,
- mock provider,
- feature force-enabled,
- disabled validation for release.

## 51.9 AI-generated secrets/config references

- variable added to code but not CI/platform,
- production build will fail only after deployment.

---

# 52. Static Verification Matrix

| Check ID | Category | Release stage | Expected condition | Evidence | Result |
|---|---|---|---|---|---|
| `{ID}` | `{}` | `{}` | `{}` | `{}` | `{PASS/FAIL/INCONCLUSIVE}` |

---

# 53. Static Verification Exit Gate

Phase 2A passes only when:

- [ ] CI triggers/checks reviewed.
- [ ] Build reproducibility reviewed.
- [ ] Artifact provenance reviewed.
- [ ] Environment separation reviewed.
- [ ] Production config reviewed.
- [ ] Migration sequencing reviewed.
- [ ] Rollback reviewed.
- [ ] DNS/TLS/CDN reviewed where applicable.
- [ ] Mobile release reviewed where applicable.
- [ ] Smoke/monitoring reviewed.
- [ ] Manual steps reviewed.
- [ ] AI-generated release risks reviewed.
- [ ] RD0/RD1 candidates have evidence.

---

# PHASE 2B — CONTROLLED DEPLOYMENT VALIDATION

# 54. Objective

Prove release mechanics in an approved environment.

### Mandatory restrictions

- Prefer staging/pre-production.
- Do not deploy production unless explicitly authorized.
- Use synthetic data.
- Do not modify production DNS.
- Do not publish store builds.
- Do not run destructive migration against production.
- Record exact commit/version.

---

# 55. Deployment Test Categories

| Prefix | Category |
|---|---|
| `RD-BUILD-xx` | Production build |
| `RD-DEPLOY-xx` | Deployment |
| `RD-MIG-xx` | Migration |
| `RD-SMOKE-xx` | Smoke test |
| `RD-ROLL-xx` | Rollback |
| `RD-CFG-xx` | Configuration |
| `RD-DNS-xx` | DNS |
| `RD-TLS-xx` | TLS |
| `RD-MOB-xx` | Mobile build |
| `RD-HOTFIX-xx` | Hotfix |

---

# 56. Controlled Deployment Matrix

| Test ID | Release scenario | Version | Environment | Expected result | Actual result | Evidence | Result |
|---|---|---|---|---|---|---|---|
| `{ID}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{PASS/FAIL/INCONCLUSIVE}` |

---

# 57. Clean Production Build Test

From clean checkout/environment:

1. use declared runtime/package manager,
2. install reproducibly,
3. inject approved non-secret test config,
4. build production target,
5. record artifact hash/version if practical,
6. verify no debug/test mode.

---

# 58. Staging Deployment Test

Deploy exact build.

Verify:

- expected commit/version,
- expected environment,
- health,
- config,
- routing,
- logs.

---

# 59. Migration Deployment Test

Where release includes migration:

- snapshot/test backup,
- apply migration,
- deploy compatible app version,
- verify reads/writes,
- verify old/new compatibility if required.

---

# 60. Post-Deploy Smoke Test

Execute critical smoke cases.

| Smoke ID | Check | Expected | Actual | Result |
|---|---|---|---|---|
| `SMOKE-001` | `{}` | `{}` | `{}` | `{}` |

---

# 61. Rollback Test

In controlled environment:

1. deploy version A,
2. deploy version B,
3. verify B,
4. rollback to A,
5. verify A,
6. verify DB compatibility,
7. verify config/cache compatibility.

---

# 62. Failed Deployment Test

Where safely simulatable:

- build failure,
- startup failure,
- health check failure.

Verify platform does not route production-like traffic to unhealthy release.

---

# 63. Feature Flag Release Test

Where applicable:

- deploy code with flag off,
- verify old behavior,
- enable in controlled environment,
- verify new behavior,
- disable,
- verify rollback-like behavior.

---

# 64. DNS / TLS Validation

Where non-production equivalent exists:

- resolve domain,
- verify certificate,
- verify redirects,
- verify API routing,
- verify CDN/cache.

Production certificate/domain may require separate read-only verification.

---

# 65. Mobile Production Build Validation

Where applicable:

- build release artifact,
- verify bundle/package ID,
- version/build number,
- signing,
- production endpoint/config,
- release mode.

Do not publish without explicit authorization.

---

# 66. Release Identification Test

Verify deployed version appears in:

- health/build endpoint where appropriate,
- logs,
- error tracking,
- release metadata,
- deployment dashboard.

---

# 67. Controlled Deployment Summary

| Metric | Result |
|---|---|
| Production-mode builds | `{PASS}/{TOTAL}` |
| Deployment tests | `{PASS}/{TOTAL}` |
| Migration tests | `{PASS}/{TOTAL}` |
| Rollback tests | `{PASS}/{TOTAL}` |
| Smoke checks | `{PASS}/{TOTAL}` |
| RD0 findings | `{COUNT}` |
| RD1 findings | `{COUNT}` |
| RD2 findings | `{COUNT}` |

---

# 68. Controlled Deployment Exit Gate

Phase 2B passes only when:

- [ ] Clean production-mode build succeeds.
- [ ] Exact version deploys to approved environment.
- [ ] Critical migrations validated where applicable.
- [ ] Smoke tests pass.
- [ ] Rollback tested where feasible.
- [ ] Release identification verified.
- [ ] Production config model verified.
- [ ] Every FAIL has finding ID.
- [ ] No critical release claim is based only on documentation.

---

# 69. Finding Register

| Finding ID | Category | Severity | Release stage | Summary | Evidence | Rollback impact | Launch blocker? | Status |
|---|---|---|---|---|---|---|---|---|
| `RD-001` | `{}` | `{RD0-RD4}` | `{}` | `{}` | `{}` | `{}` | `{YES/NO}` | `OPEN` |

---

# PHASE 3 — REMEDIATION DESIGN

# 70. Mandatory Notice

> ⚠️ **This remediation plan is proposed and not yet implemented.** Release pipeline, migration, DNS, certificate, and production configuration changes require separate technical approval. Nothing below should be described as release-ready until controlled deployment validation passes.

---

# 71. Objective

Design release-process fixes that reduce deployment ambiguity and recovery risk.

Prefer:

- reproducible builds,
- immutable/versioned artifacts,
- explicit promotion,
- staged migrations,
- safe flags,
- automated checks,
- documented rollback,
- post-deploy verification.

---

# 72. Root-Cause Map

| Finding | Release symptom | Root cause | Confidence | Related findings | Remediation phase |
|---|---|---|---|---|---|
| `RD-001` | `{}` | `{}` | `{}` | `{}` | `R1` |

---

# 73. Remediation Principles

| Principle | Application |
|---|---|
| Build once, identify exactly | Artifact tied to source/version |
| Separate environments | No ambiguous config |
| Fail pipeline on critical checks | Do not ship known failures |
| Migrate compatibly | Expand before destructive contract |
| Roll back intentionally | Code/config/schema considered together |
| Automate repeatable steps | Reduce human error |
| Preserve emergency path | Hotfix without chaos |
| Verify after deploy | Deployment completion ≠ system readiness |
| Observe releases | Every incident traceable to version |

---

# 74. CI/CD Remediation Requirements

For pipeline changes document:

- trigger,
- checks,
- artifact,
- environment,
- approval,
- secrets,
- failure behavior,
- rollback,
- expected duration if relevant.

---

# 75. Migration Release Requirements

For schema-changing release document:

- compatibility plan,
- backup/recovery prerequisite,
- sequence,
- application versions compatible,
- backfill,
- cutover,
- cleanup,
- rollback/forward-fix.

---

# 76. DNS/TLS Change Requirements

For domain/certificate changes:

- current state,
- target state,
- TTL,
- validation,
- rollback,
- propagation expectations,
- certificate ownership/renewal.

---

# 77. Mobile Release Requirements

For production mobile release document:

- version/build number,
- signing identity,
- target environment,
- release notes,
- phased rollout if used,
- rollback/store limitation,
- monitoring after publication.

---

# 78. Remediation Phase Table

| # | Action | Findings closed | Release component | Environments affected | Risk | Rollback | Retest |
|---|---|---|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` |

---

# 79. Remediation Exit Gate

Implementation-ready only when:

- [ ] Root cause documented.
- [ ] Pipeline/config change explicit.
- [ ] Migration impact reviewed.
- [ ] Environment impact known.
- [ ] Rollback defined.
- [ ] Smoke test defined.
- [ ] Observability/release tagging defined.
- [ ] No undocumented manual dependency remains for critical release path.

---

# FINAL — RELEASE & DEPLOYMENT PRODUCTION READINESS REPORT

# 80. Objective

Produce one release decision for the exact audited deployment process and version.

---

# 81. Executive Summary

### System
`{SYSTEM_NAME}`

### Version / Commit
`{VERSION}`

### Target environment
`{PRODUCTION}`

### Production build
`{PASS / FAIL / NOT RUN}`

### Deployment validation
`{PASS}/{EXECUTED}`

### Rollback validation
`{PASS / FAIL / NOT RUN}`

### Open findings
- RD0: `{COUNT}`
- RD1: `{COUNT}`
- RD2: `{COUNT}`
- RD3: `{COUNT}`

### Critical unknowns
`{COUNT + SUMMARY}`

### Final recommendation
`{🟢 GO / 🟡 CONDITIONAL GO / 🔴 NO-GO}`

---

# 82. Launch Decision Rules

## 🟢 GO

Use **GO** only when:

- Zero open RD0.
- Zero open RD1.
- Clean production build succeeds.
- Exact deployed source/version is identifiable.
- Production configuration is known.
- CI/CD required checks pass.
- Migration sequence is safe.
- Critical deployment path is reproducible.
- Rollback/recovery is understood and tested where feasible.
- DNS/TLS are production-ready where applicable.
- Mobile production build is correct where applicable.
- Smoke checks pass.
- Release is observable/version-tagged.
- No critical undocumented manual step remains.
- No critical release unknown remains.

## 🟡 CONDITIONAL GO

Use only when:

- Zero RD0.
- Zero launch-blocking RD1.
- Production build/deploy path is controlled.
- Remaining issues are bounded RD2 process debt.
- Rollback/recovery still safe.
- Release owner accepts residual risk.
- No critical unknown remains.

## 🔴 NO-GO

Use if:

- Any RD0 remains.
- Production build cannot be reproduced.
- Deployed artifact cannot be traced to source.
- Production config is ambiguous or incomplete.
- Critical migration can break active clients/data.
- Rollback is impossible/unknown for a high-risk release.
- Production points to test/preview infrastructure.
- Critical CI failures are ignored.
- DNS/TLS is invalid for required production domain.
- Mobile release build uses wrong environment/signing/package ID.
- Smoke checks fail.
- Critical release behavior remains unknown.

---

# 83. Launch Gate Table

| Gate | Requirement | Evidence | Status |
|---|---|---|---|
| `LG-RD-01` | Zero open RD0 | `{REGISTER}` | `{PASS/FAIL}` |
| `LG-RD-02` | Zero launch-blocking RD1 | `{REGISTER}` | `{PASS/FAIL}` |
| `LG-RD-03` | Reproducible production build | `{TEST}` | `{PASS/FAIL}` |
| `LG-RD-04` | Artifact/source provenance verified | `{EVIDENCE}` | `{PASS/FAIL}` |
| `LG-RD-05` | Production config verified | `{EVIDENCE}` | `{PASS/FAIL}` |
| `LG-RD-06` | CI/CD mandatory checks pass | `{PIPELINE}` | `{PASS/FAIL}` |
| `LG-RD-07` | Migration sequence safe | `{TEST/EVIDENCE}` | `{PASS/FAIL/N/A}` |
| `LG-RD-08` | Rollback path verified | `{TEST}` | `{PASS/FAIL}` |
| `LG-RD-09` | DNS/TLS production-ready | `{EVIDENCE}` | `{PASS/FAIL/N/A}` |
| `LG-RD-10` | Mobile release config correct | `{TEST}` | `{PASS/FAIL/N/A}` |
| `LG-RD-11` | Post-deploy smoke tests pass | `{TESTS}` | `{PASS/FAIL}` |
| `LG-RD-12` | Release version observable | `{EVIDENCE}` | `{PASS/FAIL}` |
| `LG-RD-13` | No critical undocumented manual steps | `{RUNBOOK}` | `{PASS/FAIL}` |
| `LG-RD-14` | No critical unknowns | `{OPEN ITEMS}` | `{PASS/FAIL}` |

Any mandatory FAIL prevents GO.

---

# 84. Release Checklist

Before production release:

- [ ] Exact commit/version approved.
- [ ] Production build generated.
- [ ] Required tests/checks pass.
- [ ] Dependency/config audit gates satisfied.
- [ ] Database migration reviewed.
- [ ] Backup/recovery prerequisite satisfied.
- [ ] Feature flags set intentionally.
- [ ] Production environment variables verified by name/presence.
- [ ] DNS/TLS verified.
- [ ] Rollback artifact/path available.
- [ ] Smoke test owner identified.
- [ ] Monitoring/alerts ready.
- [ ] Release notes/changelog prepared.
- [ ] Release owner identified.
- [ ] Final GO/NO-GO recorded.

---

# 85. Post-Deploy Checklist

Immediately after approved production release:

- [ ] Deployment platform healthy.
- [ ] Correct version visible.
- [ ] Health/readiness passes.
- [ ] Login/auth works.
- [ ] Critical read path works.
- [ ] Critical write path works where safely testable.
- [ ] DB migration state correct.
- [ ] Queue/workers healthy.
- [ ] Critical integration status healthy.
- [ ] Error/crash rate normal.
- [ ] Latency normal.
- [ ] No unexpected alert.
- [ ] Feature flags correct.
- [ ] Smoke test result recorded.
- [ ] Rollback decision threshold monitored.

---

# 86. Residual Risk Register

| Risk ID | Finding | Severity | Probability | Production impact | Mitigation | Owner | Required before launch? |
|---|---|---|---|---|---|---|---|
| `RISK-RD-001` | `{REF}` | `{RD}` | `{LOW/MED/HIGH}` | `{}` | `{}` | `{}` | `{YES/NO}` |

---

# 87. Out-of-Scope / Not Verified

Explicitly list:

- production deploy not executed,
- production DNS write not tested,
- production certificate renewal not tested,
- app-store submission not executed,
- mobile phased rollout not tested,
- infrastructure provisioning excluded,
- production secret values not inspected,
- autoscaling excluded,
- regional failover excluded,
- formal change-management process excluded,
- anything intentionally excluded.

Do not convert lack of access into PASS or FAIL.

---

# 88. Final One-Sentence Recommendation

### GO example

> Release & Deployment recommendation: **GO for production** for `{VERSION}` because all mandatory release gates passed and the exact release can be reproducibly built, deployed, verified, observed, and safely rolled back or recovered if necessary.

### CONDITIONAL GO example

> Release & Deployment recommendation: **CONDITIONAL GO** for `{VERSION}`, subject to explicit acceptance of the documented RD2 residual process risks; the critical production release and recovery path remains controlled.

### NO-GO example

> Release & Deployment recommendation: **NO-GO** for `{VERSION}` until findings `{RD-xxx...}` are remediated and the associated build, migration, deployment, smoke-test, provenance, and rollback validations pass.

---

# 89. Required Deliverables

A complete Release & Deployment Audit should produce:

1. `01_RELEASE_DEPLOYMENT_DISCOVERY_REPORT.md`
2. `02_RELEASE_DEPLOYMENT_STATIC_VERIFICATION_REPORT.md`
3. `03_RELEASE_DEPLOYMENT_VALIDATION_REPORT.md`
4. `04_RELEASE_DEPLOYMENT_REMEDIATION_PLAN.md`
5. `05_RELEASE_DEPLOYMENT_PRODUCTION_READINESS_REPORT.md`

Optional supporting files:

- `RELEASE_FLOW_MAP.md`
- `ENVIRONMENT_MATRIX.md`
- `BUILD_ARTIFACT_INVENTORY.md`
- `MIGRATION_RELEASE_SEQUENCE.md`
- `ROLLBACK_RUNBOOK.md`
- `POST_DEPLOY_SMOKE_TEST.md`
- `RELEASE_DEPLOYMENT_FINDINGS.csv`

---

# 90. Instructions to the AI Auditor

When this template is supplied to an AI coding agent:

1. Read this template completely before starting.
2. Do not deploy to production without explicit authorization.
3. Do not publish mobile builds.
4. Do not modify DNS/certificates.
5. Do not alter CI/CD secrets.
6. Do not assume a green CI pipeline covers all critical checks.
7. Do not assume current production state proves reproducibility.
8. Verify exact source-to-artifact provenance.
9. Inspect environment separation.
10. Inspect build-time/runtime config.
11. Inspect migration sequencing.
12. Inspect rollback limitations.
13. Inspect preview/test URLs.
14. Inspect multiple/duplicate deployment configs.
15. Inspect ignored CI failures.
16. Inspect manual one-off deployment steps.
17. Inspect production debug/mock settings.
18. Inspect mobile environment/signing/package configuration where applicable.
19. Cite exact workflow/config/script paths.
20. Preserve stable finding IDs.
21. Cross-reference Dependencies/Config, Database Integrity, Backup/Recovery, Reliability, Observability, and Security audits where relevant.
22. Retest deployment/rollback before marking findings Verified Closed.
23. End with exactly one recommendation: **GO, CONDITIONAL GO, or NO-GO**.

---

# 91. Completion Standard

This audit is complete only when an independent reviewer could answer:

- What environments exist?
- How does code become a production release?
- Which commit/version produced the release?
- Are builds reproducible?
- What checks are mandatory before deployment?
- How is production configuration injected?
- How are migrations sequenced?
- Can the system run through old/new schema compatibility where required?
- How is rollback performed?
- What rollback limitations exist?
- Are DNS/TLS production-ready?
- Is the mobile release configuration correct where applicable?
- What smoke tests are required?
- Can the release be identified in monitoring?
- Which steps remain manual?
- What deployment tests were actually executed?
- What remains unknown?
- What remediation is proposed versus verified?
- Can this exact version be safely built, deployed, verified, and recovered in production?

If those questions cannot be answered from the audit outputs, the audit is not complete.
