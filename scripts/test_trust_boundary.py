#!/usr/bin/env python3
"""Trust-boundary regression tests (Engineering Remediation Pass, Phase 5).

Operates directly on the real repo (read-only checks, plus regenerating the
gitignored `generated/` output via the real pipeline) rather than a throwaway
copy, since nothing here mutates a committed file.
"""
import csv
import json
import re
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KB = ROOT / 'production-readiness-results' / 'knowledge-base'

THREE_PREGNANCY_LOSS_NIFAS_IDS = {'MLK-NIFAS-29', 'SHF-NIFAS-29', 'HNB-NIFAS-29'}
FORBIDDEN_APPROVAL_STRINGS = ['SCHOLAR_APPROVED', 'MEDICALLY_APPROVED', 'Scholar-Approved', 'Medically-Approved']


def read_csv(path):
    with path.open(encoding='utf-8-sig', newline='') as f:
        return list(csv.DictReader(f))


class DispositionTrustBoundaryTest(unittest.TestCase):
    def setUp(self):
        self.master = read_csv(KB / 'PRODUCTION_DISPOSITION_MASTER.csv')

    def test_254_total_atoms_reconcile(self):
        self.assertEqual(len(self.master), 254)
        fiqh = [r for r in self.master if r['domain'] == 'FIQH']
        health = [r for r in self.master if r['domain'] == 'HEALTH_SAFETY']
        self.assertEqual(len(fiqh), 180)
        self.assertEqual(len(health), 74)

    def test_211_production_eligible_43_fail_closed(self):
        eligible = [r for r in self.master if r['production_disposition'] == 'PRODUCTION_ELIGIBLE']
        fail_closed = [r for r in self.master if r['production_disposition'] == 'FAIL_CLOSED']
        self.assertEqual(len(eligible), 211)
        self.assertEqual(len(fail_closed), 43)
        self.assertEqual(len(eligible) + len(fail_closed), 254)

    def test_every_row_human_review_status_is_not_reviewed(self):
        statuses = {r['human_review_status'] for r in self.master}
        self.assertEqual(statuses, {'NOT_REVIEWED'})

    def test_three_pregnancy_loss_nifas_rows_are_fail_closed(self):
        by_id = {r['atom_id']: r for r in self.master}
        for atom_id in THREE_PREGNANCY_LOSS_NIFAS_IDS:
            self.assertIn(atom_id, by_id, f'{atom_id} missing from disposition master')
            self.assertEqual(
                by_id[atom_id]['production_disposition'], 'FAIL_CLOSED',
                f'{atom_id} (pregnancy-loss/nifas joint scholar-and-medical review) must be FAIL_CLOSED'
            )

    def test_no_row_status_field_claims_scholar_or_medical_approval(self):
        # Checks the STRUCTURED status columns only (human_review_status,
        # production_disposition, evidence_status, internet_audit_status) --
        # never the free-text reason_for_disposition/qualifications prose,
        # which legitimately needs to say things like "no SCHOLAR_APPROVED
        # exists" (a defensive negation, not a mislabel). A substring check
        # over the whole file would false-positive on exactly that sentence.
        status_columns = ['evidence_status', 'internet_audit_status', 'human_review_status', 'production_disposition']
        for r in self.master:
            for col in status_columns:
                value = r.get(col, '')
                for forbidden in FORBIDDEN_APPROVAL_STRINGS:
                    self.assertNotIn(
                        forbidden, value,
                        f'{r["atom_id"]}.{col} = {value!r} must never claim scholar/medical approval'
                    )


