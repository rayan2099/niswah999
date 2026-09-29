#!/usr/bin/env python3
"""Materialize production KB candidates from the canonical disposition master.

A row enters production because PRODUCTION_DISPOSITION_MASTER.csv explicitly
says `production_disposition == PRODUCTION_ELIGIBLE` for its atom_id -- never
because it happens to belong to some hardcoded evidence-status category. This
script does not re-derive eligibility from evidence_status/audit_status
values at all; it only reads them (from the underlying evidence files) to
populate content fields for rows the disposition master already approved.

Fails loudly (SystemExit, before writing anything) if:
  - an atom_id known to the underlying evidence files is missing from the
    disposition master, or vice versa (an orphan master row);
  - the disposition master contains a duplicate atom_id;
  - total row count in the disposition master is not exactly 254;
  - any row's production_disposition is a value other than
    PRODUCTION_ELIGIBLE or FAIL_CLOSED;
  - any frozen source artifact's current on-disk SHA-256 does not match the
    checksum recorded in EVIDENCE_SNAPSHOT_FREEZE_MANIFEST.json.
"""
import csv
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KB = ROOT / 'production-readiness-results' / 'knowledge-base'
OUT = KB / 'generated'
OUT.mkdir(exist_ok=True)

ALLOWED_DISPOSITIONS = {'PRODUCTION_ELIGIBLE', 'FAIL_CLOSED'}
EXPECTED_TOTAL = 254


def rows(name):
    with (KB / name).open(encoding='utf-8-sig', newline='') as f:
        return list(csv.DictReader(f))


def write(name, fieldnames, data):
    with (OUT / name).open('w', encoding='utf-8', newline='') as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(data)


