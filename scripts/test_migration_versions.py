from pathlib import Path
import tempfile
import unittest

from scripts.check_migration_versions import duplicate_versions


class MigrationVersionTests(unittest.TestCase):
    def test_parallel_community_and_split_migrations_collide(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            names = ['20261030090000_community_ugc_safety.sql',
                     '20261030090000_bleeding_episode_split_merge.sql']
            for name in names:
                (directory / name).touch()
            self.assertEqual(duplicate_versions(directory), {'20261030090000': sorted(names)})

    def test_renamed_split_and_community_have_distinct_versions(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            for name in ['20261030090000_community_ugc_safety.sql',
                         '20261030012106_bleeding_episode_split_merge.sql',
                         '20261029130000_bleeding_episode_end_unknown.sql']:
                (directory / name).touch()
            self.assertEqual(duplicate_versions(directory), {})


if __name__ == '__main__':
    unittest.main()
