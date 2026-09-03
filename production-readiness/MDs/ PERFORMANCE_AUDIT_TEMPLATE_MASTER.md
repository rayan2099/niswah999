# Performance Audit — Reusable Master Template

> **Purpose:** A reusable production-readiness audit for determining whether an application's frontend, backend, database, and integrations are fast enough, efficient enough, and scalable enough for launch.
>
> This template is designed for applications built manually or with AI coding agents. It is intentionally evidence-driven: **do not mark performance PASS because the app "feels fast" on one machine or because a local build loads quickly. Critical performance claims must be backed by measurements, reproducible test conditions, and clearly defined thresholds.**

---

# 0. Operating Rules

## 0.1 Audit objective

Determine whether the current application is performance-ready for production by verifying:

- Critical user journeys meet defined latency and responsiveness targets.
- Backend endpoints respond within acceptable service-level targets.
- Database queries are efficient and do not create avoidable load.
- No critical N+1 query behavior exists.
- Frontend/network payloads are appropriately sized.
- Bundle size and startup cost are controlled.
- Rendering/re-rendering behavior is reasonable.
- Memory use is stable.
- Long-running sessions do not leak resources.
- Caching is intentional and correct.
- External API latency is bounded.
- Timeouts and slow-dependency behavior are handled safely.
- Background jobs do not create hidden bottlenecks.
- Pagination and batch sizing prevent uncontrolled data loads.
- The application remains usable under realistic concurrency.
- The system has enough headroom for expected launch traffic.
- Performance bottlenecks are observable and measurable.
- AI-generated code has not introduced duplicate requests, unnecessary recomputation, inefficient polling, large unbounded loops, or hidden hot paths.

## 0.2 Non-goals

This audit does **not** replace:

- Security testing.
- Functional QA.
- Code quality audit.
- Database integrity audit.
- API/backend correctness audit.
- Reliability/resilience testing.
- Full infrastructure capacity planning.
- Formal stress testing at destructive scale.

If one of those areas creates a performance blocker, record and cross-reference it.

---

# 1. Mandatory Methodology

Use these stages in order:

| Stage | Name | What happens | Required output |
|---|---|---|---|
| 1 | **Discovery** | Understand architecture, hot paths, critical journeys, expected traffic, dependencies, queries, assets, and execution model | Performance map |
| 2A | **Static Verification** | Inspect code/config for likely bottlenecks and anti-patterns | Static performance findings |
| 2B | **Controlled Measurement** | Execute repeatable performance tests in an approved environment | Measurement matrix |
| 3 | **Remediation Design** | Design fixes for confirmed bottlenecks — **design only unless separately authorized** | Remediation plan |
| Final | **Production Readiness Report** | Consolidate evidence and issue launch recommendation | GO / CONDITIONAL GO / NO-GO |

### Golden rule

**Never use subjective speed as evidence.**

Every material performance conclusion must state:

- what was measured,
- under what conditions,
- on what environment/device,
- with what dataset/load,
- and against what target.

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
| Environment | `{Local / Dev / Staging / Production}` |
| Test device / machine | `{DEVICE_OR_MACHINE}` |
| Network profile | `{LAN / Wi-Fi / 4G / throttled / etc.}` |
| Dataset size | `{SIZE}` |
| Concurrent users / workers | `{LOAD}` |
| Restrictions | `{WHAT_WAS_NOT_DONE}` |
| Report created | `{THIS_FILENAME}` |

---

# 3. Evidence and Confidence Key

| Symbol | Meaning |
|---|---|
| 🟥 **Confirmed by Measurement** | Proven by repeatable timing/load/resource measurement |
| 🟧 **Confirmed by Code/Config** | Proven through static implementation/config evidence |
| 🟨 **Likely** | Strong performance inference, direct measurement incomplete |
| 🟦 **Requires Controlled Measurement** | Must be measured before conclusion |
| ⬜ **Not Applicable / False Positive** | Does not apply or was disproven |

For every meaningful finding, include:

- Finding ID.
- Component/journey/endpoint/query.
- Metric.
- Test condition.
- Actual result.
- Target/expectation.
- Evidence.
- Severity.
- Launch-blocker status.
- Confidence.

