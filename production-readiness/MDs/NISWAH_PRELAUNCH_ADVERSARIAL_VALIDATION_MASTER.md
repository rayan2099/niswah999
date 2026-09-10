# Niswah Pre-Launch Adversarial Validation Program
## Canonical Master Methodology

**Document:** `NISWAH_PRELAUNCH_ADVERSARIAL_VALIDATION_MASTER.md`  
**Purpose:** Establish the governing validation methodology used to determine whether Niswah is genuinely ready for production launch.  
**Status:** Canonical methodology  
**Applies to:** iOS, Android, Supabase backend, authentication, user state, AI systems, fiqh logic, privacy, notifications, release builds, and all launch-critical user journeys.

---

# 1. Executive Objective

The purpose of this program is not to prove that the code compiles, that automated tests are green, or that individual features work in isolation.

The purpose is to establish defensible confidence that **real users can use Niswah safely, correctly, consistently, and recoverably under realistic and adverse conditions before production launch**.

This program combines:

- adversarial QA
- end-to-end acceptance testing
- state-machine validation
- negative-path testing
- fault-injection testing
- data-integrity validation
- privacy/isolation testing
- mobile lifecycle testing
- production configuration verification
- accessibility validation
- AI-context validation
- deterministic fiqh verification
- release-build verification

The program is intentionally stricter than ordinary feature QA.

A passing unit test is evidence.

A passing real user journey is stronger evidence.

A passing real user journey that also survives interruptions, stale state, failures, duplicate actions, cross-device behavior, and backend errors is stronger still.

---

# 2. Governing Principle

Niswah must not be considered launch-ready merely because:

- code review found no obvious defect
- unit tests pass
- widget tests pass
- integration tests pass
- CI is green
- the backend responds successfully
- a feature works in the happy path
- a screen renders correctly
- an AI response sounds plausible

Critical journeys must be validated at the evidence level appropriate to the risk they carry.

The governing principle is:

> **Critical user outcomes require live, stateful, adversarial evidence — not assumptions.**

---

# 3. Validation Philosophy

The program evaluates Niswah as users actually experience it.

The app must be tested as:

- a brand-new user
- a returning user
- a partially onboarded user
- a logged-out user
- a user with stale local state
- a user switching accounts
- a user returning after reinstall
- a user with weak or lost connectivity
- a user who backgrounds the app
- a user who force-closes the app
- a user who taps twice
- a user who enters incomplete or unusual data
- a user using Arabic
- a user using English
- a user crossing day/month/year boundaries
- a user whose data state changes over time
- a user using assistive technology
- a user whose backend request fails
- a user whose session expires
- a user whose AI context has recently changed
- a user whose fiqh case is ambiguous
- a user whose madhhab differs from the local majority
- a user who does not know her madhhab
- a user whose religious case cannot safely be answered automatically

The objective is not to manufacture failure.

The objective is to discover whether Niswah behaves correctly when reality becomes messy.

---

# 4. Evidence Strength Model

Every major finding and launch-critical journey must carry an explicit evidence level.

## E0 — ASSUMED

No meaningful verification.

Examples:

- "This probably works."
- "The implementation looks fine."
- "The framework normally handles this."

**Not acceptable for closure.**

## E1 — STATIC VERIFIED

Evidence obtained through code/configuration inspection.

Examples:

- route guard inspected
- RLS policy inspected
- environment variable wiring inspected
- deep-link configuration inspected
- signing configuration inspected

Useful, but insufficient for critical user journeys.

## E2 — AUTOMATED VERIFIED

Behavior demonstrated by automated tests.

Examples:

- unit test
- widget test
- integration test
- semantics-tree test
- mocked backend response test
- database test
- CI validation

Required for many features, but still not sufficient for high-risk real-world lifecycle behavior.

## E3 — INTEGRATION VERIFIED

Behavior demonstrated against a real service or backend.

