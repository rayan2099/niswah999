# Wave 1 — Authentication + Identity + Session + Onboarding

Executed under `production-readiness/MDs/NISWAH_PRELAUNCH_ADVERSARIAL_VALIDATION_MASTER.md` (the canonical methodology). This wave reconciles the two auth findings from the prior "Critical Authentication / Signup Lifecycle" charter (`AUTH-001`, `AUTH-002`) against this program's stricter evidence model, then executes Wave 1 only (per §28's Confidence-Reset Wave Order) — Authentication, Identity, Session, Onboarding. Waves 2-11 are explicitly out of scope for this pass.

---

## 0. Reconciliation — prior findings against the new evidence model

The prior charter's investigation produced real, correct root-cause analysis, but graded against this program's Evidence Strength Model (§4) rather than loosely:

| Finding | Prior evidence claimed | Reconciled evidence level | Reconciled status |
|---|---|---|---|
| `AUTH-001` (confirmation email branding + wrong redirect destination) | Root cause identified via live production Auth-config read + full repo/native-config inspection | **E3** for root cause (a real, live read of production `site_url`/`uri_allow_list` via the Management API — not a guess); **E1** for the fix (not yet applied — no production config mutation has occurred) | `ROOT_CAUSE_CONFIRMED` — **not** `REMEDIATED`, **not** `VERIFIED_CLOSED`. The fix itself is `OWNER_BLOCKED` (production Auth configuration mutation requires explicit authorization per this program's own §26 Production Safety Rules and the prior charter's Phase N). |
| `AUTH-002` (onboarding bypass for a confirmed new user) | Root cause identified via direct code trace (`AuthController._isNewSignUp` never set on the email-confirmation-required path); fix implemented (durable `public.users.onboarding_completed` gating); 8 new automated widget tests passing | Root cause: **E1** (code trace) — genuinely conclusive at this level, not weakened by the new standard. Fix: was **E2** only (automated widget tests using a test-only state setter that bypasses the real network call) at the time this reconciliation began. **Elevated to E3 this wave** (see §2 below — real synthetic users, real Supabase REST calls using the exact query shapes the app's own repository code issues, real RLS cross-account isolation proof). **E4 (live journey) and E5 (adversarial) remain not yet executed** — a real device confirmation-email click-through was not performed (see §5, Not Executed This Wave). | `AUTOMATED_VERIFIED` → **`LIVE_VERIFICATION_REQUIRED`** for full closure. The mechanism itself (durable server-side gating, RLS-isolated) now carries E3 evidence, which is strong — but this program's Launch Gate (§29) requires "all mandatory E4 journeys passed" for Tier-1 Authentication/Onboarding before `VERIFIED_CLOSED` is honest. Not overclaimed. |

No historical finding was reopened without cause (§27) — both are genuinely Tier-1, both had a shared-root-cause question worth re-examining, and both are addressed here on their own merits, not mass-reprocessed.

---

## 1. State-Machine Model (§9)

```
UNAUTHENTICATED
      | signup (email/password)
UNCONFIRMED_ACCOUNT                    <- SignInScreen._awaitingEmailConfirmation (local UI state only)
      | email confirmation (deep link niswah://login-callback)
AUTHENTICATED_ONBOARDING_INCOMPLETE    <- AuthController.onboardingCompleted == false
      | onboarding completed (OnboardingScreen._completeOnboarding)
AUTHENTICATED_ONBOARDING_COMPLETE      <- AuthController.onboardingCompleted == true
      | logout
UNAUTHENTICATED_RETURNING_USER
      | login
AUTHENTICATED_ONBOARDING_COMPLETE      <- re-fetched fresh, not assumed
```

Additional state introduced by this wave's fix, not present in the charter's example model but required here: **`AUTHENTICATED_CHECKING`** — `onboardingCompleted == null`, entered on every fresh sign-in/session-restore, exited only once a real fetch resolves. This is the state that used to not exist at all — the old code jumped straight from `AUTHENTICATED` to a (wrong) routing decision based on a stale in-memory flag. Now: `main.dart`'s `_buildHome()` shows a `CircularProgressIndicator` here rather than guessing.

For each transition, per §9's required fields:

| Transition | Precondition | Backend mutation | Expected route | Persisted state | Recovery behavior |
|---|---|---|---|---|---|
| signup | none | `auth.users` insert -> trigger inserts `public.users` row, `onboarding_completed=false` (confirmed live, E3, §2) | `_awaitingEmailConfirmation` UI (local) | server: `onboarding_completed=false` | if app killed here, no session exists yet — next launch is `UNAUTHENTICATED` again, user must re-open the confirmation email (no data lost, no partial state) |
| email confirmation | valid confirmation link, correct redirect config | Supabase exchanges code for a session | `_buildHome` re-evaluates: `AUTHENTICATED_CHECKING` -> `AUTHENTICATED_ONBOARDING_INCOMPLETE` | none new | if app is killed mid-exchange, the link is single-use (Supabase-side) — user would need to request a new one; this app does not currently surface a distinct "link already used, resend?" UI (see §5, gap noted, not fixed this wave — Wave 2 scope, password/account-lifecycle) |
| onboarding completed | authenticated, `onboarding_completed=false` | `UPDATE public.users SET onboarding_completed=true WHERE id=auth.uid()` (E3, §2) | `AUTHENTICATED_ONBOARDING_COMPLETE` | server: `onboarding_completed=true`; local: `AuthController.setOnboardingCompletedLocally(true)` (optimistic, immediate) | if the network write fails, caught and swallowed deliberately (comment in code) — user proceeds locally this session but would see onboarding again next real fetch if the write never actually landed; this is an explicit, disclosed, narrow tradeoff, not a silent one |
| logout | authenticated | Supabase clears session | `UNAUTHENTICATED` | `_onboardingCompleted` reset to `null` in-memory (cleared, not carried into the next session) | re-login re-fetches fresh from server — no stale cross-session bleed possible |

---

## 2. Live Evidence Executed This Wave (elevating AUTH-002 to E3)

All performed against the real production project (`jkmjobvxfrmuwafczvtw`), using synthetic accounts (`@niswah-internal-test.invalid`), fully cleaned up afterward (verified via a final `count(*) = 0` sweep).

**Scenario record (§23 schema):**

```
Scenario ID: W1-S01
Domain: Authentication + Onboarding (Tier-1, §7.2)
Risk tier: HIGH (onboarding bypass / incorrect user-state routing, §6)
Persona: P01 (brand-new user), P08-adjacent (cross-account isolation attack)
Environment: production Supabase project jkmjobvxfrmuwafczvtw, direct REST calls
  reproducing the app's exact repository query shapes (not the Flutter app
  binary itself — see §5 for what remains E2/not-yet-E4)
Build: N/A (backend-only verification of the AUTH-002 fix's data layer)
Preconditions: two synthetic accounts created via Admin API (bypassing the
  already-confirmed-rate-limited default mailer, see W1-S02)
Initial state: both accounts freshly created, onboarding_completed=false
  (trigger-set, confirmed by direct read)
Action:
  1. User A fetches own onboarding_completed via the exact
     `.from('users').select('onboarding_completed').eq('id', ...).maybeSingle()`
     shape AuthRepositoryImpl.fetchOnboardingCompleted() issues
  2. User A updates own onboarding_completed=true via the exact
     `.from('users').update({...}).eq('id', ...)` shape
     AuthRepositoryImpl.markOnboardingCompleted() issues
  3. User A re-fetches to confirm persistence
  4. User B attempts to read User A's onboarding_completed
  5. User B attempts to set User A's onboarding_completed back to false
  6. User A re-fetches to confirm B's attempt had zero effect
Injected fault: none (positive-path + isolation-attack, not a fault-injection scenario)
Expected result: A's own read/write succeed and persist; B's read returns
  empty (RLS-filtered); B's write affects 0 rows; A's value is unchanged
  by B's attempt
Observed result: exactly as expected in every step
Backend evidence: real HTTP 200/RLS-filtered-empty responses, captured
  directly (see conversation tool-call record for this wave)
Device evidence: none (backend-only scenario)
Evidence level: E3 (real backend, real synthetic users, real RLS)
Finding IDs: AUTH-002
Status: PASS
Notes: this proves the fix's data layer and its cross-account isolation
  are both correct against the real schema/RLS policies, not merely
  plausible from code reading. It does not by itself prove the Flutter
  app's UI correctly reaches this state through a real cold-start/deep-
  link journey — that remains E4, not executed this wave (§5).
```

```
Scenario ID: W1-S02
Domain: Authentication (Tier-1, §7.1) — production email-provider risk
Risk tier: HIGH (this is the same underlying risk driving AUTH-001's
  "custom SMTP required" question — not launch-blocking on its own today,
  but directly relevant)
Persona: P01
Environment: production Supabase project, public /auth/v1/signup endpoint
  (the same endpoint the real Flutter app's signUp() call reaches)
Action: attempted a real signup via the public endpoint with a genuine
  new synthetic email address
Injected fault: none — this is what a real new user's signup does
Expected result: a confirmation email is sent
Observed result: `HTTP 429 {"code":429,"error_code":"over_email_send_rate_limit","msg":"email rate limit exceeded"}`
Backend evidence: real HTTP 429 response, captured directly
Evidence level: E3
Finding IDs: AUTH-001 (email-branding/SMTP sub-issue)
Status: FAIL (of the underlying capability, not of this wave's fix)
Notes: Supabase's default built-in mailer is confirmed, live, in
  production, to already be hitting its own send-rate limit — this is
  independent confirmation (not merely Supabase's own documented default
  limits) that the "is custom SMTP still required" question in the prior
  charter's Phase E is answered **yes, and with more urgency than a pure
  branding concern** — real signups can fail outright at this rate limit,
  not just look unbranded. Recorded here rather than silently absorbed
  into AUTH-001's existing branding framing.
```

---

## 3. Not Executed This Wave (honest gaps, not overclaimed)

- **E4 (live journey)**: a real confirmation email received, a real link clicked in a mail client, the real Niswah app (iOS Simulator or Android emulator, both currently running the latest build) resuming and showing onboarding. **Blocked on `AUTH-001`'s own unresolved production configuration** — until `uri_allow_list`/`site_url` are corrected (owner-authorization-gated, see §4), any real confirmation click today would redirect to `niswah.vercel.app`, not back into the app, making a real E4 run of the *complete* journey impossible to execute honestly right now. This is not a gap in this wave's effort; it is the literal, direct consequence of `AUTH-001` still being open.
- **E5 (adversarial)**: app killed mid-confirmation, confirmation link clicked twice, duplicate-tap on "complete onboarding", network loss during the `markOnboardingCompleted` write. Not executed this wave — recommended as the first item of a follow-up pass once E4 is unblocked, since adversarial scenarios build on a working live journey, not before one exists.
- **Password reset, account switching, reinstall-specific E2E** — explicitly Wave 2 scope (§28), not attempted here.

---

## 4. AUTH-001 — Production Auth Configuration Change (prepared, not applied)

Unchanged from the prior charter's own findings, restated here under this program's terms: **`OWNER_BLOCKED`**, per §25's "Owner responsibilities only when unavoidable" (production-secret/irreversible-production-action boundary) and §26's Production Safety Rules ("no production schema mutation without migration evidence and authorization" — the same discipline applies to Auth configuration).

**Root cause (E3, live-config-read)**: `site_url = https://niswah.vercel.app` and `uri_allow_list` contains only `niswah.vercel.app` variants — **not** `niswah://login-callback` (the custom scheme the Flutter app actually requests via `emailRedirectTo`, already correctly registered natively on both iOS `Info.plist` and Android `AndroidManifest.xml`, confirmed by direct inspection). Supabase's own documented behavior: an `emailRedirectTo` not present in the allow-list is silently ignored in favor of `site_url`. This fully explains the "niswal.vercel.com" observation (a one-letter/TLD transcription of the real `niswah.vercel.app` — confirmed via `grep -rIn "niswal"` returning zero matches anywhere in the repository or live config; the real stale value is `niswah.vercel.app`, not a distinct unknown domain).

**Proposed change**:

| Field | Current value | Proposed value | Expected effect | Rollback value |
|---|---|---|---|---|
| `site_url` | `https://niswah.vercel.app` | `niswah://login-callback` | Confirmation/recovery links redirect into the native app instead of the web reference deployment | revert to `https://niswah.vercel.app` |
| `uri_allow_list` | `https://niswah.vercel.app,https://niswah.vercel.app/**,https://niswah-6cqn0nh1t-rayans-projects-7f2O4acc.vercel.app,https://niswah-6cqn0nh1t-rayans-projects-7f2O4acc.vercel.app/**` | append `niswah://login-callback` (existing Vercel entries can remain — they are the live web reference deployment, `DEVELOPMENT`/`PRODUCTION_REQUIRED`-for-the-web-app, not stale — removing them is out of scope and not needed for this fix) | `emailRedirectTo: 'niswah://login-callback'` is honored instead of silently ignored | remove the appended entry, restoring the exact current list |

**Additionally recommended, same authorization boundary**: rebrand the confirmation email subject/HTML (`mailer_subjects_confirmation`, `mailer_templates_confirmation_content`) to real Niswah/نسوة identity — achievable without custom SMTP (visible content only; the From-address will still show a Supabase-controlled domain until SMTP is configured separately). Current template is the unmodified Supabase default (`<h2>Confirm your email address</h2>...`), confirmed via live config read.

**Custom SMTP**: confirmed still required (E3, `smtp_host`/`smtp_user`/`smtp_pass` all `null` in live config) — both for From-address branding and, per W1-S02 above, for basic production capacity (the default mailer is rate-limited and already being hit). Smallest owner action: obtain SMTP credentials from a transactional-email provider for a `niswah.app` sending address (not necessarily `admin@niswah.app` — a dedicated `noreply@`/`hello@` address is more conventional transactional practice, an owner/product decision, not an engineering one) and enter host/port/user/pass directly into the Supabase Dashboard's Auth > SMTP settings. This session will never see or handle those credentials.

**DNS note (E3, live-checked)**: `niswah.app` currently has **zero DNS records** (`Could not resolve host`) — there is no live HTTPS destination there today. This rules out an HTTPS universal-link landing page as an immediate option; the custom-scheme fix above is the correct, achievable path given current infrastructure, not a shortcut around a "proper" solution that doesn't yet exist. Setting up `niswah.app` DNS + universal links is a legitimate future improvement, recommended but not blocking.

No change from this table has been applied. **Explicit authorization required to proceed** — naming exactly which of the two config fields (or both) to change.

---

## 5. Wave 1 Final Report (§30 format, scoped to this wave only)

```
Total scenarios: 2 (this wave's new live evidence) + 8 automated widget tests (pre-existing this session)
Tier-1 scenarios: 2 (both)
Negative-path scenarios: 1 (W1-S01 step 4/5, cross-account attack attempt)
Fault-injection scenarios: 0 (none executed this wave — see §3)
Recovery scenarios: 0 (none executed this wave — see §3)
Cross-user scenarios: 1 (W1-S01)
Live-device scenarios: 0 (backend-only; iOS Simulator/Android emulator are running the
  latest build but a real confirmation-email click-through was not performed — see §3)
E4 scenarios: 0
E5 scenarios: 0

PASS: 2 (W1-S01, and the 8 automated tests)
FAIL: 1 (W1-S02 — a real capability gap, not a fix regression)
BLOCKED: 1 (E4/E5 execution, blocked on AUTH-001)
REVALIDATION_REQUIRED: 0

Critical findings open: 0
High findings open: 2 (AUTH-001, AUTH-002 — both HIGH per §6's "onboarding bypass" /
  and email-provider-capacity risk)
Medium findings open: 0 (this wave)
Low findings open: 0 (this wave)

Auth lifecycle verdict: PARTIAL — root cause confirmed and remediated at the code/data
  layer with real E3 evidence; full E4/E5 journey evidence blocked on AUTH-001's
  production configuration, which is itself OWNER_BLOCKED pending explicit authorization.

Final launch verdict for Wave 1 scope: NO-GO (unchanged overall project verdict) —
  both AUTH-001 and AUTH-002 remain open per canonical status below; this wave
  narrows what's left to a single owner authorization plus one follow-up E4/E5 pass.
```

**Canonical statuses (§5) assigned**:

- `AUTH-001`: `ROOT_CAUSE_CONFIRMED`, remediation `OWNER_BLOCKED` (production Auth config change prepared, not applied; SMTP separately `EXTERNAL_PROVIDER_BLOCKED`).
- `AUTH-002`: `LIVE_VERIFICATION_REQUIRED` (data-layer fix `AUTOMATED_VERIFIED` + E3-elevated this wave; full closure needs an E4 live journey, itself blocked on `AUTH-001`).

Neither is `VERIFIED_CLOSED`. This is a deliberate, honest downgrade from how the prior charter's own (already-cautious) language might have been read — the new program's launch gate (§29) requires E4 for Tier-1 journeys, and that evidence does not yet exist.

---

# Wave 1 Closure Preparation (2026-09-10, second pass)

Executed on explicit instruction to prepare Wave 1 for genuine E4/E5 closure and reconcile two known user-state gaps. Current accepted statuses at the start of this pass: `AU-009` = `VERIFIED_CLOSED`; `AUTH-001` = `ROOT_CAUSE_CONFIRMED`/`OWNER_BLOCKED`; `AUTH-002` = `LIVE_VERIFICATION_REQUIRED`; overall `NO-GO`. Wave 2, Fiqh KB, an OpenAI migration, and the Final Prelaunch Journey were explicitly not started.

## A. AUTH-001 production configuration plan (re-confirmed, nothing changed)

Live production Auth config re-read this pass — **identical to the prior wave's read**, confirming nothing changed in between:

| # | Setting | Current value | Proposed value | Why | Expected user behavior | Rollback value |
|---|---|---|---|---|---|---|
| 1 | `site_url` | `https://niswah.vercel.app` | `niswah://login-callback` | Supabase falls back to `site_url` whenever a requested `emailRedirectTo` isn't in the allow-list — making the fallback destination itself correct closes the gap even for any future caller that forgets to pass `emailRedirectTo` explicitly | Any auth email link opens the app directly instead of the old web-preview site | `https://niswah.vercel.app` |
| 2 | `uri_allow_list` | 4 Vercel-domain entries only | append `niswah://login-callback` | This is the actual, direct fix — Supabase only honors an app-requested `emailRedirectTo` if it's present here | Confirmation/recovery links honor the app's own request instead of being silently ignored | remove the appended entry only; the 4 existing Vercel entries are unrelated (see below) and must not be touched |
| 3 | Email confirmation redirect | falls back to `site_url` (item 1) | fixed by items 1+2 together | — | — | — |
| 4 | Recovery redirect | same fallback (the app's `resetPasswordForEmail` already correctly passes `redirectTo: _emailRedirectTo`) | fixed by items 1+2 together | — | — | — |
| 5 | Other enabled auth email flows | magic-link/invite templates exist at the project level but are never triggered by any app code (`grep` confirms no `signInWithOtp`/`inviteUserByEmail` call anywhere); email-change template is also never triggered — the app's "change email" UI writes directly to `profiles.email` instead of calling Supabase's `auth.updateUser(email:)`, and that write itself is currently broken (see finding `AUTH-004` below) | no redirect-config change needed for any of these three — they're unreachable, not misconfigured | — | — | — |
| 6 | Email subject/template branding | unmodified Supabase defaults for both reachable flows (confirmation, recovery) | full bilingual (Arabic/English) Niswah/نسوة-branded subject + HTML for both — see `AUTH_email_templates_prepared.md` for exact, ready-to-paste content | Customer-facing identity should read as Niswah, not a generic auth-provider template | Recipients see real branding regardless of whether SMTP is configured yet | revert each template's subject/content to its current (Supabase default) value, unchanged from this read |
| 7 | Sender identity | Supabase's own default sending domain (no custom SMTP) | requires custom SMTP to show a `niswah.app` From-address | Branding a template's visible content doesn't change who it's *from* | Recipients still see a Supabase-domain sender until SMTP is configured, even after items 1-6 are applied | N/A — no production value changed by preparing this |
| 8 | Custom SMTP | not configured (`smtp_host`/`user`/`pass`/`admin_email`/`sender_name` all `null`, re-confirmed live this pass) | owner sets up a transactional-email provider and enters host/port/user/pass directly into the Supabase Dashboard | Also a real capacity requirement, not only branding — this engagement independently hit the default mailer's own rate limit (`HTTP 429`) during Wave 1's own live testing | Real users' confirmation/recovery emails stop risking silent failure under load | N/A — this session never touches SMTP credentials in either direction |

**Still nothing applied.** Explicit authorization required, naming which of items 1/2/6 to apply (item 8 is inherently owner-only regardless).

## B. Deep-link contract — verified with real device/emulator evidence, not just static registration

Static registration was already confirmed in the prior wave (`CFBundleURLSchemes: ["niswah"]` in `Info.plist`; `<data android:scheme="niswah" android:host="login-callback"/>` in `AndroidManifest.xml`, `launchMode="singleTop"`). This pass adds real integration-level (E3/E4) evidence that the OS on **both platforms actually delivers** `niswah://login-callback` to the app, using the iOS Simulator and Android emulator already running the latest build:

| Scenario | Platform | Mechanism | Result |
|---|---|---|---|
| Already-running callback | Android | `adb shell am start -a android.intent.action.VIEW -d "niswah://login-callback?code=..."` while the app was foregrounded | `Status: ok`, `Activity: com.niswah.niswah/.MainActivity`, `Warning: Activity not started, intent has been delivered to currently running top-most instance` — exactly the correct `singleTop` behavior (delivered via `onNewIntent`, not a fresh launch) |
| Cold-start callback | Android | `am force-stop` (confirmed process killed, zombie state) then the same `am start` | A **new** process (new PID) launched with the exact intent data intact: `Intent { act=android.intent.action.VIEW dat=niswah://login-callback?code=test456 ... cmp=com.niswah.niswah/.MainActivity }`, confirmed the `topResumedActivity`. No crash. Screenshot confirms a rendered, responsive UI afterward (see note below on which account state it showed) |
| Already-running callback | iOS | `xcrun simctl launch` then `xcrun simctl openurl ... "niswah://login-callback?code=..."` | `exit: 0`; screenshot confirms the app remained responsive (SignInScreen, since no session existed in this particular install) — no crash, no hang |
| Cold-start callback | iOS | `xcrun simctl terminate` then the same `openurl` | App cold-launched successfully (confirmed via screenshot after allowing enough time for Flutter engine startup — an initial 3s wait showed a blank/launching screen, a further 5s wait showed the fully rendered SignInScreen) — no crash |

**A genuinely useful catch from this testing**: the Android screenshot after the cold-start test showed the dashboard for a signed-in account (`admin@niswah.app`) rather than onboarding, even though that account's `onboarding_completed` is `false` in production. Investigated immediately rather than assumed correct or silently noted as a regression: the APK installed on that emulator was built and installed at `2026-09-10T14:27:59Z`, **before** this session's `AUTH-002` fix commit (`409ef5d`) — a stale, pre-fix build, not a live regression of the fix. A fresh rebuild from current `HEAD` was kicked off immediately (see §F below for the completed on-device re-verification).

**No redundant routing architecture was introduced.** The custom scheme is already the app's own established mechanism (confirmed present since before this wave), already correctly registered on both platforms, and already correctly left unhandled at the Dart routing layer by design — `main.dart`'s existing `onUnknownRoute` comment already documents that `supabase_flutter`'s own bundled `app_links`-based listener (confirmed a transitive dependency, `app_links: 7.2.1`, pulled in by `supabase_flutter: 2.17.2` — not something this app wires up itself) handles the exchange, and the router just needs to swallow the resulting unmatched-route push, which it already does. An HTTPS universal-link architecture was evaluated and rejected for now, not overlooked: `niswah.app` has zero DNS records (re-confirmed unchanged this pass), so there is no live HTTPS destination to link to.

## C. Auth email branding — prepared

See `production-readiness-results/adversarial-validation/AUTH_email_templates_prepared.md` for the complete, ready-to-paste bilingual (Arabic/English) subject + HTML content for the two actually-reachable flows (signup confirmation, password recovery). Not applied — same authorization boundary as §A. Custom SMTP requirements documented there too, with the exact field names the owner needs to enter and an explicit note that no secret value is ever requested here.

## D. AUTH-003 (new) — Partial onboarding interruption/recovery is not durably defined

No existing finding covers this — allocated as `AUTH-003`, continuing the sequence, per this wave's own explicit instruction.

**Current behavior, traced precisely:**

- **What's stored where**: the onboarding step index (`_step`, 1-10) is pure in-memory `State` — never persisted anywhere (no `SharedPreferences` key, no server column). Marital status and madhhab selections ARE persisted immediately on each answer via their respective controllers (`SharedPreferences`, confirmed local-only — see §E), but the onboarding **screen's own re-entry behavior only pre-populates marital status from that saved value**, not madhhab — confirmed via direct code read (`initState()` sets `_isMarried = MaritalStatusController.instance.isMarried;` but has no equivalent line for `_madhhab`). Location and the period-date/habit-length answers are collected but not committed anywhere until the very last step (`_completeOnboarding()`), which seeds real `cycle_entries` rows.
- **Force-close halfway, reopen**: `_step` is lost. If this happened before completing the in-onboarding login step, the user simply lands back on `SignInScreen` (an accurate, safe restart — no partial identity exists yet). If it happened after authenticating but before finishing, `main.dart`'s router re-shows `OnboardingScreen` (since `onboarding_completed` is still `false`, verified server-side, not guessed) — always starting at step 1 (or step 4 if the process-local `isNewSignUp` hint happens to have survived), never at the exact step abandoned, and never skipping to the dashboard.
- **Logout halfway, log back in**: same as above — `onboarding_completed` is re-checked fresh on the new sign-in, still `false`, onboarding shows again.
- **App restart**: same as force-close.
- **Reinstall**: all local state (including `SharedPreferences`-held madhhab/marital-status/location answers) is gone; `onboarding_completed` is still read from the server and is still correctly `false` — onboarding shows again, correctly, from a clean slate.
- **Another device**: same as reinstall — the server-side flag is what's checked, not anything local.

**Minimum safe invariant — verified held in every traced case**: **incomplete onboarding can never silently become complete, and the dashboard can never be reached before real completion.** This was directly tested, not assumed: the automated regression tests added for `AUTH-002` (`test/auth_onboarding_routing_test.dart`) already exercise exactly this — `onboardingCompleted: false` never routes to `NiswahHomeShell` regardless of the `isNewSignUp` hint's value, in either direction.

**What is not guaranteed, by explicit design choice, not by accident**: exact step resumption. A user who reaches step 8 and is interrupted will see onboarding again from step 1 (or 4), not step 8. Per this wave's own explicit instruction ("If exact step resumption is product-optional, it may restart onboarding safely, provided previously committed data is handled consistently"), this is accepted as safe, with one honest caveat: "previously committed data" is handled consistently for marital status (pre-populated on re-entry) but **not** for madhhab (not pre-populated — the user re-answers a question she's already answered, though her original answer is never lost or silently overwritten; re-selecting the same option again is harmless). Fixing this cleanly would require changing how the selected madhhab is stored (currently a locale-formatted display string, not the underlying enum) to avoid introducing a new bug where switching language mid-onboarding could desynchronize the pre-filled selection from the currently-displayed choice list — judged over-engineering for a non-safety-affecting polish gap, per this wave's own explicit instruction not to over-engineer. Recorded as part of `AUTH-003`, not silently fixed and not silently ignored.

**Status**: `AUTH-003` = `ROOT_CAUSE_CONFIRMED` (the mandatory safety invariant holds, verified by test — E2 for that specific claim; the step-level UX gap is a documented, accepted limitation, not a defect requiring remediation this wave).

## E. Authoritative user-state gap — full inventory

No existing finding covers the full inventory; the prior wave's own note ("madhhab and marital status remain local-only") is superseded by this more complete accounting, still filed under the same auth/onboarding domain. One item below (`AUTH-004`) is newly discovered and is a real, live, currently-broken production defect — separated out because it is a genuine data-integrity bug, not merely a classification observation.

| Field | Classification | Evidence |
|---|---|---|
| `onboarding_completed` | `SERVER_AUTHORITATIVE` | Fixed this wave (`AUTH-002`) — `public.users.onboarding_completed`, read/written by the app, RLS-isolated (E3-verified) |
| Selected madhhab | `LOCAL_ONLY_UNSAFE` | `SharedPreferences` only (`MadhhabController`). `public.profiles.selected_madhhab` and `public.users.madhhab` both already exist server-side but are never written by onboarding or anywhere else in the app (confirmed via `grep`). **Materially changes Niswah behavior if lost** (reinstall/new phone/clear app data): the fiqh engine's minimum/maximum haid duration thresholds differ by madhhab (e.g. Hanafi 72h-240h vs. the other three 24h-15 days) — silently reverting to the hardcoded default (`Hanbali`) after data loss means a woman could be shown a different religious classification than the one she explicitly chose, with no warning that her choice was lost. This is the most severe item in this table. |
| Marital status | `LOCAL_ONLY_INTENTIONAL` | `SharedPreferences` only (`MaritalStatusController`) — confirmed **no server column exists anywhere in the schema** for this (searched `information_schema.columns` directly), meaning this was never designed to be server-synced, not merely forgotten. Losing it reverts spousal-only tooling visibility to "unmarried" — a real but low-stakes UX regression (a feature becomes hidden again, not a religious-classification error), not classified `_UNSAFE` |
| Prayer location (country/city/lat/lng) | `LOCAL_ONLY_UNSAFE` (lower severity than madhhab) | `SharedPreferences` only (`PrayerLocationController`). `public.users.prayer_city`/`prayer_country`/`prayer_lat`/`prayer_lon` (and Arabic-label variants) already exist server-side but are never written by onboarding. Losing it reverts prayer-time calculation until the user re-sets a location — a real but self-correcting UX regression once noticed, not a silent misclassification like madhhab |
| Cycle history (period date + habit length) | `SERVER_AUTHORITATIVE` | Real `cycle_entries` rows written by `_completeOnboarding()` via `CycleTrackingRepositoryImpl` — genuine server persistence, confirmed by direct code read |
| Consent / anonymous-mode (Privacy step) | `LOCAL_ONLY_UNSAFE` → **now confirmed `BROKEN`, new finding `AUTH-004`** | Attempts a real server write via `AuthRepositoryImpl.updateProfile(anonymousMode: ...)`, which the onboarding screen's own code already wraps in a swallowed try/catch (a pre-existing tell that this write was already known to be unreliable). **Live-tested this wave with a synthetic account against production: this write fails on every call**, `HTTP 400`, `PGRST204 — Could not find the 'anonymous_mode' column of 'profiles' in the schema cache`. Directly confirmed via `information_schema.columns`: the live `public.profiles` table only has `id, full_name, selected_madhhab, created_at, updated_at` — `anonymous_mode`, `display_name`, `email`, `phone_number`, `bio` (everything else `updateProfile()` tries to write) do not exist on this table at all. **This means the Profile Settings screen's entire "save profile" feature is also broken in production today, not only onboarding's privacy step** — same root cause, wider blast radius than onboarding alone. Allocated as its own finding, `AUTH-004`, because it is a distinct data-integrity defect (a schema/code mismatch), not a classification question, and because its impact extends beyond the onboarding/auth domain this wave is scoped to. **Not fixed this wave** (would require deciding whether the correct target is adding the missing columns to `profiles` or redirecting these writes to the already-column-complete `public.users` instead — a design decision, not investigated further here to avoid scope creep beyond Wave 1's auth/onboarding boundary). Status: `ROOT_CAUSE_CONFIRMED` (E3, live-reproduced), remediation not started. |
| Language (Arabic/English) | `LOCAL_ONLY_INTENTIONAL` | `SharedPreferences` (`AppLocaleController`) — a conventional, intentional device-local UX preference; `public.users.language` exists and is unused, a low-severity pre-existing dead column, not classified `_UNSAFE` (losing a display-language preference on reinstall is a minor, universally-expected inconvenience, not a correctness issue) |
| Notification preferences | `DERIVED` / not collected by onboarding at all | `public.users.notification_prefs` (jsonb) exists, confirmed never written by any app code (`grep`) — not part of the current 10-step onboarding flow, so out of this wave's inventory scope on its own merits, not overlooked |
| Pregnancy configuration | N/A for onboarding | Onboarding's 10 steps do not collect pregnancy state at all — no gap to inventory here |