class GeneratedOutputTrustBoundaryTest(unittest.TestCase):
    """Runs the real pipeline once for the whole class, then checks its output."""

    @classmethod
    def setUpClass(cls):
        result = subprocess.run(
            [sys.executable, str(ROOT / 'scripts' / 'build_kb_production_candidates.py')],
            capture_output=True, text=True, cwd=str(ROOT),
        )
        if result.returncode != 0:
            raise RuntimeError(f'build_kb_production_candidates.py failed:\n{result.stderr}')
        result = subprocess.run(
            [sys.executable, str(ROOT / 'scripts' / 'render_kb_seed_sql.py')],
            capture_output=True, text=True, cwd=str(ROOT),
        )
        if result.returncode != 0:
            raise RuntimeError(f'render_kb_seed_sql.py failed:\n{result.stderr}')
        cls.candidates = read_csv(KB / 'generated' / 'PRODUCTION_KB_CANDIDATES.csv')
        cls.quarantine = read_csv(KB / 'generated' / 'FIQH_QUARANTINE.csv')
        cls.seed_sql = (KB / 'generated' / 'PRODUCTION_KB_SEED.sql').read_text(encoding='utf-8')

    def test_three_pregnancy_loss_nifas_rows_are_quarantined_not_candidates(self):
        candidate_keys = {c['knowledge_key'] for c in self.candidates}
        quarantine_keys = {q['review_id'] for q in self.quarantine}
        for atom_id in THREE_PREGNANCY_LOSS_NIFAS_IDS:
            self.assertNotIn(atom_id, candidate_keys)
            self.assertIn(atom_id, quarantine_keys)

    def test_all_four_qualified_health_rows_carry_their_qualification_note(self):
        expected = {
            'HL-MENS-002': 'Population-level general guidance only; never an individual diagnostic boundary.',
            'HL-MENS-003': (
                "Escalation/education threshold, not a diagnosis. Threshold value is source-specific "
                "(8 days in OWH vs NHS's 7-day heavy-bleeding definition)."
            ),
            'HL-TTC-011': 'General referral-timing guidance.',
            'HL-PREG-012': 'Saudi-market localization, explicitly scoped as such in the corrected wording.',
        }
        by_key = {c['knowledge_key']: c for c in self.candidates}
        for atom_id, qualification in expected.items():
            self.assertIn(atom_id, by_key)
            self.assertEqual(
                by_key[atom_id]['qualification_note'], qualification,
                f'{atom_id} must carry its qualification unflattened into the candidate row',
            )

    def test_qualification_note_survives_into_rendered_seed_sql(self):
        self.assertIn(
            'Population-level general guidance only; never an individual diagnostic boundary.',
            self.seed_sql,
            'HL-MENS-002 qualification must reach the rendered SQL insert, not be dropped at this stage',
        )

    def test_no_fail_closed_status_strings_leak_into_seed_sql(self):
        for forbidden in ['SCHOLAR_CLARIFICATION_REQUIRED', 'PARTIAL_EVIDENCE'] + FORBIDDEN_APPROVAL_STRINGS:
            self.assertNotIn(forbidden, self.seed_sql)

    def test_seed_sql_registers_exactly_one_current_snapshot(self):
        self.assertEqual(self.seed_sql.count('is_current = false where is_current'), 1)
        self.assertEqual(self.seed_sql.count("true\n);"), 1)

    def test_citations_dedupe_key_never_includes_free_text_that_could_be_model_output(self):
        # Structural guarantee, not a runtime one: citationPayload's TypeScript
        # signature (kb_retrieval.ts) takes only KnowledgeHit[] -- there is no
        # parameter through which model-generated text could reach a citation.
        kb_retrieval = (ROOT / 'supabase' / 'functions' / '_shared' / 'kb_retrieval.ts').read_text(encoding='utf-8')
        match = re.search(r'export function citationPayload\(([^)]*)\)', kb_retrieval)
        self.assertIsNotNone(match, 'citationPayload signature not found')
        self.assertEqual(match.group(1).strip(), 'hits: KnowledgeHit[]')


class RetrievalSqlMadhhabBoundaryTest(unittest.TestCase):
    """Static checks on the migration's SQL text -- the closest thing to a
    Madhhab cross-leakage test available without a live Postgres instance."""

    def setUp(self):
        migration = ROOT / 'supabase' / 'migrations' / '20260929120000_knowledge_base_v1_qualification_and_snapshot.sql'
        self.sql = migration.read_text(encoding='utf-8')

    def test_fiqh_domain_requires_exact_madhhab_match_with_no_fallback(self):
        self.assertIn("p_madhhab is not null and ki.madhhab = lower(p_madhhab)", self.sql)

    def test_no_coalesce_or_default_madhhab_value_exists_in_the_filter(self):
        # A silent default (e.g. coalescing an unset madhhab to 'hanafi')
        # would be exactly the cross-madhhab leak this test exists to catch.
        madhhab_filter_section = self.sql[self.sql.index('p_domain <> \'FIQH\''):]
        madhhab_filter_section = madhhab_filter_section[:madhhab_filter_section.index(')\n      )')]
        self.assertNotIn('coalesce', madhhab_filter_section.lower())

    def test_retrieval_is_gated_on_the_active_snapshot_registry(self):
        self.assertIn('kiv.evidence_snapshot_commit = (select commit_sha from active_snapshot)', self.sql)
        self.assertIn('where exists (select 1 from active_snapshot)', self.sql)


if __name__ == '__main__':
    unittest.main()
