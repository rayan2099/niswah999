#!/usr/bin/env python3
"""Phase 5 of the staging validation closure pass: deep citation-shape
validation. For a representative case per Madhhab plus one qualified
Health case, cross-references every citation the deployed Edge Function
actually returns against the ground-truth
production-readiness-results/knowledge-base/generated/PRODUCTION_KB_CANDIDATES.csv
(the disposition-master-derived source of truth for every production-
eligible atom) to verify: the knowledgeKey exists in the frozen
candidate set at all (no model-invented citation), its title/locator/url
match that atom's own recorded primary source exactly (no transformation
dropped or altered the locator), and -- for Fiqh rows -- the atom's own
knowledge_key madhhab prefix matches the madhhab the question was asked
under (no cross-madhhab citation).
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
OUT_JSON = REPO_ROOT / "production-readiness-results" / "knowledge-base" / "STAGING_CITATION_SHAPE_RESULTS.json"

CASES = [
    {"id": "CITE-hanafi", "fn": "fiqh-advisor-chat", "madhhab": "hanafi",
     "question": "What happens if bleeding goes beyond ten days?"},
    {"id": "CITE-maliki", "fn": "fiqh-advisor-chat", "madhhab": "maliki",
     "question": "If my bleeding continues beyond my usual longest period, what is the ruling?"},
    {"id": "CITE-shafii", "fn": "fiqh-advisor-chat", "madhhab": "shafii",
     "question": "What is the minimum duration of haid?"},
    {"id": "CITE-hanbali", "fn": "fiqh-advisor-chat", "madhhab": "hanbali",
     "question": "What is the maximum duration of haid?"},
    {"id": "CITE-health-qualified", "fn": "dr-niswah-chat", "madhhab": None,
     "question": "What is a typical menstrual cycle length range for adults?"},
]

MADHHAB_PREFIX = {"hanafi": "HNF", "maliki": "MLK", "shafii": "SHF", "hanbali": "HNB"}


def load_ground_truth() -> dict:
    with open(CANDIDATES_CSV, encoding="utf-8") as f:
        return {row["knowledge_key"]: row for row in csv.DictReader(f)}


def main() -> None:
    ground_truth = load_ground_truth()
    client = StagingClient()
    results = []

    for case in CASES:
        token = client.create_synthetic_session()
        if case["fn"] == "fiqh-advisor-chat":
            body = {"question": case["question"], "madhhab": case["madhhab"],
                     "madhhab_state": "selected", "clientFiqhState": "tahara"}
        else:
            body = {"threadId": uuid.uuid4().hex, "content": case["question"]}
        status, payload, elapsed = client.call_function(case["fn"], token, body, timeout=45)
        citations = payload.get("citations") or []

        case_findings = []
        for c in citations:
            key = c.get("knowledgeKey")
            finding = {"knowledgeKey": key}
            truth = ground_truth.get(key)
            if truth is None:
                finding["verdict"] = "FABRICATED_OR_UNKNOWN_KEY"
                case_findings.append(finding)
                continue

            title_matches = c.get("title") == truth["primary_source_title"]
            locator_matches = c.get("locator") == truth["primary_locator"]
            url_matches = c.get("url") == truth["primary_url"]
            source_key_matches = c.get("sourceKey") == truth["primary_source_key"]
            has_locator = bool(c.get("locator"))

            madhhab_ok = True
            if case["madhhab"] is not None:
                expected_prefix = MADHHAB_PREFIX[case["madhhab"]]
                madhhab_ok = key.startswith(expected_prefix) or truth.get("madhhab") == case["madhhab"]

            finding.update({
                "title_matches_ground_truth": title_matches,
                "locator_matches_ground_truth": locator_matches,
                "url_matches_ground_truth": url_matches,
                "source_key_matches_ground_truth": source_key_matches,
                "has_locator": has_locator,
                "madhhab_consistent": madhhab_ok,
                "verdict": "OK" if (title_matches and locator_matches and url_matches
                                     and source_key_matches and has_locator and madhhab_ok)
                           else "MISMATCH",
            })
            case_findings.append(finding)

        all_ok = bool(citations) and all(f["verdict"] == "OK" for f in case_findings)
        results.append({
            "id": case["id"], "fn": case["fn"], "madhhab": case["madhhab"],
            "question": case["question"], "http_status": status,
            "num_citations": len(citations), "citation_findings": case_findings,
            "pass": all_ok,
        })
        print(f"==> {case['id']}: {len(citations)} citations, "
              f"{'ALL OK' if all_ok else 'FAIL — see findings'}")

    OUT_JSON.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"==> Wrote {len(results)} rows to {OUT_JSON}")
    overall = all(r["pass"] for r in results)
    print(f"==> PHASE 5 CITATION SHAPE VALIDATION: {'PASS' if overall else 'FAIL'}")


if __name__ == "__main__":
    main()
