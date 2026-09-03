# Code Quality Audit — Reusable Master Template

> **Purpose:** A reusable production-readiness audit for evaluating whether an application's codebase is maintainable, coherent, testable, understandable, and safe to operate before launch.
>
> This template is designed for projects built manually or with AI coding agents. It is intentionally evidence-driven: **do not mark code quality PASS because the app compiles, tests pass, or the code "looks clean." Quality claims must be tied to specific implementation evidence and, where appropriate, controlled execution.**

---

# 0. Operating Rules

## 0.1 Audit objective

Determine whether the current codebase is sufficiently healthy for production by verifying:

- Architecture is understandable and internally consistent.
- Core logic has clear ownership and a single source of truth.
- Duplicate or competing implementations are minimized.
- Dead, stale, experimental, and unreachable code are identified.
- Error handling is explicit and meaningful.
- Important behavior is testable.
- Types, models, schemas, DTOs, and API contracts are aligned.
- Technical debt that could create production instability is visible.
- Critical modules are not excessively coupled.
- Functions/classes/modules are reasonably scoped.
- Naming and structure make operational ownership possible.
- Build/lint/type-check/test tooling is functioning.
- Generated or agent-authored code has not introduced hidden inconsistencies.
- Risky shortcuts, placeholders, bypasses, mocks, and temporary code are not left in production paths.
- Changes can be safely reviewed, debugged, extended, and rolled back.

## 0.2 Non-goals

This audit does **not** replace:

- Security audit.
- Functional QA.
- Performance/load testing.
- Privacy/legal review.
- Accessibility review.
- Database integrity audit.
- DevOps/infrastructure review.

If obvious issues from those disciplines are discovered while reviewing code quality, record them and cross-reference the appropriate specialist audit.

---

# 1. Mandatory Methodology

Use these stages in order:

| Stage | Name | What happens | Required output |
|---|---|---|---|
| 1 | **Discovery** | Understand repository structure, architecture, conventions, major modules, toolchain, dependencies, tests, and code-generation patterns | Codebase map |
| 2A | **Static Verification** | Run safe static checks and inspect implementation quality against defined rules | Static evidence matrix |
| 2B | **Controlled Validation** | Execute build/lint/type/test/coverage or equivalent safe checks in an approved environment | PASS / FAIL / INCONCLUSIVE matrix |
| 3 | **Remediation Design** | Design root-cause fixes for quality problems — **design only unless separately authorized** | Remediation plan |
| Final | **Production Readiness Report** | Consolidate evidence into a launch decision | GO / CONDITIONAL GO / NO-GO |

### Golden rule

**Compilation is not proof of code quality.**

A codebase may compile and still be:

- duplicated,
- fragile,
- untestable,
- internally inconsistent,
- difficult to debug,
- reliant on hidden assumptions,
- or unsafe to modify after launch.

Never convert “works right now” into “maintainable for production” without evidence.

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
| Previous report | `{PREVIOUS_REPORT_FILENAME}` |
| Audit method | `{Read-only static inspection / lint / type-check / test / build / mixed}` |
| Environment | `{Local / Dev / CI / Staging}` |
| Restrictions | `{WHAT_WAS_NOT_DONE}` |
| Report created | `{THIS_FILENAME}` |

---

# 3. Evidence and Confidence Key

Use the same confidence discipline throughout all reports:

| Symbol | Meaning |
|---|---|
| 🟥 **Confirmed by Tool/Execution** | Proven by build, lint, test, type-check, static analysis, runtime-safe command, or other direct execution |
| 🟧 **Confirmed by Code** | Proven from explicit code evidence with path and location |
| 🟨 **Likely** | Strong inference, but evidence is incomplete |
| 🟦 **Requires Controlled Validation** | Must be validated by approved execution before conclusion |
| ⬜ **Not Applicable / False Positive** | Does not apply or was proven irrelevant |

For every meaningful finding, include:

- Finding ID.
- Severity.
- File/path/module.
- Evidence.
- Why it matters.
- Confidence.
- Whether it blocks launch.
- Recommended remediation category.
- Whether remediation has been implemented or is still proposed.

---

# 4. Severity Model

| Level | Classification | Code-quality meaning | Launch treatment |
|---|---|---|---|
| **CQ0** | Critical | Defect pattern likely to create data corruption, catastrophic failure, unrecoverable behavior, or unsafe releases | **Mandatory NO-GO** |
| **CQ1** | High | Core code is dangerously inconsistent, duplicated, untestable, misleading, or difficult to modify safely | **Pre-launch blocker** |
| **CQ2** | Medium | Material maintainability/reliability issue with bounded impact and a safe workaround | Requires explicit acceptance |
| **CQ3** | Low | Local readability/consistency issue with limited operational risk | Backlog acceptable |
| **CQ4** | Observation | Improvement opportunity or architectural note | Backlog |

## 4.1 Severity factors

For each CQ0–CQ2 issue, consider:

- Blast radius.
- Frequency.
- Reachability.
- Criticality of affected module.
- Likelihood of regression.
- Difficulty of detection.
- Difficulty of rollback.
- Test coverage.
- Team comprehension.
- Operational debugging impact.
- Data integrity implications.
- Whether the issue affects release safety.
- Whether AI-generated code is involved.
- Whether multiple agents have produced competing implementations.

---

# 5. Environment Warning

If validation is performed outside production:

| Dimension | Evaluation |
|---|---|
| Code-quality severity | Based on structural risk, not current traffic |
| Current actual impact | Based on whether affected code is live and reachable |
| Production impact | State how the issue could affect maintainability/reliability after launch |
| Procedural classification | Treat unresolved CQ0/CQ1 issues as **Pre-Launch Blockers** unless explicitly accepted under a separate risk decision |

