# Retrieval Contract

## Input
A retrieval request should contain:
- domain
- intent
- topic
- language
- user-state facts from canonical app state
- evidence quality
- Madhhab state and selected Madhhab if relevant

## Fiqh
Required order:
1. Verify Madhhab state.
2. If selected, filter to that Madhhab.
3. Apply topic/state/applicability filters.
4. Retrieve only APPROVED/PUBLISHED items.
5. Then run semantic ranking.

UNKNOWN/UNSET Madhhab:
- never default
- factual tracking remains available
- comparative information only if separately approved
- request selection or recommend scholar consultation where needed

## Health
1. Run safety/red-flag classification.
2. Apply pregnancy/postpartum/TTC/menstrual state filters.
3. Retrieve approved health/safety knowledge.
4. Generate with citations.

## Output
Return:
- knowledge item IDs
- version IDs
- source IDs
- exact locators
- language
- Madhhab where applicable
- safety/escalation metadata

The model must not manufacture citations.
