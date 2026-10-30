"""Reject active migrations sharing a Supabase migration version."""
from collections import defaultdict
from pathlib import Path
import re
import sys


def duplicate_versions(directory: Path) -> dict[str, list[str]]:
    versions: dict[str, list[str]] = defaultdict(list)
    for path in sorted(directory.glob('*.sql')):
        match = re.match(r'^(\d+)_', path.name)
        if match:
            versions[match.group(1)].append(path.name)
    return {version: paths for version, paths in versions.items() if len(paths) > 1}


def main() -> int:
    directory = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('supabase/migrations')
    if not directory.is_dir():
        print(f'Migration directory missing: {directory}', file=sys.stderr)
        return 1
    duplicates = duplicate_versions(directory)
    for version, names in duplicates.items():
        print(f'Duplicate migration version {version}: {", ".join(names)}', file=sys.stderr)
    if duplicates:
        return 1
    print('Active migration versions are unique.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