def sha256_of(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def locator_title(locator: str, fallback: str) -> str:
    if not locator:
        return fallback
    for separator in ('،', ','):
        if separator in locator:
            candidate = locator.split(separator, 1)[0].strip()
            if candidate:
                return candidate
    return locator.strip() or fallback


# ---------------------------------------------------------------------------
# Step 1: load the canonical disposition master and validate its own
# structural integrity FIRST -- these are pure content-shape checks that
# don't need the frozen manifest at all, and give a specific, actionable
# error (duplicate ID / wrong count / unknown value) rather than a generic
# "something changed" checksum message when the problem is really in the
# master file's own shape.
# ---------------------------------------------------------------------------
master_rows = rows('PRODUCTION_DISPOSITION_MASTER.csv')

if len(master_rows) != EXPECTED_TOTAL:
    raise SystemExit(
        f'DISPOSITION MASTER ROW COUNT MISMATCH: expected {EXPECTED_TOTAL}, got {len(master_rows)}'
    )

seen_ids = {}
duplicates = []
for r in master_rows:
    atom_id = r['atom_id']
    if atom_id in seen_ids:
        duplicates.append(atom_id)
    seen_ids[atom_id] = r
if duplicates:
    raise SystemExit(f'DUPLICATE ATOM IDs in disposition master: {sorted(set(duplicates))}')

unknown_dispositions = {
    r['atom_id']: r['production_disposition']
    for r in master_rows
    if r['production_disposition'] not in ALLOWED_DISPOSITIONS
}
if unknown_dispositions:
    raise SystemExit(f'UNKNOWN production_disposition value(s): {unknown_dispositions}')

master_by_id = {r['atom_id']: r for r in master_rows}

# ---------------------------------------------------------------------------
# Step 2: verify the frozen snapshot's source artifacts (including the
# disposition master itself, now that its own shape is known-good) have not
# drifted since the freeze. This catches "evidence changed without a new
# freeze" -- a different failure mode from "the master file is malformed".
# ---------------------------------------------------------------------------
manifest_path = KB / 'EVIDENCE_SNAPSHOT_FREEZE_MANIFEST.json'
if not manifest_path.exists():
    raise SystemExit(f'FROZEN SNAPSHOT MISSING: {manifest_path} does not exist')
manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
frozen_commit = manifest['frozen_at_commit_sha']

checksum_mismatches = []
for artifact in manifest['source_artifact_versions']:
    path = ROOT / artifact['path']
    if not path.exists():
        checksum_mismatches.append(f"{artifact['path']}: file no longer exists")
        continue
    actual = sha256_of(path)
    if actual != artifact['sha256']:
        checksum_mismatches.append(
            f"{artifact['path']}: recorded sha256={artifact['sha256']} but on-disk sha256={actual}"
        )

master_path = KB / 'PRODUCTION_DISPOSITION_MASTER.csv'
recorded_master_sha = manifest['production_disposition_master']['sha256']
actual_master_sha = sha256_of(master_path)
if actual_master_sha != recorded_master_sha:
    checksum_mismatches.append(
        f"PRODUCTION_DISPOSITION_MASTER.csv: recorded sha256={recorded_master_sha} "
        f"but on-disk sha256={actual_master_sha}"
    )

if checksum_mismatches:
    raise SystemExit(
        'FROZEN SNAPSHOT CHECKSUM MISMATCH -- refusing to build candidates against '
        'drifted evidence artifacts. A new EVIDENCE_SNAPSHOT_FREEZE_MANIFEST.json must '
        'be created before candidates can be rebuilt. Mismatches:\n  '
        + '\n  '.join(checksum_mismatches)
    )

# ---------------------------------------------------------------------------
# Step 3: load underlying content files and confirm the atom-ID universe
# matches the disposition master exactly (nothing missing, nothing orphaned).
# ---------------------------------------------------------------------------
health = rows('HEALTH_SAFETY_CANONICAL_DRAFT.csv')
corrections = {r['atom_id']: r for r in rows('HEALTH_SAFETY_EVIDENCE_CORRECTIONS.csv')}
audit = {r['atom_id']: r for r in rows('INTERNET_EVIDENCE_AUDIT.csv')}
source_additions = {r['source_id']: r for r in rows('SOURCE_REGISTRY_ADDITIONS.csv')}

fiqh_all = {}
for madhhab, filename in [
    ('hanafi', 'HANAFI_EVIDENCE_PACK.csv'),
    ('maliki', 'MALIKI_EVIDENCE_PACK.csv'),
    ('shafii', 'SHAFII_EVIDENCE_PACK.csv'),
    ('hanbali', 'HANBALI_EVIDENCE_PACK.csv'),
]:
    for r in rows(filename):
        r['madhhab'] = madhhab
        fiqh_all[r['review_id']] = r

review_packet_rows = []
for packet in [
    'HANAFI_SCHOLAR_REVIEW_PACKET.csv',
    'MALIKI_SCHOLAR_REVIEW_PACKET.csv',
    'SHAFII_SCHOLAR_REVIEW_PACKET.csv',
    'HANBALI_SCHOLAR_REVIEW_PACKET.csv',
]:
    review_packet_rows.extend(rows(packet))
fiqh_questions = {r['review_id']: r for r in review_packet_rows}

known_universe = {r['atom_id'] for r in health} | set(fiqh_all.keys())
master_ids = set(master_by_id.keys())

missing_from_master = known_universe - master_ids
orphaned_in_master = master_ids - known_universe
if missing_from_master:
    raise SystemExit(
        f'ATOM(S) MISSING FROM DISPOSITION MASTER (present in source files, absent from master): '
        f'{sorted(missing_from_master)}'
    )
if orphaned_in_master:
    raise SystemExit(
        f'ORPHANED ATOM(S) IN DISPOSITION MASTER (no matching source-file row): '
        f'{sorted(orphaned_in_master)}'
    )

# ---------------------------------------------------------------------------
# Step 4: materialize candidates / quarantine purely from master's own
# production_disposition column.
# ---------------------------------------------------------------------------
health_out = []
for r in health:
    atom = r['atom_id']
    disposition = master_by_id[atom]['production_disposition']
    if disposition != 'PRODUCTION_ELIGIBLE':
        continue  # health currently has no FAIL_CLOSED rows, but this stays disposition-driven

    corr = corrections.get(atom)
    audit_row = audit.get(atom, {})

    source_key = (corr or {}).get('canonical_primary_source') or r['primary_source_id']
    source_title = r['primary_source_title']
    source_url = r['primary_source_url']
    source_locator = r['primary_source_locator']
    if source_key != r['primary_source_id']:
        addition = source_additions.get(source_key)
        if not addition:
            raise SystemExit(f'Corrected source {source_key} for {atom} is missing from SOURCE_REGISTRY_ADDITIONS.csv')
        source_title = addition['source_title']
        source_url = addition['url']
        source_locator = addition['scope_notes']

    has_corroboration = bool((audit_row.get('independent_corroborating_source') or '').strip())
    evidence_state = 'INSTITUTIONALLY_CORROBORATED' if has_corroboration else 'PRIMARY_SOURCE_VERIFIED'

    qualification_note = ''
    if audit_row.get('verification_status') == 'VERIFIED_WITH_QUALIFICATION':
        qualification_note = (audit_row.get('scope_restrictions') or '').strip()

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
        'qualification_note': qualification_note,
        'evidence_state': evidence_state,
        'evidence_snapshot_commit': frozen_commit,
        'primary_source_key': source_key,
        'primary_source_title': source_title,
        'primary_locator': source_locator,
        'primary_url': source_url,
        'publication_state': 'PUBLISHED',
        'production_eligible': 'true',
    })

