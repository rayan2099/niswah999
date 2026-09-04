# Privacy & Compliance Audit — Phase 1: Discovery

| Field | Value |
|---|---|
| System | Niswah (Flutter mobile app, `com.niswah.niswah`) |
| Repository | Niswah |
| Branch | main |
| Commit | 13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f |
| Phase | Discovery |
| Audit date | 2026-09-04 |
| Environment | Local (static source review only; no staging/prod runtime access) |
| Jurisdiction(s) identified | UNKNOWN — bilingual EN/AR UI, location presets skew GCC/MENA (Riyadh, Jeddah, Mecca, Medina, Dubai, Cairo); no in-app jurisdiction targeting, no geo-fencing of features. Must be confirmed by product/legal owner. |
| Privacy owner | UNKNOWN — no owner identified in repo |
| Legal review available? | NO — no privacy policy document, no DPA, no legal review artifacts found anywhere in the repository |
| Restrictions | Static source review only. No runtime/staging environment available. No synthetic-account controlled testing performed (Phase 2B not executed — see report). No production Supabase dashboard or vendor console access. |
| Report created | `PC_discovery.md` |

This audit builds directly on confirmed cross-domain findings already on record: **RD-007** (no privacy policy, dead consent link), **SEC-001/SEC-006** (Gemini key bundled client-side; pregnancy context sent to Google via direct-client fallback), **BR-006** (health data flows into OS cloud backups by default), **DI-012** (message cascade delete affects the other participant), **SEC-007** (cycle/pregnancy cached in plaintext `shared_preferences`). These are treated as established evidence, not re-derived.

---

## 7. Personal Data Inventory