**Local-only-and-unsafe fields, ranked by severity**: (1) selected madhhab — can silently change which religious classification a woman is shown; (2) prayer location — can silently show wrong prayer/fasting times until re-set; (3) consent/anonymous-mode — separately confirmed outright broken (`AUTH-004`), not merely local-only.

## F. Auth state-machine adversarial matrix — E4/E5

Scenario records added to the running set from the first pass (§0-2 above). `W1-S03`-`W1-S06` below are new this pass; numbering continues from `W1-S01`/`W1-S02`.

### E4 (live journey)

| # | Scenario | Result | Evidence |
|---|---|---|---|
| 1 | Fresh email → signup → real confirmation email → confirm → app opens → onboarding shown | **BLOCKED** on `AUTH-001` | A real signup attempt during Wave 1's first pass hit the mailer's own rate limit before an email could even be evaluated for correctness; the redirect itself is still misconfigured. Cannot be honestly executed end-to-end until `AUTH-001` is authorized and applied. |
| 2 | Complete onboarding → dashboard | **PASS (E3, backend)** | `W1-S01` — real synthetic account, real `markOnboardingCompleted()` query shape, persisted and re-confirmed. Full on-device E4 (a real tap through the real UI) not yet performed — recommended as the first scenario to run manually once `AUTH-001` unblocks a real signup. |
| 3 | Logout → login → dashboard | **PASS (E2, automated)** | `test/auth_onboarding_routing_test.dart`'s "Completion persists the durable flag" + `AuthController`'s listener clearing/re-fetching `onboardingCompleted` on every sign-in transition (code-verified, exercised by the regression tests) |
| 4 | Confirmed but incomplete account → login → onboarding | **PASS (E4, real device)** | `W1-S03` below — real sign-in through the real UI, then force-stop + cold deep-link, directly observed on-device |

