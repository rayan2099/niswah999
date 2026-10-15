# Niswah admin dashboard

Implementation date: 2026-10-15. This is an operational V1, separate from the Flutter app, the old React consumer app, and the public landing page.

## Source and scope

- UI: [`admin/src/main.tsx`](../admin/src/main.tsx), [`admin/src/api.ts`](../admin/src/api.ts), [`admin/src/style.css`](../admin/src/style.css).
- Backend: [`admin_dashboard` migration](../supabase/migrations/20261015105437_admin_dashboard.sql).
- Related: [engineering map](../project-hub/generated/Engineering.md), [community](../project-hub/generated/feature-community.md), [authentication](../project-hub/generated/feature-auth.md).

Implemented: Arabic RTL UI, password login for existing accounts, TOTP enrollment/verification, real signup/onboarding/post/support counts, paginated account lookup, internal support tickets with status, reversible post/comment hiding, immutable editorial drafts, source-linked knowledge-version review decisions, staff roles/revocation, and audit pagination. Search/pagination run on the server. Sensitive account projections contain only ID/contact/verification/onboarding/login timestamps. Anonymous author identity and private messages are not returned.

Not implemented: mobile support/report submission, ticket conversations/assignment, account suspension/deletion, article editing/publication/mobile consumption, automatic KB publication or eligibility changes, AI cost tracing/kill switches, billing, notifications, retention/feature analytics, or application runtime configuration. These require separate integrations and verification. Existing `premium_status` is not treated as revenue or a paid subscription. Runtime health and regulatory compliance are not certified by this dashboard.

## Authority boundary

`niswah_admin.staff` is the only staff authority; legacy `public.users.role`, editable user metadata, and UI visibility do not grant dashboard access. `public.niswah_admin_api` is a deliberately narrow SECURITY DEFINER facade with fixed SQL operations, an empty search_path, explicit permission checks, and minimal projections. Its only pre-MFA operation returns the caller's staff role. Every data/action request requires a live `auth.sessions` record, unexpired session, active membership, and AAL2. Private tables enable RLS without client policies/grants. They are intentionally denied direct API access.

Roles: owner; support (account lookup/tickets); moderator (community); editor (drafts); medical reviewer (HEALTH/SAFETY_ESCALATION versions); fiqh reviewer (FIQH versions); operator (aggregate overview). Owner can inspect review records but cannot sign medical/scholarly reviews. Reviewer qualification is the owner's responsibility when assigning the role; it is not inferred from sources. Revocation is checked from the database on every request. Owner changes serialize and cannot remove the last active owner.

Review decisions are append-only, attributable to a version and reviewer, and do not update `production_eligible`, `publication_state`, snapshots, citations, or deterministic calculations. See the original [review governance](../production-readiness-results/knowledge-base/REVIEW_READINESS_GATE.md) and [founder decisions](../production-readiness-results/knowledge-base/FOUNDER_DECISIONS.md); this dashboard does not replace their authority.

Moderation adds `is_hidden` to posts/comments. Restrictive SELECT policies exclude hidden posts and their comments. An invoker trigger prevents ordinary clients from setting moderation flags. Existing content ownership rules remain in effect. Data already loaded on a user's device may remain until refreshed. Hiding preserves content; it does not permanently delete it. Audit stores actor, action, target, time, and limited metadata, without copying health records, article bodies, search queries, or account contact information. Moderation reasons must not contain sensitive personal records.

## Build and deployment

Use a separate Vercel project with root directory `admin`, production branch `feat/admin-dashboard` for the initial staging deployment, build `npm run build`, output `dist`, and `admin/vercel.json` security headers. Do not change the landing page's project or the consumer app's Vite configuration. The root TypeScript configuration excludes `admin` so its dependencies/types remain isolated.

Install with `npm ci --prefix admin`; verify with `npm run build --prefix admin` and `npm test --prefix admin`.

Configure the four public environment values documented in [`admin/.env.example`](../admin/.env.example). Use only the publishable key, never a secret/service-role key. Project URL/ref must match; environment must explicitly be staging or production. Auth session storage is tab-scoped. Deployments should use a dedicated admin identity, not a personal health account, because MFA factors belong to the whole Supabase identity.

