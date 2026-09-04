# 02 — Security Static Verification Report / Finding Register — Niswah

Methodology: Phase 2A (Static Verification) per `01_SECURITY_AUDIT.md`. Phase 2B (Controlled Security Validation) was **not performed** — no staging/runtime access was available; every finding below is evidence type 🟧 (Confirmed by Code/Config) unless marked otherwise. No control is marked PASS solely from documentation or framework defaults.

Evidence key: 🟥 Confirmed by Controlled Test · 🟧 Confirmed by Code/Config · 🟨 Likely · 🟦 Requires Controlled Validation · ⬜ N/A / False positive

---

## Finding Register

| Finding ID | Category | Severity | Component | Summary | Launch blocker? | Status |
|---|---|---|---|---|---|---|
| SEC-001 | SECRET / AI | **SEC0 — Critical** | `pubspec.yaml`, `lib/core/services/gemini_service.dart`, `lib/features/ai_advisor/`, `lib/features/dream_interpreter/`, `lib/features/ai_assistant/presentation/viewmodels/chat_view_model.dart` | Live third-party AI API key (`GEMINI_API_KEY`) is bundled into the compiled app binary and called directly from the client with no server-side gate | YES | OPEN |
| SEC-002 | AI / CFG | SEC2 — Medium | `lib/core/config/app_environment.dart` | Secret-material validation (`_validateSecretConfig`) guards three env vars (`OPENAI_API_KEY`, `NISWAH_AI_API_KEY`, `DREAM_INTERPRETER_API_KEY`) that are never actually used anywhere in the app, while the real key in use (`GEMINI_API_KEY`) bypasses this validation entirely — dead code creates false assurance | NO (contributing factor to SEC-001) | OPEN |
| SEC-003 | CFG | **SEC1 — High** | `android/app/build.gradle.kts` | Android release build type is signed with the **debug** signing config (`signingConfig = signingConfigs.getByName("debug")`), with a `TODO` left unaddressed | YES | OPEN |
| SEC-004 | AUTHZ / DATA | **SEC1 — High** | `supabase/migrations/20260822210000_private_messaging.sql` | RLS `UPDATE` policy on `private_messages` for recipients ("Recipients can mark messages as read") is not column-scoped — a recipient can rewrite `content`/`sender_id` of any message in their own conversations, not just `is_read` | YES | OPEN |
| SEC-005 | RATE | SEC2 — Medium | `supabase/functions/dr-niswah-chat/index.ts` | No application-level rate limiting/abuse control on the (paid, per-call) Gemini-backed edge function beyond requiring a valid JWT | NO (explicit acceptance candidate) | OPEN |
| SEC-006 | AI / DATA | SEC2 — Medium | `lib/features/ai_assistant/presentation/viewmodels/chat_view_model.dart`, `lib/features/ai_assistant/domain/services/dr_niswah_persona.dart` | Direct-Gemini fallback path for the Dr. Niswah persona sends pregnancy week/trimester/postpartum/high-risk-flag context straight from the client to Google, bypassing the edge function's `flagged_conversations` clinical audit log | NO (explicit acceptance candidate) | OPEN |
| SEC-007 | DATA | SEC3 — Low | `lib/features/cycle_tracking/data/datasources/local_cycle_tracking_data_source.dart`, `lib/features/pregnancy_tracking/data/datasources/local_pregnancy_tracking_data_source.dart` | Menstrual-cycle and pregnancy-milestone data is cached on-device in plaintext via `shared_preferences` rather than platform secure storage | NO (backlog) | OPEN |
| SEC-008 | CORS | SEC4 — Observation | `supabase/functions/dr-niswah-chat/index.ts` | Wildcard CORS (`Access-Control-Allow-Origin: '*'`) on the edge function | NO | OPEN |
| SEC-009 | INJ (AI-xx) | SEC3 — Low | `lib/features/private_messaging/data/repositories/private_messaging_repository.dart` | PostgREST `.or()` filters built via raw string interpolation of a caller-supplied user ID instead of structured filter builders; not currently exploitable because RLS independently backstops every returned row, but fragile | NO (backlog) | OPEN |
| SEC-010 | — | UNKNOWN | Live Supabase project | Whether the migrations in `supabase/migrations/` (and `schema.sql`) have actually been applied, in this order, to the production Supabase project was **not verifiable** from source alone | Contributes to "no critical unknown" gate | UNKNOWN |
| SEC-011 | — | UNKNOWN | Live Supabase project / dashboard | Live dashboard-only configuration (Auth rate limits, leaked-password protection, email-confirmation requirement, redirect-URL allow-list for `niswah://login-callback`, Realtime RLS enforcement toggle, actual `SUPABASE_SERVICE_ROLE_KEY` scoping) was **not accessible** | Contributes to "no critical unknown" gate | UNKNOWN |