---

# 4. Severity Model

| Level | Classification | Performance meaning | Launch treatment |
|---|---|---|---|
| **PF0** | Critical | Core system becomes unusable, times out, crashes, exhausts resources, or collapses under realistic launch load | **Mandatory NO-GO** |
| **PF1** | High | Core journey materially too slow or critical backend/database path scales poorly | **Pre-launch blocker** |
| **PF2** | Medium | Noticeable performance issue with bounded impact and acceptable workaround | Explicit acceptance required |
| **PF3** | Low | Minor inefficiency or localized responsiveness issue | Backlog acceptable |
| **PF4** | Observation | Optimization opportunity | Backlog |

## 4.1 Severity factors

Evaluate:

- User-facing delay.
- Frequency.
- Criticality of affected journey.
- Percentile affected.
- Load sensitivity.
- Resource consumption.
- Failure threshold.
- Dataset growth sensitivity.
- Device/network sensitivity.
- Third-party dependency impact.
- Operational cost impact.
- Recoverability.
- Whether issue worsens nonlinearly.

---

# 5. Environment Warning

When testing outside production:

| Dimension | Evaluation |
|---|---|
| Technical severity | Based on observed bottleneck |
| Current actual impact | Based on current environment/load |
| Production impact | State likely behavior under real traffic/data volume |
| Procedural classification | Unresolved PF0/PF1 issues are **Pre-Launch Blockers** |

Do not extrapolate exact production capacity from local measurements unless environment differences are explicitly modeled.

---

# PHASE 1 — DISCOVERY

# 6. Objective

Identify likely hot paths before measuring.

### Mandatory restrictions

During discovery:

- Prefer read-only inspection.
- Do not run destructive load tests.
- Do not saturate production.
- Do not enable debug profilers in production without approval.
- Do not change caching/config.
- Do not optimize while auditing.
- Do not add indexes automatically.
- Do not change query behavior.

---

# 7. Critical Journey Performance Map

Define the journeys whose speed materially affects product value.

Use:

- `PJ-001`, `PJ-002`, ...

| Journey ID | Journey | Role | Start | End | User expectation | Criticality |
|---|---|---|---|---|---|---|
| `PJ-001` | `{JOURNEY}` | `{ROLE}` | `{START}` | `{END}` | `{TARGET}` | `{Critical/High/Normal}` |

Examples:

- App launch.
- Login.
- Feed load.
- Search.
- Checkout.
- Booking.
- Order creation.
- Dashboard.
- File upload.
- Report generation.
- Admin table load.
- Realtime update.

---

# 8. Performance Budget Definition

Define budgets before measurement.

Possible metrics:

- Initial load.
- Time to interactive.
- Largest Contentful Paint.
- Interaction delay.
- API p50/p95/p99.
- Query duration.
- Job duration.
- Memory.
- Bundle size.
- Payload size.
- CPU.
- Requests per journey.
- Database calls per request.

| Metric | Target | Hard limit | Scope | Rationale |
|---|---:|---:|---|---|
| `{METRIC}` | `{TARGET}` | `{LIMIT}` | `{JOURNEY/API}` | `{RATIONALE}` |

Do not invent arbitrary targets when product expectations are unknown. If no target exists, mark **TARGET REQUIRED** and use industry/general benchmarks only as external reference, not authoritative product requirements.

---

# 9. Traffic / Usage Model

Document expected launch assumptions:

- Daily active users.
- Peak concurrent users.
- Requests per second.
- Orders/bookings per minute.
- Background jobs.
- File uploads.
- Realtime connections.
- Dataset size.
- Growth projection.

| Workload | Expected normal | Expected peak | Unknown? |
|---|---:|---:|---|
| `{WORKLOAD}` | `{}` | `{}` | `{YES/NO}` |

Unknown traffic assumptions must be called out.

---

# 10. Frontend Performance Inventory

Document:

- Framework.
- Rendering model.
- Routing.
- State management.
- Code splitting.
- Lazy loading.
- Images.
- Fonts.
- Third-party scripts.
- Analytics.
- Large dependencies.
- Hydration/SSR if applicable.
- Mobile app startup.
- Local persistence.
- Offline cache.