Do not run destructive migration commands, production writes, irreversible code generation, dependency upgrades, or auto-fixes during audit unless separately authorized.

---

# PHASE 1 — DISCOVERY

# 6. Objective

Understand the codebase before judging it.

Discovery is not refactoring.

### Mandatory restrictions

During discovery:

- Read only where possible.
- Safe informational commands are allowed.
- Do not modify source files.
- Do not run formatters in write mode.
- Do not run auto-fix commands.
- Do not upgrade dependencies.
- Do not delete files.
- Do not regenerate code unless explicitly allowed.
- Do not run destructive migrations.
- Do not rewrite architecture.
- Do not silently “clean up” code while auditing.

---

# 7. Repository Structure Map

Document the repository structure:

- Monorepo or single repo.
- Applications.
- Packages/libraries.
- Frontend(s).
- Backend(s).
- Shared code.
- Database/schema/migrations.
- Tests.
- Scripts.
- Configuration.
- CI/CD files.
- Documentation.
- Generated code.
- Vendor code.
- Build artifacts.
- Experimental folders.
- Legacy folders.

Example:

| Path | Purpose | Criticality | Ownership clarity | Notes |
|---|---|---|---|---|
| `{PATH}` | `{PURPOSE}` | `{Critical/High/Normal}` | `{Clear/Unclear}` | `{NOTES}` |

---

# 8. Tech Stack and Toolchain Inventory

Document:

| Category | Technology | Version | Evidence | Actually used? | Confidence |
|---|---|---|---|---|---|
| Language | `{}` | `{}` | `{PATH}` | `{YES/NO}` | `{}` |
| Framework | `{}` | `{}` | `{PATH}` | `{YES/NO}` | `{}` |
| Build tool | `{}` | `{}` | `{PATH}` | `{YES/NO}` | `{}` |
| Package manager | `{}` | `{}` | `{PATH}` | `{YES/NO}` | `{}` |
| Linter | `{}` | `{}` | `{PATH}` | `{YES/NO}` | `{}` |
| Formatter | `{}` | `{}` | `{PATH}` | `{YES/NO}` | `{}` |
| Type checker | `{}` | `{}` | `{PATH}` | `{YES/NO}` | `{}` |
| Test framework | `{}` | `{}` | `{PATH}` | `{YES/NO}` | `{}` |
| Coverage tool | `{}` | `{}` | `{PATH}` | `{YES/NO}` | `{}` |
| Static analyzer | `{}` | `{}` | `{PATH}` | `{YES/NO}` | `{}` |
| Code generator | `{}` | `{}` | `{PATH}` | `{YES/NO}` | `{}` |

Flag tools that are configured but never executed.

---

# 9. Architectural Map

Identify:

- Main architectural pattern.
- Layer boundaries.
- Domain boundaries.
- Application services.
- Data access layer.
- API layer.
- UI layer.
- State management.
- Shared utilities.
- Cross-cutting concerns.
- Event system.
- Background workers.
- External service adapters.
- Dependency direction.

Create a simplified dependency map.

Example:

`UI → Application/Use Cases → Domain → Data/Integration`

If actual dependencies violate intended architecture, record evidence.

---

# 10. Module Inventory

| Module ID | Module | Responsibility | Inputs | Outputs | Dependencies | Criticality | Cohesion | Notes |
|---|---|---|---|---|---|---|---|---|
| `MOD-001` | `{MODULE}` | `{RESPONSIBILITY}` | `{}` | `{}` | `{}` | `{}` | `{High/Med/Low}` | `{}` |

Flag modules that:

- Have no clear responsibility.
- Mix unrelated concerns.
- Contain UI + business logic + persistence.
- Are depended on by nearly everything.
- Depend on too many other modules.
- Duplicate another module.
- Appear obsolete but remain reachable.
- Contain large amounts of generated code mixed with handwritten logic.

---

# 11. Source of Truth Inventory

Identify where each critical concept is defined.

Examples:

- User roles.
- Permissions.
- Prices.
- Delivery fees.
- Status values.
- Subscription plans.
- Validation rules.
- API endpoints.
- Feature flags.
- Environment configuration.
- Date/time rules.
- Currency formatting.
- Business calculations.

| Concept | Current source(s) | Expected source | Duplicated? | Drift risk | Finding |
|---|---|---|---|---|---|
| `{CONCEPT}` | `{PATHS}` | `{SOURCE}` | `{YES/NO}` | `{LOW/MED/HIGH}` | `{ID}` |

Multiple sources of truth are not automatically wrong, but must be justified.

---

# 12. Error-Handling Architecture

Document:

- Global error boundary/handler.
- API error handling.
- Domain errors.
- Validation errors.
- Database errors.
- Third-party integration errors.
- Background-job failures.
- Retry behavior.
- Logging behavior.
- User-facing error translation.
- Unhandled exception path.

Flag:

- Empty catch blocks.
- `catch (e) {}`.
- Broad exception swallowing.
- `console.log` as sole handling.
- `print`/debug-only behavior.
- Success returned after failure.
- Generic 200 responses on failed operations.
- Error strings used as control flow.
- Different layers handling same error inconsistently.
- Secrets or sensitive payloads logged.
- Stack traces exposed to users.

---

# 13. Test Architecture Inventory

Document:

- Unit test organization.
- Integration tests.
- End-to-end tests.
- Mock strategy.
- Fixtures.
- Factories.
- Test helpers.
- Snapshot tests.
- Contract tests.
- Database test isolation.
- Test data cleanup.
- CI test execution.

