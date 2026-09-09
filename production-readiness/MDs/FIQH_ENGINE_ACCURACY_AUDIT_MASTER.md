# FIQH_ENGINE_ACCURACY_AUDIT_MASTER.md

## Purpose

This audit validates the Niswah fiqh engine as a **rule-driven, source-grounded, madhhab-aware decision system**. Its goal is to prevent arbitrary rulings, unsupported values, hidden assumptions, cross-madhhab rule mixing, and calculation errors.

This is not a generic content review. It is a production-readiness audit for every fiqh rule, state transition, date calculation, range, exception, and user-facing conclusion produced by the app.

The audit must preserve finding IDs, distinguish verified rules from assumptions, and never mark a rule PASS without source-backed evidence and executable test evidence where applicable.

## Core Principles

1. **No random rulings** — every fiqh conclusion must trace to an explicit rule and an approved source.
2. **No silent madhhab mixing** — Hanafi, Maliki, Shafi'i, and Hanbali logic must remain separate where they differ.
3. **No false precision** — if only a range, estimate, conditional outcome, or unresolved state is justified, the engine must not output an exact value.
4. **Deterministic calculations** — same inputs + madhhab + rule version must yield the same result.
5. **Explicit uncertainty** — insufficient facts must resolve to request-more-information, conditional result, bounded range, or scholar escalation.
6. **Traceability** — every ruling should be internally traceable to madhhab, rule ID, source ID, inputs, calculation version, output, and uncertainty state.

## Audit Scope

Audit all fiqh-sensitive functionality in Niswah, including:
- menstruation / hayd
- purity / tuhr
- irregular bleeding / istihada
- postpartum bleeding / nifas
- pregnancy-related bleeding classifications
- prayer eligibility / prayer status
- fasting eligibility where implemented
- ghusl-related transitions where implemented
- habitual-cycle logic
- minimum / maximum duration rules
- clean-period calculations
- interrupted / overlapping bleeding
- date boundaries and day-count conventions
- timezone effects
- retrospective reclassification
- madhhab switching
- incomplete histories
- predictions / estimated windows
- Doctor's Report fiqh state
- Dr Niswah explanations
- fiqh search / grounding

If other fiqh-sensitive features exist, add them to scope.

## Source Governance

### Approved Source Hierarchy

For each madhhab, define a reviewed source hierarchy before validating rules.

Each rule must have:
- `source_id`
- madhhab
- work / authority
- exact chapter / section / page or stable reference where available
- precise source-derived rule summary
- interpretation note
- reviewer status
- rule version

Do not use anonymous websites, social posts, forum comments, or AI summaries as primary authority.

### Rule Source Status

Every fiqh rule must be one of:
- `SOURCE_VERIFIED`
- `SOURCE_PARTIAL`
- `SOURCE_CONFLICT_REQUIRES_REVIEW`
- `SOURCE_MISSING`
- `NOT_APPLICABLE`

`SOURCE_MISSING` rules cannot be production-authoritative.

### Madhhab Separation

Maintain a rule matrix:

| Rule ID | Topic | Hanafi | Maliki | Shafi'i | Hanbali | Shared? | Source Status |
|---|---|---|---|---|---|---|---|

If rules differ, store separate rule implementations or explicit madhhab branches.

## Fiqh Rule Inventory

Create a complete inventory of every fiqh-sensitive rule found in:
- Dart/Flutter
- backend
- Supabase functions
- SQL
- config
- JSON
- prompts
- hard-coded constants
- UI copy
- tests
- docs

For each rule record:
- Rule/Finding ID
- file
- function/class
- madhhab
- inputs
- output
- constants
- branch conditions
- source
- test coverage
- production usage
- status

Pay special attention to hidden constants:
- day counts
- minimums
- maximums
- thresholds
- cutoffs
- recurrence rules
- rounding
- date normalization
- timezone conversion

No fiqh constant may remain unexplained.

## Calculation Accuracy Audit

For each calculation:

### Specification
Write:
- inputs
- preconditions
- madhhab
- formula / decision tree
- boundary behavior
- exceptions
- invalid-input behavior
- expected output

### Boundary Testing
Test:
- one unit below minimum
- exact minimum
- one unit above minimum
- one unit below maximum
- exact maximum
- one unit above maximum
- zero
- invalid/negative values
- missing values
- duplicates
- overlapping dates
- reversed dates
- timezone boundary
- midnight boundary
- DST boundary where relevant

### Date Arithmetic
Confirm:
- inclusive vs exclusive counting
- role of Hijri/Gregorian calendar if any
- local timezone vs UTC
- date-only vs datetime
- partial-day handling
- leap years
- month/year boundaries

No calculation may silently change because of device timezone.

## Menstrual-State Engine Validation

Model the engine as an explicit state machine, as applicable:
- `UNKNOWN`
- `BLEEDING_UNCLASSIFIED`
- `HAYD`
- `ISTIHADA`
- `TUHR`
- `NIFAS`
- `PREGNANCY_RELATED_STATE`
- `REQUIRES_MORE_INFORMATION`
- `REQUIRES_SCHOLAR_REVIEW`

For every transition verify:
- triggering facts
- madhhab
- prior-state dependency
- duration dependency
- habit dependency
- exception rules
- worship implications if exposed
- user explanation

No state transition may depend solely on AI interpretation.

## Habit / Historical Pattern Logic

If the app uses menstrual habits or prior-cycle history, verify:
- how a habit is established
- minimum history required
- whether one event can change habit
- how changed habits are handled
- interrupted/missing history
- madhhab-specific habit definitions
- retrospective recalculation

Never infer a stable habit from insufficient evidence.

## Prediction vs Fiqh Ruling Separation

Keep distinct:
- observed fact
- deterministic fiqh classification
- statistical prediction
- religious implication

Predictions must not be phrased as religious certainty.

## AI / Dr Niswah Fiqh Guardrails

AI may:
- explain a deterministic result
- summarize source-backed differences
- ask clarifying questions
- explain uncertainty
- recommend qualified scholarly consultation

AI must not:
- invent a madhhab rule
- choose a madhhab for the user
- alter deterministic calculations
- fabricate sources
- resolve scholarly disagreement silently
- output certainty with missing facts
- override the rule engine

Provide AI structured context with:
- selected madhhab
- deterministic classification
- relevant rule IDs
- uncertainty state
- approved source references
- prohibited inference boundaries



## AI User-State Context Layer — Mandatory

Every AI experience in Niswah must operate with an accurate, current, user-specific context assembled from the data the user has provided across the app.

This is a **mandatory product requirement**, not an optional enhancement.

The AI must not behave like an isolated chatbot that only sees the latest message. It must understand the user's current state, relevant history, and recent app inputs before generating advice, explanations, interpretations, summaries, or fiqh-related guidance.

### Required Context Domains

Where relevant to the specific AI feature, the context layer should be able to include:

- current menstrual state
- recent bleeding history
- selected madhhab
- current fiqh classification
- pregnancy status
- gestational week / pregnancy stage where available
- pregnancy-related symptoms and tracked events
- cycle history and recent changes
- prayer-related state where applicable
- wellbeing / psychological state entered by the user
- mood and emotional-tracking inputs
- symptoms
- user-authored notes / `الملاحظات`
- recent important events entered inside the app
- relevant profile attributes
- previous AI interactions when appropriate
- unresolved warnings or uncertainty states
- Doctor's Report / health-summary context where appropriate
- any user correction that changes a previously-derived state

The system must distinguish raw facts from derived conclusions and predictions.

### Context Assembly Contract

Before an AI request is sent, the application/backend should construct a structured user-state object.

Example structure:

```json
{
  "user_id": "opaque-internal-id",
  "context_version": "1",
  "generated_at": "timestamp",
  "madhhab": "hanafi",
  "menstrual_state": {
    "current_classification": "hayd",
    "source": "deterministic_fiqh_engine",
    "rule_ids": ["..."],
    "uncertainty": "none"
  },
  "cycle": {
    "current_state": "...",
    "recent_history_summary": "...",
    "predictions": {
      "type": "estimated_range",
      "value": "..."
    }
  },
  "pregnancy": {
    "is_pregnant": true,
    "stage": "...",
    "tracked_inputs": []
  },
  "wellbeing": {
    "recent_mood_summary": "...",
    "recent_user_inputs": []
  },
  "notes": {
    "relevant_recent_notes": []
  },
  "safety_flags": [],
  "data_freshness": {
    "last_updated_at": "..."
  }
}
```

The exact schema may differ, but the principle is required: **AI receives structured application truth, not an unstructured guess about the user.**

### Context Relevance

Not every AI needs every piece of user data on every request.

The system should provide the **minimum relevant context necessary** for the AI's task while still giving it enough awareness to avoid contradictory or generic answers.

Examples:

- A fiqh assistant should receive current menstrual classification, madhhab, relevant bleeding history, uncertainty state, and approved rule/source IDs.
- Dr Niswah should receive relevant cycle, pregnancy, symptoms, wellbeing, safety flags, and recent notes.
- A wellbeing-focused AI should receive relevant mood/wellbeing history and recent notes, while still being aware of major states such as pregnancy or menstruation when they materially affect the conversation.
- A general assistant should be able to understand major user-state facts so it does not respond as though the user is pregnant when she is not, or ignore a currently-recorded pregnancy, period, symptom, or emotional state.

### Notes / الملاحظات

User-authored notes are part of the user's longitudinal context.

They must not be treated as invisible data if they contain information relevant to the AI's task.

Audit:

- whether notes are retrievable for AI context
- whether only the current user's notes can be accessed
- whether relevant notes are selected rather than blindly dumping all notes
- whether deleted/edited notes disappear from future context
- whether sensitive notes are redacted from logs and observability systems
- whether notes are clearly treated as user-entered statements rather than verified medical facts

### Context Freshness

The AI context must reflect the **latest application state**.

Test:

- period begins
- period ends
- pregnancy status changes
- user edits cycle history
- user changes madhhab
- user adds a symptom
- user changes mood/wellbeing entry
- user adds/edits/deletes a note
- a fiqh classification is recomputed
- a safety flag appears

After each change, the next AI interaction must use the updated context.

Stale AI context is a production defect.

### Cross-AI Consistency

All AIs must derive their user-state context from a common authoritative context layer or equivalent canonical sources.

One AI must not believe:

- the user is pregnant

while another AI, using the same current account state, believes:

- the user is not pregnant

unless the difference is explicitly caused by scope, timing, or a documented uncertainty state.

Audit consistency across every AI feature.

### Deterministic State vs AI Interpretation

The AI may explain context, but it must not rewrite authoritative application state.

Examples:

- pregnancy status comes from the user's tracked/profile state
- menstrual/fiqh classification comes from the deterministic fiqh engine where applicable
- recorded symptoms come from user input
- recorded notes remain user-authored content
- statistical predictions remain predictions

The AI must never silently convert its own inference into persisted truth.

### Missing or Conflicting Context

If required context is:

- missing
- stale
- contradictory
- incomplete
- awaiting recomputation

the AI must not guess.

It should either:

- ask a clarifying question
- state that the information is insufficient
- present a conditional answer
- defer to the deterministic engine
- or escalate to a qualified professional/scholar where appropriate

### Privacy and Isolation Requirements

Because this context may include highly sensitive health, religious, and wellbeing information:

- context must be user-scoped
- cross-user leakage must be impossible
- only necessary fields should be sent to each AI
- raw context must not be written to logs unnecessarily
- Sentry/analytics must not capture private notes, health history, or chat payloads
- deleted user data must not remain in future AI context
- account deletion must remove the user's AI-context source data according to the app's deletion contract