---

# 11. Backend Performance Inventory

Document:

- Runtime.
- Server architecture.
- Worker model.
- Concurrency model.
- Connection pools.
- Thread/process pools.
- Background queues.
- External API calls.
- Caching.
- Serialization.
- File processing.

---

# 12. Database Performance Inventory

Document:

- Database engine.
- Main high-volume tables/collections.
- Largest tables.
- Key query patterns.
- Indexes.
- joins.
- aggregations.
- search.
- pagination.
- count queries.
- transaction-heavy paths.

---

# 13. External Dependency Latency Map

| Integration | Used by | Typical latency known? | Timeout | Retry | Critical path? |
|---|---|---|---|---|---|
| `{SERVICE}` | `{JOURNEY}` | `{}` | `{}` | `{}` | `{YES/NO}` |

---

# 14. Asset / Payload Inventory

Inspect:

- JS bundles.
- CSS.
- images.
- fonts.
- video.
- JSON payloads.
- API responses.
- GraphQL responses.
- downloadable files.

Flag:

- oversized images.
- uncompressed assets.
- duplicate fonts.
- huge API payloads.
- entire objects returned when only few fields used.

---

# 15. Existing Performance Tooling

Document:

- browser profiler.
- Lighthouse.
- framework profiler.
- APM.
- tracing.
- database slow-query log.
- query analyzer.
- load-test scripts.
- benchmark tests.
- synthetic monitoring.

---

# 16. Discovery Execution Log

### Fully reviewed
`{AREAS}`

### Partially reviewed
`{AREAS}`

### Structurally scanned only
`{AREAS}`

### Could not inspect
`{AREAS + REASON}`

### Commands/actions performed
| Action | Purpose | Result |
|---|---|---|

### Actions deliberately avoided
| Action avoided | Reason |
|---|---|

---

# 17. Discovery Exit Gate

Phase 1 passes only when:

- [ ] Critical performance journeys identified.
- [ ] Performance targets/budgets defined or gaps documented.
- [ ] Expected workload modeled.
- [ ] Frontend architecture mapped.
- [ ] Backend architecture mapped.
- [ ] Database hot paths identified.
- [ ] External dependencies identified.
- [ ] Major asset/payload sources identified.
- [ ] Measurement tooling identified.
- [ ] Unknown areas documented.

---

# PHASE 2A — STATIC VERIFICATION

# 18. Objective

Inspect implementation for likely performance bottlenecks.

Use stable prefixes:

| Prefix | Category |
|---|---|
| `FE-xx` | Frontend |
| `NET-xx` | Network |
| `BUNDLE-xx` | Bundle/assets |
| `RENDER-xx` | Rendering |
| `STATE-xx` | State management |
| `BE-xx` | Backend |
| `DBQ-xx` | Database query |
| `N1-xx` | N+1 query |
| `CACHE-xx` | Caching |
| `POOL-xx` | Connection/thread pools |
| `EXT-xx` | External dependencies |
| `JOB-xx` | Background jobs |
| `MEM-xx` | Memory |
| `CPU-xx` | CPU |
| `LOOP-xx` | Inefficient loops |
| `PAG-xx` | Pagination |
| `SER-xx` | Serialization |
| `LOAD-xx` | Load/scalability |
| `AI-xx` | AI-agent-specific performance defects |

---

# 19. Frontend Request Audit

Inspect:

- duplicate API calls.
- calls on every render.
- calls on every keystroke.
- unbounded polling.
- waterfall requests.
- serial requests that could be parallel.
- prefetch abuse.
- repeated identical fetches.
- missing request cancellation.
- hidden background refresh loops.

---

# 20. Rendering Audit

Inspect:

- unnecessary re-renders.
- state updates high in tree.
- large lists without virtualization.
- expensive derived computation.
- expensive formatting inside render.
- repeated selectors.
- unstable keys.
- excessive context/global state updates.
- layout thrashing.
- synchronous blocking work.

---

# 21. Bundle / Dependency Audit

