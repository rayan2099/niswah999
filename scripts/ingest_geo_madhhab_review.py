#!/usr/bin/env python3
"""Imports a qualified scholar's reviewer decisions from a reviewed copy of
one of the geographic Madhhab reviewer CSVs (the full packet, the focused
QA batch, or the high-confidence batch -- any file sharing the same
`mapping_id`/`reviewer_decision`/`reviewer_name`/`reviewer_date`/
`reviewer_notes` columns) back into
production-readiness-results/fiqh-engine/geographic_madhhab_mapping.json.

This is the ONLY supported way to change an `evidence_status` value in
that file to SCHOLAR_REVIEWED or REJECTED -- never edit it by hand, so
every scholar decision is traceable to an actual reviewer_name +
reviewer_date, not a guess. It is NOT used to set SOURCE_VERIFIED -- that
tier comes from the separate, internet-research-based verification pass
(see the Knowledge-Base Source-Verification wave's research report),
applied directly to the dataset with real source citations, not through
this reviewer-decision CSV flow. The two tiers are both eligible to
surface a suggestion at runtime, but have different provenance and must
never be confused with each other.

Deliberately does NOT touch madhhab_suggestion_service.dart's Dart mirror.
A decision recorded here does not, by itself, change what the app shows --
the corresponding `_MappingEntry` in that file still needs its own
`evidenceStatus` updated by an engineer as a separate, explicit step. This
script prints a reminder listing exactly which entries need that
follow-up (only ever for SCHOLAR_REVIEWED rows; a REJECT needs no Dart
follow-up since a rejected entry was never eligible to surface anyway).

Safety:
  - Dry-run by default. Nothing is written to geographic_madhhab_mapping.json
    unless --apply is passed.
  - Validates every row BEFORE writing anything. If any row is malformed,
    nothing is written at all, even for the rows that were fine -- the
    whole batch is refused, so a partial/silent apply can never happen.
  - A blank reviewer_decision is a no-op (not reviewed yet), never treated
    as any kind of decision.
  - REVISE never auto-edits likely_madhahib/confidence from free-text notes
    -- it only records that a revision was requested, for an engineer to
    apply by hand after reading reviewer_notes.

Usage:
  python3 scripts/ingest_geo_madhhab_review.py <reviewed.csv>              # dry-run report only
  python3 scripts/ingest_geo_madhhab_review.py <reviewed.csv> --apply      # writes the JSON file
"""

import csv
import json
import sys
from datetime import datetime

JSON_PATH = "production-readiness-results/fiqh-engine/geographic_madhhab_mapping.json"
VALID_DECISIONS = {"APPROVE", "REJECT", "REVISE"}
REQUIRED_COLUMNS = {"mapping_id", "reviewer_decision", "reviewer_name", "reviewer_date", "reviewer_notes"}

DECISION_TO_EVIDENCE_STATUS = {
    "APPROVE": "SCHOLAR_REVIEWED",
    "REJECT": "REJECTED",
    "REVISE": "REVISION_REQUESTED",
}


def load_json():
    with open(JSON_PATH) as f:
        return json.load(f)


def validate_rows(rows, by_id):
    """Returns (problems, decisions). `problems` is a list of human-readable
    strings; if non-empty, the caller must refuse to write anything at all."""
    problems = []
    decisions = []  # list of (mapping_id, decision, name, date, notes)
    seen_ids = set()

    for i, row in enumerate(rows, start=2):  # row 1 is the header
        mapping_id = (row.get("mapping_id") or "").strip()
        decision = (row.get("reviewer_decision") or "").strip()
        name = (row.get("reviewer_name") or "").strip()
        date = (row.get("reviewer_date") or "").strip()
        notes = (row.get("reviewer_notes") or "").strip()

        if not mapping_id:
            problems.append(f"row {i}: missing mapping_id entirely")
            continue

        if not decision:
            # No decision yet -- a legitimate, common, non-error state.
            # Not added to `decisions`; changes nothing.
            continue

        if mapping_id in seen_ids:
            problems.append(f"row {i} ({mapping_id}): duplicate mapping_id with a decision in this file -- refusing, ambiguous which one wins")
            continue
        seen_ids.add(mapping_id)

        if mapping_id not in by_id:
            problems.append(f"row {i} ({mapping_id}): no such mapping_id in {JSON_PATH} -- refusing (typo, or reviewing a stale export?)")
            continue

        if decision not in VALID_DECISIONS:
            problems.append(f"row {i} ({mapping_id}): reviewer_decision is '{decision}', must be exactly one of {sorted(VALID_DECISIONS)} (case-sensitive) or left blank")
            continue

        if not name:
            problems.append(f"row {i} ({mapping_id}): reviewer_decision='{decision}' but reviewer_name is blank -- every decision must be attributed to a real reviewer")
            continue

        if not date:
            problems.append(f"row {i} ({mapping_id}): reviewer_decision='{decision}' but reviewer_date is blank")
            continue
        try:
            datetime.strptime(date, "%Y-%m-%d")
        except ValueError:
            problems.append(f"row {i} ({mapping_id}): reviewer_date '{date}' is not a valid YYYY-MM-DD date")
            continue

        entry = by_id[mapping_id]
        if decision == "APPROVE" and not entry["likely_madhahib"]:
            problems.append(
                f"row {i} ({mapping_id}, {entry['country']}): cannot APPROVE -- this entry's "
                f"likely_madhahib is empty (classification={entry['classification']}, "
                f"unresolved_reason={entry['unresolved_reason']}). There is nothing to approve "
                f"a suggestion of. If you believe a specific madhhab should be suggested here "
                f"after all, use REVISE with the proposed madhhab in reviewer_notes instead."
            )
            continue

        decisions.append((mapping_id, decision, name, date, notes))

    return problems, decisions