### Required AI Context Tests

For every AI feature, add tests proving:

1. current menstrual state is available when relevant
2. pregnancy state is available when relevant
3. selected madhhab and fiqh state are available to fiqh-sensitive AI
4. psychological/wellbeing inputs are available when relevant
5. relevant notes can influence context
6. deleted notes do not remain in context
7. updated user data appears in the next AI interaction
8. one user's context cannot appear in another user's request
9. stale derived state is not used after recomputation
10. conflicting context triggers an explicit safe state rather than guessing
11. AI cannot overwrite deterministic application truth
12. all AI features agree on shared major user-state facts
13. context payload contains no unnecessary sensitive fields
14. observability/logging does not leak context payloads

### AI Context Finding Severity

- `AICTX-0` — cross-user context leakage, materially wrong user state, or AI acts on stale/incorrect state in a way that can produce harmful religious/health guidance
- `AICTX-1` — major context omission causing materially misleading guidance
- `AICTX-2` — partial context freshness/relevance defect
- `AICTX-3` — non-user-impacting maintainability/documentation issue

Any open `AICTX-0` is an automatic launch blocker.

### AI Context Final Acceptance

Before launch, every production AI must prove:

- correct user-state assembly
- correct user isolation
- fresh context after state changes
- cross-AI consistency
- deterministic-state respect
- note/wellbeing awareness where relevant
- safe missing-context behavior
- no sensitive-context leakage into logs/analytics

No AI feature may be considered production-ready if it only sees the latest chat message while ignoring relevant state already known by the app.


## Madhhab Switching

Test all 12 directional switches among Hanafi, Maliki, Shafi'i, and Hanbali.

Verify:
- raw user observations stay unchanged
- derived rulings recompute
- stale caches invalidate
- reports update
- UI explanations update
- AI context updates
- no mixed-rule residue remains

## Golden Fiqh Test Dataset

Build a version-controlled corpus.

Example:
```json
{
  "case_id": "FIQH-CASE-001",
  "madhhab": "hanafi",
  "inputs": {},
  "expected_classification": "",
  "expected_calculations": {},
  "expected_user_explanation": "",
  "source_ids": [],
  "review_status": "SCHOLAR_VERIFIED"
}
```

Required categories:
- simple normal case
- exact minimum boundary
- exact maximum boundary
- interrupted bleeding
- overlapping intervals
- insufficient history
- changed habit
- postpartum case
- pregnancy-related case where supported
- irregular bleeding
- retrospective correction
- timezone boundary
- cross-month
- cross-year
- madhhab-difference case
- deliberately ambiguous case

The golden dataset must be reviewed by a qualified scholar/domain reviewer before claiming religious correctness.

## Property / Invariant Tests

Examples:
- end date cannot precede start date
- raw observations never change when madhhab changes
- prediction cannot overwrite fact
- same inputs + same madhhab + same rule version = same output
- ambiguous case cannot return certainty
- unsupported rule cannot silently fall back to another madhhab
- derived classifications recompute after correction
- AI cannot mutate deterministic fiqh state
- users cannot access each other's fiqh history

## Regression Tests

Every defect must receive:
- finding ID
- reproducer
- fix
- regression test

Closure requires:
1. source correctness
2. implementation correctness
3. regression test
4. affected cross-screen retest

## Cross-Screen Consistency

Verify consistent fiqh state across:
- dashboard
- cycle tracking
- prayer tracking
- pregnancy views
- Doctor's Report
- Dr Niswah
- notifications
- exports
- profile/history
- summaries/widgets

Trace:
`INPUT → persistence → rule engine → derived state → UI → report/export → AI context`

## Persistence / Recalculation

Verify:
- raw facts stored separately from derived rulings
- derived values are recomputable
- rule version stored where necessary
- madhhab changes trigger recomputation
- historical corrections propagate
- stale caches invalidate
- server/client results agree

## User Explanation Quality