Inspect:

- large libraries imported for small feature.
- duplicate dependencies.
- entire icon/library imports.
- unused code in bundle.
- no code splitting.
- large polyfills.
- large locale bundles.
- debug/dev libraries shipped to production.

---

# 22. Image / Media Audit

Inspect:

- image dimensions vs display size.
- compression.
- responsive variants.
- lazy loading.
- placeholders.
- preloading abuse.
- video preload.
- format.
- CDN use where applicable.

---

# 23. API Payload Audit

Inspect:

- over-fetching.
- nested huge objects.
- repeated metadata.
- unused response fields.
- unbounded arrays.
- server returning all records.
- base64 content embedded in JSON.
- excessive precision/verbosity.

---

# 24. Backend Hot-Path Audit

Inspect:

- expensive work inside request.
- repeated service calls.
- synchronous file processing.
- large loops.
- repeated serialization.
- blocking CPU work.
- duplicate DB lookups.
- missing batching.
- external calls performed serially.

---

# 25. N+1 Query Audit

Actively search for:

- query inside loop.
- ORM lazy loading in list endpoints.
- per-item relationship fetch.
- per-item permission lookup.
- per-item count query.

| Finding | Endpoint | Parent query | Child queries | Estimated amplification | Severity |
|---|---|---|---|---|---|
| `{ID}` | `{}` | `{}` | `{}` | `{}` | `{PF}` |

---

# 26. Database Query Audit

Inspect:

- full-table scans.
- missing filters.
- unbounded `SELECT *`.
- expensive joins.
- repeated count.
- sorting unindexed field.
- wildcard search.
- huge `IN`.
- unnecessary nested subqueries.
- query in transaction longer than needed.
- large offset pagination.

---

# 27. Pagination Audit

Verify:

- all large collections paginated.
- page size bounded.
- cursor preferred where large offset cost matters.
- count not recalculated expensively on every request.
- stable order.

---

# 28. Caching Audit

Inspect:

- what is cached.
- key granularity.
- TTL.
- invalidation.
- stale tolerance.
- duplicate caches.
- cache penetration.
- cache stampede.
- per-user vs shared cache.
- large cached objects.

Do not confuse cache correctness with performance gain.

---

# 29. Connection / Pool Audit

Inspect where applicable:

- DB connection pool size.
- HTTP connection reuse.
- worker concurrency.
- thread/process pool.
- queue worker count.
- exhausted pool behavior.

Flag:
- new DB connection per request.
- no connection reuse.
- unbounded workers.

---

# 30. External API Performance Audit

Inspect:

- calls on critical path.
- sequential dependency chains.
- timeout.
- retry.
- caching.
- batching.
- fallback.
- response size.

---

# 31. Background Job Performance Audit

Inspect:

- long-running jobs.
- giant batches.
- no chunking.
- no backpressure.
- retry storms.
- duplicate jobs.
- one slow job blocking queue.
- synchronous work that should be background.
- background work that must actually be synchronous for correctness.

---

# 32. Memory Audit

Inspect likely leak patterns:

- unremoved listeners.
- subscriptions not closed.
- timers not cleared.
- growing in-memory cache.
- unbounded arrays/maps.
- retained references.
- large file buffering.
- reading entire large file into memory.
- image/video processing buffers.

---

# 33. CPU Audit

Inspect:

- expensive loops.
- nested loops on large collections.
- repeated parsing.
- repeated encryption/compression.
- large synchronous JSON transformations.
- image processing.
- regex on huge inputs.
- unnecessary recomputation.

---

# 34. AI-Agent-Specific Performance Audit

Mandatory when AI agents were used.

Actively search for:

## 34.1 Duplicate fetches

- same API called in parent and child.
- useEffect/watchers duplicate calls.
- fetch on mount + fetch on focus + polling unintentionally overlapping.

## 34.2 Over-fetching

- API returns full objects by default.
- all relationships loaded.
- all rows loaded because pagination was omitted.
- admin endpoint reused for lightweight mobile screen.

## 34.3 N+1 from generated ORM code

- agent loops through entities and queries relationships individually.

## 34.4 Patch-based performance degradation