def apply_decisions(data, decisions):
    by_id = {m["mapping_id"]: m for m in data["mappings"]}
    diffs = []
    dart_followups = []

    for mapping_id, decision, name, date, notes in decisions:
        entry = by_id[mapping_id]
        before_status = entry["evidence_status"]
        before_record = entry.get("scholar_review_record")

        new_status = DECISION_TO_EVIDENCE_STATUS[decision]

        entry["evidence_status"] = new_status
        entry["scholar_review_record"] = {
            "decision": decision,
            "reviewer_name": name,
            "reviewer_date": date,
            "reviewer_notes": notes,
        }

        diffs.append(
            {
                "mapping_id": mapping_id,
                "country": entry["country"],
                "region": entry["region"],
                "before_evidence_status": before_status,
                "after_evidence_status": new_status,
                "before_scholar_review_record": before_record,
                "after_scholar_review_record": entry["scholar_review_record"],
            }
        )

        if decision == "APPROVE":
            dart_followups.append((mapping_id, entry["country"], entry["region"]))

    return diffs, dart_followups


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)

    csv_path = sys.argv[1]
    apply_mode = "--apply" in sys.argv[2:]

    with open(csv_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        missing_cols = REQUIRED_COLUMNS - set(reader.fieldnames or [])
        if missing_cols:
            print(f"REFUSING: '{csv_path}' is missing required column(s): {sorted(missing_cols)}")
            sys.exit(1)
        rows = list(reader)

    data = load_json()
    by_id = {m["mapping_id"]: m for m in data["mappings"]}

    problems, decisions = validate_rows(rows, by_id)

    if problems:
        print("=" * 70)
        print(f"REFUSING TO APPLY ANYTHING — {len(problems)} problem(s) found in '{csv_path}'")
        print("=" * 70)
        for p in problems:
            print(f"  - {p}")
        print()
        print("Nothing was written. Fix every problem above and re-run.")
        sys.exit(1)

    if not decisions:
        print(f"'{csv_path}': every row's reviewer_decision is blank — nothing to do, nothing written.")
        sys.exit(0)

    diffs, dart_followups = apply_decisions(data, decisions)

    print("=" * 70)
    print(f"{'APPLYING' if apply_mode else 'DRY RUN — would apply'} {len(diffs)} reviewer decision(s)")
    print("=" * 70)
    for d in diffs:
        region_suffix = f" / {d['region']}" if d["region"] else ""
        print(
            f"  {d['mapping_id']} ({d['country']}{region_suffix}): "
            f"evidence_status {d['before_evidence_status']!r} -> {d['after_evidence_status']!r} "
            f"(decision={d['after_scholar_review_record']['decision']}, "
            f"by {d['after_scholar_review_record']['reviewer_name']} on {d['after_scholar_review_record']['reviewer_date']})"
        )

    if dart_followups:
        print()
        print(f"REMINDER — {len(dart_followups)} entr{'y' if len(dart_followups) == 1 else 'ies'} "
              f"scholar-approved here still need a manual follow-up in "
              f"lib/features/onboarding/domain/services/madhhab_suggestion_service.dart:")
        print("  A SCHOLAR_REVIEWED status in this JSON file does NOT make a suggestion appear in")
        print("  the app by itself -- the matching _MappingEntry's `evidenceStatus` field (default")
        print("  'UNVERIFIED') must also be explicitly set to 'SCHOLAR_REVIEWED', by an engineer, as")
        print("  its own separate, deliberate step. Entries needing that edit:")
        for mapping_id, country, region in dart_followups:
            region_suffix = f" / {region}" if region else ""
            print(f"    - {mapping_id} ({country}{region_suffix})")

    print()
    if apply_mode:
        with open(JSON_PATH, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
        print(f"Written to {JSON_PATH}.")
    else:
        print("This was a DRY RUN. Nothing was written. Re-run with --apply to write these changes.")


if __name__ == "__main__":
    main()
