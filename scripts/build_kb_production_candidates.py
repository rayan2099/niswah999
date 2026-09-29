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
EXPECTED_QUARANTINE = 43
EXPECTED_JUDGMENT = 29
EXPECTED_INSUFFICIENT = 14


def rows(name):
    with (KB / name).open(encoding='utf-8-sig', newline='') as f:
        return list(csv.DictReader(f))


def write(name, fieldnames, data):
    with (OUT / name).open('w', encoding='utf-8', newline='') as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(data)


def locator_title(locator: str, fallback: str) -> str:
    if not locator:
        return fallback
    for separator in ('،', ','):
        if separator in locator:
            candidate = locator.split(separator, 1)[0].strip()
            if candidate:
                return candidate
    return locator.strip() or fallback


health = rows('HEALTH_SAFETY_CANONICAL_DRAFT.csv')
corrections = {r['atom_id']: r for r in rows('HEALTH_SAFETY_EVIDENCE_CORRECTIONS.csv')}
audit = {r['atom_id']: r for r in rows('INTERNET_EVIDENCE_AUDIT.csv')}
source_additions = {r['source_id']: r for r in rows('SOURCE_REGISTRY_ADDITIONS.csv')}
fiqh_audit = {r['review_id']: r for r in rows('FIQH_INTERNET_EVIDENCE_AUDIT.csv')}

review_packet_rows = []
for packet in [
    'HANAFI_SCHOLAR_REVIEW_PACKET.csv',
    'MALIKI_SCHOLAR_REVIEW_PACKET.csv',
    'SHAFII_SCHOLAR_REVIEW_PACKET.csv',
    'HANBALI_SCHOLAR_REVIEW_PACKET.csv',
]:
    review_packet_rows.extend(rows(packet))
fiqh_questions = {r['review_id']: r for r in review_packet_rows}

health_out = []
for r in health:
    atom = r['atom_id']
    corr = corrections.get(atom)
    audit_row = audit.get(atom, {})
    status = (corr or {}).get('post_correction_evidence_status') or audit_row.get('audit_status')
    if status not in {'PRIMARY_SOURCE_VERIFIED', 'INSTITUTIONALLY_CORROBORATED'}:
        raise SystemExit(f'Health row {atom} is not evidence eligible: {status}')

    source_key = (corr or {}).get('canonical_primary_source') or r['primary_source_id']
    source_title = r['primary_source_title']
    source_url = r['primary_source_url']
    source_locator = r['primary_source_locator']

    # If a correction replaces the canonical authority (for example Saudi-market
    # folic-acid guidance), replace the complete citation tuple — never mix a new
    # source key with the old source's URL/locator.
    if source_key != r['primary_source_id']:
        addition = source_additions.get(source_key)
        if not addition:
            raise SystemExit(f'Corrected source {source_key} for {atom} is missing from SOURCE_REGISTRY_ADDITIONS.csv')
        source_title = addition['source_title']
        source_url = addition['url']
        source_locator = addition['scope_notes']

    health_out.append({
        'knowledge_key': atom,
        'domain': r['domain'],
        'category': r['category'],
        'topic': r['subtopic'],
        'madhhab': '',
        'search_text_ar': (corr or {}).get('corrected_canonical_ar') or r['draft_canonical_ar'],
        'search_text_en': (corr or {}).get('corrected_canonical_en') or r['draft_canonical_en'],
        'canonical_en': (corr or {}).get('corrected_canonical_en') or r['draft_canonical_en'],
        'canonical_ar': (corr or {}).get('corrected_canonical_ar') or r['draft_canonical_ar'],
        'safety_class': r['escalation_class'],
        'evidence_state': status,
        'primary_source_key': source_key,
        'primary_source_title': source_title,
        'primary_locator': source_locator,
        'primary_url': source_url,
        'publication_state': 'PUBLISHED',
        'production_eligible': 'true',
    })