Flag:

- Test suites that rely on test order.
- Tests that mutate global state.
- Large amounts of skipped tests.
- Flaky test patterns.
- Snapshot overuse.
- Mocking so extensive that real behavior is not tested.
- Tests asserting implementation details instead of behavior.
- Production logic existing solely to satisfy tests.

---

# 14. Generated and AI-Authored Code Inventory

Identify code that appears to be:

- Generated by framework tools.
- Generated from schemas.
- Generated from API specifications.
- Generated by AI agents.
- Copied from previous implementations.
- Produced during abandoned refactors.

Document whether generated code is:

- Regenerated deterministically.
- Hand-edited.
- Committed.
- Ignored.
- Mixed with manual logic.
- Out of sync with its source schema.

Flag hand-editing of generated files where regeneration can overwrite changes.

---

# 15. Discovery Execution Log

### Fully reviewed
`{FILES / MODULES / DIRECTORIES}`

### Partially reviewed
`{FILES / MODULES / DIRECTORIES}`

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

# 16. Discovery Exit Gate

Phase 1 passes only when:

- [ ] Repository structure is mapped.
- [ ] Toolchain is identified.
- [ ] Architecture is understood well enough to review.
- [ ] Critical modules are identified.
- [ ] Main sources of truth are identified.
- [ ] Error handling approach is understood.
- [ ] Test architecture is inventoried.
- [ ] Generated/AI-authored code risk areas are identified.
- [ ] Unknown/unreviewed areas are explicitly listed.
- [ ] No critical architectural ambiguity prevents further review.

If critical module ownership or data flow cannot be understood, mark Phase 1 **INCOMPLETE**.

---

# PHASE 2A — STATIC VERIFICATION

# 17. Objective

Evaluate implementation quality through evidence from the codebase.

Use stable finding prefixes:

| Prefix | Category |
|---|---|
| `ARCH-xx` | Architecture |
| `DUP-xx` | Duplication |
| `DEAD-xx` | Dead/stale/unreachable code |
| `SIZE-xx` | Oversized/over-complex code |
| `COUP-xx` | Coupling/dependency problems |
| `COH-xx` | Cohesion/responsibility problems |
| `ERR-xx` | Error handling |
| `TYPE-xx` | Type/schema/model drift |
| `TEST-xx` | Test quality |
| `NAME-xx` | Naming/readability |
| `CONF-xx` | Configuration/code organization |
| `GEN-xx` | Generated/AI code |
| `ASYNC-xx` | Async/concurrency implementation quality |
| `STATE-xx` | State-management quality |
| `DATA-xx` | Data-access quality |
| `API-xx` | API contract quality |
| `DOC-xx` | Documentation/operational clarity |
| `BUILD-xx` | Build/toolchain quality |

---

# 18. Duplication Audit

Inspect for:

- Exact duplicate functions.
- Near-duplicate functions with small differences.
- Repeated validation rules.
- Repeated API request logic.
- Repeated mapping/serialization code.
- Repeated business calculations.
- Repeated constants.
- Duplicate components.
- Duplicate services.
- Duplicate repository/data-access methods.
- Parallel implementations created by different agent sessions.
- Old and new versions both reachable.

For each duplication finding:

| Finding | Locations | Duplicated responsibility | Behavior identical? | Drift risk | Severity |
|---|---|---|---|---|---|
| `{ID}` | `{PATHS}` | `{RESPONSIBILITY}` | `{YES/NO/UNCLEAR}` | `{LOW/MED/HIGH}` | `{CQ}` |

Do not refactor duplication blindly. Determine whether the code represents genuinely different domain behavior first.

---

# 19. Dead / Stale / Unreachable Code Audit

Look for:

- Unused exports.
- Unused functions/classes.
- Unreferenced routes.
- Dead feature flags.
- Disabled features.
- Legacy adapters.
- Old migrations/scripts.
- Commented-out code.
- Duplicate backup files.
- `.old`, `.bak`, `copy`, `final2`, `new`, `legacy` patterns.
- Abandoned prototypes.
- Unused environment variables.
- Unused assets.
- Unreachable branches.
- Temporary debug utilities.
- Obsolete API versions.

For each candidate, classify:

- Confirmed dead.
- Likely dead.
- Runtime-reachable.
- Framework-reflected/dynamic use — requires validation.
- Do not know.

Never delete code simply because text search shows no reference if the framework supports dynamic loading/reflection.

---

# 20. Complexity Audit

Evaluate:

- Very large files.
- Very large classes.
- Very large functions.
- Deep nesting.
- Excessive branching.
- Excessive boolean flags.
- Long parameter lists.
- High cyclomatic complexity where tooling supports measurement.
- Complex conditional rendering.
- Large controllers.
- Massive service classes.
- Utility "god files."
- Many responsibilities in one method.

For each high-risk item:

| Finding | File/function | Size/complexity signal | Responsibility count | Testability | Risk |
|---|---|---|---|---|---|
| `{ID}` | `{PATH}` | `{METRIC}` | `{COUNT}` | `{HIGH/MED/LOW}` | `{CQ}` |

Numbers alone do not determine severity. Consider criticality and clarity.

---

# 21. Coupling Audit

Inspect for:

- Circular dependencies.
- UI importing database internals.
- Domain code importing framework UI code.
- Core business logic directly tied to third-party SDKs.
- Modules with excessive imports.
- Shared global mutable state.
- Tight coupling to environment variables.
- Tight coupling to concrete implementations.
- Hidden singleton dependencies.
- Service locator abuse.
- Cross-module internal imports.
- Components knowing too much about API payload structure.

