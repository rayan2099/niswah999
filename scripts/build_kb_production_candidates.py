#!/usr/bin/env python3
import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KB = ROOT / 'production-readiness-results' / 'knowledge-base'
OUT = KB / 'generated'
OUT.mkdir(exist_ok=True)

ELIGIBLE_FIQH = {'LOCATOR_VERIFIED'}
FAIL_CLOSED_FIQH = {'SCHOLAR_CLARIFICATION_REQUIRED', 'PARTIAL_EVIDENCE', 'PRIMARY_LOCATOR_NEEDED'}
EXPECTED_HEALTH = 74
EXPECTED_FIQH = 137


def rows(name):
    with (KB / name).open(encoding='utf-8-sig', newline='') as f:
        return list(csv.DictReader(f))


def write(name, fieldnames, data):
    with (OUT / name).open('w', encoding='utf-8', newline='') as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader(); w.writerows(data)

health = rows('HEALTH_SAFETY_CANONICAL_DRAFT.csv')
corrections = {r['atom_id']: r for r in rows('HEALTH_SAFETY_EVIDENCE_CORRECTIONS.csv')}
audit = {r['atom_id']: r for r in rows('INTERNET_EVIDENCE_AUDIT.csv')}

health_out = []
for r in health:
    atom = r['atom_id']
    corr = corrections.get(atom)
    audit_row = audit.get(atom, {})
    status = (corr or {}).get('post_correction_evidence_status') or audit_row.get('audit_status')
    if status not in {'PRIMARY_SOURCE_VERIFIED', 'INSTITUTIONALLY_CORROBORATED'}:
        raise SystemExit(f'Health row {atom} is not evidence eligible: {status}')
    health_out.append({
        'knowledge_key': atom,
        'domain': r['domain'],
        'category': r['category'],
        'topic': r['subtopic'],
        'madhhab': '',
        'canonical_en': (corr or {}).get('corrected_canonical_en') or r['draft_canonical_en'],
        'canonical_ar': (corr or {}).get('corrected_canonical_ar') or r['draft_canonical_ar'],
        'safety_class': r['escalation_class'],
        'evidence_state': status,
        'primary_source_key': (corr or {}).get('canonical_primary_source') or r['primary_source_id'],
        'primary_locator': r['primary_source_locator'],
        'primary_url': r['primary_source_url'],
        'publication_state': 'PUBLISHED',
        'production_eligible': 'true',
    })

fiqh_out = []
for madhhab, filename in [
    ('hanafi','HANAFI_EVIDENCE_PACK.csv'), ('maliki','MALIKI_EVIDENCE_PACK.csv'),
    ('shafii','SHAFII_EVIDENCE_PACK.csv'), ('hanbali','HANBALI_EVIDENCE_PACK.csv')]:
    for r in rows(filename):
        state = r['evidence_status']
        if state in FAIL_CLOSED_FIQH:
            continue
        if state not in ELIGIBLE_FIQH:
            raise SystemExit(f'Unknown fiqh state {state} for {r["review_id"]}')
        fiqh_out.append({
            'knowledge_key': r['review_id'],
            'domain': 'FIQH',
            'category': 'FIQH',
            'topic': r['issue'],
            'madhhab': madhhab,
            'canonical_en': r['source_supported_proposition'],
            'canonical_ar': '',
            'safety_class': '',
            'evidence_state': 'PRIMARY_SOURCE_VERIFIED',
            'primary_source_key': f'{madhhab}:{r["review_id"]}:primary',
            'primary_locator': r['primary_locator'],
            'primary_url': r['primary_url'],
            'publication_state': 'PUBLISHED',
            'production_eligible': 'true',
        })

if len(health_out) != EXPECTED_HEALTH:
    raise SystemExit(f'Expected {EXPECTED_HEALTH} Health/Safety candidates, got {len(health_out)}')
if len(fiqh_out) != EXPECTED_FIQH:
    raise SystemExit(f'Expected {EXPECTED_FIQH} Fiqh candidates, got {len(fiqh_out)}')

fields = list(health_out[0].keys())
write('PRODUCTION_KB_CANDIDATES.csv', fields, health_out + fiqh_out)
print(f'OK: {len(health_out)} Health/Safety + {len(fiqh_out)} Fiqh = {len(health_out)+len(fiqh_out)} production candidates')