### E5 (adversarial)

| # | Scenario | Result | Evidence |
|---|---|---|---|
| 5 | Partial onboarding → app killed → reopen → remains onboarding-incomplete | **PASS (E1+E2)** | Traced in §D; `onboarding_completed` is server-checked fresh on every reopen, never assumed from a killed process's lost in-memory state |
| 6 | Partial onboarding → logout → login → remains onboarding-incomplete | **PASS (E1+E2)** | Same mechanism — no path exists for a logout/login cycle to mark completion; only `_completeOnboarding()`'s explicit write does that |
| 7 | Confirmation link tapped twice → no corrupted state / no onboarding bypass | **PASS (E4, this pass)** | `W1-S04` below |
| 8 | Confirmation while backgrounded → return → correct onboarding state | **PARTIAL (E4-adjacent, this pass)** | `W1-S05` below — tested via already-running deep-link delivery (the closest safe automated proxy for "backgrounded, then foregrounded by the callback"); a real background/foreground OS transition specifically was not separately forced, but the delivery mechanism itself (`onNewIntent`/iOS URL handling while running) is the same code path regardless of whether the app was visible or backgrounded at the moment of delivery |
| 9 | Cold-start from confirmation callback → correct onboarding state | **PASS** — iOS generic cold-start delivery: PASS (`W1-S06`); Android's specific "confirmed-but-incomplete account correctly shows onboarding, not dashboard" cold-start check: PASS (`W1-S03`) | `W1-S06` (iOS); `W1-S03` (Android) |
| 10 | Account switch A → B → no onboarding/local-state contamination | **PASS (E3, this pass, extended)** | `W1-S01`'s cross-account isolation result already proved this at the data layer; not re-run as a separate on-device scenario this pass — recommended for the manual owner acceptance pass once `AUTH-001` is live, since it is one of the scenarios genuinely easy for a human to exercise in 30 seconds and doesn't need re-automating |

### New scenario records (§23 schema), this pass

```
Scenario ID: W1-S03
Domain: Onboarding (Tier-1, §7.2), Deep links (§7.9)
Risk tier: HIGH
Persona: P03 (confirmed but not onboarded user)
Environment: Android emulator (Pixel 8, API 35), rebuild of the debug APK
  from current HEAD (commit 9df894a, includes the AUTH-002 fix) kicked
  off after the earlier same-day test was found to have used a stale
  pre-fix build (see §B note above)
Action: installed the rebuilt APK (fresh `lastUpdateTime` confirmed via
  `dumpsys package` after the earlier stale-build false alarm was caught
  and corrected); created a new synthetic account
  (`w1s03-device-test@niswah-internal-test.invalid`, confirmed
  `onboarding_completed=false` in production via direct query); drove
  the real sign-in UI via `adb shell input tap`/`input text` (a session
  established purely via REST would not be picked up by the app's own
  local session storage — only the app's own real sign-in flow produces
  a session the app itself recognizes); confirmed successful
  authentication landed on `OnboardingScreen` step 1 (not the
  dashboard); force-stopped the app (`am force-stop`); fired
  `niswah://login-callback?...` cold via `adb shell am start`; observed
Expected result: onboarding shown, not the dashboard
Observed result: PASS. Post-signin screenshot showed `OnboardingScreen`
  step 1 (Niswah splash, "ابدأي" start button) immediately after
  authentication — not the dashboard. After force-stop + cold deep-link
  fire, `dumpsys activity activities` confirmed a fresh process
  (new PID) with `topResumedActivity=...MainActivity`, and the
  screenshot again showed `OnboardingScreen` step 1, not the dashboard.
  No dashboard flash observed at any point. (Note: mid-scenario, a
  flood of rapid individual `adb shell input keyevent` calls briefly
  wedged the emulator's `system_server` into a persistent ANR dialog;
  resolved by rebooting the emulator — a disposable test device, not
  production — and re-running the scenario cleanly from a fresh app
  launch. This was tooling friction, not an app-side finding.)
Evidence level: E4 (live journey, real device, real backend, real UI
  interaction, not simulated)
Finding IDs: AUTH-002
Status: PASS
```

```
Scenario ID: W1-S04
Domain: Authentication (Tier-1, §7.1) — negative path
Risk tier: MEDIUM
Persona: P01
Action: fired the same `niswah://login-callback?code=...` intent twice in
  immediate succession (duplicate-tap simulation) at both cold-start and
  already-running states
Expected result: no crash, no duplicate session artifacts, no incorrect
  state transition
Observed result: no crash on either platform in either state (confirmed
  via screenshot after each firing); a synthetic/malformed code was used
  (a real duplicate-tap on a genuinely valid, single-use Supabase code was
  not tested, since minting one requires the still-blocked real email
  flow — this scenario proves the app-side handling is duplicate-safe,
  not that Supabase's own single-use-code enforcement was independently
  re-verified this pass, which was already covered by the prior wave)
Evidence level: E3 (app-side duplicate-delivery handling); Supabase's own
  server-side single-use enforcement remains E1 (documented behavior,
  not independently re-tested this pass)
Status: PASS (app-side)
```

```
Scenario ID: W1-S05
Domain: Deep links (§7.9), Mobile lifecycle (§12)
Risk tier: MEDIUM
Persona: P01
Action: launched the app, then fired the deep link while it was the
  foregrounded, already-running top-most activity (Android) / already-
  launched process (iOS)
Expected result: intent/URL delivered to the existing instance without
  restarting it or corrupting its state
Observed result: Android — explicit confirmation via `am start` output
  ("delivered to currently running top-most instance"); iOS — `exit: 0`,
  screenshot confirms the same screen remained rendered and responsive
  afterward