Record dependency direction violations.

---

# 22. Cohesion and Responsibility Audit

Ask for each important module:

- Does it have one clear reason to change?
- Does it mix persistence, validation, calculations, and presentation?
- Does it mix unrelated domains?
- Are utility modules becoming dumping grounds?
- Are models carrying unrelated behavior?
- Are controllers/services bloated?

Flag “god objects,” “god services,” and overly broad shared modules.

---

# 23. Naming and Readability Audit

Inspect:

- Misleading names.
- Generic names (`data`, `item`, `thing`, `helper`, `manager`, `util`) in critical logic.
- Inconsistent domain terminology.
- Same concept with multiple names.
- Abbreviations with unclear meaning.
- Functions whose names do not match side effects.
- Boolean names without clear truth meaning.
- Negative booleans causing double negatives.
- Comments contradicting code.
- TODO comments on critical paths.

Low-level naming issues should not be inflated into launch blockers unless they materially increase operational or regression risk.

---

# 24. Magic Values and Hardcoding Audit

Look for:

- Magic numbers.
- Hardcoded URLs.
- Hardcoded IDs.
- Hardcoded role names.
- Hardcoded status strings.
- Hardcoded prices/fees.
- Hardcoded timeouts.
- Hardcoded feature behavior.
- Production-specific configuration inside code.
- Localhost URLs.
- Test credentials.
- Fixed dates.
- Fixed currencies/locales.
- Hidden fallback values.

Classify each value:

- Legitimate constant.
- Domain constant.
- Configuration.
- Secret — escalate to Security Audit.
- Temporary/test artifact.
- Unknown.

---

# 25. Type and Model Quality Audit

Where typing exists, inspect:

- `any`.
- `dynamic`.
- unchecked casts.
- unsafe non-null assertions.
- overly broad dictionary/map types.
- ignored type errors.
- duplicated interfaces/models.
- frontend/backend model drift.
- database schema/model drift.
- enum/string drift.
- nullable mismatch.
- serialization mismatch.
- generated types out of date.

Where no static type system exists, inspect equivalent validation/model discipline.

---

# 26. API Contract Quality Audit

Inspect:

- Request DTOs.
- Response DTOs.
- Validation models.
- Consistent error structures.
- Status-code usage.
- Versioning.
- Optional/required field consistency.
- Naming consistency.
- Serialization.
- Date/time formats.
- Pagination shape.
- Null behavior.
- Backward compatibility.
- Frontend assumptions.

Flag:

- UI parsing undocumented response shapes.
- Controllers returning inconsistent types.
- Business logic using raw request objects directly.
- APIs with silent field ignoring.
- API contracts duplicated manually across applications.

---

# 27. Data Access Quality Audit

Inspect:

- Repository/data-access boundaries.
- Raw queries mixed through application logic.
- ORM misuse.
- Repeated queries.
- Transaction boundaries.
- Partial writes.
- Data mapping.
- Query-building duplication.
- Hidden side effects.
- Persistence from UI layer.
- Inconsistent soft-delete handling.
- Domain rules implemented only in queries.

Do not perform a full database-integrity audit here; cross-reference database findings that need deeper treatment.

---

# 28. Async and Concurrency Code Audit

Inspect:

- Missing `await`.
- Fire-and-forget tasks.
- Unhandled Promise/Future rejection.
- Race-prone shared state.
- Async work inside loops.
- Unsafe parallelism.
- Cancellation handling.
- Timer lifecycle.
- Subscription cleanup.
- Stream cleanup.
- Debounce/throttle misuse.
- Request cancellation.
- Background task ownership.
- Duplicate event listeners.

Flag async behavior that can create silent failures or duplicate actions.

---

# 29. State Management Audit

Inspect:

- Multiple sources of UI truth.
- Derived state stored redundantly.
- Global state overuse.
- Stale cache.
- Uncontrolled mutation.
- State reset on logout.
- User A state leaking to User B.
- Optimistic updates without rollback.
- Store persistence mismatch.
- State tied to navigation lifecycle incorrectly.
- Business logic inside presentation state.

---

# 30. Error Handling Audit

For each critical path, identify:

1. What can fail?
2. Where is the failure caught?
3. Is the error transformed or swallowed?
4. Is it logged appropriately?
5. Does the caller know the operation failed?
6. Does the user see accurate feedback?
7. Is partial state rolled back?
8. Can retry safely occur?
9. Is context preserved for debugging?

Flag especially:

- Empty catch.
- Generic catch returning success.
- Logging and continuing with invalid state.
- Error suppression.
- Exceptions used as expected control flow.
- User messages that hide actual failure.
- Error branches that are never tested.

---

# 31. Logging Quality Audit

Review code quality aspects of logging:

- Consistent logger use.
- Structured logging.
- Context fields.
- Correlation/request IDs.
- Severity levels.
- Error object preservation.
- Excessive logging.
- Debug logs in production paths.
- Logging in hot loops.
- Duplicate logging of same error.
- Logs that provide no actionable context.

Sensitive-data issues should be cross-referenced to Security/Privacy audits.

---

# 32. Configuration Quality Audit

Inspect:

- Centralized configuration.
- Typed/validated configuration.
- Required environment variables.
- Defaults.
- Environment-specific branching.
- Feature flags.
- Runtime configuration.
- Local/dev/prod consistency.
- Config duplication.
- Hidden fallback behavior.
- Missing config startup validation.

Flag application startup that silently continues with missing critical config.

---

