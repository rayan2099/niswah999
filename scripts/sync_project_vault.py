#!/usr/bin/env python3
"""Generate project-wide Obsidian navigation from tracked files, without copying content."""
import argparse
import json
import posixpath
import re
import subprocess
from collections import defaultdict
from pathlib import Path, PurePosixPath
from urllib.parse import quote, unquote

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'project-hub/generated'


def tracked_files():
    raw = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT)
    return sorted(p for p in raw.decode().split('\0') if p and (ROOT / p).is_file())


def link(source, target, label=None):
    relative = posixpath.relpath(target, str(PurePosixPath(source).parent))
    return f'[{label or Path(target).name}]({quote(relative, safe="/")})'


def page(name, title, body, kind='index'):
    return f'---\ntype: {kind}\ngenerated: true\n---\n\n# {title}\n\nGenerated navigation; edit source files or `scripts/sync_project_vault.py`, then regenerate.\nThese links do not certify current runtime behavior, review approval, or launch readiness.\n\n{link(name, "project-hub/Home.md", "Project home")}\n\n{body.rstrip()}\n'


def generate(files):
    outputs = {}
    docs = [p for p in files if p.lower().endswith('.md') and not p.startswith('project-hub/')]
    groups = defaultdict(list)
    for p in docs:
        groups[str(PurePosixPath(p).parent)].append(p)
    name = 'project-hub/generated/Documents.md'
    body = f'**{len(docs)} existing Markdown documents**, grouped by source folder.\n\n'
    for folder, paths in sorted(groups.items()):
        body += f'## {folder}\n\n' + '\n'.join('- ' + link(name, p) for p in paths) + '\n\n'
    outputs[name] = page(name, 'Document catalog', body)

    modules = sorted({p.split('/')[2] for p in files if p.startswith('lib/features/')})
    name = 'project-hub/generated/Features.md'
    outputs[name] = page(name, 'Feature map', '\n'.join('- ' + link(name, f'project-hub/generated/feature-{m}.md', m.replace('_', ' ').title()) for m in modules))
    # Explicitly known cross-feature dependencies; other matches are navigation hints only.
    related = {
        'onboarding': ['auth', 'madhhab_resolution', 'cycle_tracking'],
        'auth': ['onboarding', 'settings', 'legal'],
        'madhhab_resolution': ['onboarding', 'ai_advisor', 'cycle_tracking'],
        'ai_advisor': ['madhhab_resolution', 'cycle_tracking', 'fiqh'],
        'ai_assistant': ['pregnancy_profile', 'doctor_report'],
        'cycle_tracking': ['dashboard', 'insights', 'fiqh_report', 'notifications'],
        'pregnancy_profile': ['ai_assistant', 'doctor_report'],
        'private_messaging': ['community'],
    }
    functions = {'ai_advisor': 'fiqh-advisor-chat', 'ai_assistant': 'dr-niswah-chat', 'dream_interpreter': 'dream-interpreter-chat'}
    for m in modules:
        name = f'project-hub/generated/feature-{m}.md'
        source = [p for p in files if p.startswith(f'lib/features/{m}/')]
        tests = [p for p in files if p.startswith('test/') and m in Path(p).name]
        body = '## Implementation\n\n' + '\n'.join('- ' + link(name, p) for p in source) + '\n\n'
        body += '## Test navigation hints\n\nFilename matches only; inspect imports and behavior to establish actual coverage.\n\n'
        body += ('\n'.join('- ' + link(name, p) for p in tests) or 'No filename matches. Search `test/` and inspect dependencies before concluding coverage is missing.') + '\n\n'
        if m in functions:
            function = f'supabase/functions/{functions[m]}/index.ts'
            if function in files:
                body += '## Backend entry point\n\n- ' + link(name, function) + '\n\n'
        neighbors = [n for n in related.get(m, []) if n in modules]
        if neighbors:
            body += '## Related features to inspect\n\n' + '\n'.join('- ' + link(name, f'project-hub/generated/feature-{n}.md', n.replace('_', ' ').title()) for n in neighbors) + '\n\n'
        body += '## Requirements, decisions, and verification\n\nRead the ' + link(name, 'project-hub/generated/Documents.md', 'document catalog') + ' and ' + link(name, 'project-hub/Work-Queue.md', 'work queue') + '. Add explicit links from authored decision/work notes to this feature. Existing audit reports are dated evidence; check their scope and freshness.\n'
        outputs[name] = page(name, m.replace('_', ' ').title(), body, 'feature')

    buckets = {
        'Engineering': ('lib/core/', 'lib/app/', 'lib/main.dart', 'pubspec.yaml', 'supabase/functions/', 'supabase/migrations/', 'docs/database-migration-strategy.md'),
        'Quality-and-Release': ('test/', '.github/workflows/', 'scripts/', 'docs/', 'production-readiness-results/master/', 'production-readiness-results/release-deployment/'),
        'Knowledge-and-Review': ('production-readiness-results/knowledge-base/', 'production-readiness-results/fiqh-engine/', 'haidfigh.md'),
    }
    for title, prefixes in buckets.items():
        name = f'project-hub/generated/{title}.md'
        selected = [p for p in files if not p.startswith('project-hub/') and any(p == s or p.startswith(s) for s in prefixes)]
        grouped = defaultdict(list)
        for p in selected:
            grouped[str(PurePosixPath(p).parent)].append(p)
        body = ''
        for folder, paths in sorted(grouped.items()):
            body += f'## {folder}\n\n' + '\n'.join('- ' + link(name, p) for p in paths) + '\n\n'
        outputs[name] = page(name, title.replace('-', ' '), body)
    outputs['project-hub/generated/inventory.json'] = json.dumps({'source_documents': docs, 'feature_modules': modules}, indent=2) + '\n'
    return outputs


