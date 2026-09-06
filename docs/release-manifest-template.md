# Release Manifest Template

Created by the RD-009 (Production Rollback / Rapid Recovery Capability) wave, 2026-09-06.

A release manifest is the deterministic record of exactly what "last known good" means for one release. Without it, identifying what to roll back *to* during an incident becomes manual reconstruction under pressure — exactly the failure mode `RD-009` describes. Fill one out (or generate one via `scripts/generate_release_manifest.sh` — see `release-manifest.template.json` for the machine-readable equivalent) for every real release, and store it durably (see the Artifact Retention section of `production-readiness-results/release-deployment/RD_release_rollback_runbook.md` — not this repository, since `build/` artifacts and manifests referencing them should not be committed to source control).

## Manifest

| Field | Value | How to obtain |
|---|---|---|
| Git commit SHA | | `git rev-parse HEAD` |
| Git branch/tag | | `git rev-parse --abbrev-ref HEAD` |
| App semantic version | | `grep '^version:' pubspec.yaml` (the part before `+`) |
| Android `versionCode` (build number) | | `grep '^version:' pubspec.yaml` (the part after `+`), or the `--build-number` override actually used |
| Environment | production / staging / development | the `--dart-define=APP_ENV=` value actually passed to the build |
| Flutter SDK version | | `flutter --version` (first line) — must match `.github/workflows/ci.yml`'s pinned `FLUTTER_VERSION` |
| Build timestamp (UTC) | | `date -u +%Y-%m-%dT%H:%M:%SZ` at build time |
| Artifact type | APK / AAB | |
| Artifact SHA-256 checksum | | `shasum -a 256 <artifact path>` |
| Artifact file size | | `ls -la <artifact path>` |
| Signing certificate | | `apksigner verify --print-certs <artifact path>` — must read `CN=Niswah, OU=Mobile, O=Niswah`, never `CN=Android Debug` |
| Edge Function versions (all 4) | `dr-niswah-chat=`, `fiqh-advisor-chat=`, `dream-interpreter-chat=`, `ai-assistant-chat=` | `supabase functions list --project-ref <ref>` (read-only) — **record manually**, no automated correlation to this specific client build exists (see the runbook's Edge Function Rollback section) |
| DB migration state at build time | | `supabase migration list --linked` — the last migration confirmed applied to production as of this build (per `BR-002`, this is **not** the same as "the last migration in `supabase/migrations/`" — the tracked ledger and the live schema have historically disagreed) |
| Known-good verification state | pass/fail per check | `dart analyze lib/` issue count, `flutter test` pass count, artifact inspection checklist (see runbook) — all at build time |

## Notes

- **Do not include secrets.** No keystore password, no `SUPABASE_ANON_KEY`/service-role key, no `SENTRY_DSN`, no database connection string belongs in a manifest. The manifest identifies a build; it does not carry credentials for it.
- **Edge Function versions require a manual step**, marked clearly above — Supabase's `functions list` output has no reliable, automated link back to a specific client release's manifest. If a release depends on a specific Edge Function version (e.g., a client update that assumes a new RPC exists), record that dependency explicitly in a free-text note, not just the version number.
- A manifest with `NOT YET TESTED` in the verification-state row is not itself a defect — it documents an honest state, matching this engagement's standing "no invented evidence" rule. See `production-readiness-results/release-deployment/RD_release_rollback_runbook.md` for the full verification sequence.