# 33. Dependency Injection / Dependency Ownership Audit

Where relevant, inspect:

- Direct construction of infrastructure clients throughout code.
- Hidden globals.
- Singleton misuse.
- Hard-to-replace dependencies.
- Test-only injection paths.
- Mixed dependency patterns.
- Circular dependency workarounds.
- Service locator patterns.

The goal is not enforcing one design pattern. The goal is safe ownership and testability.

---

# 34. Abstraction Quality Audit

Identify:

### Under-abstraction
- Repeated domain logic.
- Repeated integration wrappers.
- Repeated validation.
- Repeated data mapping.

### Over-abstraction
- One-use interfaces.
- Excessive factories.
- Wrapper-on-wrapper chains.
- Generic frameworks built for hypothetical future needs.
- Indirection that obscures behavior.
- AI-generated abstraction layers with no real value.

For each case, explain why the current abstraction level increases risk.

---

# 35. Comment and Documentation Quality Audit

Review:

- README accuracy.
- Setup instructions.
- Architecture notes.
- Environment setup.
- Local development.
- Test execution.
- Migration execution.
- Deployment assumptions.
- Module comments.
- Complex algorithm explanations.
- Operational runbooks.

Flag:

- Instructions that no longer work.
- Commands referencing old tooling.
- Missing critical setup steps.
- Contradictory comments.
- Comments describing code that changed.

---

# 36. Temporary / Placeholder Code Audit

Search for patterns such as:

- TODO
- FIXME
- HACK
- TEMP
- DEBUG
- MOCK
- STUB
- PLACEHOLDER
- SAMPLE
- FAKE
- DEMO
- `return true`
- `return null`
- `throw new Error("Not implemented")`
- `console.log`
- `print`
- `alert`
- commented production logic
- fake delay/sleep
- hardcoded success response

Each occurrence must be classified, not automatically treated as a defect.

---

# 37. AI-Generated Code Audit

This section is mandatory when AI agents were used.

Actively search for **AI-specific failure patterns**:

## 37.1 Competing implementations

- Multiple services for same responsibility.
- Multiple hooks/controllers/repositories doing same job.
- "Old", "new", "v2", "final" implementations coexisting.
- Different agents inventing different conventions.

## 37.2 False completeness

- Code exists but is not connected.
- UI calls mock service instead of real service.
- Route exists but is not registered.
- Handler exists but is never called.
- API exists but frontend still uses old endpoint.
- Schema exists but migration is missing.
- Database field exists but serialization ignores it.

## 37.3 Hallucinated APIs

Look for:

- Calls to methods not supported by current SDK version.
- Configuration keys that do not exist.
- Unsupported library patterns.
- Code copied from another ecosystem/version.
- Incorrect framework lifecycle methods.

Validate against installed versions or official source where necessary.

## 37.4 Silent compatibility drift

- AI updates one side of a contract but not the other.
- UI model changed without backend change.
- Backend enum changed without frontend change.
- Migration changed without generated model update.
- Test fixture no longer reflects schema.
- Mobile and web clients diverge.

## 37.5 Patch layering

Identify code where agents appear to have fixed symptoms by adding:

- more conditionals,
- duplicated branches,
- fallback-after-fallback,
- wrappers around broken wrappers,
- special-case flags,
- comments explaining unexplained behavior.

Determine whether the root cause remains unresolved.

## 37.6 Unnecessary reinvention

Flag custom implementations of functionality already reliably provided by the existing framework/library where reinvention materially increases risk.

## 37.7 Unsafe generated refactors

Look for:

- Mass renames with stale imports.
- Deleted logic reintroduced elsewhere.
- Partial model changes.
- Duplicate migrations.
- Broken tests ignored rather than fixed.
- Type errors suppressed.
- Lint rules disabled.
- Broad exception handling added after failures.

---

# 38. Static Verification Matrix

| Check ID | Category | Scope | Method | Expected quality condition | Evidence | Result |
|---|---|---|---|---|---|---|
| `{ID}` | `{CATEGORY}` | `{MODULE}` | `{CODE REVIEW/STATIC TOOL}` | `{EXPECTED}` | `{PATH/METRIC}` | `{PASS/FAIL/INCONCLUSIVE}` |

Allowed results:

- PASS
- FAIL
- INCONCLUSIVE
- NOT APPLICABLE

Do not use “looks okay.”

---

# 39. Static Verification Exit Gate

Phase 2A passes only when:

- [ ] Critical modules were reviewed.
- [ ] Duplication was assessed.
- [ ] Dead/stale code was assessed.
- [ ] Error handling was assessed.
- [ ] Type/model/API consistency was assessed.
- [ ] Test architecture was assessed.
- [ ] Configuration organization was assessed.
- [ ] AI-generated-code patterns were assessed.
- [ ] All CQ0/CQ1 candidates have evidence.
- [ ] Unknowns requiring tool execution are listed.
- [ ] No critical claim is based only on subjective style preference.

---

# PHASE 2B — CONTROLLED VALIDATION

# 40. Objective

Execute safe quality checks against the exact audited version.

Typical validations:

- Dependency install/restore if already allowed.
- Build.
- Lint.
- Formatter check mode.
- Type-check.
- Unit tests.
- Integration tests.
- Coverage.
- Static analyzer.
- Dead-code analyzer.
- Dependency graph tool.
- Complexity tool.

Do not mutate code during audit.

---

# 41. Command Safety Rules

For every command:

1. Record the exact command.
2. Confirm whether it can modify files.
3. Prefer check/read-only modes.
4. Avoid auto-fix flags.
5. Avoid upgrade flags.
6. Avoid destructive database commands.
7. Avoid production credentials.
8. Record exit code.
9. Record summary output.
10. Redact secrets if unexpectedly printed.