Every fiqh-sensitive conclusion should say:
- what was classified
- which madhhab is applied
- whether result is certain/conditional/estimated/ambiguous
- what facts caused it
- what additional information is needed
- when scholar consultation is appropriate

## Failure Modes

Test:
- backend unavailable
- rule data missing
- corrupted history
- partial sync
- offline state
- AI unavailable
- source grounding unavailable
- invalid madhhab
- unsupported rule version

Safe behavior:
- preserve raw data
- do not fabricate rulings
- show uncertainty/unavailability honestly
- avoid irreversible derived updates
- allow retry/recalculation

## Versioning

Expose a fiqh engine/rule version.

Changes to:
- interpretation
- madhhab logic
- constants
- calculation behavior
- source mapping

must increment the appropriate version identifier.

Historical outputs should remain traceable to the rule version that produced them.

## Scholar Review Gate

Software verification alone cannot prove that a religious interpretation is authoritative.

Require qualified review of:
- source hierarchy
- madhhab rule matrix
- disputed-rule handling
- golden test cases
- user-facing religious wording
- escalation conditions

Track:
- `NOT_REVIEWED`
- `REVIEW_IN_PROGRESS`
- `APPROVED`
- `REJECTED`
- `REVISION_REQUIRED`

No rule materially affecting worship obligations should be labeled fully verified solely by engineering tests.

## Finding Severity

### FIQH-0 — Critical
Could materially misstate a worship-related ruling.

Examples:
- wrong hayd/istihada classification
- wrong prayer/fasting implication
- cross-madhhab contamination
- arbitrary threshold
- AI overriding deterministic state

### FIQH-1 — High
Incorrect classification in plausible edge cases.

### FIQH-2 — Medium
Explanation, uncertainty, traceability, or uncommon-edge defect.

### FIQH-3 — Low
Documentation/maintainability/non-user-impacting issue.

Any open `FIQH-0` = automatic `FIQH NO-GO`.

## Execution Phases

### Phase 1 — Discovery
Inventory code, calculations, constants, madhhab branches, prompts, persisted derived values, and UI/report surfaces.

### Phase 2 — Source Mapping
Map every rule to approved authoritative sources and build the madhhab comparison matrix.

### Phase 3 — Logic Verification
Compare implementation against sourced specification; test calculations, boundaries, state transitions, and habit/history logic.

### Phase 4 — Cross-System Verification
Verify database, UI, reports, AI, exports, and screen-to-screen consistency.

### Phase 5 — Golden Dataset
Construct cases, obtain qualified review, automate tests.

### Phase 6 — Remediation
Fix findings one at a time and add regression tests.

### Phase 7 — Final Fiqh Certification
Require:
- zero open FIQH-0
- zero open FIQH-1 unless explicitly accepted by qualified reviewer
- all production rules source-mapped
- madhhab isolation proven
- golden dataset passing
- boundary suite passing
- cross-screen consistency passing
- scholar-review gate completed

## Required Final Report

Return:
1. total fiqh rules discovered
2. rules by madhhab
3. source-mapped rule count
4. source-missing rule count
5. calculations audited
6. boundary tests executed
7. state-transition tests executed
8. cross-madhhab contamination result
9. madhhab-switching result
10. golden dataset case count
11. scholar-reviewed case count
12. AI guardrail result
13. cross-screen consistency result
14. persistence/recalculation result
15. open FIQH-0 findings
16. open FIQH-1 findings
17. remaining owner/scholar actions
18. final verdict:
   - `FIQH GO`
   - `FIQH CONDITIONAL GO`
   - `FIQH NO-GO`

## Stop Rules

Do not:
- silently choose a religious interpretation
- fabricate a source
- combine madhhab rules for convenience
- convert an estimate into certainty
- use AI as authoritative fiqh logic
- mark source-unverified rules as PASS
- claim "100% religious accuracy" based only on software tests
- modify production rules without review and regression testing

When interpretation is genuinely disputed, record and escalate the disagreement rather than hiding it.
