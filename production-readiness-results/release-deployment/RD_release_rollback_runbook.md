# Release & Rollback Runbook (Release Engineering Wave, 2026-09-05)

Addresses `RD-009` (no feature-flag/rollback path faster than a full store review) and the general absence of a documented release procedure this engagement's `RD_findings.md` flagged. This is a **procedure document** — it does not itself close `RD-009` (that requires an actual feature-flag/remote-kill-switch mechanism, out of scope for this pass), but it is the first real, written release process this project has had.

## Producing a release build

1. Confirm `android/key.properties` exists locally (gitignored, never committed — see `android/app/build.gradle.kts`'s `hasKeystoreProperties` check, which now fails the build loudly instead of silently debug-signing if it's missing).
2. Bump `version:` in `pubspec.yaml` (`X.Y.Z+N` — increment `N` on every store submission, per `RD-006`).
3. Build with the correct environment:
   ```
   flutter build appbundle --release --dart-define=APP_ENV=production
   ```
   (`--dart-define=APP_ENV=production` is required — the bundled `.env` asset alone cannot distinguish a release build from a local dev run; see `AppEnvironment.load()`.)
4. Inspect the artifact before upload (see the Artifact Inspection Checklist below) — do not upload unverified.
5. Upload the `.aab` to Play Console / App Store Connect.

## Artifact Inspection Checklist (before every upload)

- [ ] `apksigner verify --print-certs` shows the real release certificate (`CN=Niswah`), not `CN=Android Debug`.
- [ ] Extracted `assets/flutter_assets/.env` contains no `GEMINI_API_KEY`, no `service_role` string, no unexpected secret.
- [ ] `versionCode`/`versionName` match the intended release and are strictly greater than the last uploaded build.
- [ ] A test install reports the correct `environment` tag to Sentry (not `development`) — see the Sentry verification section of this wave's report.

## Recovery Readiness Gate (added by the Backup/Recovery wave, 2026-09-05 — see `00_09` §20 Phase I)

A risky release should not proceed without confirming these, in addition to the artifact checklist above:

- [ ] Recovery artifact (`supabase/canonical_baseline/00_public_baseline_draft.sql`) is current — no live schema change has occurred since its last validation, or it has been regenerated and re-validated against a fresh live capture.
- [ ] Restore procedure is current — matches `BR_recovery_runbook.md` §4 (which requires moving `supabase/migrations/` aside and applying the baseline directly; do **not** assume `supabase db push`/the tracked migrations work, they don't — `BR-002`).
- [ ] Last restore test date is known and recent (target: within Phase H's quarterly cadence — see `BR_recovery_runbook.md`).
- [ ] **For any release containing a database migration specifically:** a fresh, verified backup/restore checkpoint exists **before** the migration executes — not "a backup exists somewhere," a checkpoint taken and confirmed restorable for this specific change. No migration in this project's history has ever had this — establish it starting with the next one.
- [ ] Migration review complete — a second reviewer (not just the author) has read the migration SQL before it runs against production.
- [ ] Rollback/recovery decision documented for this specific release — what happens if it needs to be reverted (cross-references the Rollback procedure section below, still unresolved for `RD-009`).

## Rollback procedure (current state — no remote kill-switch exists)

**There is currently no way to roll back a bad release faster than a new store submission.** This is `RD-009`, unresolved by this pass. Until a real mechanism exists:

1. If a release is discovered to be broken post-launch: prepare a fixed build immediately (steps above), following the fastest safe path through app-store review.
2. The only existing partial mitigation is the informal `dr-niswah-chat` Edge Function kill-switch (documented in `00_09`) — verified for exactly one feature, not confirmed to generalize (`UNK-011`). It does not help with a broken *client* release.
3. **Recommended next step (not implemented this pass):** a simple remote config table (Supabase-backed, read at app startup) the client checks for a "minimum supported version" or per-feature kill flags — this is the natural, lowest-effort real fix for `RD-009`/`ROOT-008`, but requires a schema addition and is out of this wave's DB-change restriction.

## Owner actions this runbook cannot complete

- **iOS signing (`DC-010`):** requires the owner's real Apple Developer Team ID in Xcode's Signing & Capabilities (or `DEVELOPMENT_TEAM` in `project.pbxproj`) — no team ID exists anywhere in this project and none can be safely fabricated.
- **Backing up the newly-generated Android release keystore:** `android/app/niswah-release.jks` and `android/key.properties` were generated in this session's sandboxed environment. **If this is to be the app's real, permanent signing identity, back both up externally immediately** (a password manager or secrets vault) — losing this keystore means no future update can ever be published under the same app identity on the Play Store. If the owner prefers to generate their own keystore instead, replace these two files before the first real upload.