---

# 42. Validation Command Log

| Command ID | Command | Purpose | Modifies files? | Exit code | Result | Evidence |
|---|---|---|---|---|---|---|
| `CMD-001` | `{COMMAND}` | `{PURPOSE}` | `{YES/NO}` | `{CODE}` | `{PASS/FAIL}` | `{REF}` |

---

# 43. Build Validation

Verify:

- Clean build succeeds.
- Production build succeeds if safe.
- No unexplained warnings.
- Generated code is up to date where applicable.
- Assets resolve.
- Environment assumptions are explicit.
- Build does not rely on local-only files.

Record:

| Build target | Result | Warnings | Blocking? | Evidence |
|---|---|---|---|---|
| `{TARGET}` | `{PASS/FAIL}` | `{COUNT/SUMMARY}` | `{YES/NO}` | `{REF}` |

A successful dev build does not automatically prove production build readiness.

---

# 44. Lint Validation

Record:

- Total lint findings.
- Errors.
- Warnings.
- Suppressed rules.
- Files excluded.
- Generated files excluded.
- Critical categories.

Flag:

- blanket disable comments,
- project-wide ignored rules,
- disabled type-safety rules,
- large excluded directories containing handwritten code.

---

# 45. Type-Check Validation

Where applicable:

- Run strictest configured check.
- Record type errors.
- Record ignored files.
- Record suppressed errors.
- Identify `any`/dynamic hotspots in critical code.

A passing type-check with widespread suppression may still produce a FAIL finding.

---

# 46. Test Validation

Record:

| Test suite | Total | Passed | Failed | Skipped | Flaky/retried | Result |
|---|---:|---:|---:|---:|---:|---|
| `{SUITE}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{PASS/FAIL}` |

Flag:

- tests not runnable,
- large skip counts,
- tests requiring hidden local state,
- order dependence,
- inconsistent results across reruns.

---

# 47. Coverage Validation

If coverage tooling exists:

Record by critical module, not only global average.

| Module | Statements | Branches | Functions | Lines | Criticality | Assessment |
|---|---:|---:|---:|---:|---|---|
| `{MODULE}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` |

Do **not** define a universal percentage threshold.

Assess whether:

- Critical business logic is covered.
- Error branches are covered.
- State transitions are covered.
- Regression-prone modules are covered.

100% shallow coverage can be worse than lower meaningful coverage.

---

# 48. Complexity Validation

If a supported analyzer exists, record:

- Cyclomatic complexity.
- Cognitive complexity.
- File size.
- Function size.
- Dependency fan-in.
- Dependency fan-out.
- Circular dependencies.

Use metrics as evidence, not as automatic verdicts.

---

# 49. Dead-Code Validation

Use available tooling where safe.

Classify results:

- Confirmed dead.
- Likely dead.
- Dynamic/reflection false positive.
- Framework entry point.
- Generated code.
- Requires runtime validation.

Never delete during audit.

---

# 50. Dependency Graph Validation

Where practical, inspect:

- Cycles.
- Illegal layer dependencies.
- Highly connected modules.
- Boundary violations.
- Duplicate package ownership.

Record major graph findings.

---

# 51. Controlled Validation Exit Gate

Phase 2B passes only when:

- [ ] Build was executed or explicitly blocked.
- [ ] Lint was executed if configured.
- [ ] Type-check was executed if configured.
- [ ] Tests were executed if available.
- [ ] Important tool exclusions/suppressions were reviewed.
- [ ] Critical failures have finding IDs.
- [ ] No result is reported as executed if only inferred from config.
- [ ] Exact version/commit is recorded.
- [ ] Validation did not silently modify audited source code.

---

# 52. Finding Register

Every confirmed issue must be recorded:

| Finding ID | Category | Severity | Location | Summary | Evidence | Root-cause status | Launch blocker? | Status |
|---|---|---|---|---|---|---|---|---|
| `CQ-001` | `{CATEGORY}` | `{CQ0-CQ4}` | `{PATH}` | `{SUMMARY}` | `{EVIDENCE}` | `{UNKNOWN/LIKELY/CONFIRMED}` | `{YES/NO}` | `OPEN` |

---

# PHASE 3 — REMEDIATION DESIGN

# 53. Mandatory Notice

> ⚠️ **This remediation plan is proposed and not yet implemented.** It requires technical review and a separate implementation decision. Nothing below should be described as fixed until code changes are completed and validation is rerun.

---

# 54. Objective

Design remediation around root causes.

Do not “clean the code” randomly.

Prioritize changes that:

- reduce ambiguity,
- remove competing sources of truth,
- improve failure visibility,
- restore clear boundaries,
- reduce regression risk,
- improve testability,
- eliminate production-path temporary code.

---

# 55. Root-Cause Map

| Finding | Symptom | Root cause | Confidence | Related findings | Remediation phase |
|---|---|---|---|---|---|
| `CQ-001` | `{SYMPTOM}` | `{CAUSE}` | `{SYMBOL}` | `{IDs}` | `R1` |

Group symptoms that share one cause.

---

# 56. Remediation Principles

Recommended principles:

| Principle | Application |
|---|---|
| Single source of truth | Consolidate duplicated business rules/configuration |
| Explicit dependencies | Make module ownership clear |
| Fail visibly | Do not swallow critical failures |
| Prefer deletion over parallel legacy paths | Remove obsolete implementation after verification |
| Behavior before abstraction | Do not invent generic architecture without need |
| Test before refactor | Capture current expected behavior first |
| Small reversible changes | Avoid giant one-shot rewrites |
| Preserve contracts | Refactor internals without silently breaking consumers |
| Retest every critical path | Code cleanliness alone is not closure |