Examples:

- live Supabase request
- live Edge Function request
- real database mutation with synthetic test user
- real email provider interaction
- real release workflow
- real signed artifact
- real RLS isolation test

Stronger than isolated automated evidence.

## E4 — LIVE JOURNEY VERIFIED

A realistic user journey is executed through the actual app against the real relevant backend/service environment.

Examples:

- real signup email received
- real confirmation link clicked
- app resumes
- onboarding appears correctly
- onboarding completed
- logout/login behavior verified
- real device cycle entry reflected in backend state
- real AI context reflects newly-entered user data

This is mandatory for launch-critical journeys where practical.

## E5 — ADVERSARIAL VERIFIED

The live journey also survives controlled adverse conditions.

Examples:

- app killed mid-flow
- confirmation link clicked twice
- network removed during request
- session expires
- partial onboarding resumed
- local state conflicts with server state
- duplicate submission attempted
- account switching performed
- stale cache tested
- backend temporarily unavailable
- timezone/date boundary crossed
- malformed or delayed service response handled safely

This is the highest standard in the program.

---

# 5. Finding Lifecycle

Findings must not jump directly from OPEN to VERIFIED_CLOSED without evidence appropriate to their risk.

Canonical statuses:

```text
OPEN
ROOT_CAUSE_CONFIRMED
REMEDIATED
AUTOMATED_VERIFIED
LIVE_VERIFICATION_REQUIRED
ADVERSARIAL_VERIFIED
VERIFIED_CLOSED
OWNER_BLOCKED
LEGAL_REVIEW_REQUIRED
SCHOLAR_REVIEW_REQUIRED
EXTERNAL_PROVIDER_BLOCKED
REVALIDATION_REQUIRED
DEFERRED
```

## REVALIDATION_REQUIRED

Use this status when:

- a previous finding was validly closed under an older evidence standard
- the fix is not known to be wrong
- but the evidence no longer meets the stricter launch criterion

This status must not be interpreted as failure.

It means:

> The prior evidence is insufficient for the launch-critical confidence threshold now required.

---

# 6. Risk Classification

Each scenario and finding must receive a severity.

## CRITICAL

Potential for:

- cross-user data exposure
- authentication bypass
- account takeover
- destructive data loss
- materially incorrect religious state or ruling
- materially incorrect health-context usage
- duplicate payment or monetary loss
- broken account deletion/privacy rights
- production release/signing failure
- systemic backend corruption
- unrecoverable user state

Launch is blocked.

## HIGH

Potential for:

- onboarding bypass
- incorrect user-state routing
- stale AI context
- lost user input
- broken password recovery
- severe notification/deep-link malfunction
- repeated crashes in critical journeys
- major accessibility blockage
- persistent incorrect state after app restart

Normally launch-blocking until resolved.

## MEDIUM

Material defect with workaround that does not threaten core safety, privacy, correctness, or identity.

May be launch-blocking depending on affected journey.

## LOW

Non-critical polish, minor usability defect, cosmetic issue, or limited edge case.

---

# 7. Tier-1 Launch-Critical Domains

The following domains require the strongest validation.

## 7.1 Authentication and Identity

Validate:

- signup
- email confirmation
- callback handling
- login
- logout
- password reset
- session restoration
- token refresh
- account switching
- reinstall
- account deletion
- user identity isolation

## 7.2 Onboarding and User State

Validate:

- new-user detection
- onboarding completion
- partial onboarding
- resume after interruption
- server-side source of truth
- no local-only authority
- correct routing after confirmation
- correct routing after reinstall
- required profile state creation
- downstream state assumptions

## 7.3 Cycle Tracking

Validate:

- cycle creation
- edits
- deletion
- bleeding start/end
- unusual intervals
- retrospective corrections
- date boundaries
- timezone behavior
- repeated updates
- derived state correctness

## 7.4 Pregnancy Tracking

Validate:

- pregnancy start
- gestational state
- updates
- termination/end state
- switching between pregnancy/cycle states where applicable
- stale AI context
- date-calculation boundaries

## 7.5 Wellbeing, Symptoms, and Notes

Validate:

- create/edit/delete
- freshness
- data isolation
- optional/null fields
- AI-context propagation
- stale-state prevention

## 7.6 AI Context

For all relevant AIs, validate:

- correct authenticated user
- current pregnancy state
- current cycle state
- current bleeding state
- current symptoms
- current wellbeing
- current notes
- madhhab context
- jurisdiction context where applicable
- no stale context
- no cross-user context
- no contradictory shared state between AIs

## 7.7 Fiqh Engine and Fiqh Advisor

Validate:

- deterministic state first
- madhhab isolation
- source traceability
- source approval status
- no invented citations
- no madhhab mixing
- explicit madhhab overrides geography
- geography suggests rather than declares
- ambiguity handling
- abstention when evidence is insufficient
- scholar-review gates
- jurisdictional supplementation
- edge/boundary cases

## 7.8 Privacy and User Rights

Validate:

- consent
- data export
- account deletion
- logout cleanup
- cached data
- local encrypted storage
- user isolation
- deletion propagation
- sensitive data exposure
- analytics boundaries

## 7.9 Notifications and Deep Links

Validate:

- notification permission granted
- permission denied
- notification tap from foreground
- background
- terminated app
- deep link valid
- deep link invalid
- stale deep link
- duplicated deep link
- wrong-user deep link
- auth callback
- notification routing

## 7.10 Release Builds

Validate:

- production Android release artifact
- production iOS release artifact when available
- signing
- environment configuration
- backend endpoints
- production bundle/package identity
- no debug-only assumptions
- startup behavior
- crash reporting
- deep links
- permissions
- upgrade behavior

---

# 8. Persona Matrix

Every Tier-1 domain must be considered across relevant personas.

Canonical personas:

```text
P01 — Brand-new user
P02 — Returning fully-onboarded user
P03 — Confirmed but not onboarded user
P04 — Partially onboarded user
P05 — Logged-out returning user
P06 — Reinstalled user
P07 — User switching devices
P08 — User switching accounts
P09 — Arabic user
P10 — English user
P11 — User with incomplete data
P12 — User with unusual/edge-case cycle history
P13 — Pregnant user
P14 — User with fiqh ambiguity
P15 — User with unknown madhhab
P16 — User with explicit minority madhhab
P17 — User with accessibility needs
P18 — User with weak/intermittent network
P19 — User with stale local state
P20 — Confused/non-linear user
```

Additional personas may be introduced when a scenario justifies them.

---

# 9. State-Machine Validation

Critical workflows must be modeled as states and transitions.

Example authentication model:

```text
UNAUTHENTICATED
      ↓ signup
UNCONFIRMED_ACCOUNT
      ↓ email confirmation
AUTHENTICATED_ONBOARDING_INCOMPLETE
      ↓ onboarding completed
AUTHENTICATED_ONBOARDING_COMPLETE
      ↓ logout
UNAUTHENTICATED_RETURNING_USER
      ↓ login
AUTHENTICATED_ONBOARDING_COMPLETE
```

Every meaningful transition must be tested.

For each transition define:

- precondition
- action
- backend mutation
- expected local mutation
- expected route
- expected persisted state
- expected recovery behavior
- expected analytics/observability event if applicable
- negative cases
- interruption cases

---

# 10. Transition Interruption Testing

For every Tier-1 state transition, evaluate what happens if the app is interrupted:

```text
before request
during request
after backend success but before UI confirmation
while app is backgrounded
after force-close
after device restart
after session expiration
after network loss
after duplicate action
```

No transition should leave the user in an unrecoverable or contradictory state.

---

# 11. Negative-Path Testing

Each critical journey must include negative paths.

