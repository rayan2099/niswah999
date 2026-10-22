# App-wide notifications — 2026-10-22

Status: implementation prepared on `feat/app-wide-notifications`, stacked on [PR #35](https://github.com/rayan2099/niswah999/pull/35). Not deployed. This extends [notification reliability](notification-reliability.md) and [prayer-time integrity](prayer-time-integrity.md); their dated results do not establish verification of this change.

Navigation: [notifications map](../../project-hub/generated/feature-notifications.md), [engineering map](../../project-hub/generated/Engineering.md).

## Coverage and boundaries

| App area | Implemented behavior | Release boundary |
|---|---|---|
| Private messages | Live conversation updates, reconnect/resume refresh, live unread counts, account-private inbox events, queued phone push, verified conversation destination | Remote inbox migration and provider activation pending |
| Community | Comments on one's own posts; one grouped like event per post per UTC day; self/hidden activity excluded; verified post destination | Comments phone preference on, likes off by default; remote activation pending |
| Cycle | Existing estimated-start reminder opens Calendar | Estimate, not a guaranteed start date |
| Active bleeding / fiqh | Existing daily factual check-in retains episode/account validation | No automatic religious ruling or prediction of purity |
| Fertility | New optional reminder uses the same estimated window as Calendar; opens Calendar | Off by default; history uncertainty is preserved; not contraception guidance |
| Prayer | Existing five-day planner now records typed Prayer Tracking destinations in the bell and native payload | Confirmed calculation settings required; inexact Android timing |
| Pregnancy / postpartum | Existing milestone and neutral postpartum reminders open the relevant tracking destination | No inferred end of bleeding or obligation to resume prayer |
| Wellbeing | Existing daily reminder opens the check-in | Repeated OS occurrences are not individual delivery receipts in the bell |
| Learning | New optional daily reminder opens learning journeys | Off by default; default 20:00 |
| Urgent AI chat | Discreet existing alert now opens its authenticated original thread | Does not replace urgent care; no message text on the lock screen |
| Account emails | Existing authentication email paths retained | Actual SMTP/provider deliverability not tested here |

There is no medication, appointment or billing domain in this implementation to attach new alerts to. Notification settings distinguish scheduled reminder controls from incoming activity phone controls. The bell merges local schedule history and server activity, with a server-derived unread count independent of the latest 200 displayed activity rows. A failed load preserves known entries and shows a retry state.

## Delivery choices

- Incoming message/comment phone preferences default on; likes off. OS permission is requested on explicit user action, not at startup. The settings screen reports when phone alerts are inactive. Activity remains in the inbox when phone alerts are disabled.
- Quiet hours default disabled; the editable default window is 22:00–08:00. Start is inclusive and end exclusive, including windows crossing midnight. A valid named device timezone is required to enable them. The app updates the server's timezone/locale on resume; travel while the app stays closed can leave the server using the last known zone.
- Scheduled reminders whose chosen time falls inside quiet hours are skipped, not shifted to another time. Incoming remote activity waits until eligible, expires after 24 hours, and remains accessible in the inbox. Quiet hours do not change fiqh calculations.
- Reopening/resuming renews the existing five-day prayer and thirty-day tracking windows. Six fixed slots plus 25 prayer and 30 tracking slots give a conservative maximum of 61 pending scheduled requests, below iOS's 64-request limit. Learning/wellbeing repeat natively; this does not provide indefinite prayer scheduling.
- The feed records accepted schedules and activity events, not verified OS delivery. Provider acceptance, display, sound and a person's seeing a notification are separate outcomes. Devices, Focus settings, network outages and Android power management can delay or suppress alerts.
- Foreground push is deduplicated, revalidated against the current account's inbox, and suppressed while that conversation is visible. Background notification payloads are displayed by the OS; a read/sign-out occurring after provider acceptance cannot recall an already accepted OS alert. Payloads contain only opaque routing/account IDs and generic bilingual text.
- Taps validate the current account, ownership/membership and accessible content before opening private conversations, posts or AI threads. Deleted/unavailable targets show a clear message. Old feed rows without a recorded target are retained without inventing a destination.

## Backend integrity

The [migration](../../supabase/migrations/20261022084701_app_wide_notifications.sql) creates owner-scoped public inbox/preferences tables and a private device registry/outbox. No private message text, actor name or health history is copied into the inbox or provider payload. Client grants permit reading one's inbox and changing only `read_at`; clients cannot manufacture events or destinations. Live-session validation rejects revoked sessions before their access JWT expires. Device records reference the auth session and cascade on its removal; globally unique tokens rebind on account changes.

Firebase Messaging 17 uses `register`/`onRegistered` Firebase Installation IDs, enabled by native manifest/plist flags. The database token column stores this opaque identifier; the worker sends it using the HTTP v1 `fid` field. These contracts were checked against the installed SDK example and [Firebase send reference](https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages).

Database triggers create activity transactionally. Reads mark corresponding message events read. A partial unique index enforces daily like grouping even under concurrent inserts. The worker uses service-role-only claim/confirm/finish operations, bounded batches, `SKIP LOCKED`, two-minute leases and distinct accepted/suppressed states. It rechecks consent, quiet hours, source visibility/existence, unread status and live session immediately before sending. Newer activity coalesces older queued events; accepted groups have a one-minute message/five-minute community cooldown. Failed work has bounded backoff, at most five claims and a 24-hour event lifetime. Ambiguous network failures can cause retry duplicates; this is not an exactly-once delivery guarantee.

Explicit FCM `UNREGISTERED` responses remove invalid devices; generic provider errors do not. Maintenance deletes bounded batches of expired/read queue records and inbox records older than 90 days. Maintenance requires the worker schedule to be active. Public realtime publication membership changes are limited to inbox, messages and conversations; protected Supabase realtime schema objects are untouched.

Source: [session bridge](../../lib/features/notifications/data/services/app_notification_session.dart), [inbox repository](../../lib/features/notifications/data/repositories/activity_notification_repository.dart), [inbox state](../../lib/features/notifications/presentation/viewmodels/activity_inbox_controller.dart), [navigation](../../lib/features/notifications/presentation/navigation/notification_navigator.dart), [worker](../../supabase/functions/notification-dispatch/worker.ts), [worker entry point](../../supabase/functions/notification-dispatch/index.ts), [controls](../../lib/features/notifications/presentation/widgets/notification_controls_card.dart).

## Hardening follow-up — 2026-10-22

Implemented and tested on `feat/notifications-hardening` (stacked on this branch); not deployed. The migration file was edited in place because it has not been applied to any environment.

- **Source writes never fail because of notifications.** The activity trigger catches its own errors and logs a warning, so a message, comment or like is saved even if the inbox insert fails.
- **Like groups stay deliverable.** A later like the same UTC day moves the day's group onto an existing like, marks it unread, and re-arms the phone alert only if none was accepted that day. Before, unliking the first like silenced the rest of the day.
- **Server-owned read state.** A trigger stamps `read_at` with the database clock and stops clients from making a read event unread again, which would re-arm delivery.
- **Client grants are explicit.** Supabase's default privileges give every new public table full `anon`/`authenticated` grants, so the original migration let owners update `kind`/`target_id`/`source_id` on their own inbox rows. The migration now revokes those defaults first, and the SQL tests reproduce Supabase's default privileges. Found while verifying staging on 2026-10-22.
- **No device lockout.** Registering an eleventh device now retires the least recently registered one instead of failing. Reinstalling the app issues a new installation ID without signing out.
- **Delivery.** Lock-screen copy names only the activity kind (message, comment, post activity), never a name or text. Android uses a dedicated `niswah_activity` channel (created by the app and set as the manifest default), so people can mute activity without muting reminders. APNs expiry now matches the one-hour Android TTL. The worker drains a backlog in up to five 50-job rounds within a 40-second budget, and a run that goes past its budget stops starting new sends.
- **App.** Foreground alerts reuse one slot per conversation or post. The bell groups unread events per conversation or post per day and marks the whole group read. Reads update the badge immediately and are rolled back on failure. Bursts of realtime changes trigger at most one follow-up reload. Inbox rows of an unknown kind are skipped instead of failing the inbox. The device's locale and timezone are seeded for accounts that never opened activity settings, so alerts no longer default to Arabic. An unreadable timezone no longer overwrites the stored one. Settings have a "Turn on phone alerts" action.

Verification: backend SQL/worker suite **21 passed** (the new SQL regressions fail against the previous migration). The full non-golden app suite has **1,558 passed** with 7 skips, and the analyzer reports no errors or warnings. The Deno type check of `index.ts` was not rerun; it changed only by an import and a shared batch-size constant. Physical-device acceptance remains open as described below.

## Activation runbook — pending approval/configuration

Automatic approval review rejected applying the migration to **Niswah Staging** (`ovgvevzrcefloitgcsia`) because the implementation request did not explicitly authorize persistent changes to that environment's tables, triggers, functions, grants and publication. No staging or production notification migration/worker/schedule was applied. **Niswah production is unchanged.** Do not bypass this rejection with another SQL transport.

1. Obtain explicit approval for applying the prepared staging migration. Apply it once through the migration workflow, inspect RLS/security advisors and publication membership, and verify two synthetic staging accounts cannot read each other's rows. Do not run the activation script at this point.
2. Register Android and iOS mobile apps for `com.niswah.niswah` in the intended Firebase project. The existing prototype web configuration is not a mobile app registration. Configure Apple Push Notifications capability/provisioning and upload the correct APNs authentication key in Firebase. The current Firebase SDK requires iOS **15.0** (the repository already targets it); signed-device validation remains necessary.
3. Copy [public client config](../../config/notifications.example.json) to an ignored environment config, fill public mobile Firebase fields, and set `NISWAH_PUSH_ENABLED` true only for the intended build. Validate with `python scripts/notifications/check_client_config.py <config-path> --platform android` (or `ios`/`both`). Build using `--dart-define-from-file=<config-path>`. The checker rejects server credential fields and web app IDs. Never put a service-account private key or service-role key in Flutter.
4. In the intended Supabase project's secret store, configure `FIREBASE_SERVICE_ACCOUNT_JSON` and a random `NOTIFICATION_WORKER_SECRET` of at least 32 characters. Keep keys in the secret store, not chat, git, client config or logs. The provider account must have permission to send FCM messages for the same Firebase project. Supabase supplies its server URL/service-role environment values to the function.
5. After environment-specific approval, deploy `notification-dispatch` with the checked-in function configuration. It uses its dedicated bearer secret because `verify_jwt=false`; requests without a matching long secret are rejected. A missing provider config returns 503 before claiming work. Invoke manually with synthetic staging events and inspect acceptance, reads, opt-outs, quiet hours, deletion and invalid-token cleanup.
6. Only after successful device checks, store the intended worker URL and matching secret in Supabase Vault as `notification_worker_url` and `notification_worker_secret`. Review [activation SQL](../../scripts/notifications/activate_dispatch.sql) and enable the one-minute cron using pg_cron/pg_net/Vault. The script validates a Supabase function URL and minimum secret length; it does not select an environment. Monitor failed/expired leases, queue age and provider acceptance separately from delivery.
7. Roll back delivery by unscheduling `niswah-notification-dispatch` and disabling the client push flag in a subsequent build as appropriate. Keep inbox data and existing app writes intact. Rotate exposed secrets through Firebase/Supabase, never through a source change. Production migration, worker and cron activation require their own explicit environment authorization.

Remote activity features require both this client and the migration. Keep the change in draft/staging until that combination is validated; deploying the client alone will show an unavailable activity inbox/settings state. Existing local reminder scheduling is independent of Firebase.

## Verification

All automated fixtures are synthetic. Local database tests execute the actual new migration in embedded PostgreSQL with synthetic auth/source-table stubs; they do not replace a full Supabase migration-chain or staging integration check.

- Focused app notification/realtime/navigation suite: **19 passed**.
- Backend SQL security/queue and pure worker suite: **14 passed**.
- Public client configuration tests: **4 passed**.
- Existing release-tooling Python checks: **13 passed**; app/server pregnancy parity **21/21**.
- Full non-golden app suite: **1,558 passed, zero failures, two skips**, across 175 files. Golden image tests are excluded by the repository CI policy; this is not a pixel-parity verification.
- Notification continuity/repository clock matrix: **213 passed in each of seven zones** (UTC, Riyadh, Kolkata, Lord Howe, Kiritimati, Los Angeles, Pago Pago); London DST regression files: **5 passed**.
- Changed notification code/new tests: **no analyzer issues**. Whole-library analysis has no errors/warnings (22 pre-existing info notices).
- Worker entry point and worker passed Deno 2.9.6 type checking against the pinned Supabase SDK, using identical source copies with isolated dependencies.
- Native Android/iOS compile and full Supabase migration-chain CI are requested through the draft PR; inspect their actual results before merge. Physical-device delivery and signed-release tests remain open.
- Project-vault regeneration/check and `git diff --check` pass.

Test sources: [inbox/privacy](../../test/app_wide_notification_controller_test.dart), [quiet hours and scheduling](../../test/app_wide_notification_scheduling_test.dart), [foreground push](../../test/app_wide_push_dispatch_test.dart), [navigation](../../test/app_wide_notification_navigation_test.dart), [private realtime](../../test/private_messaging_realtime_test.dart), [SQL](../../test/notification_backend/schema.test.mjs), [worker](../../test/notification_backend/worker.test.mjs), [config](../../scripts/notifications/test_client_config.py). CI runs the database/worker/config regressions on future changes.

Physical Android and iPhone acceptance remains open: foreground/background/terminated; permission denial/regrant; Android reboot/update; active/covered chat screens; correct tap destination; revoked sessions and account replacement; comments/likes opt-outs; quiet-hour boundaries and timezone travel; deleted/hidden content; discreet locked-screen copy; retries/provider outage; schedule renewal. A signed iOS build must verify APNs provisioning. Native compile CI alone cannot establish any of these delivery outcomes.