---

# 57. Remediation Phase Table

| # | Action | Findings closed | Files/modules | Contract impact | Data impact | Test impact | Risk | Rollback | Retest |
|---|---|---|---|---|---|---|---|---|---|
| `{}` | `{ACTION}` | `{IDs}` | `{PATHS}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{TESTS}` |

---

# 58. Refactor Safety Requirements

Before any large refactor:

- [ ] Existing behavior is understood.
- [ ] Relevant tests exist or are added first.
- [ ] Interfaces/contracts are documented.
- [ ] Data migrations are separated from code refactors.
- [ ] Rollback strategy exists.
- [ ] Feature flags are considered if necessary.
- [ ] Deployment ordering is documented.
- [ ] Cross-client compatibility is considered.
- [ ] Generated-code regeneration path is understood.
- [ ] No unrelated cleanup is bundled into the same change.

---

# 59. Regression Requirements

Each remediation must map to:

1. Original finding.
2. A verification command or test.
3. A critical behavior check if applicable.
4. Any dependent modules.
5. Build/lint/type-check rerun.
6. Relevant Functional QA tests where behavior may change.

A finding is **not closed** when code is merely edited.

Status progression:

`OPEN → IMPLEMENTED → VERIFIED CLOSED`

---

# 60. Remediation Exit Gate

A remediation phase is implementation-ready only when:

- [ ] Root cause is documented.
- [ ] Proposed scope is bounded.
- [ ] Affected contracts are known.
- [ ] Rollback exists where needed.
- [ ] Regression tests are defined.
- [ ] Dependencies between changes are known.
- [ ] No unnecessary rewrite is proposed.
- [ ] Behavior-changing work is cross-referenced to Functional QA.
- [ ] Security-sensitive changes are cross-referenced to Security Audit.

---

# FINAL — CODE QUALITY PRODUCTION READINESS REPORT

# 61. Objective

Produce one decision document for the release owner.

The final report must distinguish:

- What was inspected.
- What was executed.
- What passed.
- What failed.
- What remains unknown.
- What was excluded.
- What is merely stylistic.
- What creates operational risk.
- What has been fixed.
- What remains proposed.
- Whether the exact version is maintainable enough to launch.

---

# 62. Executive Summary

### System
`{SYSTEM_NAME}`

### Commit / Version
`{VERSION_OR_COMMIT}`

### Review coverage
`{SUMMARY + LIMITATIONS}`

### Tool validation
- Build: `{PASS/FAIL/NOT RUN}`
- Lint: `{PASS/FAIL/NOT RUN}`
- Type-check: `{PASS/FAIL/NOT RUN}`
- Tests: `{PASS/FAIL/NOT RUN}`
- Coverage: `{SUMMARY/NOT AVAILABLE}`

### Open findings
- CQ0: `{COUNT}`
- CQ1: `{COUNT}`
- CQ2: `{COUNT}`
- CQ3: `{COUNT}`

### Critical unknowns
`{COUNT + SUMMARY}`

### Final code-quality recommendation
`{🟢 GO / 🟡 CONDITIONAL GO / 🔴 NO-GO}`

---

# 63. Launch Decision Rules

## 🟢 GO

Use **GO** only when:

- Zero open CQ0 findings.
- Zero open CQ1 findings.
- Production build succeeds where applicable.
- No critical lint/type/test failures remain.
- Critical modules have understandable ownership.
- No dangerous competing source of truth remains.
- No known critical placeholder/mock/stub remains in a production path.
- No critical errors are silently swallowed.
- No known critical API/model/schema drift remains.
- No unresolved AI-generated false-completeness issue exists in a critical path.
- Required tests are runnable.
- Remaining CQ2/CQ3 issues are documented and bounded.

## 🟡 CONDITIONAL GO

Use **CONDITIONAL GO** only when:

- Zero CQ0 findings.
- Zero CQ1 findings affecting release safety.
- Build and critical validation checks pass.
- Remaining issues are bounded maintainability debt.
- The debt does not create immediate reliability/data integrity risk.
- Release owner explicitly accepts the residual CQ2 risk.
- No critical unknown remains.

Do **not** use CONDITIONAL GO to disguise major architectural uncertainty.

## 🔴 NO-GO

Use **NO-GO** if any of the following is true:

- Any CQ0 remains open.
- Any CQ1 creates high regression/release risk.
- Production build fails.
- Critical type/lint/test failures are ignored.
- Critical module behavior cannot be understood safely.
- Multiple reachable implementations disagree on core business logic.
- Critical code silently converts failure into success.
- Core models/contracts are materially out of sync.
- Production paths still use mock/stub/placeholder behavior.
- AI-generated code is visibly incomplete or disconnected in critical flows.
- Testing/tooling is so broken that release quality cannot be evaluated.

---

# 64. Launch Gate Table

