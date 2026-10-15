"""Cross-platform navigation regressions; uses synthetic repository paths."""
import unittest
import ntpath
from unittest.mock import patch
from scripts import sync_project_vault as vault


class NavigationTests(unittest.TestCase):
    def test_links_do_not_depend_on_native_relpath(self):
        with patch('os.path', ntpath):
            self.assertEqual(
                vault.link('project-hub/generated/Documents.md', 'docs/Arabic note.md'),
                '[Arabic note.md](../../docs/Arabic%20note.md)',
            )

    def test_unicode_and_parentheses_in_links(self):
        result = vault.link('project-hub/Home.md', 'docs/حيض (review).md')
        self.assertNotIn('\\', result)
        self.assertIn('%28review%29.md)', result)
        self.assertIn('%D8', result)

    def test_directory_headings_use_repository_separators(self):
        files = ['production-readiness/MDs/Example.md', 'lib/features/auth/screen.dart']
        output = vault.generate(files)
        self.assertIn('## production-readiness/MDs\n', output['project-hub/generated/Documents.md'])
        self.assertNotIn('%5C', ''.join(output.values()))
        self.assertEqual(output, vault.generate(files))

    def test_missing_local_link_is_rejected(self):
        output = {'project-hub/generated/Test.md': '[Missing](definitely-missing.md)'}
        self.assertTrue(any('definitely-missing.md' in e for e in vault.verify_links(output)))


if __name__ == '__main__':
    unittest.main()