- additional API call added to "fix" missing data.
- additional query added instead of changing original query.
- repeated fallback calls.
- multiple caches layered.

## 34.5 Re-render storms

- agent puts large object in global state.
- unstable object/function props.
- state set inside render lifecycle incorrectly.

## 34.6 Unbounded polling

- short-interval timers.
- retry loops.
- websocket fallback + polling both active.

## 34.7 Inefficient parsing/transforms

- map/filter/reduce chains repeatedly executed on same dataset.
- large data sorting on every render.
- JSON stringify/parse used for deep clone in hot path.

## 34.8 Accidental debug cost

- verbose logs.
- expensive dev checks in production.
- large analytics payloads.

---

# 35. Static Verification Matrix

| Check ID | Category | Scope | Expected condition | Evidence | Result |
|---|---|---|---|---|---|
| `{ID}` | `{}` | `{}` | `{}` | `{}` | `{PASS/FAIL/INCONCLUSIVE}` |

---

# 36. Static Verification Exit Gate

Phase 2A passes only when:

- [ ] Critical frontend paths inspected.
- [ ] Backend hot paths inspected.
- [ ] Query patterns reviewed.
- [ ] N+1 risks reviewed.
- [ ] Payload/bundle issues reviewed.
- [ ] Caching reviewed.
- [ ] External dependency latency design reviewed.
- [ ] Background jobs reviewed.
- [ ] Memory/CPU risks reviewed.
- [ ] AI-specific performance risks reviewed.
- [ ] PF0/PF1 candidates have evidence.

---

# PHASE 2B — CONTROLLED MEASUREMENT

# 37. Objective

Measure real performance under controlled and repeatable conditions.

### Mandatory restrictions

- Prefer staging or performance-test environment.
- Do not saturate production.
- Use synthetic accounts/data.
- Record environment specs.
- Record dataset size.
- Record network profile.
- Repeat tests.
- Prefer percentile metrics over averages.

---

# 38. Measurement Principles

For each test record:

- warm/cold state.
- cache state.
- device.
- browser/app version.
- network.
- dataset size.
- concurrent load.
- repetition count.
- p50/p95/p99 where applicable.

Do not report one timing as a representative result.

---

# 39. Frontend Measurement Matrix

| Test ID | Journey | Device | Network | Cold/Warm | Metric | Target | Actual | Result |
|---|---|---|---|---|---|---:|---:|---|
| `PERF-FE-001` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{PASS/FAIL}` |

Possible metrics:

- First Contentful Paint.
- Largest Contentful Paint.
- Time to interactive.
- Interaction latency.
- Screen transition time.
- App startup.
- API-to-render time.

---

# 40. Backend Endpoint Measurement

| Test ID | Endpoint | Load | Dataset | Metric | Target | p50 | p95 | p99 | Result |
|---|---|---:|---:|---|---:|---:|---:|---:|---|
| `PERF-API-001` | `{}` | `{}` | `{}` | `Latency` | `{}` | `{}` | `{}` | `{}` | `{}` |

Also record:

- error rate.
- throughput.
- timeout rate.
- resource use.

---

# 41. Database Query Measurement

For critical queries:

| Query ID | Operation | Rows/data size | Execution time | Plan quality | Index used? | Result |
|---|---|---:|---:|---|---|---|
| `PERF-DB-001` | `{}` | `{}` | `{}` | `{}` | `{YES/NO}` | `{}` |

Where supported, inspect query plan safely.

---

# 42. N+1 Runtime Verification

Measure query count for a list size of:

- 1
- 10
- 50
- 100

If query count grows linearly per item unexpectedly, record finding.

---

# 43. Load Test Matrix

Use non-destructive realistic load.

| Test ID | Scenario | Users/RPS | Duration | p95 | Error rate | Resource use | Result |
|---|---|---:|---:|---:|---:|---|---|
| `PERF-LOAD-001` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` |

---

# 44. Scalability Curve

Measure increasing load:

- low.
- normal.
- peak.
- peak + headroom.

Record where latency/error/resource behavior changes materially.

Do not push to destructive failure unless explicitly authorized.