fiqh_out = []
quarantine_out = []
for review_id, r in fiqh_all.items():
    disposition = master_by_id[review_id]['production_disposition']
    question = fiqh_questions.get(review_id)
    if not question:
        raise SystemExit(f'Fiqh row {review_id} has no scholar-packet routing metadata')

    if disposition == 'FAIL_CLOSED':
        quarantine_out.append({
            'review_id': review_id,
            'madhhab': r['madhhab'],
            'issue': r['issue'],
            'question_ar': question['question_ar'],
            'question_en': question['question_en'],
            'evidence_status': r['evidence_status'],
            'production_disposition': disposition,
            'reason_for_disposition': master_by_id[review_id]['reason_for_disposition'],
            'primary_locator': r['primary_locator'],
            'primary_url': r['primary_url'],
            'secondary_locator': r.get('secondary_locator', ''),
            'secondary_url': r.get('secondary_url', ''),
        })
        continue

    has_secondary = bool((r.get('secondary_url') or '').strip())
    evidence_state = 'INSTITUTIONALLY_CORROBORATED' if has_secondary else 'PRIMARY_SOURCE_VERIFIED'

    # The Arabic question is routing metadata only. It is NOT promoted to a
    # canonical Arabic ruling. The authoritative proposition remains the
    # source-supported English proposition until reviewed Arabic wording exists.
    fiqh_out.append({
        'knowledge_key': review_id,
        'domain': 'FIQH',
        'category': question['category'] or 'FIQH',
        'topic': r['issue'],
        'madhhab': r['madhhab'],
        'search_text_ar': question['question_ar'],
        'search_text_en': question['question_en'],
        'canonical_en': r['source_supported_proposition'],
        'canonical_ar': '',
        'safety_class': '',
        'qualification_note': '',
        'evidence_state': evidence_state,
        'evidence_snapshot_commit': frozen_commit,
        'primary_source_key': f"{r['madhhab']}:{review_id}:primary",
        'primary_source_title': locator_title(r['primary_locator'], f"{r['madhhab'].title()} primary classical source"),
        'primary_locator': r['primary_locator'],
        'primary_url': r['primary_url'],
        'publication_state': 'PUBLISHED',
        'production_eligible': 'true',
    })

# ---------------------------------------------------------------------------
# Step 5: final reconciliation against the disposition master itself (no
# hardcoded per-domain expectations -- only that everything the master
# marked eligible became a candidate, everything it marked fail-closed
# became quarantine, and nothing leaked between the two).
# ---------------------------------------------------------------------------
production_keys = {r['knowledge_key'] for r in health_out + fiqh_out}
quarantine_keys = {r['review_id'] for r in quarantine_out}

expected_eligible = {a for a, r in master_by_id.items() if r['production_disposition'] == 'PRODUCTION_ELIGIBLE'}
expected_fail_closed = {a for a, r in master_by_id.items() if r['production_disposition'] == 'FAIL_CLOSED'}

if production_keys != expected_eligible:
    raise SystemExit(
        f'CANDIDATE SET DOES NOT MATCH MASTER: '
        f'in candidates but not eligible={sorted(production_keys - expected_eligible)}; '
        f'eligible but missing from candidates={sorted(expected_eligible - production_keys)}'
    )
if quarantine_keys != expected_fail_closed:
    raise SystemExit(
        f'QUARANTINE SET DOES NOT MATCH MASTER: '
        f'in quarantine but not fail-closed={sorted(quarantine_keys - expected_fail_closed)}; '
        f'fail-closed but missing from quarantine={sorted(expected_fail_closed - quarantine_keys)}'
    )

overlap = production_keys & quarantine_keys
if overlap:
    raise SystemExit(f'FAIL-CLOSED LEAK: quarantined rows also present in production candidates: {sorted(overlap)}')

total = len(health_out) + len(fiqh_out) + len(quarantine_out)
if total != EXPECTED_TOTAL:
    raise SystemExit(f'RECONCILIATION FAILED: {total} total rows produced, expected {EXPECTED_TOTAL}')

fields = list(health_out[0].keys())
write('PRODUCTION_KB_CANDIDATES.csv', fields, health_out + fiqh_out)
write('FIQH_QUARANTINE.csv', list(quarantine_out[0].keys()), quarantine_out)
qualified_count = sum(1 for r in health_out if r['qualification_note'])
print(
    f'OK: {len(health_out)} Health/Safety + {len(fiqh_out)} Fiqh = '
    f'{len(health_out) + len(fiqh_out)} production candidates '
    f'({qualified_count} carrying a qualification_note); '
    f'{len(quarantine_out)} quarantined; snapshot commit={frozen_commit[:12]}; '
    f'all counts derived from PRODUCTION_DISPOSITION_MASTER.csv, zero hardcoded per-domain assumptions.'
)
