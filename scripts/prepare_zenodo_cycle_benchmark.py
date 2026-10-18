#!/usr/bin/env python3
"""Prepare the pinned, public CC BY 4.0 research release outside the checkout.

Source: Forster & Mitesser, https://doi.org/10.5281/zenodo.15598359 (v1).
The associated paper reports written consent; see docs/external-cycle-benchmark.md.
Never commit either the source CSV or the generated date histories.
"""

import argparse
import csv
import hashlib
import io
import json
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from statistics import median

SOURCE_SHA256 = "7712b11290d2d34384eaa3bca02739067a0dd6ddc8bd90c6fe91c545efffe28f"


def prepare(source: Path, output: Path):
    repo = Path(__file__).resolve().parents[1]
    if output.resolve() == repo or repo in output.resolve().parents:
        raise ValueError("Health-history output must be outside the checkout")
    raw = source.read_bytes()
    if hashlib.sha256(raw).hexdigest() != SOURCE_SHA256:
        raise ValueError("Source does not match the pinned release")
    dates = defaultdict(set)
    studies = defaultdict(set)
    excluded = set()
    rows = duplicates = 0
    for row in csv.DictReader(io.StringIO(raw.decode("utf-8-sig")), delimiter=";"):
        rows += 1
        key = row["Woman"]
        if not key:
            raise ValueError("Missing source identifier")
        date = datetime.strptime(row["Date"], "%d.%m.%Y").date()
        studies[key].add(row["Study"])
        flags = [row[k] for k in ("BeforeBirth", "AfterBirth", "Birth")]
        if any(flag not in ("0", "1") for flag in flags):
            raise ValueError("Unexpected birth-related flag encoding")
        if "1" in flags:
            excluded.add(key)
        if date in dates[key]:
            duplicates += 1
        dates[key].add(date)
    # Preserve source encounter order; output no identifiers or demographics.
    eligible = [key for key in dates if key not in excluded]
    if any(studies[key] not in ({"old"}, {"new"}) for key in eligible):
        raise ValueError("Unexpected study membership")
    output.mkdir(parents=True, exist_ok=True)
    for suffix, keys in (
        ("", eligible),
        ("-old", [key for key in eligible if studies[key] == {"old"}]),
        ("-new", [key for key in eligible if studies[key] == {"new"}]),
    ):
        histories = [[d.isoformat() for d in sorted(dates[key])] for key in keys]
        (output / f"zenodo-unflagged{suffix}.json").write_text(
            json.dumps(histories, separators=(",", ":")) + "\n"
        )
    intervals = [
        (b - a).days
        for key in eligible
        for a, b in zip(sorted(dates[key]), sorted(dates[key])[1:])
    ]
    summary = {
        "sourceDOI": "10.5281/zenodo.15598359",
        "sourceSHA256": SOURCE_SHA256,
        "sourceRows": rows,
        "sourceIDs": len(dates),
        "sourceDuplicateDates": duplicates,
        "excludedIDsWithBirthRelatedFlags": len(excluded),
        "primaryHistories": len(eligible),
        "primaryStarts": sum(len(dates[key]) for key in eligible),
        "primaryIntervals": len(intervals),
        "minimumIntervalDays": min(intervals),
        "maximumIntervalDays": max(intervals),
        "intervalsBelow15Days": sum(x < 15 for x in intervals),
        "intervalsAbove90Days": sum(x > 90 for x in intervals),
        "medianStartsPerHistory": median(len(dates[key]) for key in eligible),
        "cohortRule": "Exclude whole source IDs with any birth-related flag; deduplicate same-ID dates; no gap trimming or outcome-based exclusions. IDs are not verified unique participants.",
    }
    (output / "preparation-aggregate.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_csv", type=Path)
    parser.add_argument("output_directory", type=Path)
    args = parser.parse_args()
    try:
        prepare(args.source_csv, args.output_directory)
    except (ValueError, KeyError, OSError, UnicodeError):
        parser.exit(1, "Preparation failed: check pinned source, schema, and external output location.\n")