---

# 45. Memory Stability Test

For long-running apps/services:

- establish baseline.
- execute repeated workflow.
- monitor memory.
- idle.
- repeat.

Flag monotonic growth without release.

---

# 46. Background Job Measurement

Record:

- queue wait.
- execution duration.
- throughput.
- retries.
- backlog growth.
- worker utilization.

---

# 47. External Dependency Measurement

Where safe:

- latency distribution.
- timeout rate.
- contribution to total critical-path latency.
- fallback/retry impact.

---

# 48. Cache Measurement

Compare:

- cold cache.
- warm cache.
- hit rate.
- miss penalty.
- stale invalidation behavior.

---

# 49. Controlled Measurement Summary

| Metric | Result |
|---|---|
| Critical journeys within target | `{PASS}/{TOTAL}` |
| Critical endpoints within target | `{PASS}/{TOTAL}` |
| PF0 findings | `{COUNT}` |
| PF1 findings | `{COUNT}` |
| PF2 findings | `{COUNT}` |
| Peak tested load | `{LOAD}` |
| Error rate at peak | `{}` |
| Critical unknowns | `{COUNT}` |

---

# 50. Controlled Measurement Exit Gate

Phase 2B passes only when:

- [ ] Critical journeys measured.
- [ ] Critical endpoints measured.
- [ ] Critical queries measured.
- [ ] Peak/expected load tested where applicable.
- [ ] N+1 runtime behavior checked where relevant.
- [ ] Memory stability checked where relevant.
- [ ] External dependency impact measured where relevant.
- [ ] Environment/test conditions documented.
- [ ] Every FAIL has finding ID.
- [ ] No critical result is based on a single unrepeatable measurement.

---

# 51. Finding Register

| Finding ID | Category | Severity | Component | Metric | Target | Actual | Evidence | Launch blocker? | Status |
|---|---|---|---|---|---|---|---|---|---|
| `PF-001` | `{}` | `{PF0-PF4}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{YES/NO}` | `OPEN` |

---

# PHASE 3 — REMEDIATION DESIGN

# 52. Mandatory Notice

> ⚠️ **This remediation plan is proposed and not yet implemented.** It requires technical review and a separate implementation decision. Nothing below should be described as fixed until changes are deployed to an approved environment and measurements are rerun.

---

# 53. Objective

Design fixes around measured bottlenecks, not generic optimization.

Prioritize:

- user-impacting hot paths.
- bottlenecks with high load sensitivity.
- database inefficiencies.
- excessive network requests.
- oversized payloads.
- blocking synchronous work.
- memory leaks.
- repeated computation.

---

# 54. Root-Cause Map

| Finding | Symptom | Root cause | Confidence | Related findings | Remediation phase |
|---|---|---|---|---|---|
| `PF-001` | `{}` | `{}` | `{}` | `{}` | `R1` |

---

# 55. Remediation Principles

| Principle | Application |
|---|---|
| Measure before optimize | Fix confirmed bottlenecks first |
| Optimize critical paths | Do not spend launch effort on irrelevant micro-optimizations |
| Remove duplicate work | Queries, fetches, renders, computations |
| Bound all large operations | Pagination, batches, payloads |
| Cache intentionally | Only where correctness permits |
| Move heavy work appropriately | Background vs synchronous based on user need |
| Protect the database | Efficient queries and connection use |
| Preserve behavior | Performance fixes require regression tests |
| Remeasure after changes | No optimization is considered successful without evidence |

---

# 56. Remediation Phase Table