| Gate | Requirement | Evidence | Status |
|---|---|---|---|
| `LG-CQ-01` | Zero open CQ0 | `{REGISTER}` | `{PASS/FAIL}` |
| `LG-CQ-02` | Zero launch-blocking CQ1 | `{REGISTER}` | `{PASS/FAIL}` |
| `LG-CQ-03` | Production build passes | `{CMD}` | `{PASS/FAIL}` |
| `LG-CQ-04` | Critical lint/type checks pass | `{CMD}` | `{PASS/FAIL}` |
| `LG-CQ-05` | Critical tests pass | `{CMD}` | `{PASS/FAIL}` |
| `LG-CQ-06` | No critical duplicate source of truth | `{FINDINGS}` | `{PASS/FAIL}` |
| `LG-CQ-07` | No critical placeholder/mock code | `{FINDINGS}` | `{PASS/FAIL}` |
| `LG-CQ-08` | Error handling is operationally safe | `{FINDINGS}` | `{PASS/FAIL}` |
| `LG-CQ-09` | Critical model/API/schema consistency verified | `{FINDINGS}` | `{PASS/FAIL}` |
| `LG-CQ-10` | No critical AI-agent false completeness | `{FINDINGS}` | `{PASS/FAIL}` |
| `LG-CQ-11` | Critical modules are maintainable/testable enough for post-launch support | `{ASSESSMENT}` | `{PASS/FAIL}` |
| `LG-CQ-12` | No critical unknowns | `{OPEN ITEMS}` | `{PASS/FAIL}` |

If any mandatory launch gate is FAIL, this audit cannot issue GO.

---

# 65. Residual Risk Register

| Risk ID | Finding | Severity | Probability | Production impact | Mitigation | Owner | Required before launch? |
|---|---|---|---|---|---|---|---|
| `RISK-CQ-001` | `{REF}` | `{CQ}` | `{LOW/MED/HIGH}` | `{IMPACT}` | `{ACTION}` | `{OWNER}` | `{YES/NO}` |

---

# 66. Out-of-Scope / Not Verified

Explicitly list:

- Repositories not accessible.
- Branches not reviewed.
- Generated code not regenerated.
- CI not accessible.
- Tests not runnable.
- Production build not executable.
- Framework-generated internals excluded.
- Vendor code excluded.
- Dynamic/reflection-based behavior not provable statically.
- Mobile/web client not available.
- Backend/frontend counterpart not available.
- Database schema not available.
- Closed-source SDK behavior not inspectable.
- Anything intentionally excluded.

Do not treat absence of access as PASS or FAIL.

---

# 67. Final One-Sentence Recommendation

### GO example

> Code Quality recommendation: **GO for production** for `{VERSION}` because all mandatory code-quality launch gates passed and remaining findings are bounded, documented, and non-blocking.

### CONDITIONAL GO example

> Code Quality recommendation: **CONDITIONAL GO** for `{VERSION}`, subject to explicit acceptance of the documented CQ2 maintainability risks; no code-quality launch blocker remains.

### NO-GO example

> Code Quality recommendation: **NO-GO** for `{VERSION}` until findings `{CQ-xxx...}` are remediated and the required validation commands and regression tests pass.

---

# 68. Required Deliverables

A complete Code Quality Audit should produce:

1. `01_CODEBASE_DISCOVERY_REPORT.md`
2. `02_CODE_QUALITY_STATIC_VERIFICATION_REPORT.md`
3. `03_CODE_QUALITY_VALIDATION_REPORT.md`
4. `04_CODE_QUALITY_REMEDIATION_PLAN.md`
5. `05_CODE_QUALITY_PRODUCTION_READINESS_REPORT.md`

Optional supporting files:

- `CODE_QUALITY_FINDINGS.csv`
- `DEPENDENCY_GRAPH.md`
- `DEAD_CODE_CANDIDATES.md`
- `DUPLICATION_MAP.md`
- `AI_GENERATED_CODE_FINDINGS.md`

---

# 69. Instructions to the AI Auditor

When this template is supplied to an AI coding agent:

1. Read this template completely before starting.
2. Do not modify source code during Discovery or Verification.
3. Do not use auto-fix commands unless separately authorized.
4. Do not upgrade dependencies during the audit.
5. Do not delete code.
6. Do not refactor while auditing.
7. Do not claim a tool passed unless it was actually executed.
8. Record exact commands and exit results.
9. Cite exact file paths and symbols for code-derived claims.
10. Separate subjective style preference from production risk.
11. Do not penalize a codebase merely for not using your preferred architecture.
12. Judge consistency, correctness, maintainability, and operational risk instead.
13. Treat duplicated business logic more seriously than duplicated presentation markup.
14. Treat silent error swallowing in critical flows as high priority.
15. Inspect all major TODO/FIXME/MOCK/STUB candidates.
16. Trace suspicious AI-generated code to actual reachability.
17. Never assume a function is active because it exists.
18. Never assume a feature is complete because related files exist.
19. Never assume tests are meaningful because test files exist.
20. Never assume generated types are current because generated files exist.
21. Do not invent intended architecture where none is documented.
22. If two competing implementations exist, determine which is actually reachable.
23. If code quality issues overlap security, database, API, or functional behavior, cross-reference them.
24. Preserve stable finding IDs throughout remediation.
25. End with exactly one recommendation: **GO, CONDITIONAL GO, or NO-GO**.

---

# 70. Completion Standard

This audit is complete only when an independent technical reviewer could answer:

- What is the repository structure?
- What architecture is actually implemented?
- Which modules are critical?
- Where are the main sources of truth?
- Where is code duplicated?
- What dead/stale code remains?
- What error-handling risks exist?
- Are types/models/API contracts internally aligned?
- Are tests meaningful and runnable?
- Does the production build pass?
- What tooling was actually executed?
- What critical code-quality issues remain?
- Which findings are objective versus stylistic?
- What AI-generated-code risks were found?
- What remains unknown?
- What remediation is proposed versus verified?
- Can this exact version be safely maintained and supported after launch?

If those questions cannot be answered from the audit outputs, the audit is not complete.