---

## SEC-001 — Client-exposed, unrestricted third-party AI API key (Critical)

- **Affected component:** `pubspec.yaml` (asset bundling), `lib/core/services/gemini_service.dart`, `lib/features/ai_advisor/ai_advisor_service.dart`, `lib/features/dream_interpreter/presentation/viewmodels/dream_interpreter_view_model.dart`, `lib/features/ai_assistant/presentation/viewmodels/chat_view_model.dart` (`_sendViaDirectModel`, lines ~271-336)
- **Attack path / control:** Any party who obtains a release APK/IPA (trivial — sideload, app-store download, or a leaked build) can unzip it and read the bundled `.env` file directly, or decompile the app to find the same key referenced via `flutter_dotenv`. No jailbreak/root or runtime instrumentation is required.
- **Expected behavior:** Third-party API credentials (`GEMINI_API_KEY`) must never ship inside a client binary; all calls to a metered/billable external AI provider should be proxied through an authenticated, rate-limited, server-side boundary (exactly as the app already does correctly for the `drNiswah` primary path).
- **Actual behavior:**
  1. `pubspec.yaml` → `flutter: assets:` lists `.env` (line: `- .env`), which causes the Flutter build to compile the entire `.env` file — including `GEMINI_API_KEY` — into the app's asset bundle for every release build.
  2. `lib/core/services/gemini_service.dart:45` reads `GEMINI_API_KEY` via `flutter_dotenv` and calls `https://generativelanguage.googleapis.com/v1beta/interactions` **directly from the device**, with the key sent as the `x-goog-api-key` header (line 75).
  3. Three separate client code paths call this service directly, with zero Niswah-side authentication/authorization/rate-limit gate in front of the third-party call:
     - `AiAdvisorService.askFiqh()` (`lib/features/ai_advisor/ai_advisor_service.dart:15`) — fiqh-ruling Q&A with Google Search grounding.
     - `DreamInterpreterViewModel.sendMessage()` (`lib/features/dream_interpreter/presentation/viewmodels/dream_interpreter_view_model.dart:155`) — dream interpretation.
     - `ChatViewModel._sendViaDirectModel()` (`lib/features/ai_assistant/presentation/viewmodels/chat_view_model.dart:327`) — used unconditionally for `fiqhAdvisory`/`general` threads, and as a **fallback for `drNiswah`** threads when `DrNiswahBackendService.instance.isAvailable` is false (see SEC-006).
  4. By contrast, `DrNiswahBackendService` (`lib/features/ai_assistant/data/services/dr_niswah_backend_service.dart`) correctly proxies the primary Dr. Niswah path through the Supabase Edge Function `dr-niswah-chat`, which holds `GEMINI_API_KEY` **only** in its server-side Deno environment (`supabase/functions/dr-niswah-chat/index.ts:153`) and requires a validated Supabase JWT before doing anything (see the edge function's positive-control note under "Related positive controls" below). This demonstrates the team already knows the correct pattern — it just wasn't applied to 3 of the 4 AI surfaces.
- **Evidence:**
  - `pubspec.yaml` (assets block): `- .env`
  - `lib/core/services/gemini_service.dart:43-49` (`_apiKey` getter, `dotenv.env['GEMINI_API_KEY']`), `:70-91` (direct HTTP POST to Google with the key in a header).
  - `lib/features/ai_advisor/ai_advisor_service.dart:15`, `lib/features/dream_interpreter/presentation/viewmodels/dream_interpreter_view_model.dart:155`, `lib/features/ai_assistant/presentation/viewmodels/chat_view_model.dart:322-336`.
  - Confirmed via `grep -rn "GeminiService" lib/` that exactly these three call sites exist (plus `dr_niswah_chat_screen.dart:340`, which only checks `isConfigured` for UI state).
- **Severity:** **SEC0 — Critical.** This is a direct, unauthenticated, financially-unbounded exposure of a live paid third-party credential (`SEC0` definition: "sensitive-data exposure... or catastrophic authorization failure"). It also functions as a "critical unknown" in reverse — the blast radius is bounded only by whatever quota/budget Google enforces on the key.
- **Exploitability:** Trivial. `unzip app-release.apk`, locate the asset, read the key — no reverse engineering, no root, no MITM required. (Static confirmation only — no APK was actually built/extracted during this audit, per the "do not perform any destructive action" instruction; the bundling mechanism itself, `flutter: assets: - .env`, is a well-documented, deterministic Flutter build behavior, so this is 🟧 Confirmed by Code/Config, not merely 🟨 Likely.)
- **Production impact:**
  - **Cost/quota abuse:** anyone extracting the key can make unlimited calls against the developer's Google Cloud billing/quota, independent of the Niswah app or any Supabase-authenticated user — a classic "key harvested from a mobile app and resold/abused at scale" scenario.
  - **Service disruption:** if the key's quota is exhausted or Google suspends it for abuse, the AI Advisor, Dream Interpreter, and (on the fallback path) Dr. Niswah chat all break for every legitimate user simultaneously.
  - **Content/policy risk:** the key could be used for arbitrary prompts unrelated to Niswah's use case, potentially violating Google's terms and risking the key/project being flagged or suspended.
  - No direct read/write access to Supabase data results from this key alone (it is scoped to Google's API, not Supabase), so it is not itself a path to health-data exfiltration — but it is a full compromise of that specific trust boundary.
- **Launch-blocker status:** **YES.** Directly matches the template's mandatory NO-GO criterion: "Sensitive secret is exposed."
- **Confidence:** Confirmed by code/config (🟧). Exploitability is 🟨 Likely/near-certain given deterministic Flutter asset-bundling behavior, but was not physically demonstrated via APK extraction in this audit (safety-rules-compliant: read-only, no build artifacts produced).

---

## SEC-002 — Dead secret-validation code creates false assurance (Medium)

- **Affected component:** `lib/core/config/app_environment.dart`
- **Attack path / control:** Not directly exploitable itself; this is a **process/verification-integrity** finding that materially increases the risk of SEC-001 going unnoticed in future reviews.
- **Expected behavior:** If an environment-config module validates "AI credentials," that validation should cover the AI credential(s) actually in use.
- **Actual behavior:** `AppEnvironment.load()` reads and validates `OPENAI_API_KEY`, `NISWAH_AI_API_KEY`, and `DREAM_INTERPRETER_API_KEY` (lines 14-40, 62-73), each passed through `_validateSecretConfig` which rejects values containing `service_role`/`secret`/`anon` substrings. **Grep across all of `lib/` confirms none of `openAiApiKey`, `niswahAiApiKey`, `dreamInterpreterApiKey`, or `aiApiKeys` is ever read by any other file** — this validation exists in complete isolation. Meanwhile `GEMINI_API_KEY` — the key actually used for every AI call — is read directly via `dotenv.env['GEMINI_API_KEY']` in `gemini_service.dart:45`, entirely outside `AppEnvironment`, and has **zero** validation of any kind (not even an emptiness check beyond `isConfigured`'s placeholder-string comparison).
- **Evidence:** `grep -rn "OPENAI_API_KEY\|NISWAH_AI_API_KEY\|DREAM_INTERPRETER_API_KEY\|openAiApiKey\|niswahAiApiKey\|dreamInterpreterApiKey\|aiApiKeys" lib/` → all hits confined to `app_environment.dart` itself. `grep -rn "GEMINI_API_KEY" lib/` → only `gemini_service.dart`.
- **Severity:** SEC2 — Medium. The code doesn't cause a breach on its own, but it is exactly the kind of "security library/control installed but not actually applied to the thing that matters" pattern the template's §43.11 calls out, and it would mislead a future reviewer skimming `app_environment.dart` into believing AI-key hygiene is handled.
- **Exploitability:** N/A (not directly exploitable).
- **Production impact:** Indirect — perpetuates SEC-001 by giving false confidence.
- **Launch-blocker status:** NO on its own, but should be fixed alongside SEC-001's remediation (the validated variable names should either be wired to the actual key in use, or removed).
- **Confidence:** Confirmed by code (🟧) via exhaustive grep.

---

## SEC-003 — Android release build signed with the debug key (High)

- **Affected component:** `android/app/build.gradle.kts`
- **Attack path / control:** Release build integrity / code-signing.
- **Expected behavior:** Production release builds must be signed with a dedicated, securely-stored release signing key (or enrolled in Google Play App Signing), never the shared debug keystore.
- **Actual behavior:**
  ```kotlin
  buildTypes {
      release {
          // TODO: Add your own signing config for the release build.
          // Signing with the debug keys for now, so `flutter run --release` works.
          signingConfig = signingConfigs.getByName("debug")
      }
  }
  ```
  The `release` build type explicitly uses the `debug` signing config, with the `TODO` left in place.
- **Evidence:** `android/app/build.gradle.kts`, `buildTypes.release` block (verbatim above).
- **Severity:** **SEC1 — High.** The debug keystore is a well-known, developer-machine-local, non-secret credential by Android tooling convention (predictable password `android`/`androiddebugkey`, often shared across a team's machines or CI images, not intended to protect anything). Shipping a release artifact signed with it means:
  1. Anyone with the (widely-documented, often-default) debug keystore can produce an APK that Android treats as update-compatible with a genuine release build signed the same way, undermining update integrity guarantees.
  2. It is very unlikely this configuration is compatible with a legitimate Google Play production listing under Play App Signing without additional remediation, since Play expects a dedicated upload key — this is a direct release-readiness blocker independent of any exploit.
  3. It signals the release pipeline itself was never hardened for production (no ProGuard/R8 minification config was found either — see Static Verification Matrix below), consistent with a repo still in a pre-production state.
- **Exploitability:** Low technical bar once the (commonly-known) debug key or a copy of the developer's debug keystore is available; the more immediate production impact is the store-submission/update-integrity problem rather than a remote attack.
- **Production impact:** Release/update-integrity compromise; likely blocks or invalidates a proper Play Store production release as configured.
- **Launch-blocker status:** **YES.**
- **Confidence:** Confirmed by code/config (🟧) — this is static build configuration, not runtime behavior, so no further validation is needed to confirm the setting itself; whether it has already been used to ship a build is UNKNOWN (out of scope — no access to any distributed artifact or Play Console).

---

## SEC-004 — Private-message `UPDATE` RLS policy is not column-scoped (High)

- **Affected component:** `supabase/migrations/20260822210000_private_messaging.sql`, table `private_messages`
- **Attack path / control:** IDOR-adjacent data-integrity bypass within a trust boundary the user is legitimately inside (their own conversation).
- **Expected behavior:** The "mark as read" feature should only ever be able to flip `is_read`; message `content` (and `sender_id`) should be immutable once written, especially by the *other* party to a private conversation.
- **Actual behavior:** The policy is:
  ```sql
  CREATE POLICY "Recipients can mark messages as read" ON private_messages
    FOR UPDATE USING (
      is_conversation_participant(conversation_id) AND auth.uid() <> sender_id
    )
    WITH CHECK (
      is_conversation_participant(conversation_id) AND auth.uid() <> sender_id
    );
  ```
  Postgres RLS `USING`/`WITH CHECK` clauses govern **which rows** may be touched, not **which columns**. Because there is no column-level `GRANT`/`REVOKE`, no `BEFORE UPDATE` trigger restricting the diff to `is_read`, and no check that other columns are unchanged, any authenticated participant who is *not* the sender of a given message can issue a PostgREST `PATCH` (bypassing the Flutter app's own `PrivateMessagingRepository.markMessagesAsRead()`, which only ever sends `{'is_read': true}` — the app's restraint is not a security control) that rewrites that message's `content` to arbitrary text, or reassigns `sender_id` to any other valid `auth.users` id.
- **Evidence:** `supabase/migrations/20260822210000_private_messaging.sql:86-92`; contrasted with the app-side call site `lib/features/private_messaging/data/repositories/private_messaging_repository.dart:129-145` (`markMessagesAsRead`, which only ever updates `is_read` — confirming the app's *intended* use, not what the database *permits*).
- **Severity:** **SEC1 — High.** This is a private-message integrity failure inside a feature explicitly named in the audit brief as a DM-privacy concern. A malicious or compromised participant can retroactively tamper with what the other party appears to have said, which is a serious trust/integrity issue for a private-messaging feature (potential for social engineering, harassment cover-up, or fabricated "evidence" within the app), and does so entirely through the ordinary anon-key + user-JWT REST path — no privilege escalation beyond "recipient of the message" is required.
- **Exploitability:** Moderate — requires calling PostgREST directly (or a small script) rather than going through the Flutter UI, but this requires nothing more than the credentials any legitimate app user already has (their own JWT + the public anon key). No admin/service-role access needed.
- **Production impact:** Message-content tampering within DMs; scoped to conversations the attacker already legitimately participates in (not a cross-user/cross-tenant breach — an attacker cannot touch a conversation they are not part of, since `is_conversation_participant()` still gates row access).
- **Launch-blocker status:** **YES** — matches "IDOR/cross-tenant access is exploitable" in spirit (object-level authorization gap on a sensitive table), even though it is scoped to rows the attacker is already a participant of.
- **Confidence:** Confirmed by code/config (🟧) — the policy text is unambiguous about what it does and does not restrict; runtime confirmation via a controlled PATCH request against a synthetic pair of test accounts (`SEC-IDOR-xx` per the template's Phase 2B) is recommended before closing this finding, since exact Postgres/PostgREST behavior should be re-verified against the live project.

---

## SEC-005 — No abuse/rate-limit control on the Gemini-backed edge function (Medium)

- **Affected component:** `supabase/functions/dr-niswah-chat/index.ts`
- **Expected behavior:** An endpoint that triggers a billable third-party AI call per request should have some abuse control (per-user cooldown, daily cap, or platform-level rate limiting) beyond "the caller has a valid JWT."
- **Actual behavior:** The function validates the JWT (`userClient.auth.getUser()`, lines 224-230) and validates input shape (`threadId`/`content`, lines 233-239), but performs no request-frequency check of any kind before calling `callGemini()`. A single authenticated (even legitimately-signed-up, low-cost) user can loop calls to this endpoint indefinitely.
- **Evidence:** Full read of `supabase/functions/dr-niswah-chat/index.ts` — no rate-limit table, no Supabase-native rate-limit header check, no cooldown logic present.
- **Severity:** SEC2 — Medium. Bounded by the fact that the caller must be an authenticated, identifiable Supabase user (traceable, bannable, and Google's own per-key quota still applies), unlike SEC-001's fully anonymous exposure.
- **Exploitability:** Easy for any signed-up user to script a loop.
- **Production impact:** Elevated Gemini API cost; potential quality-of-service degradation for other users if the shared server-side key hits Google's rate limit.
- **Launch-blocker status:** NO — candidate for explicit residual-risk acceptance (SEC2 per template rules), but should be remediated soon after launch.
- **Confidence:** Confirmed by code (🟧).

---

## SEC-006 — Direct-Gemini fallback leaks pregnancy/health context and skips clinical audit logging (Medium)

- **Affected component:** `lib/features/ai_assistant/presentation/viewmodels/chat_view_model.dart` (`_sendViaDirectModel`, `useBackend` check at lines 195-197), `lib/features/ai_assistant/domain/services/dr_niswah_persona.dart`
- **Expected behavior:** All Dr. Niswah conversations — which are explicitly personalized with pregnancy week/trimester/postpartum/high-risk-flag context — should go through the server-side edge function so the key stays server-side and red-flag detections are consistently logged to `flagged_conversations` for clinical review.
- **Actual behavior:** `useBackend` is only `true` when `threadType == ChatThreadType.drNiswah && DrNiswahBackendService.instance.isAvailable`, where `isAvailable` merely checks `NiswahSupabase.clientOrNull != null` (i.e., whether the Supabase SDK itself initialized) — **not** whether the edge function is reachable or healthy. When `false` (e.g., Supabase failed to initialize, or a future refactor changes this check), the code falls through to `_sendViaDirectModel`, which for `drNiswah` threads calls `DrNiswahPersona.buildSystemInstruction(userId: userId)` — this fetches the user's live `pregnancy_profile` row (week, trimester, postpartum status, fasting status, **high-risk flags**) and embeds it in a system prompt sent **directly to Google from the client**, using the same exposed key from SEC-001. On this path, red-flag messages still show the local urgent banner (`DrNiswahRedFlags.matches` is checked independently, `chat_view_model.dart:280-320`), but they are **never written to `flagged_conversations`** — that logging only happens inside the edge function (`index.ts:246-254`), so a clinically-relevant message handled via the fallback path is invisible to the Doctor's Report feature and any future moderator review.
- **Evidence:** `lib/features/ai_assistant/presentation/viewmodels/chat_view_model.dart:194-219, 271-336`; `lib/features/ai_assistant/domain/services/dr_niswah_persona.dart:62-102` (fetches and serializes `pregnancy_profile` client-side).
- **Severity:** SEC2 — Medium. Narrow trigger condition in the current build (Supabase initialization failing would likely break most of the app, including auth, so this path is not the common case today), but the health-data content sent to a third party is materially more sensitive than a fiqh question or dream description, and the audit-log gap is a real clinical-safety regression versus the primary path.
- **Exploitability:** Not attacker-triggered directly; occurs under a specific app-state condition, but is architecturally present and would also fire if `DrNiswahBackendService.isAvailable`'s check were ever loosened.
- **Production impact:** Health-data-in-prompt exposure via the same unrestricted key as SEC-001; loss of clinical audit trail for red-flag content on this path.
- **Launch-blocker status:** NO independently — resolved as a side effect of properly fixing SEC-001 (once no client path calls Gemini directly, this finding closes too).
- **Confidence:** Confirmed by code (🟧).

---

## SEC-007 — Sensitive health data cached unencrypted in local device storage (Low)

- **Affected component:** `lib/features/cycle_tracking/data/datasources/local_cycle_tracking_data_source.dart`, `lib/features/pregnancy_tracking/data/datasources/local_pregnancy_tracking_data_source.dart`
- **Expected behavior:** Highly sensitive health data (menstrual/haid cycle logs, pregnancy milestones) cached on-device for offline use should use platform secure storage (iOS Keychain / Android Keystore-backed encryption, e.g. via `flutter_secure_storage`), not plaintext `shared_preferences`.
- **Actual behavior:** Both data sources serialize the user's full cycle-log / pregnancy-milestone list to JSON and store it via `SharedPreferences.setString()` under a fixed key (`niswah_cycle_tracking_logs`, `niswah_pregnancy_tracking_milestones`). `shared_preferences` on Android backs onto an unencrypted XML file in app-private storage; on iOS, `NSUserDefaults`-backed plist storage, similarly unencrypted at the app-storage layer (both rely on OS-level sandboxing/full-disk encryption, not app-level encryption).
- **Evidence:** `lib/features/cycle_tracking/data/datasources/local_cycle_tracking_data_source.dart:1-54`; `lib/features/pregnancy_tracking/data/datasources/local_pregnancy_tracking_data_source.dart:1-58`.
- **Severity:** SEC3 — Low. Exploitation requires local device access (physical access, malware with storage-scoped access, a rooted/jailbroken device, or an unencrypted-device/ADB-backup scenario) — not remotely exploitable — but the sensitivity of the data (menstrual/religious-practice/pregnancy status) makes this worth hardening given the app's stated purpose.
- **Exploitability:** Requires local/physical device compromise.
- **Production impact:** Local data-at-rest exposure on a compromised or unencrypted device.
- **Launch-blocker status:** NO — backlog item.
- **Confidence:** Confirmed by code (🟧).

---

## SEC-008 — Wildcard CORS on the edge function (Observation)

- **Affected component:** `supabase/functions/dr-niswah-chat/index.ts:14-18`
- **Actual behavior:** `Access-Control-Allow-Origin: '*'`.
- **Severity:** SEC4 — Observation. Because this endpoint uses bearer-JWT auth (not cookies) and returns no ambient-credential-based access, wildcard CORS does not by itself grant cross-origin attackers anything they couldn't already do by calling the endpoint directly with a stolen token — the real risk is token theft, not CORS. Standard/acceptable for a mobile-first Supabase Edge Function. No action required for launch; consider scoping if a web client is ever added.
- **Launch-blocker status:** NO.
- **Confidence:** Confirmed by code (🟧).

---

## SEC-009 — Raw string interpolation in PostgREST `.or()` filters (Low / Observation)

- **Affected component:** `lib/features/private_messaging/data/repositories/private_messaging_repository.dart:33, 76-79`
- **Actual behavior:** `fetchConversations()` and `getOrCreateConversation()` build filter strings like `'and(participant_one.eq.$otherUserId,participant_two.eq.$currentUserId)'` via direct Dart string interpolation instead of the Supabase client's structured filter builder methods.
- **Analysis:** `currentUserId`/`uid` values originate from `_client.auth.currentUser.id` (server-issued UUID, not attacker-controlled). `otherUserId` in `getOrCreateConversation` is caller-supplied; if it ever contains PostgREST filter metacharacters (commas, parens, operator keywords), the resulting `.or()` expression could be malformed or semantically altered. However, **every row this query could possibly surface is still independently gated by RLS** (`auth.uid() = participant_one OR auth.uid() = participant_two`), so a malformed/hijacked filter cannot cause the query to return a conversation the caller isn't already authorized to see — worst case is a failed query or an unintended duplicate-conversation insert attempt (which would then fail its own FK/RLS checks). This is a **code-quality / defense-in-depth gap**, not a currently-exploitable authorization bypass, per the AI-generated-code-risk category (§43.6 unsafe raw queries) the template asks to check for.
- **Severity:** SEC3 — Low.
- **Launch-blocker status:** NO — backlog.
- **Confidence:** Confirmed by code (🟧); exploitability assessed as ⬜ N/A given the RLS backstop, but the pattern itself should be corrected proactively.

---

## SEC-010 — UNKNOWN: Live migration state on the production Supabase project

Static review can only confirm that RLS-enabling and per-table policies are **declared** correctly across `supabase/schema.sql` and every file in `supabase/migrations/`. Whether these migrations have actually been applied, in order, to the live production Supabase project referenced by the shipped `SUPABASE_URL` was **not verifiable** without dashboard/CLI access to that project, which was not provided. Several migration file comments (e.g. `20260830140000_community_schema_reset.sql`, `20260825210000_...`, `20260826090000_...`) describe **prior live-schema drift** that had to be corrected after-the-fact ("every real cloud write to `cycle_entries` has been failing... since before this table was ever successfully written to from the app"), which is direct evidence that source-declared schema and live-deployed schema have diverged before in this project's history. This must be independently confirmed (e.g., `supabase db diff` against the linked project, or a dashboard review of `pg_policies`) before this control can be marked Enforced/Tested rather than merely Declared/Implemented.

**Status: UNKNOWN / NOT VERIFIED.** Do not infer PASS from the source-code evidence alone.

---

## SEC-011 — UNKNOWN: Live Supabase dashboard configuration

The following are configured outside the reviewed source tree, on the Supabase project dashboard, and were not accessible during this audit:
- Auth rate limiting / brute-force protection thresholds for login, OTP, and password-reset.
- Leaked-password protection and password-complexity policy.
- Whether email confirmation is actually required before a session is issued (client code assumes so — `signUpWithEmail` returns `response.session == null` to detect pending confirmation — but this is a project-level toggle).
- The redirect-URL allow-list actually containing `niswah://login-callback` (the code comment in `auth_repository_impl.dart:16-22` explicitly notes this is required and "Supabase silently ignores it and uses the default Site URL anyway" if misconfigured — a silent misconfiguration would not surface as a code-level bug).
- Realtime RLS enforcement toggle for the `private_messages` channel used by `PrivateMessagingRepository.subscribeToMessages`.
- The actual scope/rotation status of the live `SUPABASE_SERVICE_ROLE_KEY` and `GEMINI_API_KEY` values.

**Status: UNKNOWN / NOT VERIFIED.**

---

## Static Verification Matrix (selected)

| Check ID | Category | Component | Expected control | Evidence | Result |
|---|---|---|---|---|---|
| CFG-01 | Production config | `AppEnvironment._validateClientConfig` | Reject service-role/secret material in client anon key | `app_environment.dart:104-129`, invoked from `main.dart:45` before `NiswahSupabase.initialize()` | **PASS** (control exists, is wired up, and is invoked at startup — confirmed by code; runtime firing not independently tested) |
| CFG-02 | Production config | `android/app/build.gradle.kts` | Release build uses a dedicated release signing config, minification enabled | Debug signing config used in `release`; no `minifyEnabled`/`isMinifyEnabled`/ProGuard rules found anywhere under `android/` | **FAIL** — SEC-003 |
| SECRET-01 | Secret management | `pubspec.yaml` + `gemini_service.dart` | No live third-party API secret bundled into client asset/binary | `.env` (containing `GEMINI_API_KEY`) listed under `flutter: assets:` | **FAIL** — SEC-001 |
| SECRET-02 | Secret management | `lib/`, `supabase/functions/` | No hardcoded secrets/keys in source | `grep -rnE "sk-[A-Za-z0-9]{10,}|AIza[A-Za-z0-9_-]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----"` across `lib/` and `supabase/functions/` → no matches | **PASS** |
| AUTHZ-01 | Authorization | `supabase/schema.sql` + all migrations | RLS enabled + `auth.uid()`-scoped policy on every user-data table | Confirmed for `users`, `profiles`, `cycle_entries`, `symptoms_log`, `prayer_entries`, `adah_ledger`, `istihadah_episodes`, `nifas_records`, `ramadan_records`, `pregnancy_milestones`, `pregnancy_profile`, `secret_vault_entries`, `dream_entries`, `chat_threads`, `chat_messages`, `wellbeing_logs`, `flagged_conversations`, `private_conversations`, `private_messages`, `community_posts/comments/likes` (public-read tables use intentional `USING (true)` for SELECT only; all writes are `auth.uid()`-scoped) | **PASS** (declared/implemented; live-enforcement is SEC-010 UNKNOWN) |
| AUTHZ-02 | Authorization | `private_messages` UPDATE policy | Column-scoped update permission for "mark as read" | Row-scoped only, not column-scoped | **FAIL** — SEC-004 |
| AI-01 | AI-agent risk (§43.5) | All migrations | No overly-permissive/broad DB policy (`USING (true)` on sensitive tables) | Only `educational_resources` (intentionally public content) and `community_*` SELECT (intentionally public UGC) use `USING (true)`; no sensitive/private table does | **PASS** |
| AI-02 | AI-agent risk (§43.2) | `lib/`, `supabase/functions/` | No convenience-hardcoded secrets | See SECRET-02 | **PASS** |
| AI-03 | AI-agent risk (§43.1/§43.4) | RLS across all migrations | Backend enforces ownership, not just UI | Confirmed throughout — Flutter repositories accept caller-supplied user IDs (e.g. `PrivateMessagingRepository.sendMessage(senderId: ...)`) but RLS `WITH CHECK (auth.uid() = ...)` is the actual authoritative boundary in every case reviewed | **PASS** |
| INJ-01 | Injection | All `lib/features/*/data/` repositories reviewed | No raw/concatenated SQL | Confirmed — Supabase structured query builder used throughout; one raw-string PostgREST filter pattern noted (RLS-backstopped) | **PASS** (with SEC-009 observation) |
| AUTHN-01 | Authentication | `supabase/functions/dr-niswah-chat/index.ts:206-231` | Server verifies caller identity via provider, not just presence of a header | `userClient.auth.getUser()` called and checked before any DB/AI action; 401 returned on missing/invalid session | **PASS** |
| RATE-01 | Rate limiting | `dr-niswah-chat` edge function | Abuse control on expensive AI calls | None found | **FAIL** — SEC-005 |
| DATA-01 | Sensitive data | Local storage (`shared_preferences`) | Sensitive health data encrypted at rest on-device | Plaintext | **FAIL** — SEC-007 |
| FILE-01 | File upload | Entire `lib/` tree | N/A check — no upload surface | No `Supabase Storage.upload()` or multipart endpoints found; PDFs generated and shared locally only | **N/A** |

---

## Static Verification Exit Gate

- [x] Authentication reviewed.
- [x] Authorization reviewed.
- [x] Object/tenant isolation reviewed (single-tenant consumer app; per-user ownership is the isolation boundary, verified above).
- [x] Session/token handling reviewed (delegated to `supabase_flutter`; no custom logic found).
- [x] Input/injection reviewed.
- [x] XSS/CSRF/CORS reviewed where applicable (native app — XSS/CSRF N/A; CORS reviewed for the one HTTP-exposed edge function).
- [x] SSRF reviewed where applicable (no user-controlled URL fetch surface found).
- [x] File upload reviewed (N/A — no surface).
- [x] Secret handling reviewed.
- [x] Sensitive data exposure reviewed.
- [x] Rate limiting/abuse reviewed.
- [x] Webhooks/payment reviewed where applicable (N/A — no webhook or payment surface found in-scope).
- [x] Admin surface reviewed (none exists in the audited app; `flagged_conversations.reviewed` implies an unbuilt moderator workflow — noted, not a vulnerability).
- [x] Production config reviewed.
- [x] AI-specific risks reviewed (§43 — see AI-01/AI-02/AI-03 above and SEC-001/002/005/006).
- [x] SEC0/SEC1 candidates have evidence (SEC-001, SEC-003, SEC-004 all have file/line evidence above).

Phase 2A complete. Phase 2B (Controlled Security Validation) was not performed — see `SEC_production_readiness_report.md` §74 for the explicit out-of-scope list.
