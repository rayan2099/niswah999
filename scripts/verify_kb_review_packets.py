#!/usr/bin/env python3
"""Fail closed on Niswah V1 KB/reviewer-packet drift.

This validator is intentionally stdlib-only so it can run in GitHub Actions and
locally without installing dependencies.
"""
from __future__ import annotations

import csv
import hashlib
from collections import Counter
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
KB = ROOT / "production-readiness-results" / "knowledge-base"

ALLOWED_REVIEW_DECISIONS = {
    "PENDING",
    "APPROVED",
    "APPROVED_WITH_EDITS",
    "CONFLICT_REQUIRES_REVIEW",
    "REJECTED",
    "NOT_APPLICABLE",
}
ALLOWED_EVIDENCE = {
    "LOCATOR_VERIFIED",
    "PARTIAL_EVIDENCE",
    "SCHOLAR_CLARIFICATION_REQUIRED",
    "PRIMARY_LOCATOR_NEEDED",
}

errors: list[str] = []


def fail(msg: str) -> None:
    errors.append(msg)


def rows(name: str) -> list[dict[str, str]]:
    path = KB / name
    if not path.exists():
        fail(f"missing required file: {name}")
        return []
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def require_unique(items: list[dict[str, str]], key: str, label: str) -> None:
    vals = [r.get(key, "") for r in items]
    blanks = [i for i, v in enumerate(vals, start=2) if not v]
    if blanks:
        fail(f"{label}: blank {key} at CSV rows {blanks[:10]}")
    dups = [v for v, n in Counter(vals).items() if v and n > 1]
    if dups:
        fail(f"{label}: duplicate {key}: {dups[:10]}")


def git_blob_sha(path: Path) -> str:
    data = path.read_bytes()
    header = f"blob {len(data)}\0".encode()
    return hashlib.sha1(header + data).hexdigest()


# 1) Atomic denominator.
atomic = rows("ATOMIC_KNOWLEDGE_MATRIX.csv")
require_unique(atomic, "atom_id", "atomic matrix")
if len(atomic) != 261:
    fail(f"atomic matrix: expected 261 rows, got {len(atomic)}")
domain_counts = Counter(r.get("domain", "") for r in atomic)
expected_domains = {
    "FIQH": 180,
    "HEALTH": 59,
    "SAFETY_ESCALATION": 15,
    "NISWAH_PRODUCT": 7,
}
for domain, expected in expected_domains.items():
    if domain_counts[domain] != expected:
        fail(f"atomic matrix: expected {expected} {domain} rows, got {domain_counts[domain]}")

# 2) Health/Safety source-mapped draft.
health = rows("HEALTH_SAFETY_CANONICAL_DRAFT.csv")
require_unique(health, "atom_id", "health/safety draft")
if len(health) != 74:
    fail(f"health/safety draft: expected 74 rows, got {len(health)}")
for r in health:
    atom = r.get("atom_id", "?")
    if not r.get("draft_canonical_en") or not r.get("draft_canonical_ar"):
        fail(f"{atom}: missing English/Arabic draft")
    if not r.get("primary_source_url") or not r.get("primary_source_locator"):
        fail(f"{atom}: missing primary source URL/locator")
    if r.get("review_status") != "DRAFT_REVIEW_REQUIRED":
        fail(f"{atom}: unexpected review_status={r.get('review_status')!r}")
    if r.get("publication_status") != "NOT_APPROVED_NOT_PUBLISHED":
        fail(f"{atom}: draft must remain NOT_APPROVED_NOT_PUBLISHED")

# 3) Fiqh evidence + scholar packets.
school_files = {
    "hanafi": ("HANAFI_EVIDENCE_PACK.csv", "HANAFI_SCHOLAR_REVIEW_PACKET.csv", "HNF-"),
    "maliki": ("MALIKI_EVIDENCE_PACK.csv", "MALIKI_SCHOLAR_REVIEW_PACKET.csv", "MLK-"),
    "shafii": ("SHAFII_EVIDENCE_PACK.csv", "SHAFII_SCHOLAR_REVIEW_PACKET.csv", "SHF-"),
    "hanbali": ("HANBALI_EVIDENCE_PACK.csv", "HANBALI_SCHOLAR_REVIEW_PACKET.csv", "HNB-"),
}
evidence_total = Counter()

