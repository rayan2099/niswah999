# Niswah V1 Knowledge Base Architecture

## Purpose
Provide an authoritative, reviewable knowledge layer for Niswah AI without allowing raw documents, model memory, or legacy app state to become truth by accident.

## Core invariant
- **Database / canonical app state = user facts**
- **Knowledge Base = approved knowledge**
- **LLM = explanation and language generation**

The model must never independently invent the user's menstrual state, Madhhab, pregnancy state, Nifas state, TTC state, diagnosis, ruling, or citation.

## Domains
1. HEALTH
2. FIQH
3. NISWAH_PRODUCT
4. SAFETY_ESCALATION

These domains may contribute to one response, but their authority must remain distinguishable.

## Retrieval architecture
SOURCE
→ reviewed knowledge statement
→ structured applicability/conditions
→ approved publication state
→ structured filtering
→ semantic retrieval
→ model
→ cited answer

Raw documents are never production-authoritative merely because they were uploaded.

## Fiqh retrieval
FIQH retrieval must filter by confirmed Madhhab before semantic retrieval. UNKNOWN/UNSET Madhhab never defaults silently.

## Safety precedence
Health safety classification runs before ordinary generation. Urgent escalation may override normal educational dialogue.

## Language
Arabic and English are first-class reviewed representations of the same canonical concept. Fiqh terminology is controlled through the terminology glossary.

## Versioning
Published statements are immutable historical versions. Updates create a new version with source and reviewer provenance.

## Production gate
Only APPROVED/PUBLISHED knowledge is retrievable in production.