| Data ID | Data element | Category | Source | Required? | Purpose | Storage | Sensitivity |
|---|---|---|---|---|---|---|---|
| PD-001 | Email / phone number, password, display name | Account/auth | User (sign-up) | Yes | Authentication | Supabase `auth.users`, `profiles` | Normal (phone/email is identifying) |
| PD-002 | Menstrual/bleeding logs, flow level, symptoms | Health / cycle | User | Core to product | Cycle prediction, fiqh eligibility calc | Supabase `cycle_entries`, `symptoms_log`; local cache (`shared_preferences`, per SEC-007) | **Sensitive** (health) |
| PD-003 | Pregnancy status, week/trimester, milestones, TTC mode, postpartum/nifas state | Health / pregnancy | User | Core to product | Pregnancy tracking, fiqh eligibility, AI chat context | Supabase `pregnancy_profile`, `pregnancy_milestones`; local cache | **Sensitive** (health) |
| PD-004 | Madhhab (fiqh school) selection, istihadah episodes, nifas records, ramadan records, adah ledger | Religious practice | User | Core to product | Personalizes fiqh rulings on prayer/fasting eligibility | Supabase `adah_ledger`, `istihadah_episodes`, `nifas_records`, `ramadan_records`; local `MadhhabController` prefs | **Sensitive** (religious belief-adjacent, inferred from health data) |
| PD-005 | Precise GPS coordinates (lat/lng) | Location | Device (Geolocator) | Optional (city presets available) | Prayer-time calculation | **Local only** — `shared_preferences` (`niswah_prayer_location_lat/lng/label`); not observed being synced to Supabase | **Sensitive** (precise geolocation) |
| PD-006 | Private message content between users | Communications | User | Optional feature | 1:1 messaging | Supabase `private_messages`, `private_conversations` | **Sensitive** (private communications) |
| PD-007 | Community posts, comments, likes | User-generated content | User | Optional feature | Community feature | Supabase `community_posts`, `community_comments`, `community_likes` | Normal–Sensitive (may contain health/personal disclosures by nature of app) |
| PD-008 | AI chat transcripts (Dr. Niswah, Fiqh advisor, general assistant), incl. pregnancy/health context assembled into system prompts | Health + communications | User + system-derived | Optional feature | AI-assisted guidance | Supabase `chat_threads`, `chat_messages`; **sent to Google Gemini** (server-side edge function `dr-niswah-chat` AND direct-client fallback, see AI-01/AI-02) | **Sensitive** (health data shared with third party) |
| PD-009 | Dream interpretation entries | User-generated / possibly health-adjacent | User | Optional feature | Dream interpretation feature | Supabase `dream_entries`; **sent to Google Gemini** directly from client | Sensitive (personal/psychological content) |
| PD-010 | "Secret vault" entries (`entry_type`, `encrypted_content`) | Unknown / potentially sensitive | User (feature not found wired into `lib/`) | Unknown | Unknown — table exists, no client code references it | Supabase `secret_vault_entries` (schema says client-side AES-256 encrypted) | Unknown/Sensitive — **dormant schema, flagged for owner confirmation** |
| PD-011 | Marital status, anonymous-mode flag | Profile preference | User | Optional | Gates spouse-only features / community display identity | Supabase `profiles.anonymous_mode`; local `MaritalStatusController` | Normal |
| PD-012 | Auth session tokens / JWT | Device identifier | System (Supabase SDK) | Required | Session management | Supabase Auth (device-local secure token storage via `supabase_flutter`) | Normal |
| PD-013 | PDF report exports (Fiqh log, Doctor's report, Mental-state report, Husband report) | Derived health/religious document | System-generated from PD-002/003/004 | Optional | User-initiated document generation | Rendered locally (`pdf`/`printing` packages); not confirmed whether transiently stored server-side | Sensitive (aggregates health+religious data into one document, including for husband recipient) |

No standalone name/DOB/government-ID/payment fields were found — the app does not appear to process financial or government-identifier data. No analytics/crash-reporting/advertising SDK was found in `pubspec.yaml` (no Firebase, Sentry, Mixpanel, AdMob, etc.) — this is a **positive** finding: no confirmed third-party telemetry vendor beyond Google Gemini and Supabase itself.

---

## 8. Data Flow Map (selected sensitive elements)

| Data ID | Collected at | Processed by | Stored in | Shared with | Retention | Deletion path |
|---|---|---|---|---|---|---|
| PD-002/003 | Onboarding steps 7-8, cycle/pregnancy screens | Flutter app, local controllers | Supabase Postgres + local `shared_preferences` (plaintext, SEC-007) | Google Gemini (indirectly, via AI chat context — see PD-008) | UNKNOWN — no retention policy found | No in-app account deletion (see DEL-01). Item-level delete exists for individual logs/milestones. |
| PD-004 | Onboarding step 4, Fiqh screens | Flutter app | Supabase Postgres | Not directly; informs AI fiqh-advisor prompts sent to Gemini | UNKNOWN | Same as above |
| PD-005 | Onboarding step 6, Profile > Prayer Times Settings | `PrayerLocationController` + `geolocator` | **Local device only** (`shared_preferences`) | Not observed sent to any backend or vendor | Indefinite — no expiry/purge logic found | Overwritten on re-selection; no explicit clear/delete action; persists after logout (see RET-01) |
| PD-006 | Private messaging screens | Supabase | Supabase `private_messages` | Not shared with third parties | UNKNOWN | `ON DELETE CASCADE` from `auth.users` — but only reachable via account deletion, which has **no user-facing trigger** (DEL-01); DI-012 notes the other participant's copy is destroyed too |
| PD-008 | AI Advisor / Dr. Niswah / general chat screens | Edge function `dr-niswah-chat` (server-side) **and** direct client-side Gemini calls (`GeminiService`, `AiAdvisorService`, `_sendViaDirectModel`) | Supabase `chat_messages` + Google Gemini API (external) | **Google (Gemini API)** — confirmed sub-processor for health/pregnancy-context-bearing prompts | UNKNOWN (both Supabase-side and Google-side) | Per-thread delete exists in UI (`chat_view_model.dart:deleteThread`); no evidence this also requests deletion on Google's side (technically not possible via this API) |
| PD-009 | Dream Interpreter screen | `GeminiService` direct client call | Supabase `dream_entries` + Google Gemini | Google (Gemini) | UNKNOWN | Per-entry delete exists (`dream_interpreter_repository_impl.dart`) |

---

## 14. Permission Inventory

| Permission | Feature | Required? | Just-in-time explanation? | Decline behavior | Persisted consent? |
|---|---|---|---|---|---|
| Location (iOS `NSLocationWhenInUseUsageDescription`, Android `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION`) | Prayer-time calculation | No — city presets are a full substitute | **Yes** — onboarding shows "Used only to calculate accurate prayer times." before the OS prompt; iOS purpose string matches; only when-in-use requested (no background location) | Graceful — `LocationPermissionDenied`/`LocationServiceDisabled` are caught and the user is redirected to pick a preset city instead (`onboarding_screen.dart:_useDeviceLocation`) | OS-level only; no app-side record of the grant/denial decision or timestamp |

No other device permissions (camera, microphone, contacts, notifications beyond local scheduling, Bluetooth) were found requested in the manifests reviewed.

---

## 15. Consent / Preference Inventory

| Mechanism | Where | Default state | Gates anything? | Withdrawal mechanism |
|---|---|---|---|---|
| "I agree to the Privacy Policy and Terms of Use" checkbox | `sign_in_screen.dart` `_SignInContentState._agreed` | Unchecked | **No** — confirmed by code read: `_agreed` is referenced only in the checkbox's own `onTap`/color/icon; it is never read by the Email/Phone/Google auth buttons' `onPressed` handlers. A user can sign up and immediately have cycle/pregnancy/religious data collected without ever checking the box. | None — nothing to withdraw since nothing was ever recorded |
| Onboarding step 9, labeled **"Privacy"** (`_Privacy` widget, title "Anonymous Mode") | `onboarding_screen.dart` step 9 | Off | Only toggles `profiles.anonymous_mode` (identity display in community) — **not** a data-processing consent of any kind | Toggle reversible any time in Profile > Privacy Settings |
| Madhhab selection (step 4), married status (step 5), location (step 6), last-period date (step 7) | Onboarding | — | These ARE the sensitive-data collection points themselves; no distinct consent step precedes any of them beyond the one non-functional checkbox on step 3 | N/A |

**No consent event (checkbox state, timestamp, policy version) is written to the database anywhere** — confirmed by absence of any `consent`/`agreed`/`policy_version` column in `schema.sql` and absence of any write call in `auth_repository_impl.dart`.

---

## 16. Privacy Notice / Disclosure Inventory

| Notice | Exists? | Evidence |
|---|---|---|
| Privacy Policy document | **No** | Confirmed by RD-007 and independently by repo-wide search: no `*privacy*polic*` file anywhere in the repository (checked outside `src/` reference app too) |
| Terms of Use document | **No** | Same search; the checkbox links to nothing |
| In-app AI-disclosure ("your data is sent to Google") | **No** | No string referencing Google, Gemini, or third-party AI processing found in any user-facing screen text reviewed (`ai_advisor_service.dart`, `dr_niswah_chat_screen.dart`, `dream_interpreter_screen.dart`) |
| Location purpose explanation | **Yes** | `onboarding_screen.dart` step 6: "Used only to calculate accurate prayer times." |
| Account-deletion explanation | **N/A** | No deletion feature exists to explain (see DEL-01) |
| Support/contact/DPO email | **No** | No `mailto:`, `support@`, `privacy@`, or contact form found anywhere in `lib/` |

---

## 17. Third-Party Processor Inventory

| ID | Vendor | Purpose | Data received | Data location known? | Retention known? | Contract/DPA known? | Criticality |
|---|---|---|---|---|---|---|---|
| TP-001 | Supabase (Postgres + Auth + Edge Functions) | Primary backend: auth, database, edge function hosting | All PD-001–013 categories except PD-005 (location stays local) | Region UNKNOWN (project-config dependent, not in repo) | UNKNOWN | UNKNOWN — **LEGAL/COMPLIANCE OWNER REVIEW REQUIRED** | Critical |
| TP-002 | Google (Gemini API, `generativelanguage.googleapis.com`) | LLM inference for Dr. Niswah chat, Fiqh advisor, general assistant, Dream Interpreter | Prompt text including pregnancy week/trimester/high-risk flags (per SEC-006), fiqh questions, dream descriptions | Region UNKNOWN | UNKNOWN — Google's standard API data-retention terms not reviewed here | **UNKNOWN — no DPA/processing terms found in repo; LEGAL/COMPLIANCE OWNER REVIEW REQUIRED** | Critical (special-category data) |
| TP-003 | Google Sign-In (OAuth) | Social login | Email, name, profile from Google account | Google-managed | N/A (auth only) | Standard OAuth, no custom DPA needed for this narrow use | Low |

No analytics, crash-reporting, advertising, email/SMS, payment, or CRM vendor was found integrated in `pubspec.yaml` or `lib/`.

---

## 18. AI Provider Inventory

| Provider | User data sent? | Data fields | Purpose | Training use known? | Retention known? | User disclosure exists? |
|---|---|---|---|---|---|---|
| Google Gemini | **Yes** | Free-text prompts built from user chat input plus system-instruction context that includes pregnancy week/trimester/risk flags (`DrNiswahPersona.buildSystemInstruction`), madhhab selection, fiqh questions, dream descriptions | AI chat replies (Dr. Niswah, Fiqh advisor, general assistant), dream interpretation | **UNKNOWN** — not reviewed/confirmed; Google's public API terms would need explicit legal review | **UNKNOWN** | **No** — no in-app text discloses that Gemini/Google receives this content |

Two distinct data paths reach Gemini: (1) server-side via the `dr-niswah-chat` Supabase Edge Function (source not in this repo — cannot verify what it forwards), and (2) **directly from the client device** (`GeminiService.generateText`, called from `AiAdvisorService`, `chat_view_model._sendViaDirectModel`, and `dream_interpreter` — confirming SEC-001/SEC-006's "direct-client fallback path").

---

## 19. Cookie / Local Storage Inventory

| Storage item | Purpose | Personal identifier? | Essential? | Expiry | Consent dependency |
|---|---|---|---|---|---|
| `shared_preferences` — cycle/pregnancy cache | Offline cache of PD-002/003 | Health data (indirectly identifies user's cycle/pregnancy state) | App-functional | None found | None |
| `shared_preferences` — `niswah_prayer_location_lat/lng/label` | Cache last-resolved prayer location | Precise GPS coordinate | App-functional | None found (persists indefinitely, including post-logout — not verified cleared on sign-out) | None |
| `shared_preferences` — madhhab, marital status, TTC mode, theme, locale | UI/religious preference cache | Some sensitive (madhhab) | App-functional | None found | None |
| Supabase Auth session storage | Session/JWT | Auth token | Essential | Supabase default session lifetime | N/A |

No browser cookies (mobile app). No advertising identifiers observed being read (no AdMob/IDFA/GAID usage found).

---

## 21/22. Retention & Deletion — Summary (see Findings for detail)

- **No retention period is defined anywhere** in code, schema comments, or documentation for any data category. This is an unknown, not an assumption — flagged per template rule ("do not invent retention periods").
- **No account-deletion capability exists in the app UI.** `AuthRepositoryImpl` has no `deleteAccount`/`deleteUser` method; `ProfileScreen` and `AccountSettingsScreen` offer only "Sign Out." The database schema is well-designed for cascade deletion (`ON DELETE CASCADE` from `auth.users` propagates through 15+ tables including `private_messages`, `chat_messages`, `dream_entries`, `pregnancy_profile`, etc.) but there is **no user-reachable trigger** for it anywhere in `lib/`.
- Item-level deletion exists for: cycle logs, pregnancy milestones, prayer entries, chat threads, dream entries, community posts/comments. This is real and functioning at the row level.
- BR-006 (prior wave): local health-data caches have no backup-exclusion decision, so they flow into standard OS cloud backups by default — an additional, unaddressed retention surface beyond Supabase.

---

## 23. Data Access / Export Inventory

Profile screen has a section literally labeled **"Data Export"**, but it only offers four **curated PDF reports** (Fiqh log, Doctor's report, Mental-state report, Husband report) generated from a subset of the user's data for sharing with third parties (a doctor, a husband, a scholar). It is **not** a complete personal-data export (no raw export of messages, community posts, account metadata, AI chat transcripts, or full profile record). No mechanism was found for a user to see the complete set of data held about her (no "my data" or "download everything" screen).

---

## 43. Minors / Age-Related Verification

No age-gate, minimum-age declaration, date-of-birth field, or age-related consent language was found anywhere in `lib/` (search included onboarding, sign-in, profile, and schema). A menstrual-health app is plausibly used by minors in some markets; this app currently has **zero technical age-assurance mechanism**. This is expected-and-confirmed absence, not an inference — **CHILD-01** below.

---

## 28. Discovery Execution Log

### Fully reviewed
`lib/features/auth/` (sign-in, onboarding trigger, repository), `lib/features/onboarding/`, `lib/features/auth/presentation/screens/profile_screen.dart`, `lib/features/auth/presentation/screens/account_settings_screen.dart`, `lib/core/preferences/prayer_location_controller.dart`, `lib/core/services/gemini_service.dart`, `lib/features/ai_advisor/ai_advisor_service.dart`, `lib/features/ai_assistant/data/services/dr_niswah_backend_service.dart`, `lib/features/ai_assistant/presentation/viewmodels/chat_view_model.dart` (relevant sections), `supabase/schema.sql`, `supabase/migrations/20260822210000_private_messaging.sql`, `pubspec.yaml`, `ios/Runner/Info.plist`, `android/**/AndroidManifest.xml`, `.gitignore`/`.env.example`.

### Partially reviewed
Community feature repository/RLS (delete/read paths only, not full policy set), dream interpreter and pregnancy profile repositories (schema + delete paths, not full CRUD), `dr_niswah_persona.dart` (referenced, not fully read — pregnancy-context assembly logic relies on prior wave's SEC-006 confirmation rather than a fresh full read here).

### Structurally scanned only
Full `lib/features/` directory tree (structure only), all migration files (grep for `ON DELETE CASCADE`/`CREATE POLICY` only, not full policy logic).

### Could not inspect
Supabase Edge Function source for `dr-niswah-chat` (not present in this repo — likely deployed separately; cannot verify server-side data minimization or exactly what is forwarded to Gemini). Supabase project dashboard (region, retention settings, auth provider config, storage buckets) — no runtime/console access available. Google Cloud/Gemini API console (data-retention/training settings for this project's API key) — no access available. Any vendor DPA/contract documents — none found in repo, no access to a contract repository.

### Actions performed

| Action | Purpose | Result |
|---|---|---|
| Repo-wide grep for privacy policy files | Corroborate RD-007 | Confirmed: none exist |
| Read `sign_in_screen.dart` in full | Verify consent checkbox mechanics | Confirmed checkbox does not gate sign-up (new finding beyond RD-007) |
| Read `onboarding_screen.dart` in full | Map onboarding data-collection order and consent points | Confirmed order, confirmed step 9 "Privacy" is mislabeled anonymity toggle |
| Grep for `deleteAccount`/`deleteUser` across `lib/` and `supabase/` | Verify account-deletion capability | Confirmed: none exists |
| Read `prayer_location_controller.dart` in full | Verify location purpose limitation and storage | Confirmed local-only storage, clear purpose text, no expiry |
| Read `gemini_service.dart`, `ai_advisor_service.dart`, `dr_niswah_backend_service.dart`, relevant `chat_view_model.dart` section | Verify AI data flow (server-side vs. direct-client) | Confirmed dual-path architecture; corroborates SEC-001/SEC-006 |
| Grep `schema.sql` for `ON DELETE CASCADE`/`CREATE TABLE` | Build data inventory and verify cascade design | Confirmed cascade design is correct at DB level but unreachable from UI |
| Grep for age/minor/DOB terms | Check for age-gate | Confirmed: none found |
| Grep for support/contact/DPO email | Check for alternate DSR channel | Confirmed: none found |
| Check `.gitignore`/`git ls-files` for `.env` | Verify no secret leakage into git history via this audit's own scope | Confirmed `.env` is gitignored, only `.env.example` tracked (does not itself confirm SEC-001's client-bundling concern, which is a build-time asset-bundling issue, not a git-hygiene issue) |

### Actions deliberately avoided

| Action avoided | Reason |
|---|---|
| Reading contents of `.env` | Could contain live secrets; template forbids copying secrets into audit reports and this audit does not need the actual key value, only confirmation of the bundling mechanism (already established by SEC-001) |
| Querying live Supabase project / production data | No production access provisioned; template forbids exporting/inspecting real user records |
| Creating a synthetic test account and executing Phase 2B controlled deletion/export tests | No staging environment or explicit authorization provided for this audit pass; Phase 2B is marked **not executed** in the readiness report rather than fabricated |
| Reading full `src/` web reference app | Out of scope per repo convention (`src/` is reference-only, not the release candidate) |
