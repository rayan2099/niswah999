# Mobile Store Release Preparation — 2026-10-05

This document begins the mobile store-release workstream after the production backend deployment workstream was closed successfully.

## Repository-side changes in this release-prep branch

- Android production networking: the main Android manifest now declares `android.permission.INTERNET`. Previously only the debug/profile overlays declared it, which meant a signed release build could be produced without the permission required for Supabase/API/Sentry traffic.
- Google Play artifact: the routine production release workflow now builds a signed Android App Bundle (`.aab`) in addition to the signed APK. The AAB is the store artifact retained by the workflow.
- Artifact provenance: `scripts/generate_release_manifest.sh` now records the signer identity/fingerprint for AAB files using `keytool -printcert -jarfile`, matching the provenance already captured for APK artifacts.
- The routine workflow verifies both APK and AAB signer identity contains `CN=Niswah` before publishing either as a GitHub Actions artifact.

## Already-established release configuration

- Android application ID: `com.niswah.niswah`.
- iOS bundle ID: `com.niswah.niswah`.
- App semantic version in source: `1.0.0`; routine releases compute a monotonic build number in CI.
- Production environment is selected at build time with `--dart-define=APP_ENV=production`.
- Android release signing deliberately fails closed if `android/key.properties` is absent.
- CI pins Flutter `3.47.0`.
- Production backend/KB/OpenAI/Sentry deployment is already closed as PASS in the production deployment execution log.

## Historical workflow evidence

The existing manual routine-release workflow has already completed successfully twice on GitHub Actions. The most recent successful run was routine-release run #2 on 2026-09-08, which produced a verified signed Android artifact (build 102) and a no-codesign iOS release artifact. This proves the Android production signing/environment secret path was functional at that time; the next production release run still needs to re-validate the currently configured secrets rather than assuming they remain unchanged.

## External owner actions still required before store submission

These cannot be completed safely from repository code alone:

1. **Apple signing identity** — configure the Apple Developer Team ID plus an App Store distribution certificate/provisioning profile for `com.niswah.niswah`. The current repo can compile an iOS release with `--no-codesign`, but that is not a store-submittable IPA.
2. **Public privacy-policy URL** — the app has a real in-app Privacy Policy screen, but its own source explicitly records that a publicly hosted copy is still required for App Store Connect / Google Play privacy-policy fields. Legal review of the policy text remains an owner/legal action.
3. **Store-console setup** — verify/create the Google Play Console and App Store Connect listings, app ownership, privacy/data-safety declarations, screenshots, age/content ratings, support contact, and regional availability.
4. **Release secrets/custody** — confirm the GitHub Actions secrets used by the routine workflow are present and current: the production client environment file, Android release keystore, and Android key.properties content. Secret values must never be committed or printed.

## Release artifact sequence after owner actions

1. Run the routine production release workflow with `app_env=production`.
2. Require analyze/tests to pass.
3. Require Android APK + AAB signing verification to pass.
4. Retain the AAB, APK, and release manifest from the workflow.
5. Produce a signed iOS archive/IPA using the approved Apple signing identity.
6. Smoke-test the exact signed release artifacts against production: sign-in/onboarding, Supabase reads/writes, AI assistant, Fiqh fail-closed behavior, notification permission flow, deep-link callback, location-based prayer times, account deletion, and Sentry.
7. Submit the AAB/IPA only after the release manifest and store metadata are complete.

No backend redeployment is part of this workstream.