fiqh_out = []
quarantine_out = []
for madhhab, filename in [
    ('hanafi', 'HANAFI_EVIDENCE_PACK.csv'),
    ('maliki', 'MALIKI_EVIDENCE_PACK.csv'),
    ('shafii', 'SHAFII_EVIDENCE_PACK.csv'),
    ('hanbali', 'HANBALI_EVIDENCE_PACK.csv'),
]:
    for r in rows(filename):
        review_id = r['review_id']
        state = r['evidence_status']
        question = fiqh_questions.get(review_id)
        if not question:
            raise SystemExit(f'Fiqh row {review_id} has no scholar-packet routing metadata')

        if state in FAIL_CLOSED_FIQH:
            disposition = fiqh_audit.get(review_id)
            if not disposition:
                raise SystemExit(f'Fail-closed Fiqh row {review_id} has no internet-audit disposition')
            quarantine_out.append({
                'review_id': review_id,
                'madhhab': madhhab,
                'issue': r['issue'],
                'question_ar': question['question_ar'],
                'question_en': question['question_en'],
                'prior_evidence_status': state,
                'internet_audit_status': disposition['internet_audit_status'],
                'production_disposition': disposition['production_disposition'],
                'audit_reason': disposition['audit_reason'],
                'primary_locator': r['primary_locator'],
                'primary_url': r['primary_url'],
                'secondary_locator': r.get('secondary_locator', ''),
                'secondary_url': r.get('secondary_url', ''),
                'next_action': (
                    'QUALIFIED_MADHHAB_REVIEW'
                    if disposition['internet_audit_status'] == 'CONFLICT_OR_JUDGMENT_REQUIRED'
                    else 'OBTAIN_STRONGER_DIRECT_EVIDENCE_OR_EXPERT_REVIEW'
                ),
            })
            continue
        if state not in ELIGIBLE_FIQH:
            raise SystemExit(f'Unknown fiqh state {state} for {review_id}')

        # The Arabic question is routing metadata only. It is NOT promoted to a
        # canonical Arabic ruling. The authoritative proposition remains the
        # source-supported English proposition until reviewed Arabic wording exists.
        fiqh_out.append({
            'knowledge_key': review_id,
            'domain': 'FIQH',
            'category': question['category'] or 'FIQH',
            'topic': r['issue'],
            'madhhab': madhhab,
            'search_text_ar': question['question_ar'],
            'search_text_en': question['question_en'],
            'canonical_en': r['source_supported_proposition'],
            'canonical_ar': '',
            'safety_class': '',
            'evidence_state': 'PRIMARY_SOURCE_VERIFIED',
            'primary_source_key': f'{madhhab}:{review_id}:primary',
            'primary_source_title': locator_title(r['primary_locator'], f'{madhhab.title()} primary classical source'),
            'primary_locator': r['primary_locator'],
            'primary_url': r['primary_url'],
            'publication_state': 'PUBLISHED',
            'production_eligible': 'true',
        })

if len(health_out) != EXPECTED_HEALTH:
    raise SystemExit(f'Expected {EXPECTED_HEALTH} Health/Safety candidates, got {len(health_out)}')
if len(fiqh_out) != EXPECTED_FIQH:
    raise SystemExit(f'Expected {EXPECTED_FIQH} Fiqh candidates, got {len(fiqh_out)}')
if len(quarantine_out) != EXPECTED_QUARANTINE:
    raise SystemExit(f'Expected {EXPECTED_QUARANTINE} quarantined Fiqh rows, got {len(quarantine_out)}')

judgment_count = sum(r['internet_audit_status'] == 'CONFLICT_OR_JUDGMENT_REQUIRED' for r in quarantine_out)
insufficient_count = sum(r['internet_audit_status'] == 'INSUFFICIENT_EVIDENCE' for r in quarantine_out)
if judgment_count != EXPECTED_JUDGMENT or insufficient_count != EXPECTED_INSUFFICIENT:
    raise SystemExit(
        f'Quarantine split mismatch: judgment={judgment_count} (expected {EXPECTED_JUDGMENT}), '
        f'insufficient={insufficient_count} (expected {EXPECTED_INSUFFICIENT})'
    )

production_keys = {r['knowledge_key'] for r in health_out + fiqh_out}
quarantine_keys = {r['review_id'] for r in quarantine_out}
overlap = production_keys & quarantine_keys
if overlap:
    raise SystemExit(f'FAIL-CLOSED LEAK: quarantined rows also present in production candidates: {sorted(overlap)}')

fields = list(health_out[0].keys())
write('PRODUCTION_KB_CANDIDATES.csv', fields, health_out + fiqh_out)
write('FIQH_QUARANTINE.csv', list(quarantine_out[0].keys()), quarantine_out)
print(
    f'OK: {len(health_out)} Health/Safety + {len(fiqh_out)} Fiqh = '
    f'{len(health_out) + len(fiqh_out)} production candidates; '
    f'{len(quarantine_out)} quarantined ({judgment_count} judgment, {insufficient_count} insufficient)'
)
