# Source Registry Schema

Fields:
- source_id
- domain
- title
- author_or_body
- edition
- publisher
- publication_date
- language
- source_type
- authority_tier
- approval_state
- approved_by
- approved_date
- license_status
- url_or_reference
- notes
- version

States:
- CANDIDATE
- REVIEWING
- APPROVED
- REJECTED
- RETIRED

Credibility and ingestion rights are separate decisions. A source may be authoritative for review but not legally suitable for bulk AI ingestion.
