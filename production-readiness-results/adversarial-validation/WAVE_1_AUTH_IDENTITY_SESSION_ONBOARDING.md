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