Examples:

- invalid email
- duplicate account
- already-confirmed account
- expired confirmation link
- reused confirmation link
- invalid reset link
- incorrect password
- lost internet
- backend timeout
- 401
- 403
- 404
- 409
- 429
- 500
- malformed response
- delayed response
- duplicate tap
- app killed
- stale session
- stale local cache
- missing optional data
- missing required backend row
- unexpected null
- permission denied

---

# 12. Fault-Injection Program

Controlled failures must be intentionally introduced where safe.

## Network

- offline before request
- offline mid-request
- very slow response
- intermittent connectivity

## Authentication

- expired access token
- refresh failure
- revoked session
- account deleted remotely

## Backend

- timeout
- service unavailable
- database function unavailable
- expected row absent
- duplicate request

## Mobile Lifecycle

- background
- foreground
- force-close
- cold start
- device reboot
- OS reclaim

## User Behavior

- rapid repeated taps
- back navigation
- abandoning workflow
- restarting workflow
- entering conflicting data

Production-destructive fault injection must never occur without explicit authorization.

---

# 13. Data-Integrity Validation

Every state-changing Tier-1 action must verify:

- exactly one intended write
- no duplicate rows
- correct user ID
- correct timestamps
- correct foreign-key relationships
- correct derived state
- no accidental overwrite
- no stale data winning over newer data
- no partial write leaving invalid state
- safe retry behavior
- correct deletion behavior

When practical, compare:

```text
BEFORE STATE
ACTION
AFTER STATE
EXPECTED STATE
```

---

# 14. Cross-Account Isolation

For any user-specific feature, test with at least two synthetic accounts where practical.

Verify:

- User A cannot read User B
- User A cannot update User B
- User A cannot delete User B
- User A's local state does not leak to User B
- logout clears user-scoped local state
- account switching does not retain previous user's data
- AI context uses only the authenticated user's state
- cached UI does not show prior-user sensitive data

Cross-user leakage is CRITICAL.

---

# 15. Fresh-Install and Reinstall Testing

## Fresh install

Verify:

- no stale local assumptions
- correct first route
- correct auth state
- correct onboarding state
- permissions handled safely

## Reinstall

Verify:

- server-side state remains authoritative
- completed onboarding remains completed
- incomplete onboarding remains incomplete
- local cache loss does not corrupt user state
- app safely reconstructs state from backend

---

# 16. Locale, RTL, and Time Validation

Validate critical journeys under:

- Arabic
- English
- RTL
- LTR
- device timezone changes
- midnight boundary
- month boundary
- year boundary
- daylight-saving changes where relevant
- locale switch during app use

Date-sensitive cycle and fiqh logic must never rely on display strings.

---

# 17. Cross-Feature Scenario Testing

Features must not be tested only in isolation.

## Scenario A

```text
New account
+ Arabic
+ email confirmation outside app
+ app backgrounded
+ onboarding incomplete
+ app killed
+ app reopened
```

Expected:

- authenticated state restored correctly
- onboarding resumed
- no dashboard bypass
- locale preserved
- no duplicate profile creation

## Scenario B

```text
Pregnant user
+ existing cycle history
+ current symptom
+ wellbeing note
+ pregnancy week updated
+ asks Dr Niswah
+ asks Fiqh Advisor
```

Expected:

- shared factual state agrees
- irrelevant context excluded
- deterministic fiqh state preserved
- no stale prior pregnancy week
- no conflicting user identity

---

# 18. Accessibility Validation

Accessibility requires both engineering evidence and live assistive-technology acceptance where applicable.

Validate:

- semantics labels
- meaningful focus order
- touch targets
- VoiceOver
- TalkBack
- text scaling
- Arabic accessibility
- loading-state announcements
- dialogs
- destructive actions
- form fields
- validation errors

Automated semantics tests do not replace live AT testing for launch-critical journeys.

---