for school, (evidence_name, packet_name, prefix) in school_files.items():
    ev = rows(evidence_name)
    pkt = rows(packet_name)
    require_unique(ev, "review_id", evidence_name)
    require_unique(pkt, "review_id", packet_name)
    if len(ev) != 45:
        fail(f"{evidence_name}: expected 45 rows, got {len(ev)}")
    if len(pkt) != 45:
        fail(f"{packet_name}: expected 45 rows, got {len(pkt)}")
    if {r.get("review_id") for r in ev} != {r.get("review_id") for r in pkt}:
        fail(f"{school}: evidence/review packet review_id sets differ")

    for r in ev:
        rid = r.get("review_id", "?")
        if not rid.startswith(prefix):
            fail(f"{rid}: wrong prefix for {school}")
        status = r.get("evidence_status", "")
        if status not in ALLOWED_EVIDENCE:
            fail(f"{rid}: invalid evidence_status={status!r}")
        evidence_total[status] += 1
        if not r.get("primary_url"):
            fail(f"{rid}: missing primary_url")
        if status == "PRIMARY_LOCATOR_NEEDED":
            fail(f"{rid}: PRIMARY_LOCATOR_NEEDED is not allowed at review-readiness gate")

    for r in pkt:
        rid = r.get("review_id", "?")
        decision = r.get("scholar_decision", "")
        if decision not in ALLOWED_REVIEW_DECISIONS:
            fail(f"{rid}: invalid scholar_decision={decision!r}")
        publication = r.get("publication_status", "")
        if decision == "PENDING":
            if publication != "NOT_APPROVED_NOT_PUBLISHED":
                fail(f"{rid}: pending row cannot be published")
        elif decision in {"APPROVED", "APPROVED_WITH_EDITS"}:
            for field in (
                "approved_canonical_ruling_ar",
                "approved_canonical_ruling_en",
                "reviewer_name",
                "reviewer_qualification",
                "review_date",
            ):
                if not r.get(field):
                    fail(f"{rid}: {decision} requires {field}")
        elif publication not in {"NOT_APPROVED_NOT_PUBLISHED", ""}:
            fail(f"{rid}: non-approved decision cannot be published")

expected_evidence = {
    "LOCATOR_VERIFIED": 137,
    "SCHOLAR_CLARIFICATION_REQUIRED": 29,
    "PARTIAL_EVIDENCE": 14,
    "PRIMARY_LOCATOR_NEEDED": 0,
}
for status, expected in expected_evidence.items():
    if evidence_total[status] != expected:
        fail(f"fiqh evidence: expected {expected} {status}, got {evidence_total[status]}")

# 4) Aggregate Fiqh status report must agree.
status_rows = rows("FIQH_EVIDENCE_STATUS.csv")
total_row = next((r for r in status_rows if r.get("madhhab") == "TOTAL"), None)
if not total_row:
    fail("FIQH_EVIDENCE_STATUS.csv: missing TOTAL row")
else:
    checks = {
        "total": 180,
        "locator_verified": 137,
        "scholar_clarification_required": 29,
        "partial_evidence": 14,
        "primary_locator_needed": 0,
        "scholar_approved": 0,
    }
    for field, expected in checks.items():
        try:
            actual = int(total_row.get(field, "-1"))
        except ValueError:
            actual = -1
        if actual != expected:
            fail(f"FIQH_EVIDENCE_STATUS TOTAL {field}: expected {expected}, got {actual}")

# 5) Source-quality audit: all 180 rows must be review-suitable with primary URLs.
audit = rows("FIQH_SOURCE_QUALITY_AUDIT.csv")
require_unique(audit, "review_id", "source quality audit")
if len(audit) != 180:
    fail(f"source quality audit: expected 180 rows, got {len(audit)}")
for r in audit:
    rid = r.get("review_id", "?")
    if r.get("quality_flag") != "OK_FOR_SCHOLAR_REVIEW":
        fail(f"{rid}: source quality flag is {r.get('quality_flag')!r}")
    if r.get("primary_quality") == "MISSING" or not r.get("primary_host"):
        fail(f"{rid}: primary source quality/host missing")

