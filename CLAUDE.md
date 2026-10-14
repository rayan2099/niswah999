# Claude Code — Niswah project context

Load the shared repository instructions and project workspace at session startup:

@AGENTS.md
@project-hub/Home.md
@project-hub/Agent-Workflow.md

## Use the workspace during development

- Before substantive changes, follow the relevant feature/engineering map to original requirements, decisions, code, and tests. Read only task-relevant material rather than the entire vault.
- Preserve existing local edits and commits. Inspect the branch and working tree before Git operations; do not discard unrelated onboarding or research work.
- After meaningful changes, update affected source documentation and link significant decisions or unresolved work using the project templates.
- Generated navigation is not proof of runtime readiness or expert approval. Follow the authority/publication rules in AGENTS.md.
- Stage only intended files before regenerating tracked-file navigation. Run `python3 scripts/sync_project_vault.py` and `python3 scripts/sync_project_vault.py --check` after document/module inventory changes.
- Never manually edit generated maps. Obsidian need not be running; the workspace is Markdown in this repository.

This entry point applies to Claude Code. For an already-running session, explicitly read this file or start a new session; verify loaded project memory with `/memory` where supported.