| # | Action | Findings closed | Component | Expected metric improvement | Risk | Functional impact | Rollback | Remeasure |
|---|---|---|---|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` |

---

# 57. Database Optimization Safety

Before adding/changing indexes or queries:

- [ ] Query is measured.
- [ ] Query plan inspected where supported.
- [ ] Write overhead considered.
- [ ] Index size considered.
- [ ] Migration/locking impact considered.
- [ ] Duplicate/redundant index checked.
- [ ] Production rollout plan defined.

---

# 58. Frontend Optimization Safety

Before memoization/caching/lazy loading:

- [ ] Bottleneck measured.
- [ ] Correctness impact understood.
- [ ] Stale state risk understood.
- [ ] Loading UX considered.
- [ ] Mobile/browser support considered.
- [ ] Regression test defined.

---

# 59. Remediation Exit Gate

Implementation-ready only when:

- [ ] Root cause is measured or strongly evidenced.
- [ ] Expected improvement is explicit.
- [ ] Functional/data correctness impact reviewed.
- [ ] Rollback exists where needed.
- [ ] Remeasurement plan defined.
- [ ] No premature broad rewrite proposed.

---

# FINAL — PERFORMANCE PRODUCTION READINESS REPORT

# 60. Objective

Produce one release decision for the exact audited version/environment.

---

# 61. Executive Summary

### System
`{SYSTEM_NAME}`

### Version / Commit
`{VERSION}`

### Environment
`{ENVIRONMENT}`

### Critical journey performance
`{PASS}/{TOTAL}`

### Critical endpoint performance
`{PASS}/{TOTAL}`

### Peak tested load
`{LOAD}`

### Open findings
- PF0: `{COUNT}`
- PF1: `{COUNT}`
- PF2: `{COUNT}`
- PF3: `{COUNT}`

### Critical unknowns
`{COUNT + SUMMARY}`

### Final recommendation
`{🟢 GO / 🟡 CONDITIONAL GO / 🔴 NO-GO}`

---

# 62. Launch Decision Rules

## 🟢 GO

Use **GO** only when:

- Zero open PF0.
- Zero open PF1.
- Critical journeys meet agreed targets.
- Critical endpoints meet agreed targets.
- Critical queries are bounded and efficient enough.
- No critical N+1 behavior remains.
- Expected peak load is handled with acceptable latency/error rate.
- No critical memory leak is known.
- No unbounded critical data loading remains.
- External dependency latency is bounded.
- No critical performance unknown remains.

## 🟡 CONDITIONAL GO

Use only when:

- Zero PF0.
- Zero launch-blocking PF1.
- Core journeys remain acceptably responsive.
- Remaining issues are bounded and non-critical.
- Capacity margin is sufficient for expected launch.
- Release owner accepts residual PF2 risk.

## 🔴 NO-GO

Use if:

- Any PF0 remains.
- Core journey is unusably slow.
- Critical endpoint consistently exceeds hard limit.
- System fails under realistic expected load.
- Critical query/load grows uncontrollably.
- Critical N+1 causes material degradation.
- Memory/resource exhaustion likely.
- Critical external dependency causes uncontrolled blocking.
- Performance cannot be meaningfully evaluated due missing targets/test environment.

---

# 63. Launch Gate Table

| Gate | Requirement | Evidence | Status |
|---|---|---|---|
| `LG-PF-01` | Zero open PF0 | `{REGISTER}` | `{PASS/FAIL}` |
| `LG-PF-02` | Zero launch-blocking PF1 | `{REGISTER}` | `{PASS/FAIL}` |
| `LG-PF-03` | Critical journeys within target | `{TESTS}` | `{PASS/FAIL}` |
| `LG-PF-04` | Critical endpoints within target | `{TESTS}` | `{PASS/FAIL}` |
| `LG-PF-05` | Critical queries efficient/bounded | `{TESTS}` | `{PASS/FAIL}` |
| `LG-PF-06` | No critical N+1 | `{TESTS}` | `{PASS/FAIL}` |
| `LG-PF-07` | Peak load acceptable | `{LOAD TEST}` | `{PASS/FAIL}` |
| `LG-PF-08` | Memory stable | `{TEST}` | `{PASS/FAIL}` |
| `LG-PF-09` | Payload/bundle bounded | `{EVIDENCE}` | `{PASS/FAIL}` |
| `LG-PF-10` | External latency bounded | `{TESTS}` | `{PASS/FAIL}` |
| `LG-PF-11` | No critical unknowns | `{OPEN ITEMS}` | `{PASS/FAIL}` |

Any mandatory FAIL prevents GO.

---

# 64. Residual Risk Register

| Risk ID | Finding | Severity | Probability | Production impact | Mitigation | Owner | Required before launch? |
|---|---|---|---|---|---|---|---|
| `RISK-PF-001` | `{REF}` | `{PF}` | `{LOW/MED/HIGH}` | `{}` | `{}` | `{}` | `{YES/NO}` |

---

# 65. Out-of-Scope / Not Verified

Explicitly list:

- Production infrastructure not load-tested.
- CDN not tested.
- Mobile devices not tested.
- Slow network not tested.
- Large production dataset unavailable.
- Certain external providers unavailable.
- Long-running soak test not executed.
- Autoscaling not assessed.
- Cost scaling not assessed.
- Database replica behavior not assessed.
- Anything intentionally excluded.

Do not convert lack of access into PASS or FAIL.

---

# 66. Final One-Sentence Recommendation

### GO example

> Performance recommendation: **GO for production** for `{VERSION}` because all mandatory performance launch gates passed and the system met defined critical-journey, endpoint, database, and expected-load targets.

### CONDITIONAL GO example

> Performance recommendation: **CONDITIONAL GO** for `{VERSION}`, subject to explicit acceptance of the documented PF2 residual risks; expected launch load remains within verified operating limits.

### NO-GO example

> Performance recommendation: **NO-GO** for `{VERSION}` until findings `{PF-xxx...}` are remediated and the associated journey, endpoint, query, load, and regression measurements pass.

---

# 67. Required Deliverables

A complete Performance Audit should produce:

1. `01_PERFORMANCE_DISCOVERY_REPORT.md`
2. `02_PERFORMANCE_STATIC_VERIFICATION_REPORT.md`
3. `03_PERFORMANCE_MEASUREMENT_REPORT.md`
4. `04_PERFORMANCE_REMEDIATION_PLAN.md`
5. `05_PERFORMANCE_PRODUCTION_READINESS_REPORT.md`

Optional supporting files:

- `PERFORMANCE_BUDGETS.md`
- `CRITICAL_JOURNEY_METRICS.md`
- `API_LATENCY_REPORT.md`
- `DATABASE_QUERY_REPORT.md`
- `LOAD_TEST_RESULTS.md`
- `BUNDLE_ASSET_REPORT.md`
- `PERFORMANCE_FINDINGS.csv`

---

# 68. Instructions to the AI Auditor

When this template is supplied to an AI coding agent:

1. Read this template completely before starting.
2. Do not optimize code during Discovery or Verification.
3. Do not run destructive load against production.
4. Do not infer production capacity from one local test.
5. Record exact environment and test conditions.
6. Prefer percentiles over averages.
7. Do not mark PASS because the UI "feels fast."
8. Do not invent product performance targets.
9. Distinguish measured result from benchmark/reference.
10. Inspect duplicate fetches and repeated DB queries.
11. Inspect N+1 behavior.
12. Inspect unbounded lists and payloads.
13. Inspect polling/timers/background refresh.
14. Inspect bundle/dependency size.
15. Inspect memory/resource lifecycle.
16. Inspect external API contribution to latency.
17. Inspect AI-generated duplicate work and patch layering.
18. Cite exact paths/endpoints/queries for static findings.
19. Preserve stable finding IDs.
20. Cross-reference Functional QA, Backend, Database, and Reliability audits where appropriate.
21. Remeasure before marking findings Verified Closed.
22. End with exactly one recommendation: **GO, CONDITIONAL GO, or NO-GO**.

---

# 69. Completion Standard

This audit is complete only when an independent reviewer could answer:

- What are the critical performance journeys?
- What are the explicit performance targets?
- What traffic/load assumptions were used?
- Which frontend paths are expensive?
- Which backend endpoints are slow?
- Which database queries are expensive?
- Is there any N+1 behavior?
- Are payloads and bundles bounded?
- Is caching intentional?
- Are external dependencies part of the critical-path latency?
- Does the system handle expected peak load?
- Is memory stable?
- What was actually measured?
- Under what conditions?
- What remains unknown?
- What remediation is proposed versus verified?
- Can this exact version operate within acceptable performance limits at launch?

If those questions cannot be answered from the audit outputs, the audit is not complete.