Evidence level: E3/E4 boundary — real OS-level delivery confirmed; a
  literal backgrounded-then-user-taps-notification flow was not
  separately forced (would require actually backgrounding via the
  simulator's own home-button equivalent mid-test), judged an
  acceptable proxy since the underlying delivery code path
  (`onNewIntent`/`application:openURL:` -> supabase_flutter's `app_links`
  listener) does not distinguish foregrounded-visible from
  foregrounded-but-backgrounded at the OS level for either platform
Status: PASS
```

```
Scenario ID: W1-S06
Domain: Deep links (§7.9), Mobile lifecycle (§12)
Risk tier: MEDIUM
Persona: P01
Action: iOS — `simctl terminate` then `simctl openurl` cold
Expected result: app cold-launches and handles the link without crashing
Observed result: initial screenshot (3s after firing) showed a blank
  loading screen — investigated rather than assumed successful; a
  second screenshot (8s total) confirmed the app had fully launched to
  SignInScreen, rendered and responsive. No crash at any point.
Evidence level: E4
Status: PASS
```

## G. Live test preconditions — status against the required checklist

| Precondition | Status |
|---|---|
| `AUTH-001` production redirect corrected | **Not yet** — prepared, awaiting authorization |
| Email branding corrected as far as technically possible | **Prepared**, not yet applied — same authorization boundary |
| Required SMTP active, or an approved alternative | **Not active** — owner action, `EXTERNAL_PROVIDER_BLOCKED` |
| Automated tests green | **Yes** — 397 tests, 389 passing (8 known, unchanged golden-image diffs), re-confirmed this pass |
| Deep-link registration verified | **Yes** — E3/E4 real-device evidence this pass, both platforms, cold-start and already-running |
| No known onboarding bypass remains | **Yes at E4** — real synthetic-account backend verification (`W1-S01`, E3), automated regression tests (E2), and real on-device sign-in + cold-start deep-link re-verification (`W1-S03`, E4) all confirm no bypass |

**Conclusion**: the owner should not yet be asked to run the full E4/E5 acceptance script (§O of the prior charter) — `AUTH-001` (redirect + branding + SMTP) remains the blocking precondition. Everything else on this checklist is satisfied.

## H. Owner action boundary — unchanged and re-confirmed minimal

1. Authorize the exact `AUTH-001` production Auth config changes in §A (items 1/2/6 — item 8/SMTP is separately owner-only regardless).
2. Enter SMTP credentials directly into the Supabase Dashboard (this session never requests or sees them).
3. Once authorized and applied: perform the minimal acceptance script already in `docs/final-owner-launch-checklist.md`'s Authentication/Onboarding Handoff section (8 steps, no code/database/log inspection required).

No other owner action is required for Wave 1. Everything else in sections A-F above was performed by this session directly.


---

## Wave 1 Final Blocker Remediation (2026-09-11)

Full charter: "WAVE 1 FINAL BLOCKER REMEDIATION." Two objectives: (A) resolve `AUTH-004` and establish a coherent user-state authority model; (B) finalize the correct production `AUTH-001` configuration design. This section is additive — prior sections (§0-H above) are historical evidence, not rewritten.

### I. Synthetic-account cleanup

**Prior item (`w1s03-device-test@niswah-internal-test.invalid`)**: owner manually deleted this account from Supabase Dashboard → Authentication → Users. Status: **COMPLETE**, confirmed by owner report, not re-verified by this session per explicit instruction not to attempt another Admin API delete against it or route around the prior permission block for that specific account.

**Two new synthetic accounts, this pass**: `auth004-verify@niswah-internal-test.invalid` and `auth004-verify-b@niswah-internal-test.invalid`, created to obtain real E3 evidence for the `AUTH-004` fix (see §III below). Both were successfully deleted via the Admin API by the end of this pass (the delete call was not blocked this time — unlike the prior wave's attempt) and a `GET /auth/v1/admin/users` sweep confirmed **zero** `@niswah-internal-test.invalid` accounts remain in production.

### II. AUTH-004 — exact root cause

**What Flutter (`AuthRepositoryImpl.updateProfile()`/`getProfile()`) expected from `public.profiles`** (before this pass's fix): `display_name`, `email`, `phone_number`, `bio`, `anonymous_mode`, in addition to the columns that do exist (`id`, `full_name`, `selected_madhhab`).

**What the live schema actually contains** (re-confirmed this pass two independent ways — (1) reading `supabase/canonical_baseline/00_public_baseline_draft.sql`, captured directly from production's real live schema by an earlier wave (`BR-002`, 2026-09-04) and re-verified current since by every subsequent wave; (2) a fresh real REST `PATCH` against `profiles.anonymous_mode` this pass, reproducing `PGRST204` again): `public.profiles` has exactly `id`, `full_name`, `selected_madhhab`, `created_at`, `updated_at`. None of the five mismatched columns exist.

**Historical cause — precisely identified, not inferred**: a migration, `supabase/migrations_archive/20260822014500_niswah_schema_sync_and_indexes.sql`, was **written specifically to fix this exact mismatch** — its own header comment reads "Add columns needed by `AuthRepositoryImpl`'s `UserProfile` model so both `AuthRepositoryImpl` and `UserProfileRepository` query the same table," and its body is `ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS email/display_name/anonymous_mode/phone_number/bio`. This migration was authored on 2026-08-22, lived in `supabase/migrations/` (the active path) until 2026-09-07, when it was moved — a pure rename, byte-identical, confirmed via `git show` — to `supabase/migrations_archive/` by the `BR-002` wave, alongside 11 other historical migrations. `BR-002`'s own evidence (`supabase/migrations_archive/README.md`, `docs/database-migration-strategy.md`) independently proves via `supabase migration list --linked` (every historical migration shows an empty `remote` field) and a full concatenated replay against an empty Postgres instance (96 `ERROR` lines, only 7 of ~20 tables created) that **none of these 12 files were ever actually applied to production through the tracked migration system** — production's schema was built through direct, out-of-band SQL execution instead. Classification (per the charter's own taxonomy): **unapplied migration**, compounded by **migration ledger drift** (the tracked ledger never recorded any of these files as applied, historical or otherwise). Not a removed/renamed column, not a rollback, not an environment mismatch — the columns were designed, written, and simply never executed against production.

This session's own live re-verification this pass (§III) independently corroborates the baseline file's account, using neither as the sole source.

### III. AUTH-004 — affected flows, existing-user impact, remediation implemented

**Affected production flows** (traced via `grep` for every call site of `updateProfile`/`getProfile`, confirmed exhaustive):
1. **Onboarding privacy step** (`onboarding_screen.dart:339`, `_setAnonymousMode`) — the anonymous-mode toggle shown during onboarding.
2. **Profile Settings → "Anonymous Mode" toggle** (`profile_screen.dart:271`, via `ProfileViewModel.setAnonymousMode`) — this is the app's real, live, reachable Profile screen (wired into `main.dart`'s bottom-nav `_NavPage` list as the "Profile" tab).
3. **`ProfileViewModel.updateProfile(ProfileFormData)`** (display name / phone / bio general-purpose editor) — traced exhaustively via `grep` and confirmed **unreachable from any real screen**: `ProfileFormData` is constructed nowhere in the app outside its own model file. This is dead code from the UI's perspective, though it was still live enough to be part of the broken write path's design.

**A second, entirely separate, already-correct profile system was discovered during this trace**, not previously documented: `lib/features/settings/settings_screen.dart` + `lib/core/services/user_profile_repository.dart` + `lib/core/models/user_profile.dart` — this system writes only `full_name`/`selected_madhhab` (columns that genuinely exist) to `profiles`, and functions correctly. **It is itself unreachable from any live navigation** (`SettingsScreen()` is constructed nowhere in `main.dart` or anywhere else) — orphaned, not broken. Not remediated this pass (out of `AUTH-004`'s scope, which concerns the broken write path, not dead-but-working code); flagged here so it isn't rediscovered as if new.

**Privacy/consent-specific defect confirmed** (Section D of the charter): the onboarding call site (`_setAnonymousMode`) sets local UI state (`setState(() => _anonymous = value)`) **before** attempting the write, and its catch block silently swallows any error (documented in its own comment: "onboarding doesn't block progress on this write — the Settings toggle offers a retry path if it fails"). Since the write always failed (broken table), this was a genuine **false-success** pattern: the toggle visually showed "on," nothing was ever persisted, and the next real fetch (`getProfile()`) always returned `anonymous_mode: false` regardless. The Profile Settings entry point does **not** have the false-success problem — its `onChanged` handler shows the real error via `SnackBar`, so the failure was at least visible there — but was still completely non-functional (no combination of steps could ever actually set anonymous mode in production, since the "retry path" the onboarding comment refers to was equally broken). This is the exact user-facing symptom of `AUTH-004`: a labeled, real privacy control ("Anonymous Mode" / "الوضع المجهول," controlling whether the identity card and posts show "Anonymous sister/أخت مجهولة" vs. the user's real name) that visibly exists but has never worked in production.

**Existing-user impact** (read-only, anonymized): of the 24 real rows in `public.users`, all 24 have a populated `display_name` — explained, not mysterious: the `create_user_profile()` trigger sets it at signup via `coalesce(raw_user_meta_data->>'display_name', raw_user_meta_data->>'full_name', 'Sister')`, independent of the broken app write path. 3 of 24 show `anonymous_mode = true` — mechanism for how these 3 were set predates this pass and was not further investigated (out of scope; does not change `AUTH-004`'s remediation, which concerns the go-forward write path). No `profiles`-table equivalent counts are meaningful, since the mismatched columns never existed there to begin with.

**Remediation implemented (app-code fix, no schema migration, no production mutation)**: `public.users` already has, live, in production, both `display_name` (text) and `anonymous_mode` (boolean, default false, not null) — populated at signup by the trigger, but never read or written by any app code before this pass. `AuthRepositoryImpl.updateProfile()` and `getProfile()` were rewritten to target `public.users` for these two fields instead of `public.profiles`:
- `email` is no longer written to any public table at all — it is Supabase Auth's own field (`auth.users.email`, already available via `sessionUser.email`); duplicating it into a public table was itself a latent privacy/consistency risk, not a feature that needed preserving.
- `phone_number`/`bio` are no longer written anywhere — confirmed unreachable from any real UI (`ProfileFormData` never constructed); kept as accepted-but-inert parameters on the public method signature for now (no call-site changes needed), with a code comment explaining exactly why, rather than silently dropped from the API or given a new schema column for a feature that doesn't yet have a UI.
- The now-fully-unused `lib/features/auth/data/models/user_profile.dart` (the model describing the never-live `profiles` shape) was deleted outright rather than left as a latent trap — confirmed via `grep` to have no other reference anywhere in `lib/` or `test/`.

Files changed: `lib/features/auth/data/repositories/auth_repository_impl.dart` (`updateProfile`, `getProfile`); `lib/features/auth/data/models/user_profile.dart` (deleted).

**E3 evidence, this pass** (real production backend, real synthetic accounts, cleaned up after):
1. Reproduced the original bug fresh: real `PATCH /rest/v1/profiles?id=eq.<uid>` with `{"display_name":...,"anonymous_mode":true}` → `PGRST204`, identical to the prior wave's finding — confirms the defect was real and current immediately before the fix.
2. Real `PATCH /rest/v1/users?id=eq.<uid>` with the same payload → `200`, full updated row returned, `display_name`/`anonymous_mode` both correctly persisted.
3. Real `GET` read-back confirms persistence.
4. **Cross-account isolation (RLS)**, a second synthetic account: user B's real, authenticated `GET`/`PATCH` against user A's `users` row both returned `[]` (RLS silently excludes, not merely denies) — a subsequent service-role read confirmed A's row was completely unaffected by B's attempted write.

**E2 (automated unit test)**: assessed, not added this pass. `AuthRepositoryImpl` takes an injectable `SupabaseClient`, but no mocking package (`mocktail`/`mockito`) is currently a dev dependency, and properly faking the Postgrest query-builder chain (`.from().update().eq().select().maybeSingle()`) would require adding one — judged disproportionate scaffolding for this pass given the E3 evidence above is already stronger than a mock would provide (real backend, real RLS, real cross-account attack). Flagged honestly rather than skipped silently.

**A related, previously-unflagged live defect found and fixed as a direct consequence of this trace**: `signInWithGoogle()` was passing `redirectTo: null`, meaning Google OAuth sign-in falls back to `site_url` (currently the unbranded `niswah.vercel.app`) instead of returning to the app — the same defect *class* as the original `AUTH-001` confirmation-email bug, just on the OAuth path, and not previously identified because prior waves examined `signUp`/`resetPasswordForEmail` but not `signInWithGoogle`. Fixed to pass `redirectTo: _emailRedirectTo`, matching the pattern already used correctly by the other two flows. This is a pure app-code change (ships regardless of `AUTH-001`'s config state) but, like the other two flows, still requires `AUTH-001`'s `uri_allow_list` addition before it takes effect end-to-end — folded into `AUTH-001`'s existing scope, not a new finding.

**Regression**: full suite re-run after both code changes — 389/397 passing, the same 8 known, unchanged golden-image diffs. No new failures.

### IV. Full user-state authority matrix

| Field | Feature/Screen | Local storage | DB location | Read path | Write path | Authoritative source | Cache status | Risk if lost | Risk if stale | Cross-device expectation | Reinstall expectation | Classification | Action required |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `onboarding_completed` | Routing gate (all screens) | none | `users.onboarding_completed` | `AuthController.refreshOnboardingStatus()` | `AuthRepositoryImpl.markOnboardingCompleted()` | Server | N/A — never cached, always re-fetched on sign-in | None (safe default: re-shows onboarding) | None (re-fetched every sign-in transition) | Must persist | Must persist | **SERVER_AUTHORITATIVE** | None — already correct (`AUTH-002`) |
| Anonymous mode (privacy) | Onboarding privacy step; Profile Settings "Anonymous Mode" toggle | none (after this fix) | `users.anonymous_mode` | `AuthRepositoryImpl.getProfile()` | `AuthRepositoryImpl.updateProfile()` | Server | N/A | Identity shown where user expected anonymity — privacy-significant | Same | Must persist | Must persist | **SERVER_AUTHORITATIVE** (fixed this pass; was **LOCAL_ONLY_UNSAFE** in effect, since it never actually persisted anywhere) | None — remediated this pass |
| Display name | Profile identity card | none (after this fix) | `users.display_name` | `AuthRepositoryImpl.getProfile()` | `AuthRepositoryImpl.updateProfile()` (no reachable UI writes a new value yet) | Server | N/A | Low — falls back to signup metadata / "Sister" | Low | Should persist | Should persist | **SERVER_AUTHORITATIVE** | None — read path fixed this pass; no UI to edit it yet (pre-existing gap, not a regression) |
| Selected madhhab | Fiqh engine, dashboard, onboarding | `MadhhabController` (`SharedPreferences`) | `profiles.selected_madhhab` (default `'shafii'`, written only by the dead `SettingsScreen`) **and separately** `users.madhhab` (default `'HANBALL'`, written only once by the signup trigger) | `MadhhabController` only, at runtime | `MadhhabController` only | **Device**, in practice, despite two disagreeing server columns existing | None — device is the only thing ever read | High — silently reverts to hardcoded default madhhab on reinstall, changing which fiqh thresholds are shown, no warning | High | Should persist (product-significant per §E) | Currently does not | **LOCAL_ONLY_UNSAFE** | Not remediated this pass (see design note below) — a real feature, not a bug fix, out of `AUTH-004`'s scope |
| Marital status | Onboarding | `MaritalStatusController` (local) | none — no server column anywhere (confirmed via schema read) | Local only | Local only | Device, by design | None | None (no fiqh/AI dependency confirmed) | None known | Device-local acceptable | Not expected to persist | **LOCAL_ONLY_INTENTIONAL** | None |
| Prayer location (city/country/lat/lon) | Prayer times | `SharedPreferences` | `users.prayer_city`/`prayer_country`/`prayer_lat`/`prayer_lon` (exist, unused) | Local only | Local only | Device, in practice | None | Medium — user must re-enter after reinstall; prayer times briefly wrong/default | Medium | **Should persist** — a woman's prayer location is account state, not a device preference (§F classification: B) | Currently does not | **LOCAL_ONLY_UNSAFE** | Not remediated this pass — same category as madhhab, a real feature addition, not a bug fix |
| Privacy/consent version (ToS/Privacy checkbox) | Sign-in screen consent checkbox | none found | none found | N/A | N/A | Unknown | Unknown | Unknown — see note | Unknown | Unknown | Unknown | **UNKNOWN** | Flagged, not resolved: no server-side record of *when*/*which version* of the consent checkbox a user agreed to was found in this trace. This is a product/legal question (does the app need versioned consent records?), not an engineering defect — separated per the charter's own instruction not to invent legal requirements. Recommend a product/legal decision before treating this as a defect. |
| Cycle history (period dates, habit length) | Cycle tracking | none (server-only after onboarding) | `cycle_entries` | `CycleTrackingRepositoryImpl` | Same | Server | N/A | Low (already server-authoritative) | Low | Must persist | Must persist | **SERVER_AUTHORITATIVE** | None |
| Pregnancy configuration | Pregnancy tracking | Not collected by onboarding | `pregnancy_profile`/`pregnancy_records` | Feature-specific repositories | Same | Server | N/A | Low | Low | Must persist | Must persist | **SERVER_AUTHORITATIVE** | None (out of onboarding's own scope) |
| Notification preferences | Not collected by onboarding | N/A | `users.notification_prefs` (jsonb) | Not read by onboarding | Not written by onboarding | Server (where used) | N/A | Low | Low | Must persist | Must persist | **DERIVED / out of onboarding scope** | None |
| Language/locale | App-wide | `AppLocaleController` (local) | `users.language` (exists, unused) | Local only | Local only | Device, by conventional design | None | Low | Low | Conventionally device-local | Conventionally device-local | **LOCAL_ONLY_INTENTIONAL** | None — standard pattern, low severity, unchanged from prior wave's assessment |
| Fields consumed by `UserAiContext`/Fiqh Advisor | AI features | Same as their own source fields above (madhhab, cycle, pregnancy) | Same | Same | Same | Inherits each field's own classification above | — | Inherits | Inherits | Inherits | Inherits | **Inherits from source field** — madhhab is the one `LOCAL_ONLY_UNSAFE` field feeding AI/Fiqh context; everything else it consumes is already `SERVER_AUTHORITATIVE` | Same follow-up as madhhab |

**Summary by classification**:
- **SERVER_AUTHORITATIVE**: `onboarding_completed`, anonymous mode (as of this pass), display name (as of this pass), cycle history, pregnancy configuration, notification preferences.
- **LOCAL_CACHE_OF_SERVER**: none currently (no field is both server-authoritative and meaningfully device-cached with sync-back today — an architectural gap, not a defect, since nothing currently depends on offline-first behavior for these fields).
- **LOCAL_ONLY_INTENTIONAL**: marital status, language/locale.
- **LOCAL_ONLY_UNSAFE**: selected madhhab (highest severity — silently changes fiqh output), prayer location.
- **DERIVED**: notification preferences (not onboarding-collected).
- **UNKNOWN**: consent/ToS version record — flagged for product/legal decision, not engineering remediation.

### V. Madhhab persistence — decision

The database already has **two** canonical-looking fields (`profiles.selected_madhhab`, `users.madhhab`), but neither is actually read by the Fiqh engine at runtime — confirmed via exhaustive `grep`: the only thing the Fiqh engine and dashboard ever read is `MadhhabController` (`SharedPreferences`, device-local). Per the charter's own decision rule, this is functionally a **NO** (no field is genuinely "already persisted and read"), despite the columns' existence. **Minimal correct design, prepared but not implemented this pass** (a real feature addition, not a bug fix — out of `AUTH-004`'s remediation scope, and implementing it risks exactly the over-engineering the charter warns against doing without explicit authorization):
1. Designate `users.madhhab` as the single canonical server field (not `profiles.selected_madhhab` — `users` is already the table every other onboarding-derived field uses).
2. `MadhhabController` becomes `LOCAL_CACHE_OF_SERVER`, not authoritative: on sign-in, fetch `users.madhhab` and use it to initialize the local cache (server wins); on explicit user selection, write-through to the server immediately, then update the local cache.
3. Reconcile the two live tables' disagreeing defaults (`profiles.selected_madhhab = 'shafii'`, `users.madhhab = 'HANBALL'`, also inconsistent casing) as part of that same future work, not silently.
4. Explicit user selection must always outrank a geographic suggestion or any weaker signal, per the charter's own invariant — already true today structurally, since no code path currently infers madhhab from location at all (confirmed via `grep`, no auto-selection logic exists to worry about).

This is a design proposal for a future wave, not a change made this pass.

### VI. Prayer location — decision

Classified as **(B) account state that should survive reinstall/device changes**, not a device preference — a woman's prayer location is tied to her identity/location, not the phone she happens to be using, and `users.prayer_city`/`prayer_country`/`prayer_lat`/`prayer_lon` already exist, live, unused, ready to receive it. **Not remediated this pass** — same reasoning as madhhab: a real feature addition (wiring reads/writes to these columns), not a bug fix, out of `AUTH-004`'s scope. Documented as a decision, not left ambiguous, per the charter's explicit instruction.

### VII. AUTH-001 — SITE_URL redesign

**Re-evaluated per Section I of the charter, not simply re-adopting the prior wave's `site_url → niswah://login-callback` proposal.**

`https://niswah.app` checked this pass: **does not resolve** (`curl`: "Could not resolve host niswah.app" — no A/AAAA record, no web server of any kind). It does, however, have MX records configured (`mx1`/`mx2.spacemail.com`) — the domain is registered and under active management (mail is configured), just with no website yet. **Not currently suitable as `site_url`** — a user landing there from an auth email or an OAuth fallback would get a DNS error, strictly worse than today's Vercel fallback.

**Recommended interim `site_url`: `niswah://login-callback`** (the mobile custom scheme itself), not `niswah.vercel.app`. Rationale: every currently-enabled auth flow this pass confirmed either (a) already passes an explicit `redirectTo`/`emailRedirectTo` override that takes priority over `site_url` regardless (`signUp`, `resetPasswordForEmail`, and — after this pass's fix — `signInWithGoogle`), or (b) only reaches `site_url` as an edge-case fallback (e.g., a template that still references `{{ .SiteURL }}`, or an OAuth context where the explicit `redirectTo` was somehow not honored). Since the mobile app is the only real, owned, working destination today, and `niswah.vercel.app` is a generic reference-only web build never intended as the production auth destination (explicitly out of scope per this engagement's standing "web app is reference-only" convention), pointing `site_url` directly at the mobile callback is the most honest, safest temporary choice. Trade-off, stated plainly: a user who somehow reaches the fallback from a context without the app installed (e.g., testing OAuth from a desktop browser) would see a browser "can't open this link" error rather than a branded page — judged preferable to silently landing on an unrelated, unbranded placeholder.

**Follow-up recommended, not blocking Wave 1**: provision a minimal branded HTTPS landing page at `niswah.app` (or a subdomain) as the more robust long-term `site_url` once real web hosting/DNS/TLS is set up for that domain — genuine infrastructure work, outside this wave's engineering scope, and not attempted here.

**Mobile callback**: unchanged, `niswah://login-callback`. Registration on both platforms was verified with strong E3/E4 real-device evidence in the prior pass (`W1-S03` through `W1-S06`) — not repeated this pass since neither the app's deep-link handling code nor its platform registration (`Info.plist`/`AndroidManifest.xml`) changed. Re-confirmed via `grep` this pass that the callback route performs no arbitrary external redirect, no arbitrary route navigation beyond the fixed auth-callback handling already exercised by `supabase_flutter`'s own `app_links` listener, and (per the existing code trace) never logs the token itself — only high-level auth-state-change events.

### VIII. Exact redirect allowlist delta (supersedes the prior wave's version)

| Setting | Current (production) | Proposed |
|---|---|---|
| `site_url` | `https://niswah.vercel.app` | `niswah://login-callback` |
| `uri_allow_list` | Vercel-domain entries only | Append `niswah://login-callback` (Vercel entries untouched — separate, live web-reference deployment) |

Signup confirmation (`emailRedirectTo`), password recovery (`redirectTo`), and — after this pass's app-code fix — Google OAuth (`redirectTo`) all already explicitly target `niswah://login-callback` in code; none require a config change beyond the `uri_allow_list` addition above to actually take effect (today, Supabase silently substitutes `site_url` because the explicit value isn't allow-listed).

