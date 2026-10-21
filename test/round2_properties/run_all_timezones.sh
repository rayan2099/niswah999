#!/usr/bin/env bash
# Runs the round-2 property suite under each time zone and compares the
# R2_DIGEST lines (identical digests = identical engine outputs).
# Usage: test/round2_properties/run_all_timezones.sh  (from the repo root)
set -u
zones=(UTC Europe/London America/New_York Asia/Riyadh Pacific/Auckland)
out_dir="${TMPDIR:-/tmp}/round2_properties"
mkdir -p "$out_dir"
for tz in "${zones[@]}"; do
  safe="${tz//\//_}"
  TZ="$tz" flutter test test/round2_properties/ >"$out_dir/$safe.log" 2>&1
  echo "== $tz: $(grep -E '^[0-9:]+ \+[0-9]+.*(All tests passed|Some tests failed)' "$out_dir/$safe.log" | tail -1)"
  grep -E '^PROPERTY .*failingHistories=[1-9]|^PROPERTY \[F9 sweep\]' "$out_dir/$safe.log" | sed 's/^/   /'
  grep '^R2_DIGEST' "$out_dir/$safe.log" | sed "s|^|   |"
done
echo "== distinct digests:"
grep -h '^R2_DIGEST' "$out_dir"/*.log | sort | uniq -c