# 19. Performance Validation

Performance testing should use profile/release builds, not only debug mode.

Measure relevant areas:

- cold startup
- warm startup
- dashboard render
- scrolling
- cycle screens
- AI chat screens
- list-heavy areas
- network latency
- memory usage
- repeated navigation
- app resume
- background/foreground transitions

Performance defects should be separated into:

- app-side
- backend-side
- development-machine/simulator overhead
- network/provider latency

---

# 20. Observability Validation

For critical failures, verify that diagnostics are useful without exposing secrets.

Validate:

- crash reporting
- structured error reporting
- environment labels
- user-safe identifiers
- no secrets
- no auth tokens
- no inappropriate sensitive note contents
- enough context to diagnose failures
- production/staging separation

Critical failures should be diagnosable after launch.

---

# 21. AI Validation Standard

AI output quality must not be judged only by fluency.

Validate:

- context correctness
- source correctness
- deterministic fact preservation
- privacy isolation
- stale-context resistance
- uncertainty handling
- refusal/abstention behavior
- consistency across AIs
- injection resistance where applicable
- malformed upstream response handling
- rate-limit handling
- provider outage handling

For sensitive domains:

```text
deterministic fact
>
approved retrieved evidence
>
LLM explanation
```

The LLM must not override deterministic truth.

---

# 22. Fiqh Validation Standard

Fiqh requires the highest domain-governance standard.

A production religious answer must be attributable to:

- confirmed madhhab or clearly marked suggestion
- deterministic case state
- approved rule
- approved source
- relevant user facts
- uncertainty classification
- disagreement handling where relevant

The system must never:

- fabricate a source
- fabricate page numbers
- silently switch madhhab
- infer madhhab as fact from country
- collapse disagreement into one universal answer
- answer authoritatively when approved evidence is insufficient

Scholar approval is independent from engineering validation.

---

# 23. Scenario Record Schema

Every adversarial scenario should be recorded using a consistent structure.

```text
Scenario ID:
Domain:
Risk tier:
Persona:
Environment:
Build:
Preconditions:
Initial state:
Action:
Injected fault:
Expected result:
Observed result:
Backend evidence:
Device evidence:
Evidence level:
Finding IDs:
Status:
Notes:
```

---

# 24. Canonical Scenario Status

Use:

```text
NOT_RUN
BLOCKED
PASS
FAIL
PASS_WITH_LIMITATION
REVALIDATION_REQUIRED
```

A scenario cannot be PASS if its required evidence was not executed.

---

# 25. Automation vs Owner Responsibilities

The coding agent should perform all work that can reasonably be automated.

## Agent responsibilities

- inspect code
- inspect configuration
- build state models
- create scenario matrices
- write tests
- run tests
- run safe live backend tests
- create synthetic users
- test RLS
- perform safe fault simulation
- inspect logs
- reconcile findings
- remediate code
- rerun tests
- update evidence
- update canonical documents
- generate owner acceptance scripts

## Owner responsibilities only when unavoidable

- email-account access
- browser confirmation
- external service authorization
- Apple Developer authentication
- physical VoiceOver/TalkBack acceptance
- legal decisions
- scholar approval
- payment/KYC agreements
- irreversible production actions
- production-secret entry
- real-device actions that cannot be automated

The owner must not be asked to:

- inspect code
- reconcile findings
- manually inspect database tables
- compare logs
- choose routine implementation details
- perform work the agent can execute safely

---

# 26. Production Safety Rules

The adversarial program must not create new production risk.

Rules:

- no destructive production testing without explicit authorization
- no blind `supabase db push`
- no production dumps containing credentials
- no secret values in prompts/reports/logs
- no force-push
- no auto-deployment of unreviewed fixes
- no production schema mutation without migration evidence and authorization
- use synthetic test users where possible
- clean synthetic data after tests
- preserve audit evidence

---

# 27. Revalidation Policy for Previous Work