def verify_links(outputs):
    # Check new navigation and authored hub notes, not unrelated legacy links.
    notes = {p: text for p, text in outputs.items() if p.endswith('.md')}
    notes.update({p.relative_to(ROOT).as_posix(): p.read_text(encoding="utf-8") for p in (ROOT / 'project-hub').rglob('*.md') if 'generated' not in p.relative_to(ROOT / 'project-hub').parts})
    errors = []
    for source, text in notes.items():
        for href in re.findall(r'\]\(([^\n)]+)\)', text):
            if re.match(r'^[a-zA-Z][\w+.-]*:', href) or href.startswith('#'):
                continue
            target = ((ROOT / source).parent / unquote(href.split('#')[0])).resolve()
            if not target.is_relative_to(ROOT) or (not target.exists() and target.relative_to(ROOT).as_posix() not in outputs):
                errors.append(f'{source}: missing or out-of-vault target {href}')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Verify freshness and local hub links without writing')
    args = parser.parse_args()
    outputs = generate(tracked_files())
    errors = verify_links(outputs)
    expected = {ROOT / p for p in outputs}
    existing = {p for p in OUT.rglob('*') if p.is_file()} if OUT.exists() else set()
    if args.check:
        errors += [f'Stale or missing: {p}' for p, text in outputs.items() if not (ROOT / p).exists() or (ROOT / p).read_text(encoding="utf-8") != text]
        errors += [f'Unexpected generated file: {p.relative_to(ROOT)}' for p in existing - expected]
    elif not errors:
        for p in existing - expected:
            p.unlink()
        for p, text in outputs.items():
            target = ROOT / p
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text, encoding="utf-8", newline="\n")
    if errors:
        raise SystemExit('\n'.join(errors))
    inventory = json.loads(outputs['project-hub/generated/inventory.json'])
    print(f'OK: {len(inventory["source_documents"])} source documents, {len(inventory["feature_modules"])} feature modules; {len(outputs)} generated files; hub links valid.')


if __name__ == '__main__':
    main()
