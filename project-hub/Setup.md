# Connect Obsidian to Niswah

1. Install Obsidian and GitHub Desktop (or use Git).
2. Clone `https://github.com/rayan2099/niswah999.git` onto your computer. Until this PR is merged, check out `feat/project-obsidian-vault`; after merge use `main`.
3. In Obsidian choose **Open folder as vault** and select the **niswah999 repository root**, not just `project-hub/`. This gives existing documents and code references one shared root.
4. Open `project-hub/Home.md`. The shared configuration enables core navigation, templates, and Bases. No community plugin, API key, or Obsidian Sync subscription is required.
5. Pull changes before editing. Commit and push intentional changes through GitHub Desktop/Git, using a branch/PR for shared work. There is no automatic sync or push configured.

## Maintaining navigation

Stage added/removed files, run these from the repository root, then stage the regenerated maps:

```bash
git add <changed-paths>
python scripts/sync_project_vault.py
python scripts/sync_project_vault.py --check
git add project-hub/generated
```

CI repeats the freshness/link check. Renaming source files in Obsidian can affect code/documentation references: review the Git diff and regenerate maps before committing. Keep private layout files local; their ignore rules are already supplied.

## Editing and searching

Use Markdown links for compatibility with GitHub. Existing audit and evidence documents are edited at their source; generated pages are read-only navigation. Insert a template into a new note under `project-hub/decisions/` or `project-hub/work-items/`, replace placeholders, and add relevant links.

Obsidian displays Markdown notes and provides search/backlinks/graph navigation. Unsupported source files may be listed or opened with an external editor; Obsidian does not execute Dart, TypeScript, SQL, or deployments. Review dashboards do not change publication gates.

## Connection boundary

The repository setup is ready when checks pass. Opening this clone in your local Obsidian is a separate user step; this PR does not install desktop software or connect a cloud vault. Do not store secrets or identifiable health data in the repository.

[Project home](Home.md)
