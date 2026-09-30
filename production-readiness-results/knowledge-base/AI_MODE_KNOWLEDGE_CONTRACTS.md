# AI Mode Knowledge Contracts

## Dr Niswah / Health
Allowed:
- HEALTH
- SAFETY_ESCALATION
- NISWAH_PRODUCT where necessary

Must:
- use canonical user state
- preserve uncertainty
- escalate red flags
- avoid diagnosis
- cite approved knowledge when authoritative claims are made

## Fiqh Advisor
Allowed:
- FIQH
- NISWAH_PRODUCT
- canonical factual user state

Must:
- filter by confirmed Madhhab
- never silently default UNKNOWN Madhhab
- cite exact approved source metadata
- distinguish factual bleeding state from Fiqh ruling

## General Assistant
Allowed:
- NISWAH_PRODUCT
- selected approved general HEALTH content
- SAFETY_ESCALATION when necessary

Must not silently inherit Fiqh authority.

## Dream Interpreter
Separate, non-authoritative contract.
- non-predictive
- no certainty claims
- no implicit Fiqh authority
- safety layer still applies
- not part of authoritative Health/Fiqh KB unless a separate reviewed program is later approved
