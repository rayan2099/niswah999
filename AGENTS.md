# Working on Niswah

## Project-wide context

Before substantive changes, read `project-hub/Home.md` and the relevant generated feature or engineering map. Follow the original requirements, decisions, findings, implementation, and tests relevant to the task. Read narrowly; do not load every document on every task.

- The repository root is the Obsidian vault. Agents read Markdown directly; Obsidian need not be running.
- Original documentation stays in place. Generated maps are navigation, not new requirements or proof of readiness.
- Audit results are dated evidence. Validate scope, reviewed version, and freshness against current code; resolve conflicting reports explicitly.
- `MANIFEST.md` and other task-specific instructions still apply within their stated scope.
- Do not edit `project-hub/generated/` manually. Run `python scripts/sync_project_vault.py` after adding, removing, or renaming tracked documents/modules, and commit the generated changes.
- Stage new files before generating: the inventory reads `git ls-files`, including staged additions.
- After meaningful behavior/architecture changes, update the affected source documentation. Create a decision or work note when it preserves rationale or an unresolved question; avoid duplicating evidence or routine activity logs.
- Authored notes should link to affected feature maps, source files, findings, and verification. Separate proposed, implemented, and verified outcomes; never infer approval from a checkbox.
- Run `python scripts/sync_project_vault.py --check` before handing off hub/documentation changes, plus checks appropriate to implementation changes.

## Authority and publication

Code, authoritative evidence records, existing review policies, and actual execution results govern their respective domains. A dashboard or note does not override them. Medical and scholarly review remain separate from evidence verification and publication eligibility. Vault edits do not publish knowledge, deploy services, or certify live behavior.

## Credentials and personal data

Keep credentials, real user health records, private conversations, and production exports out of the committed vault. Use synthetic/redacted examples and reference the appropriate secure system when needed.