Do not reopen every historical finding automatically.

Revalidate only where:

- the old evidence level is below the newly required threshold
- a new defect casts doubt on the same subsystem
- a shared root cause is plausible
- the behavior is Tier-1
- the implementation changed materially
- production configuration changed
- a provider or infrastructure dependency changed

Strong previously-proven evidence remains valid unless contradicted.

Examples:

- real backup restore
- real signed release artifact
- live production RLS isolation
- live Edge Function behavior
- real synthetic-user CRUD
- real physical accessibility acceptance

---

# 28. Confidence-Reset Wave Order

Recommended execution order:

## Wave 1
Authentication + Identity + Session + Onboarding

## Wave 2
Account lifecycle + password recovery + reinstall + account switching

## Wave 3
Cycle + pregnancy + wellbeing + symptoms + notes state integrity

## Wave 4
Cross-user privacy/isolation + local-storage cleanup

## Wave 5
Notifications + deep links + background/resume + cold-start routing

## Wave 6
AI shared-context correctness across all four AIs

## Wave 7
Fiqh deterministic engine + madhhab isolation + source/retrieval behavior

## Wave 8
Export + deletion + consent/privacy flows

## Wave 9
Performance + resilience + provider/backend outage behavior

## Wave 10
Real release-build acceptance on Android/iOS

## Wave 11
Fresh end-to-end final adversarial acceptance

The sequence may change if a Critical/High finding requires immediate remediation.

---

# 29. Launch Gate

Niswah must not receive GO solely from test-count totals.

A credible final launch gate should include:

- zero unresolved CRITICAL findings
- zero unresolved HIGH findings unless explicitly accepted by owner with rationale
- all Tier-1 journeys at required evidence level
- all mandatory E4 journeys passed
- mandatory E5 adversarial scenarios passed
- cross-user isolation passed
- auth/onboarding lifecycle passed
- fresh-install path passed
- returning-user path passed
- partial-state recovery passed
- release-build validation passed
- production schema contract passed
- privacy/account deletion gate resolved
- accessibility acceptance passed
- scholar review requirements resolved for production fiqh scope
- production AI context verified
- current backend/service configuration verified

---

# 30. Final Report Format

The final adversarial report should summarize:

```text
Total scenarios:
Tier-1 scenarios:
Negative-path scenarios:
Fault-injection scenarios:
Recovery scenarios:
Cross-user scenarios:
Live-device scenarios:
E4 scenarios:
E5 scenarios:

PASS:
FAIL:
BLOCKED:
REVALIDATION_REQUIRED:

Critical findings open:
High findings open:
Medium findings open:
Low findings open:

Auth lifecycle verdict:
Data-integrity verdict:
Privacy verdict:
AI-context verdict:
Fiqh verdict:
Accessibility verdict:
Release verdict:
Performance verdict:
Recovery verdict:

Final launch verdict:
GO / CONDITIONAL GO / NO-GO
```

The report must cite actual evidence rather than rely on generalized confidence statements.

---

# 31. Definition of Done

This program is complete only when Niswah has been intentionally exercised under the realistic failure modes that matter most and the evidence demonstrates that:

1. identity is correct
2. user state is correct
3. data is isolated
4. critical state transitions are recoverable
5. backend failures are handled safely
6. local state cannot incorrectly override authoritative backend state
7. AI receives the correct current user context
8. fiqh logic remains deterministic and source-controlled
9. privacy rights behave correctly
10. accessibility works in practice
11. release builds behave correctly
12. production configuration matches intended behavior
13. unresolved risk is explicitly documented rather than assumed away

---

# 32. Core Standard

> **Do not ask whether Niswah works when everything goes right.**
>
> **Prove that Niswah remains correct, safe, recoverable, and understandable when users, devices, networks, sessions, services, and state transitions do not behave perfectly.**

That is the launch-confidence standard for Niswah.
