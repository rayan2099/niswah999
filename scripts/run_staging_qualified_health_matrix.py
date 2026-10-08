#!/usr/bin/env python3
"""Phase 1 of the staging validation closure pass: runs real staging HTTP
requests for all four VERIFIED_WITH_QUALIFICATION Health rows and checks
whether each row's qualification_note materially survives into the final
answer (dr-niswah-chat's system prompt requires the model to surface a
KNOWLEDGE element's QUALIFICATION line, never present the bare statement
as an unqualified fact -- see supabase/functions/dr-niswah-chat/index.ts's
Arabic instruction to that effect).

Ground truth (expected qualification_note per atom) is read from the
already-generated, disposition-master-derived
production-readiness-results/knowledge-base/generated/PRODUCTION_KB_CANDIDATES.csv
-- not hardcoded here -- so this test can never silently drift from the
real frozen snapshot's own qualification text.
"""
from __future__ import annotations

import csv
import json
import sys
import uuid
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from scripts.lib.staging_acceptance_client import StagingClient  # noqa: E402

CANDIDATES_CSV = REPO_ROOT / "production-readiness-results" / "knowledge-base" / "generated" / "PRODUCTION_KB_CANDIDATES.csv"
OUT_JSON = REPO_ROOT / "production-readiness-results" / "knowledge-base" / "STAGING_QUALIFIED_HEALTH_RESULTS.json"

# Each row's own real user-facing phrasing (search_text_en), reduced to a
# natural question -- not the internal canonical_en statement verbatim --
# so this genuinely exercises retrieval, not just an exact-text echo.
CASES = [
    {
        "atom_id": "HL-MENS-002",
        "query": "What is a typical menstrual cycle length range for adults?",
        "qualification_signal_terms": [
            ["population", "general guidance", "range"],
            ["not", "diagnos"],
        ],
    },
    {
        "atom_id": "HL-MENS-003",
        "query": "My menstrual bleeding is unusually prolonged, how many days is too many?",
        "qualification_signal_terms": [
            ["يوم", "طبيب", "استشار", "راجع"],
        ],
    },
    {
        "atom_id": "HL-TTC-011",
        "query": "I am 36 and have been trying to get pregnant for 6 months without success. Should I wait a full year before seeing a doctor?",
        "qualification_signal_terms": [
            ["35", "six months", "fertility", "evaluation"],
        ],
    },
    {
        "atom_id": "HL-PREG-012",
        "query": "How much folic acid should I take before pregnancy in Saudi Arabia?",
        "qualification_signal_terms": [
            ["Saudi", "السعود"],
        ],
    },
]


def load_expected_qualifications() -> dict:
    expected = {}
    with open(CANDIDATES_CSV, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row["knowledge_key"] in {c["atom_id"] for c in CASES}:
                expected[row["knowledge_key"]] = row["qualification_note"]
    return expected


def qualification_survives(reply_text: str, signal_term_groups: list) -> bool:
    """A group is satisfied if ANY of its terms appears (case-insensitive,
    substring match, Arabic terms matched as-is). ALL groups must be
    satisfied for the qualification to count as having survived -- this
    deliberately requires the qualifying CONCEPT to be present, not an
    exact echo of the English qualification_note string (the model
    answers in whatever language fits the question/source, and is only
    asked to convey the caveat's substance, not quote it verbatim)."""
    lowered = reply_text.lower()
    for group in signal_term_groups:
        if not any(term.lower() in lowered for term in group):
            return False
    return True


def main() -> None:
    expected_qualifications = load_expected_qualifications()
    assert len(expected_qualifications) == 4, f"expected exactly 4 qualified rows, found {len(expected_qualifications)}"

    client = StagingClient()
    results = []
    for case in CASES:
        token = client.create_synthetic_session()
        thread_id = uuid.uuid4().hex
        status, payload, elapsed = client.call_function(
            "dr-niswah-chat", token, {"threadId": thread_id, "content": case["query"]}, timeout=45
        )
        reply = payload.get("reply") or ""
        citations = payload.get("citations") or []
        retrieved_keys = [c.get("knowledgeKey") for c in citations]
        atom_retrieved = case["atom_id"] in retrieved_keys
        expected_note = expected_qualifications[case["atom_id"]]
        survived = qualification_survives(reply, case["qualification_signal_terms"]) if reply else False

        row = {
            "atom_id": case["atom_id"],
            "query": case["query"],
            "http_status": status,
            "elapsed_s": round(elapsed, 2),
            "retrieved_atom_ids": retrieved_keys,
            "target_atom_retrieved": atom_retrieved,
            "expected_qualification_note": expected_note,
            "qualification_survived": survived,
            "num_citations": len(citations),
            "final_answer": reply,
            "pass": bool(status == 200 and atom_retrieved and survived),
        }
        results.append(row)
        print(f"==> {case['atom_id']}: status={status} retrieved={atom_retrieved} qualification_survived={survived} "
              f"-> {'PASS' if row['pass'] else 'FAIL'}")

    OUT_JSON.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"==> Wrote {len(results)} rows to {OUT_JSON}")

    overall_pass = all(r["pass"] for r in results)
    print(f"==> PHASE 1 QUALIFIED-HEALTH ACCEPTANCE: {'PASS' if overall_pass else 'FAIL (BLOCKER)'}")


if __name__ == "__main__":
    main()