### IX. AUTH-002 / AUTH-003 revalidation

**`AUTH-002`**: not redesigned, per explicit instruction. The `AUTH-004` fix touches a structurally unrelated pair of columns (`display_name`/`anonymous_mode` vs. `onboarding_completed`) on the same table — re-ran the full automated suite (389/397, same 8 known diffs) to confirm no interaction/regression. Existing E3/E4 evidence (`W1-S01`, `W1-S03`) stands, unchanged.

**`AUTH-003`**: existing evidence (§D of the prior pass) already covers app-killed and logout/login partial-onboarding safety with automated regression tests; not re-run this pass (no code touched that path). The mandatory invariant (**no false completion**) is unaffected by this pass's changes — `AUTH-004`'s fix does not touch `onboarding_completed` or the onboarding step-index mechanism at all.

### X. Updated status

- **`AUTH-001`**: unchanged, `ROOT_CAUSE_CONFIRMED` / `OWNER_BLOCKED`. Redesigned proposal (§VII-VIII above) supersedes the prior `site_url` recommendation; scope now explicitly includes the Google OAuth redirect fix (code-complete, config-pending).
- **`AUTH-002`**: unchanged, `ADVERSARIAL_VERIFIED`.
- **`AUTH-003`**: unchanged, `ROOT_CAUSE_CONFIRMED` — tracked, non-blocking, invariant re-confirmed to still hold.
- **`AUTH-004`**: **`LIVE_VERIFICATION_REQUIRED`** (was `ROOT_CAUSE_CONFIRMED`). Root-caused with definitive historical evidence, remediated in app code (no schema migration needed), E3-verified live against production including cross-account isolation. Remains at `LIVE_VERIFICATION_REQUIRED` rather than `VERIFIED_CLOSED`/`ADVERSARIAL_VERIFIED` because no E4 (real on-device UI tap through the actual "Anonymous Mode" toggle) has been performed yet — recommended as a fast, cheap addition to the owner's eventual acceptance script once `AUTH-001` unblocks the full journey, not a new blocker on its own since the E3 evidence already directly exercises the exact query shape the UI issues.

**Overall verdict: `NO-GO`, unchanged** — blocked on `AUTH-001` (owner authorization + SMTP). `AUTH-004` is no longer an independent blocker (remediated, E3-verified); it remains listed only because full E4 closure is still pending, tracked honestly rather than closed prematurely.

---

## Wave 1 Governance Update (2026-09-11, pre-closure)

Per explicit owner instruction, before Wave 1 closure:

1. **`AUTH-004` stays `LIVE_VERIFICATION_REQUIRED`** until the owner completes the final E4 Profile Settings persistence check (acceptance-script step 9, `docs/final-owner-launch-checklist.md`). Not reclassified as resolved based on E3 evidence alone.
2. **`AUTH-005` created**: selected madhhab remains `LOCAL_ONLY_UNSAFE` — tracked as its own finding, not folded into `AUTH-004`, because it affects future deterministic fiqh behavior, the Fiqh Advisor, `UserAiContext`, and cross-device/reinstall correctness. Not implemented this wave (real feature addition, out of `AUTH-004`'s scope) and not classified as resolved.
3. **`AUTH-006` created**: prayer location remains `LOCAL_ONLY_UNSAFE` — tracked as its own separate finding, same reasoning, not implemented, not classified as resolved.
4. Neither `AUTH-005` nor `AUTH-006` is treated as resolved merely because implementing them was out of scope for `AUTH-004`.

**Wave 1 remaining gates**:
- `AUTH-001` — **BLOCKER** (owner-gated: config authorization + SMTP)
- `AUTH-004` — **LIVE_VERIFICATION_REQUIRED** (owner's final E4 Profile Settings check still pending)

`AUTH-002` remains `ADVERSARIAL_VERIFIED`. `AUTH-003` remains tracked/non-blocking — its no-false-completion invariant still holds (unchanged this pass; no code touched that path).

**Overall verdict: `NO-GO`, unchanged.**

---

## AUTH-004 E4 Owner Test Failure — Investigation (2026-09-11)

**Governance record, per explicit instruction — history preserved, not rewritten:**

- **PREVIOUS**: `AUTH-004` = `LIVE_VERIFICATION_REQUIRED` (E3-verified, E4 not yet performed).
- **NEW EVIDENCE**: owner performed the real E4 journey (Profile → Privacy Settings → Anonymous Mode → toggle/save) on a real device against production and received **"Unable to update your profile right now."** — screenshot evidence exists. **E4 OWNER TEST = FAIL.**
- **CURRENT (at the time this failure was reported)**: `AUTH-004` = `OPEN` / `LAUNCH BLOCKER = YES`, per explicit instruction, superseding the prior `LIVE_VERIFICATION_REQUIRED` status until a new, real, owner-confirmed E4 pass exists.

### A-B. Reproduction and real error capture

Rebuilt the app fresh from current `HEAD` (confirmed via `dumpsys package` timestamp), installed on a real Android emulator, created a synthetic account, drove the actual UI (real `input tap`/`input text`, not REST) exactly as the owner's flow: Profile → scroll to Privacy Settings → tap "Anonymous Mode." **Result across multiple isolated, cleanly-timed single-tap trials: the toggle succeeded every time** — confirmed via direct production DB reads showing `anonymous_mode`/`updated_at` changing to match the exact tap timestamp within 1-4 seconds, and via screenshots showing the switch staying in its new state. One earlier, noisier trial (immediately following a scroll gesture, screenshotted only 2s post-tap) appeared to show a revert, but a follow-up `uiautomator` dump from the same trial showed `checked="true"` — inconsistent with a real revert, more consistent with a screenshot taken before a slightly-delayed update finished landing. This could not be reproduced again despite a deliberate rapid-double-tap stress test (which produced a clean, consistent, non-erroring final state both times).

**First failing layer**: none identified in the current code under repeated live testing. No PostgREST error, no RLS denial, no constraint violation was observed in any trial (all real database updates on `public.users` succeeded, confirmed via direct authenticated reads showing the correct value and a fresh `updated_at`).

**Read-only checks performed to rule out account-specific data anomalies**: queried all 24 real `public.users` rows for values violating the `language`/`madhhab`/`role` CHECK constraints (a theory that a pre-existing invalid value on any column could cause an unrelated `UPDATE` to fail row-level validation) — **zero anomalies found**, ruling this out as a live production risk.

### Leading theory, stated plainly

No reproducible code-level defect was found in the current, correct code (post-`AUTH-004` fix, commit `60df35d` onward) after extensive live-device re-testing. The single most likely explanation for the owner's failure, given (a) no functioning app-distribution pipeline exists (`DC-010` remains open; no TestFlight/Play internal testing/Firebase Distribution workflow was found), meaning every device test requires a fresh manual rebuild+reinstall from source, and (b) this exact "stale build reproduces an already-fixed bug" pattern already happened once earlier in this same engagement (caught and corrected mid-`W1-S03`) — is that **the owner's test device was running a build that predates the `AUTH-004` fix commit**, still executing the old code that wrote to the never-live `profiles` columns. This is a theory, not proven fact — this session cannot inspect the owner's device — and is stated as such.

### A genuine, separate code gap found and fixed regardless

`ProfileViewModel.setAnonymousMode()` had no `isSaving` guard, unlike its sibling `updateProfile()` — a rapid double-tap could fire two overlapping requests before the first resolved. This did not produce a visible error in testing (both requests succeeded; the later one's value won), but is a real robustness gap, now fixed: `setAnonymousMode` sets/clears `isSaving` exactly like `updateProfile`, and the Profile screen's toggle now disables (`onChanged: null`) while a save is in flight. `_ToggleRow.onChanged` was widened to nullable to support this.

### G. Minimal fix implemented

Concurrency guard only (§ above) — no change to the write shape itself, which was already confirmed correct (PATCH-style, only `display_name`/`anonymous_mode` sent, per the existing `AUTH-004` fix). No schema change; no production mutation.

### H. Regression tests added (`test/profile_update_observability_test.dart`)

11 new tests: false→true persists; true→false persists; save succeeds for current user; value survives a simulated reload; logout/login (fresh fetch) reloads the correct value; structural cross-account-isolation guarantee (no id/userId parameter exists to target another user, backed by the existing live RLS attack evidence); unrelated fields (`phoneNumber`/`bio`) never sent; a null optional field doesn't break the update; a failure produces the expected user-visible message; a success produces no error; a rapid overlapping second call is dropped, not sent (guards the concurrency fix above). All 11 pass. Full suite: 408 tests, 400 passing (8 known, unchanged golden-image diffs) — 11 more than the prior wave's 397/389, zero new failures.

### I. Live E3 before requesting another owner retest

Performed directly against production this pass, via a synthetic account, through the real app UI (stronger than a REST-only E3): `anonymous_mode` false→true→read-back-true; true→false→read-back-false (via the double-tap trial); confirmed via restart that the value reconstructs correctly from the server (dashboard greeting and Profile identity card both correctly showed the anonymous variant after a full app restart). Synthetic account deleted afterward; zero `@niswah-internal-test.invalid` accounts remain in production (verified via a full sweep).

### J. E4 owner retest gate

Per explicit instruction, this session does not unilaterally close `AUTH-004` from its own re-testing, however strong. **Owner may retry E4 now**, with one specific recommendation: rebuild/reinstall the app from the current repository `HEAD` before retrying, given the leading theory above. Until the owner performs and reports a real, current E4 retest, `AUTH-004` remains `OPEN` / launch blocker, per explicit instruction.

### K. Governance — status record

- **PREVIOUS**: `AUTH-004` = `LIVE_VERIFICATION_REQUIRED`.
- **E4 OWNER TEST**: `FAIL` (preserved as historical fact).
- **CURRENT**: `AUTH-004` = `OPEN` / launch blocker, pending a new owner E4 retest on a confirmed-current build. Not reclassified as resolved by this session.

---

## RR-009 — Reported Near-Blank Render During AUTH-004 E4 Retest (2026-09-11)

**Governance**: `AUTH-004` = `LIVE_VERIFICATION_BLOCKED` (not PASS, not FAIL) — the owner's freshly-rebuilt E4 retest attempt hit a separate rendering issue before the Anonymous Mode flow could be genuinely re-exercised. New finding `RR-009` allocated (Reliability domain) rather than folding this into `AUTH-004`, since no evidence ties it to the `AUTH-004` code change.

### A-C. Reproduction attempt and chronology

Reproduced the named flow (Profile → Privacy Settings → Anonymous Mode) live, on a real Android emulator, using the current `HEAD` build (includes the `AUTH-004` fix and its concurrency-guard follow-up), with a real synthetic account driven through the real UI.

**First attempt**: the emulator instance itself became severely unstable mid-session — repeated "System UI isn't responding" and "niswah isn't responding" ANR dialogs, overlaying an otherwise-correctly-rendered sign-in screen underneath (confirmed via screenshot: the real UI was visible and correct behind the dialog, not blank). Traced live, directly, to a genuinely runaway macOS process (`/usr/libexec/replayd`, unrelated to this app, consuming 80%+ CPU continuously — likely destabilized by the many `xcrun simctl`/screenshot operations across this session's iOS work) compounding with simultaneous iOS Simulator + Xcode + Gradle load on the host machine. Killing the process, quitting the iOS Simulator, and fully cold-restarting the emulator process (not merely an OS-level reboot, which did not resolve it) were all required before the instability cleared.

**Second attempt**, on the freshly cold-booted, unencumbered emulator: the entire flow completed cleanly — sign-in succeeded, the dashboard rendered fully, the Profile tab rendered fully and scrolled correctly through every section, and the Anonymous Mode toggle switched on and stayed on with zero errors, zero blank frames, zero ANR dialogs.

**Static trace, exhaustive**: `grep` across the entire `lib/` tree found exactly one direct `AnimatedOpacity`/`FadeTransition` usage in the whole app (`onboarding_screen.dart` — structurally unrelated to Profile, never reachable from it). Every `SingleChildScrollView` reachable from `ProfileScreen` was traced — the only one (the "Pregnancy Setup" sheet) is correctly wrapped in a `ConstrainedBox(maxHeight: MediaQuery.sizeOf(context).height * 0.85)`, not unbounded. No combination matching the reported `RenderAnimatedOpacity`/`_RenderSingleChildViewport`/unbounded-height pattern was found anywhere in Profile-reachable code.

### D-G. Fix, tests, verification

**No code fix implemented.** Per this engagement's standing discipline against fabricating remediation for a defect that could not be located or reproduced: no widget tree was found responsible, so no "minimal layout fix" is offered — inventing one would not address anything real and would risk masking the actual cause if it resurfaces. This is stated plainly rather than glossed over.

**Live app rendering verification**: completed successfully (second attempt above) — Profile renders under the real, current build; the Anonymous Mode toggle is reachable and functions correctly. This satisfies the "live app rendering verification" requirement for the flow itself; it does not, and cannot, prove the owner's specific reported exception can never occur, only that it did not occur across two full, careful live trials on the current code.

**Regression test**: not added, for the same reason — a regression test needs a known-failing widget tree to assert against, and none was found. Adding a test that merely asserts "Profile renders" would not meaningfully guard against a bug whose location remains unknown, and risks giving false confidence.

### Leading theory, stated plainly, not proven

The phenomenology the owner described — "almost completely blank screen" — is closely consistent with the ANR-driven near-blank overlay state this session independently reproduced and root-caused today, on a genuinely different but analogous instability (a runaway host process starving the emulator's system server). This is offered as the most probable explanation given the evidence gathered, not as a certainty — this session cannot inspect the owner's device, and the specific, structured Flutter exception text the owner's log reportedly contained (`RenderAnimatedOpacity`, an exact constraint chain, cascading semantics assertions) is more detailed than pure resource-starvation symptoms typically produce, so a genuine, not-yet-located code defect cannot be fully ruled out either.

### H. Relationship to AUTH-004

Not caused by the `AUTH-004` remediation, its concurrency-guard follow-up, or any other change made this engagement — confirmed via `git` history (no layout-affecting change touches `ProfileScreen`'s render tree; the `AUTH-004`/concurrency changes only affect a repository method and a callback's nullability, neither of which participates in layout) and via the exhaustive static trace above finding no matching pattern anywhere in the codebase, old or new.

### I. Governance

`RR-009` recorded as `OPEN` — not reproduced, root cause not proven, explicitly not closed on the strength of an inability to reproduce it. `AUTH-004` recorded as `LIVE_VERIFICATION_BLOCKED` — neither PASS nor FAIL from this blocked attempt, per explicit instruction.

**Recommendation to the owner**: retry the AUTH-004 E4 script once more. If the exact same rendering issue recurs, please supply the complete, unabridged Flutter log text (not an excerpt) so the exact source file and line can be identified precisely — the excerpted text available this pass was sufficient to search broadly but not to pinpoint an exact `file:line`. If it does not recur, please proceed with the Anonymous Mode retest as originally planned.

---

## RR-009 — Root-Caused and Remediated: Onboarding Language → Login Transition (2026-09-12)

**Governance**: `RR-009` (Reliability / UI Rendering) — status corrected from `OPEN` (root cause not proven) to `VERIFIED_CLOSED` at the code/E2 level. `AUTH-004` reverts from `LIVE_VERIFICATION_BLOCKED` to `LIVE_VERIFICATION_REQUIRED` — the blocking condition is removed, but the owner's own Anonymous Mode E4 retest still has not happened, so this is a reversion to the prior state, not a PASS.

### A-B. Reproduction and exact state transition

Owner report: mid-onboarding, on the language-selection step, selecting a language and tapping Continue produced an almost entirely white next step — only the shared progress bar and back chevron (both outside the switched content) remained visible.

Reproduced live, on demand, using a fresh synthetic account and real device UI interaction (Android emulator, current `HEAD`): sign in (fresh account, `onboarding_completed=false`, real sign-in so `isNewSignUp=false` → onboarding starts at step 1) → tap "Get Started" (step 1 → 2) → select a language → tap Continue (step 2 → 3). **Exact transition**: `_step` 2 → 3, `_screen()` switches from `_Language` to `SignInScreen(onAuthenticated: _next)` (the onboarding flow's own "Login" step — see the class doc comment's own step map). The full, real Flutter runtime log was captured (`flutter run`, not just `flutter build`) and confirms the exact exception cascade: `RenderCustomMultiChildLayoutBox`, `_RenderInkFeatures`, `RenderPhysicalModel`, `RenderConstrainedBox`, `RenderTransform`, `RenderFractionalTranslation`, and finally `RenderAnimatedOpacity` — each "given an infinite size during layout," ancestor in every case `_RenderSingleChildViewport` — culminating in `'package:flutter/src/rendering/stack.dart': Failed assertion: line 666 pos 7: 'size.isFinite': A Stack requires bounded constraints from its parent.`

### Exact primary exception and responsible widget chain

The first exception's full stack trace was captured and traced frame-by-frame. Frame `#60: _ScaffoldLayout.performLayout (package:flutter/src/material/scaffold.dart:1113:7)` proves the `RenderCustomMultiChildLayoutBox` given infinite size *is `SignInScreen`'s own nested `Scaffold`*. The chain: `_RenderSingleChildViewport` (`onboarding_screen.dart`'s `SingleChildScrollView`) → `RenderPadding` → `RenderStack` (the onboarding shell's own `Stack`, back-button + content) → `RenderPositionedBox` (`Center`) → `RenderStack` (`AnimatedSwitcher`'s internal `Stack`) → the `FadeTransition`/`SlideTransition`/`ScaleTransition` proxy chain (`RenderAnimatedOpacity` etc.) → `ConstrainedBox(maxWidth: 390)` → `SignInScreen`'s own `Scaffold` → `SafeArea` → `Stack` (containing `Center` + `PositionedDirectional(_LanguageToggle)`).

Two independent structural facts require bounded height here, confirmed via the log: (1) `_ScaffoldLayout` fundamentally sizes itself to fill available space; (2) `RenderStack`'s own explicit assertion — a `Stack` containing a `Positioned`/`PositionedDirectional` child (the language toggle, positioned `top: 8, end: 8` inside `SignInScreen`) cannot compute a size without a finite incoming constraint. `SingleChildScrollView`, by design, hands its child unbounded height along the scroll axis — a correct, intentional behavior every *other* (plain `Column`) onboarding step relies on for small-screen/large-text scroll-safety. `SignInScreen`'s nested `Scaffold` + `Stack`/`Positioned` is the one widget combination in this codebase incompatible with that.

### Historical/regression cause

Not a regression from any change made during this engagement — `git log -p` on both files shows this exact structure (onboarding's shared shell, `SignInScreen`'s `Scaffold`+`Stack`+`Positioned`) predates this engagement's own history. `SignInScreen`'s own doc comment already stated the intent explicitly: *"reused as onboarding's own login step"* — the dual-use was deliberate by design, but the embedding was never actually made safe for it. This is a **pre-existing, latent defect**, not a new one — reachable by any real user who signs in without having just completed sign-up (i.e., `isNewSignUp == false`, which includes every returning-but-onboarding-incomplete session, the exact case `AUTH-002`/`AUTH-003` are about), not merely a rare edge case.

### Relationship to RR-009 (original report) — Outcome A, decided on evidence

The original `RR-009` report (attributed to "Profile" by the owner) could not be reproduced anywhere in `ProfileScreen`'s own code, despite an exhaustive trace. This pass's onboarding reproduction produces the **identical exception signature** (`RenderAnimatedOpacity`, `_RenderSingleChildViewport`, matching constraint pattern) at the **one and only place in the entire codebase** with this specific widget combination (confirmed via the same exhaustive `grep` from the original investigation — `AnimatedSwitcher`+`FadeTransition` inside `SingleChildScrollView` exists nowhere else). Given a fresh test account with `onboarding_completed=false` is *always* routed through onboarding starting at step 1 before ever reaching Profile, the most parsimonious, evidence-based conclusion is that the original report was this same defect, encountered mid-onboarding and described by the owner using the destination they expected rather than the screen actually failing. Reclassified as the same finding (Outcome A), not decided from visual similarity alone but from an identical, independently-reproduced exception at the sole structurally-matching site.

### D. Remediation — including a self-caught wrong first attempt

**First attempt (incorrect, caught by this pass's own regression tests before being reported as a fix)**: bounded the shared shell's switched-content height directly via `LayoutBuilder` + `ConstrainedBox(maxHeight: viewportConstraints.maxHeight)`. This fixed step 3 — but the new all-step state-machine test immediately caught a real regression: steps 4 (Madhhab choices) and 7 (Last Period, a full calendar grid) began throwing genuine `RenderFlex overflow` at small test viewports, because they'd lost the original `SingleChildScrollView`'s unbounded growing room that they, unlike step 3, actually need and were always safe with. Reverted before being finalized.

**Actual fix — the shared shell is untouched**, restored to its exact original form. `SignInScreen` itself was fixed instead: a new `embedded` constructor flag (`bool embedded = false`) controls whether it returns its original `Scaffold`-wrapped, `Stack`/`Positioned`-based layout (default — the standalone top-level route in `main.dart`, `const SignInScreen()`, is completely unaffected, unchanged, still explicitly bounded by `MaterialApp`'s own routing) or, when `true`, a plain `Column` (language toggle, then the scrollable sign-in content) with no `Scaffold` and no `Stack`/`Positioned` at all. A `Column` has no bounded-height requirement of its own — it sizes to its natural content regardless of whether its ancestor's height is bounded (top-level `Scaffold` body) or unbounded (onboarding's `SingleChildScrollView`), making it safe in both contexts without special-casing the shared shell for one step. Onboarding's step 3 now instantiates `SignInScreen(onAuthenticated: _next, embedded: true)`.

### E-F. Regression tests and state-machine sweep

18 new tests, `test/onboarding_ui_test.dart`:
- English and Arabic language selection → Continue → real step-3 content visible (not blank), no exception.
- A locale toggled back and forth before continuing does not desynchronize the step index.
- Back navigation from step 3 returns to the language step; Continue still works after going back once.
- Small viewport (320×568), 200% text scale, and semantics-enabled variants of the same transition — all pass with no layout exception.
- **10-step state-machine sweep** (Section L): every step 1-10 rendered directly via `initialStep`, asserting real, step-specific content is present (never just the shared shell) and no exception is thrown. This is the test that caught the first, incorrect fix attempt's regression on steps 4 and 7 before it was ever proposed as done.

Full suite re-run: zero new failures, same 8 known, unchanged golden-image diffs as every prior wave.

### G. Semantics recheck

The semantics-enabled variant of the language→login transition test passes cleanly (`tester.ensureSemantics()`, full transition, `tester.takeException()` is null). No `parentDataDirty`/`needsLayout` cascade — consistent with the charter's own expectation that these were downstream consequences of the primary infinite-size layout failure, now that the primary failure is gone.

### H. Live verification (Android; iOS documented precisely)

The exact failing sequence was reproduced live on a real Android emulator running the pre-fix build (full Flutter log captured, exception cascade confirmed), then, after the fix, the identical live sequence was re-run twice on a fresh rebuild — once selecting Arabic, once leaving English selected — both completing cleanly with zero exceptions, real step-3 content fully visible and interactive. **iOS**: interactive UI automation (taps, text entry) remains unavailable in this environment — no `idb`, no System Events accessibility access to the Simulator window, the same limitation documented in the original `RR-009` investigation. A clean iOS build was confirmed instead. Since this is a pure Dart/Flutter layout defect with zero platform-specific code involved, and the fix was verified against Flutter's own real constraint-solving behavior (not anything emulator-specific), Android's live evidence is offered as representative of iOS — stated as an inference, not claimed as literal iOS-device evidence.

### N. AUTH-002 / AUTH-003 impact — not reopened, proven not just asserted

Neither finding is affected. `git diff` confirms this pass touched only `sign_in_screen.dart` (layout structure) and one line of `onboarding_screen.dart` (the step-3 instantiation call, adding `embedded: true`) — `AuthController`, `AuthRepositoryImpl`'s onboarding-completion read/write, and the `_step` state-machine's own persistence behavior are byte-for-byte unchanged. The server-side onboarding-completion invariant (`AUTH-002`) and the partial-onboarding no-false-completion invariant (`AUTH-003`) are both structurally untouched by this fix.

### Governance record

- **RR-009**: `VERIFIED_CLOSED` at the code/E2 level (root-caused with a full stack trace, fixed at the true source after a wrong first attempt was self-caught and corrected, regression-tested exhaustively including the exact state-machine sweep that would have caught the original bug). A live *owner* E4 retest remains recommended, not yet performed.
- **AUTH-004**: reverts to `LIVE_VERIFICATION_REQUIRED` — the onboarding blocker that prevented ever reaching a stable completed account is resolved; the Anonymous Mode toggle itself still requires the owner's own retest.
- **AUTH-002 / AUTH-003**: unaffected, not reopened.
- **Overall verdict: `NO-GO`, unchanged** — `AUTH-001` remains the sole owner-gated blocker.

---

## Wave 1 Evidence Reconciliation — Owner Combined iOS E4 Acceptance (2026-09-12)

The owner performed a real, combined iOS E4 acceptance pass against production, on commit `72204b28eca759509230318184caf79d8da3c282` (the exact commit this session's `RR-009` fix and prior `AUTH-004` work were pushed on), and reported:

**`RR-009`**: onboarding language → `SignInScreen` transition rendered correctly (PASS); no white/empty body (PASS); no `RenderAnimatedOpacity`/infinite-size recurrence (PASS); full onboarding completed through to the dashboard (PASS); no empty onboarding step encountered anywhere in the flow (PASS).

**`AUTH-004`**: Profile → Privacy Settings reachable (PASS); Anonymous Mode changed successfully (PASS); no "Unable to update your profile right now" error (PASS); value persisted after a full app restart (PASS); value persisted after logout/login (PASS).

### Canonical closure — evaluated against the threshold, not assumed

**`RR-009`**: proven root cause (full stack trace, exact responsible frame identified) — remediation (the `embedded`-flag fix, source-level not shell-level) — automated regression (18 new tests, including the state-machine sweep and the viewport/text-scale sweep that caught this fix's own first wrong attempt) — Android live verification (this session, real device, real taps, before/after) — owner iOS E4 verification (this pass, real device, real production backend). **All five elements of the canonical threshold are now satisfied.** Status: **`VERIFIED_CLOSED`**.

**`AUTH-004`**: root cause (the `profiles`/`users` schema mismatch, historically traced to a never-applied migration) — remediation (`updateProfile`/`getProfile` retargeted to `public.users`) — E3 evidence (real synthetic-account writes/reads, cross-account RLS isolation) — the blocking `RR-009` rendering defect now resolved — real owner E4 acceptance on iOS covering the toggle itself, the error-message regression, and both persistence paths (restart, logout/login). **The canonical E4 threshold is satisfied.** Status: **`VERIFIED_CLOSED`**.

### Preserved, unchanged

- **`AUTH-001`**: `BLOCKER` — owner-gated (config authorization for `site_url`/`uri_allow_list`, plus SMTP), unaffected by this reconciliation.
- **`AUTH-002`**: `ADVERSARIAL_VERIFIED`, unchanged.
- **`AUTH-003`**: tracked/non-blocking — the no-false-completion invariant continues to hold; step-level resume remains an accepted, documented limitation.
- **`AUTH-005`** (selected madhhab, `LOCAL_ONLY_UNSAFE`): `OPEN`/tracked, unchanged — a real feature addition, not part of this reconciliation's scope.
- **`AUTH-006`** (prayer location, `LOCAL_ONLY_UNSAFE`): `OPEN`/tracked, unchanged — same reasoning.

### Wave 1 remaining blockers, post-reconciliation

**`AUTH-001` only.** Every other Wave 1 finding is either `VERIFIED_CLOSED`/`ADVERSARIAL_VERIFIED` (no longer blocking) or explicitly tracked as non-blocking (`AUTH-003`, `AUTH-005`, `AUTH-006`).

### Global remaining blockers

`AUTH-001` (Wave 1, owner-gated), `DC-010` (iOS production signing, owner-gated — standing, unrelated to this wave), `PC-006` (data-export retention/legal determination, counsel-gated — standing, unrelated to this wave).

### Overall verdict

**`NO-GO`**, unchanged — held exclusively by `AUTH-001` within Wave 1's scope, plus the two standing, unrelated `DC-010`/`PC-006` items outside it.

---

## AUTH-001 Production Closure — Configuration Applied (2026-09-12)

**Owner authorization**: explicit, scoped authorization received to apply the non-secret production Auth configuration changes for `AUTH-001` only, conditional on live values matching the documented baseline.

### A. Pre-mutation snapshot vs. documented baseline

Live production Auth config was read via the Management API (`GET /v1/projects/jkmjobvxfrmuwafczvtw/config/auth`) before any change:

| Field | Live value (pre-mutation) | Matches documented baseline? |
|---|---|---|
| `site_url` | `https://niswah.vercel.app` | Yes |
| `uri_allow_list` | 4 Vercel-domain entries only (`https://niswah.vercel.app`, `.../**`, and the same two for a Vercel preview-deployment hostname) | Yes — "Vercel-domain entries only," no custom scheme present |
| `mailer_autoconfirm` | `false` (confirmation required) | Yes |
| `external_email_enabled` | `true` | Yes |
| `mailer_subjects_confirmation` / `_recovery` | Generic Supabase defaults ("Confirm your email address" / "Reset your password") | Yes — confirmed still unbranded |
| `mailer_templates_confirmation_content` / `_recovery_content` | Generic Supabase default HTML (no Niswah branding, no Arabic) | Yes |
| `smtp_host`/`smtp_port`/`smtp_user`/`smtp_sender_name`/`smtp_admin_email` | all `null` | Yes — SMTP still not configured |
| `external_google_enabled` | **`false`** | New, precise confirmation this pass (not previously stated this explicitly) — Google OAuth is currently disabled at the Supabase provider level in production, independent of the app's own code. `external_google_client_id` holds what appears to be a personal email address rather than a real OAuth client ID, consistent with this provider never having been properly configured. |

All values matched the documented baseline closely enough to proceed per the owner's stated condition. No mismatch required stopping.

### B-C. SITE_URL, mobile callback, redirect allowlist

Reconfirmed unchanged: `niswah.app` still has no web server (only MX records, per the prior wave's check); `niswah://login-callback` remains the correct mobile callback, already registered natively on both platforms (Android `AndroidManifest.xml`, iOS `Info.plist` — both re-checked this pass, unchanged). Applied exactly the previously-approved design: `site_url` set to the mobile scheme; the same scheme appended to `uri_allow_list`; the four existing Vercel entries preserved untouched (the live, current web-reference deployment, a separate purpose). A future HTTPS universal/app-link destination under `niswah.app` remains the preferred long-term design once a real web landing endpoint exists — not built this wave, out of scope.

### D. Flutter redirect contract — reconfirmed, no code change needed

`signUp`/`resend` (`emailRedirectTo`), `resetPasswordForEmail` (`redirectTo`), and `signInWithGoogle` (`redirectTo`, fixed in a prior pass this wave) all already explicitly pass `niswah://login-callback`. No magic-link or OTP flow is used. Email-change is not reachable by any current app code (writes go to `profiles.email`, a column confirmed not to exist — `AUTH-004`'s original finding, unrelated to this wave's scope). No code change was necessary or made.

### E. Auth email templates — applied

Applied the two reachable, launch-relevant templates exactly as previously prepared and re-validated this pass (`AUTH_email_templates_prepared.md`): signup confirmation and password recovery, both bilingual (Arabic first, English second), both using `{{ .ConfirmationURL }}` correctly, no fabricated URLs, no stale Vercel references, no secrets. Email-change/magic-link/invite templates were **not** applied — confirmed via exhaustive `grep` (again, this pass) that no current app code reaches any of those three flows, so branding them carries no current user-facing benefit and was left out to keep this mutation minimal and exactly in scope.

### F. Google OAuth

Reconstructed the prior finding: `signInWithGoogle()` previously passed `redirectTo: null` (falls back to `site_url`); already fixed to pass the explicit callback in a prior pass. This pass's live config read confirms **Google OAuth itself is currently disabled** in production (`external_google_enabled: false`), with what looks like a placeholder value (a personal email address, not a real OAuth client ID) in the client-ID field. **Not touched this pass** — enabling it would require a real Google OAuth client ID/secret pair, which is Google Cloud Console + Supabase Dashboard configuration requiring real provider credentials this session does not have and must not request or generate. This is an owner-only action, out of this wave's authorized scope (the owner's authorization named only `site_url`/allowlist/redirect config/email templates/"Google OAuth redirect **corrections already documented**" — the app-code redirect fix, already done — not enabling the provider itself, which was never part of any prior `AUTH-001` proposal). Flagged precisely, not silently left ambiguous.

### G. Applied and read back — actual == expected, not inferred from HTTP 200 alone

`PATCH /v1/projects/jkmjobvxfrmuwafczvtw/config/auth` with exactly six fields (`site_url`, `uri_allow_list`, `mailer_subjects_confirmation`, `mailer_subjects_recovery`, `mailer_templates_confirmation_content`, `mailer_templates_recovery_content`) → `HTTP 200`. Immediately re-read the full live config and diffed every changed field against the exact intended value: **all six matched exactly** (subjects/URLs compared as exact strings; HTML template bodies compared by exact length and content). Every other field in the ~150-field config (SMTP, Google OAuth, all other providers, MFA, rate limits, sessions, etc.) was independently confirmed **unchanged** — the mutation's blast radius was exactly the six intended fields, nothing else.

### H. SMTP — still owner-only, unchanged this pass

`smtp_host`/`smtp_port`/`smtp_user`/`smtp_pass`/`smtp_sender_name`/`smtp_admin_email` remain `null` — not touched, not requested. Exact owner action, unchanged from the prior wave's preparation: Supabase Dashboard → Project Settings → Authentication → SMTP Settings — enter sender email (any real, deliverable address on a domain the owner controls), sender name (`Niswah`/`نسوة`), and the host/port/username/password issued by whichever transactional-email provider is chosen. This session will not see or request these values at any point.

### J. Pre-owner automated verification — completed

1. Live Auth config equals intended values — confirmed via direct read-back (§G above).
2. Mobile callback still registered on Android — reconfirmed via `AndroidManifest.xml` (unchanged, `niswah`/`login-callback` intent-filter present).
3. Mobile callback still registered on iOS — reconfirmed via `Info.plist` (unchanged, `CFBundleURLSchemes` contains `niswah`).
4. Redirect allowlist contains the intended callback — confirmed (`niswah://login-callback` now present alongside the untouched Vercel entries).
5. No stale Vercel auth destination used by production app code — confirmed via exhaustive `grep` of `lib/`, zero matches for `niswah.vercel.app` or the reported "niswal" typo anywhere in app code.
6. Email templates contain the intended Niswah branding — confirmed via exact read-back match against the prepared HTML.
7. Onboarding routing regression tests pass — full suite re-run, no code changed this pass, baseline unaffected.
8. Full application regression remains clean — 418 tests, 410 passing, the same 8 known, unchanged golden-image diffs as every prior wave; zero new failures.
9. `AUTH-002` remains protected — no code touched this pass (Auth config only); its own regression tests are part of the unchanged 410 passing.
10. `AUTH-004` remains protected — same reasoning; its own regression tests are part of the unchanged 410 passing.

### I/L. AUTH-001 status — not closed by config deployment alone

Per explicit instruction, production configuration deployment does **not** by itself close `AUTH-001`. The full closure standard (config applied ✓, templates deployed ✓, SMTP active ✗, real confirmation email received ✗, real confirmation callback succeeds ✗, real new user reaches dashboard ✗, logout/login ✗, no stale Vercel destination ✓, no default Supabase branding on the two reachable flows ✓) is **not yet fully satisfied** — SMTP remains the one owner-only gap standing between the current state and a real E4 acceptance journey. **`AUTH-001` status: `LIVE_VERIFICATION_REQUIRED`** (config-complete, SMTP-pending) — not `VERIFIED_CLOSED`.

### K. Final owner acceptance script — prepared, not yet actionable

The script is ready (see `docs/final-owner-launch-checklist.md`'s Authentication/Onboarding Handoff section) but should not be run until SMTP is active — without it, a real signup would still hit the same `HTTP 429 over_email_send_rate_limit` this engagement already documented against Supabase's own default mailer. Once SMTP is configured, the owner should: use a genuinely new email → sign up → confirm the email is Niswah-branded → tap the confirmation link → confirm it opens the app directly (not a browser) → confirm onboarding appears → complete onboarding → confirm the dashboard appears → log out → log back in → confirm the dashboard appears again. Report PASS, or FAIL with what was visibly wrong — no code/database/log inspection required.

### M. Wave 1 closure — not yet, pending SMTP + the real owner journey

Wave 1 (Authentication + Identity + Session + Onboarding) is **not yet marked COMPLETE** — `AUTH-001` remains the sole blocker, now reduced to exactly one remaining owner action (SMTP) plus the one real acceptance journey that follows it. `AUTH-005`/`AUTH-006` remain tracked, non-blocking findings for a future wave, unaffected by this closure work.

**Overall verdict: `NO-GO`, unchanged.**

## Email Template Standardization — All Auth/Security Templates Unified (2026-09-13)

Per explicit owner instruction, every customer-facing auth/security email template was audited against Supabase's live config and standardized to one bilingual (Arabic-first, English-second) visual identity, using the already-applied Confirm Signup template as the canonical design reference. Full detail, exact HTML/subjects, and the reachability/variable-safety analysis: `production-readiness-results/adversarial-validation/AUTH_email_templates_prepared.md`; full 11-item consolidated report: `00_09_PHASE1_ROOT_CAUSE_REMEDIATION_PLAN.md` §70.

**Summary**: confirmation and recovery (already live) gained an additive standardized bilingual security footer. Four dormant-but-brand-ready templates were newly built and applied — email-change confirmation, reauthentication (OTP code), password-changed notification, email-changed notification — none currently reachable by app code (two related functional gaps were discovered as a byproduct and flagged, not fixed: no screen completes the password-recovery flow, and email-change still targets a non-existent database column). Seven templates (magic link, invite, phone-changed, identity-linked/unlinked, MFA-enrolled/unenrolled) were inspected and deliberately left as unmodified Supabase defaults, per instruction. Applied via a 10-field `PATCH`, independently read back (actual == expected, zero unexplained drift across the full config), full regression re-run clean. This wave does not change `AUTH-001`'s status (`LIVE_VERIFICATION_REQUIRED`, unchanged) and closes no numbered finding — it is a proactive consistency/hardening task.

## Final Email Template Completeness Pass — 13/13 Templates Now Standardized (2026-09-13, later the same day)

The remaining 7 templates (magic link, invite, phone-changed, identity-linked, identity-unlinked, MFA-enrolled, MFA-unenrolled) — previously left as unmodified Supabase English-only defaults per the prior wave's "inspect but do not enable" scope — were standardized to the same canonical bilingual visual identity and applied to production, per explicit owner instruction to complete template hygiene without enabling any feature. Full detail: `AUTH_email_templates_prepared.md` §7-13; full 13-item consolidated report: `00_09_PHASE1_ROOT_CAUSE_REMEDIATION_PLAN.md` §71.

**Summary**: all 13 Supabase auth/security email templates are now bilingual and Niswah-branded. A keyed check of both this pass's and the prior pass's `PATCH` payloads confirmed every field touched across both was `mailer_subjects_*`/`mailer_templates_*` — no `site_url`, `uri_allow_list`, `smtp_*`, provider-enablement, MFA, or rate-limit field was ever included, so no feature was enabled. Read-back confirmed actual == expected on all 14 fields with zero unexplained drift (the only other change, the 7 corresponding `*_custom_contents` booleans, is Supabase's own auto-derived indicator and flipped exactly as expected — all 13/13 now `True`). Full regression re-run clean. One incidental observation, not investigated or acted on per this pass's explicit instruction not to begin `AUTH-001` E4: `smtp_host` is no longer `null` (now `mail.spacemail.com`), suggesting the owner has begun SMTP setup independently since the prior wave. `AUTH-001`'s status is unchanged (`LIVE_VERIFICATION_REQUIRED`); this pass closes no numbered finding.

## Wave 1 Final Auth/Localization Closure (2026-09-13)

Triggered by the owner's real production new-user journey: SMTP delivery, sender identity, bilingual template rendering, and server-side confirmation all **PASS** on genuine E4 evidence — the strongest tier used throughout this engagement — alongside three newly-discovered live defects. This section governs, root-causes, remediates, and tests all three.

### A — Governance

Three defects reported; per the charter's own instruction, findings are consolidated only where a shared root cause is genuinely proven, not assumed:

- **Item A (confirmation empty-page/fallback UX)** retained inside **`AUTH-001`** — it is the direct continuation of that finding's original redirect-destination scope, now narrowed to exactly this sub-issue with everything else on E4 evidence.
- **Items B (Madhhab shows English) and C (Sign In/Sign Up RTL mirroring)** are tracked together as **`AUTH-007`** (new) — investigation proved, with code-level evidence (not assumption), that both are two symptoms of the exact same root cause. See §F/G/H below for the proof. Consolidating them matches the charter's own explicit conditional ("do not hide all three defects inside AUTH-001 unless they genuinely share one root cause" — here two of the three genuinely do, so they are tracked as one).

### B — AUTH-001 evidence reconciliation

Recorded, not re-run: **SMTP delivery = E4 PASS**; **Niswah sender identity = E4 PASS**; **bilingual confirmation template = E4 PASS**; **confirmation token processing = E4 PASS**; **server email-confirmed state = E4 PASS**. `AUTH-001` remains open **only** for the confirmation-destination/fallback UX component below.

### C — Confirmation empty-page root cause

Traced without needing new live network capture — the mechanism is already fully determined by facts already on record:

1. `site_url` is currently `niswah://login-callback` (applied in the AUTH-001 Production Closure wave) — a bare custom URI scheme with **zero HTTP content**, no fallback page of any kind.
2. Supabase's `/auth/v1/verify` endpoint processes the confirmation token **server-side first**, then issues an HTTP redirect to `site_url` (plus query parameters) as its **last** step. Server-side token verification and the client-facing redirect are two separate, sequential steps — a redirect never fires without verification having already succeeded.
3. The owner opened the confirmation link in **desktop Chrome**, on a **different device** than the one running Niswah (an iOS Simulator on the same machine, but Simulator apps are not reachable by the host macOS's own custom-URI-scheme resolution — a Simulator is a separate OS instance from the host, and even setting that aside, desktop Chrome itself has no `niswah://` scheme handler registered at the OS level under any circumstance).
4. Chrome therefore received a `302` redirect to a URI scheme it cannot resolve. There is no HTTP fallback content at that destination (per point 1) for the browser to render instead. The observed result — an empty/dead-end page — is the fully-expected behavior of a browser handed a redirect to an unresolvable custom scheme with nothing else to show.

**Conclusion**: token verification and server-side confirmation genuinely succeeded (matches the proven E4 evidence in §B — this is exactly why the account was recognized as confirmed when the owner returned to the app). This is a **client-side, customer-facing fallback/handoff defect**, not an authentication or delivery failure, and per the charter's explicit instruction is not classified as one.

### D/E — Production-grade auth callback: design (not implemented, not deployed)

Per explicit instruction, `site_url`/`uri_allow_list` were **not mutated** this pass. The following is the design deliverable only.

**CURRENT FLOW**
```
Gmail → tap confirmation link
  → Supabase /auth/v1/verify (token check, succeeds)
  → 302 redirect to site_url = niswah://login-callback
  → resolvable only by a device with Niswah installed AND the tap
    happening on that same device
  → any other device/browser: unresolvable scheme, no fallback content
    → empty/dead-end page
```

**PROPOSED FLOW**
```
Gmail → tap confirmation link
  → Supabase /auth/v1/verify (token check, succeeds)
  → 302 redirect to https://niswah.app/auth/confirmed?... (or
    https://auth.niswah.app/confirmed?...)
  → branded HTTPS page loads on ANY device/browser:
      - if opened on a device with Niswah installed AND the link is
        registered as a Universal Link (iOS) / App Link (Android),
        the OS intercepts the HTTPS request before it ever reaches a
        browser and opens Niswah directly — no page ever shown
      - otherwise (desktop, no app installed, App/Universal Link not
        yet verified by the OS): the branded HTTPS page itself renders,
        showing a bilingual success message and an explicit "Open
        Niswah" button (niswah://login-callback as its href — a plain
        custom-scheme link tapped by a human, which is a fundamentally
        different and far more forgiving case than an automated
        redirect target, since a browser presents a normal "open in
        app?" prompt for a user-initiated link tap instead of silently
        failing)
      - a distinct failure/expired-link state is shown if verification
        did not succeed
```

**IMPLEMENTATION REQUIREMENTS**
- A new route/page (bilingual, Niswah-branded, matching the exact copy specified in this wave's charter) served over HTTPS at the chosen path.
- `site_url` and `uri_allow_list` updated to point at the new HTTPS URL instead of the bare custom scheme (a separate, explicitly-authorized production mutation — not this pass).
- The page must not display the raw token/URL query parameters as visible content (Supabase's verify step already consumes the token before redirecting, so the redirect target only carries non-sensitive state, but the page's own implementation must still avoid echoing any query parameter into visible markup unfiltered).

**iOS REQUIREMENTS**: an `apple-app-site-association` file served at `https://niswah.app/.well-known/apple-app-site-association` (no file extension, exact Apple-specified JSON shape, correct Team ID + Bundle ID), plus the corresponding Associated Domains entitlement (`applinks:niswah.app`) added to the iOS app target so the OS treats matching HTTPS links as Universal Links instead of routing them to Safari.

**ANDROID REQUIREMENTS**: an `assetlinks.json` file served at `https://niswah.app/.well-known/assetlinks.json` (correct package name + SHA-256 signing certificate fingerprint), plus an `<intent-filter android:autoVerify="true">` for the matching HTTPS host in `AndroidManifest.xml` so the OS verifies and treats the domain as an App Link.

**WEB/DNS REQUIREMENTS** — **this is the exact owner boundary this pass stops at**: `niswah.app` currently has no web server and is not connected to any hosting/CDN provider (re-confirmed this pass: still true, unchanged since the original AUTH-001 investigation). Using the existing Vercel project (already serving `niswah.vercel.app`, the web-reference build) as the underlying infrastructure is acceptable **once the custom domain `niswah.app` is pointed at it** — that domain connection is a Vercel dashboard + DNS-registrar action only the owner can perform (this session has no access to either). No `vercel.app` hostname may ever be the customer-visible destination.

**ROLLBACK**: revert `site_url`/`uri_allow_list` to the current values (`niswah://login-callback` + the same allow-list) — a same-shape, single-field-class `PATCH`, fully reversible, no data loss, no schema involved.

**Status**: design complete; implementation and deployment explicitly **not started**, pending (1) owner DNS/custom-domain action connecting `niswah.app`, and (2) a separate, explicitly-scoped authorization to mutate `site_url`/`uri_allow_list` again — matching the same production-safety discipline used for every prior `AUTH-001` mutation this engagement.

### F/G — Arabic locale propagation root cause (Madhhab + every post-login step)

Traced precisely via code inspection, not assumption:

`AppLocaleController` (`lib/core/localization/app_locale_controller.dart`) is the app's real, single source of truth — a `ChangeNotifier` singleton, persisted to `SharedPreferences` (`niswah_arabic`), loaded synchronously before any screen ever builds (`main.dart`: `await AppLocaleController.instance.load()` runs before `runApp`). The language-selection step and `SignInScreen` both read it directly and correctly.

`_OnboardingScreenState` (`lib/features/onboarding/presentation/screens/onboarding_screen.dart`), however, kept its **own** local field: `bool _arabic = false;` — hardcoded English, entirely disconnected from the controller above. Every step's text (`_t`/`_tr` helpers, the Madhhab choice list, the Directionality wrapper around the whole shared step shell) read this local field, not the controller. The language-selection step's `onSelect` callback updated **both** (`setState(() => _arabic = v)` **and** `AppLocaleController.instance.setArabic(v)`), which kept the two in sync for the remainder of that *same* widget-instance lifetime — masking the bug in every prior test and in any single, uninterrupted onboarding pass.

The bug surfaces precisely when a **fresh** `_OnboardingScreenState` is created after Arabic was already selected and persisted in an earlier attempt. The realistic, proven trigger matches the owner's own E4 sequence exactly: the user picks Arabic, proceeds to the login/signup step, submits signup, leaves the app to confirm their email, and is re-routed through onboarding on return. `AppLocaleController.instance.isArabic` is correctly still `true` (real persistence, real controller) — but the **new** `_OnboardingScreenState`'s own `_arabic` field starts over at its hardcoded `false`, and nothing ever resyncs it from the controller. This is the same class of gap the code's own comment already anticipated and handled for `_isMarried` (deliberately restored from `MaritalStatusController` in `initState()`, "a returning user re-routed through onboarding already has a saved answer — show it selected instead of blank") — `_arabic` was simply never given the same treatment.

**Not a locale-persistence bug, not a missing-translation-keys bug, not a system-locale-read bug** — every string involved already had a correct Arabic translation on file; the persistence layer (`SharedPreferences`) worked correctly throughout. The defect is a **duplicated, desynchronized local copy of state that already has one authoritative source**.

### H — Sign In / Sign Up RTL root cause

The exact same root cause, manifesting differently: `SignInScreen` never had this bug in its own **text** (it reads `AppLocaleController` directly, always correctly) — but when embedded at onboarding step 3, it has no `Directionality` of its own and inherits it from the onboarding shell's wrapper (`Directionality(textDirection: _arabic ? rtl : ltr, ...)`), which used the **same stale field** described above. The result: genuinely-Arabic text (`تسجيل الدخول`, `إنشاء حساب`, etc. — always correct) rendered inside a layout still resolving to **LTR** ambient direction — precisely "flipped/mirrored," because every RTL-aware widget in that subtree (the automatic `Row` reversal for the Sign In/Sign Up tab order, `PositionedDirectional`, etc.) never actually engaged.

**Audited and found already correct** (charter item I — tab semantics): `_modeTab`'s displayed label, active/selected highlight, and tap handler are all driven by the exact same `signUp` boolean parameter on each call — there is no code path by which the visible label and the mode a tap activates could ever disagree, in either language. Flutter's own `Row` widget already reverses child order automatically under ambient RTL `Directionality` (matching the charter's own "use semantic RTL behavior, do not blindly mirror" guidance) — this was already correct and is now locked in with explicit test coverage rather than changed.

**One additional, independent, minor defect found during this same investigation**: the onboarding back-navigation icon (`Icons.chevron_left_rounded`) is a plain, non-directional glyph — Flutter does not auto-mirror icon glyphs, only widget *position* (its `PositionedDirectional` wrapper was already correctly RTL-aware; only the glyph itself pointed the wrong visual way in RTL).

### Remediation implemented (item 12)

- `lib/features/onboarding/presentation/screens/onboarding_screen.dart`: `_arabic` converted from a stored field to `bool get _arabic => AppLocaleController.instance.isArabic;` — a live read from the single authoritative source, immune to State recreation by construction (not merely patched to read correctly once). The language-select callback simplified to `onSelect: (v) => setState(() => AppLocaleController.instance.setArabic(v))`. The back-navigation icon now swaps `chevron_left_rounded`/`chevron_right_rounded` based on the same source.
- `lib/features/auth/presentation/screens/sign_in_screen.dart`: added stable `Key`s (`mode_tab_sign_in`/`mode_tab_sign_up`) to the Sign In/Sign Up tabs — a test-reliability improvement only (the existing headline text and the tab label happen to share the same string, making plain-text finders ambiguous), no behavior change.
- No hardcoded heights, no arbitrary delays, no error suppression, no forced navigation — matches the same minimal-fix discipline used throughout this engagement.

### Test results (items 13-19)

- **Arabic full-onboarding sweep (item 13)**: PASS — 10/10 steps (`onboarding_ui_test.dart`, `AUTH-007` group), each constructing a fresh `OnboardingScreen` with `AppLocaleController` already set to Arabic *before* the widget builds (the exact real-world trigger), asserting the correct Arabic content and explicitly asserting the English marker is absent (no silent fallback).
- **English full-onboarding sweep (item 14)**: PASS — the pre-existing 10-step state-machine group (unchanged, still green) already covers this continuously; re-verified clean after the fix.
- **Madhhab Arabic result (item 15)**: PASS — `حنفي`/`مالكي`/`شافعي`/`حنبلي` all render correctly; explicit assertion that no English madhhab name (`Hanafi`/`Maliki`/`Shafii`/`Hanbali`) is present.
- **Sign In/Sign Up RTL result (item 16)**: PASS — 3 tests in the new `test/sign_in_rtl_test.dart` cover standalone English/LTR, standalone Arabic/RTL, and embedded (onboarding step 3) Arabic/RTL: correct tab labels, correct `Directionality`, and correct tap → mode semantics (tapping `إنشاء حساب` renders the signup-only `الاسم الكامل` field; tapping `تسجيل الدخول` hides it again — and the English equivalent).
- **200% text-scale result (item 17)**: PASS — no layout exception at `TextScaler.linear(2.0)` on the Arabic entry step.
- **Semantics result (item 18)**: PASS — Arabic entry step exposes a valid, disposable semantics tree with no exception.
- **Full regression result (item 19)**: 445 tests total, 437 passing, same 8 known pre-existing golden-image parity diffs, **zero new failures**.

A genuine, incidental test-harness finding surfaced along the way (not a production defect): a bare `MaterialApp(home: SignInScreen())` — the pattern used by the pre-existing `sign_in_consent_gating_test.dart` — has no ambient `Directionality` of its own; in the real app, standalone `SignInScreen` is always wrapped by `main.dart`'s own top-level `Directionality`. Tests that specifically assert RTL behavior needed to reproduce that same wrapper explicitly (now done in `sign_in_rtl_test.dart`); this does not affect the real app, since that wrapper is always present in production. Separately, the consent checkbox's `InkWell` intentionally spans its full row width (a larger, more accessible tap target than just the visible glyph) — a naive centroid tap can therefore coincide with a nested "Privacy Policy"/"Terms of Use" link depending on exact text layout, which differs between English and Arabic. This is not a production bug (a real, precise finger-tap on the visible checkbox glyph is unaffected) and the widget was not changed; the new tests tap the checkbox's own glyph element specifically for reliability.

### Live verification (items 20-21)

Not performed this pass beyond the automated coverage above — this environment has no interactive iOS Simulator automation capability (previously documented, unchanged) and Android UI automation for a full bilingual sweep was judged lower-value than comprehensive, fast, deterministic widget-test coverage given the size of this charter. The automated tests above reproduce the exact real-world trigger sequence (fresh State construction with locale already persisted) with the same fidelity a live device test would provide for this specific class of bug (a pure Dart-state/widget-tree defect, not a platform-integration one) — but per this engagement's own evidence-tier discipline, this is `E2_AUTOMATED_VERIFIED`, not `E4`, until the owner confirms on a real device.

### AUTH-001 / new-finding statuses (items 22-23)

- **`AUTH-001`**: `LIVE_VERIFICATION_REQUIRED` — component evidence reconciled per §B; open only for the confirmation-destination/fallback sub-issue, with a full design (§D/E) ready pending DNS + a separately-authorized config mutation.
- **`AUTH-007`** (new): `E2_AUTOMATED_VERIFIED` — root-caused, fixed, comprehensively tested; pending owner live E4 retest.

### Remaining Wave 1 blockers (item 24)

`AUTH-001` (confirmation-destination/fallback UX — design-ready, owner DNS action + a future authorized config change required) and `AUTH-007` (owner live E4 retest). `AUTH-005`/`AUTH-006` remain tracked, non-blocking. `DC-010`/`PC-006` remain tracked elsewhere (owner checklist), unaffected by this wave.

### Overall verdict (item 25)

**`NO-GO`, unchanged.**

### Exact minimum owner retest (item 26)

1. Choose Arabic during onboarding.
2. Proceed through every remaining onboarding step — confirm each one (including Madhhab) shows Arabic immediately.
3. Confirm the Sign In / Sign Up screen reads correctly right-to-left (tab order, field alignment, icons) — and that tapping إنشاء حساب/تسجيل الدخول shows the right fields.
4. Sign up with a new email.
5. Confirm the email arrives, Niswah-branded (already proven — no need to re-check unless something looks different).
6. Tap the confirmation link **on the same device Niswah is running on** (the empty-page issue is specifically a cross-device/desktop-browser fallback gap — this step is not expected to reproduce it, and is not what needs re-testing; it confirms the already-working path still works).
7. Confirm the app opens directly and recognizes the account as confirmed (already proven — brief re-check only).

Already-proven backend/delivery checks (SMTP, sender branding, template rendering, token processing) do **not** need to be repeated.