# 6) Medical review packet.
medical = rows("MEDICAL_REVIEW_PACKET.csv")
require_unique(medical, "atom_id", "medical review packet")
if len(medical) != 74:
    fail(f"medical review packet: expected 74 rows, got {len(medical)}")
for r in medical:
    atom = r.get("atom_id", "?")
    decision = r.get("medical_decision", "")
    if decision not in ALLOWED_REVIEW_DECISIONS:
        fail(f"{atom}: invalid medical_decision={decision!r}")
    if decision == "PENDING":
        if r.get("publication_status") != "NOT_APPROVED_NOT_PUBLISHED":
            fail(f"{atom}: pending medical row cannot be published")
    elif decision in {"APPROVED", "APPROVED_WITH_EDITS"}:
        for field in (
            "approved_canonical_en",
            "approved_canonical_ar",
            "approved_escalation_class",
            "reviewer_name",
            "reviewer_qualification",
            "review_date",
        ):
            if not r.get(field):
                fail(f"{atom}: {decision} requires {field}")
    elif r.get("publication_status") not in {"NOT_APPROVED_NOT_PUBLISHED", ""}:
        fail(f"{atom}: non-approved medical decision cannot be published")

# 7) Review-packet manifest counts + blob SHAs.
manifest = rows("REVIEW_PACKET_MANIFEST.csv")
expected_manifest = {
    "HANAFI_SCHOLAR_REVIEW_PACKET.csv": 45,
    "MALIKI_SCHOLAR_REVIEW_PACKET.csv": 45,
    "SHAFII_SCHOLAR_REVIEW_PACKET.csv": 45,
    "HANBALI_SCHOLAR_REVIEW_PACKET.csv": 45,
    "MEDICAL_REVIEW_PACKET.csv": 74,
}
manifest_by_packet = {r.get("packet", ""): r for r in manifest}
for name, expected_count in expected_manifest.items():
    row = manifest_by_packet.get(name)
    if row is None:
        fail(f"review manifest: missing {name}")
        continue
    try:
        count = int(row.get("item_count", "-1"))
    except ValueError:
        count = -1
    if count != expected_count:
        fail(f"review manifest {name}: expected item_count {expected_count}, got {count}")
    path = KB / name
    if path.exists():
        actual_sha = git_blob_sha(path)
        if row.get("blob_sha") != actual_sha:
            fail(
                f"review manifest {name}: blob SHA drift "
                f"(manifest={row.get('blob_sha')}, actual={actual_sha})"
            )
    if row.get("review_state") != "PENDING_EXTERNAL_REVIEW":
        # Once review starts/completes, this can intentionally change, but the
        # manifest and assignment tracker must be updated together.
        if row.get("review_state") not in {"IN_REVIEW", "COMPLETED"}:
            fail(f"review manifest {name}: invalid review_state={row.get('review_state')!r}")

# 8) Reviewer assignment tracker denominator.
tracker = rows("REVIEWER_ASSIGNMENT_TRACKER.csv")
expected_streams = {
    "MEDICAL_GENERAL": 59,
    "MEDICAL_SAFETY": 15,
    "FIQH_HANAFI": 45,
    "FIQH_MALIKI": 45,
    "FIQH_SHAFII": 45,
    "FIQH_HANBALI": 45,
}
tracker_by_stream = {r.get("review_stream", ""): r for r in tracker}
for stream, expected_items in expected_streams.items():
    row = tracker_by_stream.get(stream)
    if row is None:
        fail(f"reviewer tracker: missing stream {stream}")
        continue
    try:
        actual = int(row.get("items", "-1"))
    except ValueError:
        actual = -1
    if actual != expected_items:
        fail(f"reviewer tracker {stream}: expected {expected_items}, got {actual}")
    status = row.get("status", "")
    if status not in {"UNASSIGNED", "ASSIGNED", "SENT", "IN_REVIEW", "COMPLETED"}:
        fail(f"reviewer tracker {stream}: invalid status={status!r}")

if errors:
    print("KB REVIEW GATE: FAIL")
    for e in errors:
        print(f"- {e}")
    sys.exit(1)

print("KB REVIEW GATE: PASS")
print("Atomic denominator: 261")
print("Fiqh evidence: 180 = 137 verified + 29 scholar clarification + 14 partial")
print("Health/Safety drafts: 74")
print("External review packets: 4×45 Fiqh + 74 medical")
