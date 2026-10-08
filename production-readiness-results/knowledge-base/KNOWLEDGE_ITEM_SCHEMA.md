# Canonical Knowledge Item Schema

## Required fields
- knowledge_id
- domain
- category
- topic
- subtopic
- canonical_statement
- language
- source_id
- source_locator
- review_status
- version
- effective_from

## Applicability fields
- madhhab
- applicable_user_states
- conditions
- exceptions
- evidence_quality_requirement

## Review/provenance
- reviewer_role
- reviewed_by
- review_date
- approval_notes
- source_version
- created_at
- updated_at

## Retrieval fields
- retrieval_keywords
- retrieval_text
- structured_filters
- safety_class

## User-visible citation metadata
- citation_label
- source_display_name
- source_locator
- source_url_or_reference

## Domain-specific fields
FIQH:
- madhhab is mandatory
- ruling must not be published without scholar approval

HEALTH:
- escalation_class where applicable
- medical review required before publication

## Visibility
Only APPROVED/PUBLISHED versions are production-retrievable.