Initial database change was applied only to **Niswah Staging**, reference `ovgvevzrcefloitgcsia`, through an isolated transaction with `execute_sql`. Production `jkmjobvxfrmuwafczvtw` was not changed. Do not bulk-push the historical migration chain: follow [database migration strategy](database-migration-strategy.md). No live migration ledger was reconciled in this task. The checked-in file is the exact staging DDL. Staging schema is newer than the September baseline; capture/reconcile intentionally before assuming a full local replay is equivalent.

### First owner

No default staff member, shared password, public signup, or bypass is created. The founder must identify the verified email of the intended admin account in the selected Supabase environment. A trusted operator then provisions that existing UUID as an owner in the private staff table using a bound SQL parameter; record the action in audit. Do not bootstrap from a guessed email, editable metadata, or first signup. The owner signs in and enrolls TOTP; subsequent access management uses the dashboard. Dedicated-account creation/password setup remains with the user through the normal auth flow.

After confirming the dashboard's Vercel domain and login, add the exact `admin` DNS record Vercel returns in Spaceship and confirm TLS. Keep the staging label while using staging data. Production rollout requires repeating schema/access verification against the intended production environment and provisioning its owner separately.

## Verification

- `scripts/verify_admin_access.sql` passed against staging, with synthetic fixtures and all fixtures rolled back: nonstaff/forged legacy and metadata roles denied, AAL1 denied, safe account projection, cross-role denial, ticket create/update, last-owner protection, owner cannot approve as reviewer, cross-domain review denied, qualified review records without publishing, hidden-post filtering, moderation-flag protection, auditing, inactive staff and revoked-session denial.
- Frontend configuration/permission tests passed (3 tests), and strict TypeScript/Vite build passed.
- Supabase security advisors reviewed: private admin RLS/no-policy findings are intentional deny-all; authenticated SECURITY DEFINER finding is the guarded facade described above. Other warnings concern existing functions/extensions/auth configuration, outside this change. They are not asserted resolved.
- Browser checks, deployment URL, DNS, and first-owner sign-in must be recorded separately when actually verified. A compile or SQL impersonation test is not proof of a real browser MFA flow.


## Audience statistics extension — 2026-10-15

Added [Statistics.tsx](../admin/src/Statistics.tsx) and [the statistics migration](../supabase/migrations/20261015111611_admin_user_statistics.sql). Owner-only aggregates cover registered accounts, new registrations today (Riyadh midnight)/rolling 7 and 30 days, verification, onboarding, last sign-in windows, married/not-married/unknown, approximate age ranges, and saved app language. Anonymous auth users are excluded. Every composition uses the same auth-account denominator, including accounts missing a public profile. Ages are derived from birth year; missing/future/pre-1900 years are unknown. Saved language is not nationality. Last sign-in is not DAU/MAU or app engagement; the 7/30-day windows overlap. No marital or health details are added to individual account lookup.

The existing guarded API was moved into the unexposed private schema. The public facade delegates to it before computing aggregates, preserving membership/session/AAL2/audit checks. Operators keep the basic overview without demographic breakdowns. `niswah_admin.user_statistics` has no direct client execution grant.

The app previously stored `niswah_is_married` only in device preferences, defaulting to false. New `public.user_demographics` stores explicit answers only, with self-only SELECT/INSERT/UPDATE policies and an auth-user cascade. The [marital controller](../lib/core/preferences/marital_status_controller.dart) now syncs explicit onboarding/settings selections to the authenticated account, including an explicit No equal to the local default. It never uploads load-time defaults or old device values. Writes serialize and capture the account ID; failures preserve local behavior and report only a generic sync error. A later explicit choice retries. There is no automatic offline queue or historical backfill. Old/unsynced accounts remain unknown; server totals reflect last successfully saved answers. The existing UI asks married/not-married, so no separate single/divorced/widowed classification is invented.

Verification: `verify_admin_statistics.sql` passed on staging with all synthetic fixtures rolled back, testing private row ownership, cross-account denial, explicit false vs unknown, age grouping, composition totals, anonymous exclusion, verification/sign-in/today counts, and owner-only demographic access. The original admin access suite also passed after adding the facade. Frontend tests now total 5 and build passes. Flutter/Dart SDK is unavailable in this environment: the mobile sync change has not been compiled or device-tested here and must be verified in the Flutter CI/staging app before release. This task applies the statistics migration only to staging. PR #21 and its Vercel deployment remain pending; this extension does not resolve the earlier Vercel import approval blocker.
