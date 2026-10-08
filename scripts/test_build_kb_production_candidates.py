#!/usr/bin/env python3
"""Regression tests for build_kb_production_candidates.py.

Runs the real script (via subprocess, against a throwaway copy of the repo
tree) so these tests exercise the actual code path, not a reimplementation
of it. Each negative test corrupts exactly one thing the script is required
to catch and asserts it fails loudly with a specific, matching message
before writing any output.
"""
import csv
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
KB_SRC = REPO_ROOT / 'production-readiness-results' / 'knowledge-base'


class BuildKbProductionCandidatesTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix='kb_builder_test_')
        self.root = Path(self.tmp)
        (self.root / 'scripts').mkdir()
        shutil.copy2(
            REPO_ROOT / 'scripts' / 'build_kb_production_candidates.py',
            self.root / 'scripts' / 'build_kb_production_candidates.py',
        )
        dest_kb = self.root / 'production-readiness-results' / 'knowledge-base'
        shutil.copytree(KB_SRC, dest_kb)
        self.kb = dest_kb
        # Never inherit a stale `generated/` from a prior real run of the
        # script against the actual repo -- each test must start from a
        # clean slate and prove ITS OWN run produced (or didn't produce) output.
        shutil.rmtree(self.kb / 'generated', ignore_errors=True)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_script(self):
        return subprocess.run(
            [sys.executable, str(self.root / 'scripts' / 'build_kb_production_candidates.py')],
            capture_output=True, text=True, cwd=str(self.root),
        )

    def read_master(self):
        with (self.kb / 'PRODUCTION_DISPOSITION_MASTER.csv').open(encoding='utf-8') as f:
            return list(csv.DictReader(f))

    def read_generated_csv(self, name):
        with (self.kb / 'generated' / name).open(encoding='utf-8') as f:
            return list(csv.DictReader(f))

    def write_master(self, rows):
        with (self.kb / 'PRODUCTION_DISPOSITION_MASTER.csv').open('w', newline='', encoding='utf-8') as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            w.writeheader()
            w.writerows(rows)

    # ---- baseline: the real, unmodified snapshot must build cleanly ----

    def test_baseline_succeeds_with_211_eligible_43_failclosed(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)
        self.assertIn('211 production candidates', result.stdout)
        self.assertIn('43 quarantined', result.stdout)
        self.assertIn('4 carrying a qualification_note', result.stdout)

        candidates = self.read_generated_csv('PRODUCTION_KB_CANDIDATES.csv')
        quarantine = self.read_generated_csv('FIQH_QUARANTINE.csv')
        self.assertEqual(len(candidates), 211)
        self.assertEqual(len(quarantine), 43)
        self.assertEqual(len(candidates) + len(quarantine), 254)
        # zero overlap
        self.assertEqual(
            {c['knowledge_key'] for c in candidates} & {q['review_id'] for q in quarantine},
            set(),
        )

    def test_baseline_hl_mens_002_carries_qualification_note(self):
        self.run_script()
        candidates = self.read_generated_csv('PRODUCTION_KB_CANDIDATES.csv')
        row = next(c for c in candidates if c['knowledge_key'] == 'HL-MENS-002')
        self.assertEqual(
            row['qualification_note'],
            'Population-level general guidance only; never an individual diagnostic boundary.',
        )
        self.assertTrue(row['evidence_snapshot_commit'])

    def test_all_fail_closed_fiqh_rows_land_in_quarantine_never_candidates(self):
        self.run_script()
        master = self.read_master()
        expected_fail_closed = {r['atom_id'] for r in master if r['production_disposition'] == 'FAIL_CLOSED'}
        candidates = self.read_generated_csv('PRODUCTION_KB_CANDIDATES.csv')
        quarantine = self.read_generated_csv('FIQH_QUARANTINE.csv')
        self.assertEqual({q['review_id'] for q in quarantine}, expected_fail_closed)
        self.assertEqual({c['knowledge_key'] for c in candidates} & expected_fail_closed, set())

    # ---- required failure modes (Phase 1 spec) ----

    def test_fails_on_duplicate_atom_id(self):
        master = self.read_master()
        # Overwrite the last row's ID with the first row's ID -- keeps the
        # total at 254 so this isolates the duplicate-ID check specifically,
        # rather than also tripping the row-count check.
        master[-1]['atom_id'] = master[0]['atom_id']
        self.write_master(master)
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('DUPLICATE ATOM IDs', result.stderr)

    def test_fails_when_total_row_count_is_not_254(self):
        master = self.read_master()
        self.write_master(master[:-1])  # drop one row
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('ROW COUNT MISMATCH', result.stderr)

    def test_fails_on_unknown_disposition_value(self):
        master = self.read_master()
        master[0]['production_disposition'] = 'SCHOLAR_APPROVED'
        self.write_master(master)
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('UNKNOWN production_disposition', result.stderr)
        self.assertIn('SCHOLAR_APPROVED', result.stderr)

    def test_fails_when_atom_missing_from_master(self):
        master = self.read_master()
        removed_id = master[0]['atom_id']
        self.write_master(master[1:])
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        # row-count check fires first (253 != 254); still a correct, loud failure.
        self.assertTrue(
            'ROW COUNT MISMATCH' in result.stderr or 'MISSING FROM DISPOSITION MASTER' in result.stderr
        )

    def test_fails_when_master_has_orphaned_atom_id(self):
        # Simulates a manifest that WAS re-frozen against a master.csv that
        # still has an orphaned atom_id in it -- isolates the atom-universe
        # check from the (separately-tested) checksum-drift check by keeping
        # the manifest's recorded master checksum in sync with the mutation.
        master = self.read_master()
        fabricated = dict(master[0])
        fabricated['atom_id'] = 'FAKE-ATOM-DOES-NOT-EXIST-999'
        master[-1] = fabricated  # replace instead of append, to isolate the orphan check from the row-count check
        self.write_master(master)

        manifest_path = self.kb / 'EVIDENCE_SNAPSHOT_FREEZE_MANIFEST.json'
        manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
        new_sha = self._sha256(self.kb / 'PRODUCTION_DISPOSITION_MASTER.csv')
        manifest['production_disposition_master']['sha256'] = new_sha
        for artifact in manifest['source_artifact_versions']:
            if artifact['path'].endswith('PRODUCTION_DISPOSITION_MASTER.csv'):
                artifact['sha256'] = new_sha
        manifest_path.write_text(json.dumps(manifest, indent=2), encoding='utf-8')

        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(
            'ORPHANED ATOM' in result.stderr or 'MISSING FROM DISPOSITION MASTER' in result.stderr,
            msg=result.stderr,
        )

    @staticmethod
    def _sha256(path: Path) -> str:
        import hashlib
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def test_fails_on_frozen_artifact_checksum_mismatch(self):
        # Mutate a frozen source artifact's content without touching the manifest.
        pack = self.kb / 'HANAFI_EVIDENCE_PACK.csv'
        pack.write_text(pack.read_text(encoding='utf-8') + '\n# tampered\n', encoding='utf-8')
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('FROZEN SNAPSHOT CHECKSUM MISMATCH', result.stderr)
        self.assertIn('HANAFI_EVIDENCE_PACK.csv', result.stderr)

    def test_fails_when_disposition_master_itself_drifts_from_its_recorded_checksum(self):
        master = self.read_master()
        master[0]['reason_for_disposition'] = 'tampered without updating the freeze manifest'
        self.write_master(master)
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('FROZEN SNAPSHOT CHECKSUM MISMATCH', result.stderr)
        self.assertIn('PRODUCTION_DISPOSITION_MASTER.csv', result.stderr)

    def test_no_output_written_when_a_check_fails(self):
        master = self.read_master()
        master[0]['production_disposition'] = 'NOT_A_REAL_VALUE'
        self.write_master(master)
        self.run_script()
        self.assertFalse((self.kb / 'generated' / 'PRODUCTION_KB_CANDIDATES.csv').exists())
        self.assertFalse((self.kb / 'generated' / 'FIQH_QUARANTINE.csv').exists())


if __name__ == '__main__':
    unittest.main()
