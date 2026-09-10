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
