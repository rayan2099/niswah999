# Nifas Authority Follow-up

Status: BLOCKED ON SCHOLAR REVIEW / SEPARATE FROM AI CONTEXT PR  
Discovered during: AI Context Trust-Boundary Remediation  
Date: 2026-09-28

## Why this exists

The AI trust-boundary work correctly separates factual postpartum state from a
Fiqh Nifas classification. While removing the old `PregnancyStatus.phase`
shortcut, a broader pre-existing authority path was found elsewhere in the app.

This finding is deliberately NOT remediated by inventing or changing a Fiqh
rule in the engineering workstream. The knowledge/review program in PR #6 is
the appropriate source-governance path.

## Confirmed current behavior

`lib/core/preferences/pregnancy_status_controller.dart` currently contains a
separate local state machine with:

- `_nifasStartedAt`
- `isNifasActive`
- a fixed `< 40 days` rule
- `nifasDay`
- `startNifas()`
- local SharedPreferences persistence

This is independent from the canonical server `pregnancy_profile` factual
postpartum state.

Existing product/integration behavior also contains Nifas-labelled actions and
expectations, including examples such as:

- "Log birth & start Nifas"
- "Postpartum Mode (Nifas)"
- Nifas status-card behavior
- Fiqh-report Nifas behavior
- tests that expect the locally calculated Nifas state to end after a fixed
  duration

## Production-readiness concern

A birth/postpartum fact and a Fiqh Nifas classification are not the same data
class.

The product currently has at least two authorities:

1. factual postpartum state in the pregnancy profile;
2. a locally derived Nifas state in `PregnancyStatusController`.

The AI-context PR removes the incorrect assumption from AI prompts/context, but
it does NOT make the second authority reviewed or correct.

Therefore:

- `postpartum=true` must remain a factual state;
- Nifas must be a distinct Fiqh state;
- the app must not describe a fixed timer as a reviewed religious ruling until
  the relevant rule set has passed the review/governance gate;
- UI, reports, calculations, and tests must eventually consume one reviewed
  Nifas authority rather than independent hardcoded behavior.

## Required follow-up after scholar review

Create a separate implementation PR that:

1. identifies the approved Nifas rule atoms and exact reviewed packet/blob;
2. maps the reviewed rules into deterministic code with explicit Madhhab
   authority and UNKNOWN/UNSET behavior;
3. replaces the local fixed-duration authority with the reviewed state engine;
4. keeps factual postpartum timing available independently;
5. updates UI terminology so factual postpartum and Fiqh Nifas are not
   interchangeable;
6. updates the Doctor report and Fiqh report to use the correct authority;
7. rewrites the Nifas integration tests against reviewed rule fixtures;
8. records provenance/version of the rule set used to generate the state.

## Release-gate treatment

Until the relevant Nifas behavior has passed qualified review and the product's
Nifas authority has been reconciled, any production feature that presents a
definitive Nifas ruling from the current fixed timer should remain a Fiqh
release blocker.

The factual postpartum tracker itself can be validated independently.
