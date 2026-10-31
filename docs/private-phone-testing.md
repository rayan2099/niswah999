# Private phone testing

Owner decision: retain phone collection during private testing, show a test code in-app, and keep the number unverified. Verified email establishes account ownership; future real SMS is required before phone login/recovery. This change adds no authentication bypass and sends no SMS.

[Auth feature map](../project-hub/generated/feature-auth.md).

## Implemented

- Build with `--dart-define=PRIVATE_PHONE_TESTING=true` for the private staging build. Default false. Phone entry on the sign-in screen explains the verified-email prerequisite and opens email authentication. After confirming/signing in, Profile → Private phone test collects the number, displays a six-digit test code, and accepts it. Google accounts with confirmed email also qualify. Apple authentication was not added by this change.
- [Test screen](../lib/features/auth/presentation/screens/private_phone_test_screen.dart) labels this as a rehearsal and clears the displayed code when the account changes. This is deliberately a two-step enrollment: establish identity first, then test phone collection. It does not auto-resume enrollment from email confirmation.
- [Migration](../supabase/migrations/20261030210000_private_phone_testing.sql) adds owner-bound state and admin-managed tester approval. All access defaults off. RPCs require the exact staging JWT issuer, enabled tester approval, a non-anonymous account and confirmed email. Older JWTs with a different issuer fail closed.
- Five-minute expiry, 60-second issuance cooldown, five attempts, hashed codes, one-time consumption, serialized issuance. Errors return normally so failed attempts persist. Existing phone auth records, SMS auth, login, password recovery and phone linking remain unchanged. The stored `phone_verified` column is constrained to false. Duplicate unverified numbers do not establish ownership or link accounts.
- No direct anonymous/authenticated table access. Account deletion cascades both tables. Number is not copied into Auth metadata, auth.users.phone, or public profile data.

## Staging activation (not executed)

Review and apply the migration to staging only. Add only approved synthetic tester UUIDs to `public.private_phone_test_access` with `enabled = true` via an administrator. The allowlist contains no seeded accounts. Disable access by setting enabled false or deleting the access row; outstanding challenges then fail. Remove the build flag for public builds. Do not enable Supabase test-phone confirmation overrides for this feature.

Do not log RPC response bodies: the start response intentionally includes a private rehearsal code. Use synthetic numbers in device acceptance. Remove test enrollment rows and tester approval after the test session.

## Verification

Executed 19 isolated PostgreSQL checks using PGlite + pgcrypto, synthetic auth.users/auth.uid/auth.jwt fixtures: default denial, unconfirmed email, production issuer, number validation, code issuance, cooldown, direct read/write denial, incorrect code, success remaining unverified, replay, account isolation, attempt lockout, expiry, revocation, anonymous denial, unchanged auth phone, unverified constraint and deletion cascade.

Repeat: `cd test/database && npm ci --ignore-scripts && npm test`. [Tests](../test/database/private_phone_testing.mjs) and [workflow](../.github/workflows/private-phone-testing.yml).

This is not full Supabase migration/bootstrap, PostgREST, multi-connection concurrency, signed-device or live-session evidence. Flutter dependency setup was blocked by automatic approval review after it attempted instance-metadata access; analyzer, widget tests and builds have not run locally. CI and physical-device acceptance remain pending. No staging/production deployment, database application or PR merge is included.

Before public phone auth rollout, verify numbers with real SMS and explicitly migrate enrollment; never promote this rehearsal flag to verified status. Existing email, Google and real SMS paths need independent regression/device checks.
