# 01 — Security Discovery Report — Niswah

## Report Header

| Field | Value |
|---|---|
| System | Niswah (women's health / cycle-fiqh / pregnancy tracking app) |
| Repository | `/Users/rynadalsabh/Niswah` |
| Branch | `main` |
| Commit / Version | `13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f`, app version `1.0.0+1` |
| Environment | LOCAL (static source review only — no staging/prod runtime access) |
| Audit date | 2026-09-04 |
| Platforms | iOS, Android (Flutter, bundle ID `com.niswah.niswah`) |
| Auth provider | Supabase Auth (email/password, phone/OTP, Google OAuth) |
| Primary database | Supabase Postgres (RLS) |
| Major integrations | Supabase (Auth, Postgres, Edge Functions, Realtime), Google Generative Language API ("Gemini") — both **directly from the client** and **via a Supabase Edge Function** |
| Restrictions | No live Supabase dashboard/project access. No runtime/dynamic testing (no APK/IPA build or extraction performed — findings on bundling are static/config-based). No penetration test against a running instance. `src/` (React/Vite web app) reviewed only for shared-credential/config overlap, per prior project instruction that it is a design reference, not the audited surface. |

`src/` shares the repo-root `.env` (same `SUPABASE_URL`/`SUPABASE_ANON_KEY`/`GEMINI_API_KEY`) with the Flutter app and also calls Gemini directly from `src/components/DreamInterpreter.tsx` and `src/components/NiswahAI.tsx` — noted only as corroborating context for SEC-001 (same key, two client surfaces), not audited or remediated as part of this scope.

---

## 6. Architecture / Trust Boundary Inventory

| Component | Trust level | Inputs received from | Outputs sent to | Sensitive? | Internet exposed? |
|---|---|---|---|---|---|
| `SYS-001` Flutter mobile app (`lib/`) | Untrusted client | User input, device sensors (location), local storage | Supabase (Postgres/Auth/Realtime/Edge Functions), Google Generative Language API | YES | YES (installed on user devices) |
| `SYS-002` Supabase Postgres (RLS) | Trusted backend, per-row scoped | Flutter app (via PostgREST, anon key + user JWT) | Flutter app | YES | YES (PostgREST endpoint is internet-reachable; gated by anon key + RLS) |
| `SYS-003` Supabase Auth | Trusted backend | Email/password, phone/OTP, Google OAuth | JWT/session to client | YES (credentials) | YES |
| `SYS-004` Edge Function `dr-niswah-chat` (Deno, `supabase/functions/dr-niswah-chat/index.ts`) | Trusted backend, service-role capable | Flutter app (bearer JWT + JSON body) | Google Generative Language API, Postgres (`chat_messages`, `flagged_conversations` via service role) | YES (health/pregnancy context, chat content) | YES |
| `SYS-005` Google Generative Language API ("Gemini") | External third party | **(a)** Edge function (server-side, key server-only) **(b)** Flutter client directly (`GeminiService`, key bundled in app) | Model text + citations | YES (prompts carry fiqh questions, dream content, and — on one fallback path — pregnancy/health context) | YES |
| `SYS-006` Local device storage (`shared_preferences`) | Untrusted (device-local) | Cycle logs, pregnancy milestones, UI flags | N/A (read back by app) | YES (health data) | NO |
| `TRUST-001` Client ↔ Supabase Postgres boundary | RLS-enforced per-row | Any value the client sends | — | — | — |
| `TRUST-002` Client ↔ Google Gemini boundary (direct calls) | **No trust boundary — client holds a live third-party API credential** | — | — | — | — |

---

## 7. User / Role Inventory

| Role ID | Role | Authentication method | Privileges | Sensitive actions |
|---|---|---|---|---|
| `ROLE-001` | Guest (unauthenticated) | None | View onboarding only; app gates `NiswahHomeShell` behind `SignInScreen` | None |
| `ROLE-002` | Authenticated user | Supabase email/password, phone/OTP, or Google OAuth | Full CRUD on own cycle/pregnancy/prayer/wellbeing/dream data; read/write own chat threads; public read + own-write on community posts/comments/likes; DM any other user by UUID; read own `flagged_conversations` | Delete own data, private messaging, AI chat (health/fiqh) |
| `ROLE-003` | Supabase service role (server-side only, edge function + migrations) | Service-role key (env-only, not in client) | Bypasses RLS; writes `flagged_conversations`, `chat_messages` | Logs red-flag clinical concerns |
| `ROLE-004` | "Moderator/clinician" (implied by `flagged_conversations.reviewed` column) | **No corresponding role/UI found in `lib/`** | N/A — **not implemented** | N/A |

No admin app/dashboard exists in the audited surface beyond the Supabase project dashboard itself (out of scope, no access).

---

## 8. Authentication Inventory

| Method | Enrollment | Verification | Login | Logout | Recovery | Lockout/abuse | Session |
|---|---|---|---|---|---|---|---|
| Email/password | `signUpWithEmail` → Supabase `auth.signUp` | Email confirmation link → `niswah://login-callback` deep link | `auth.signInWithPassword` | `auth.signOut` | `auth.resetPasswordForEmail` → same deep link | Delegated entirely to Supabase Auth defaults (not independently configurable/verifiable from source) | `supabase_flutter` `persistSession: true, autoRefreshToken: true` |
| Phone/OTP | `signUpWithPhone` | `verifyPhoneOtp` (`auth.verifyOTP`, type `sms`) | `auth.signInWithPassword(phone:...)` | shared | `resendPhoneOtp` | Delegated to Supabase | shared |
| Google OAuth | `signInWithGoogle` → `auth.signInWithOAuth` | Delegated to Google/Supabase | — | shared | N/A | Delegated | shared |

All three methods are handled entirely by `supabase_flutter`'s built-in `auth` client (`lib/features/auth/data/repositories/auth_repository_impl.dart`) — no custom password hashing, token minting, or session logic was found in the app; this is the correct pattern (delegate to a trusted provider). Actual server-side enforcement (rate limiting on login/OTP, password policy, leaked-password protection, email-confirmation requirement) lives in the Supabase project dashboard configuration, which was **not accessible** — see `SEC-010` (UNKNOWN).

---

## 9. Authorization Inventory (representative — full detail in RLS policy read of `supabase/schema.sql` + `supabase/migrations/*.sql`)

| Action ID | Action | Allowed roles | Server-side check? | Ownership check? | Criticality |
|---|---|---|---|---|---|
| `AUTHZ-001` | Read/write own cycle/pregnancy/prayer/wellbeing/dream/chat rows | ROLE-002 | YES (Postgres RLS `auth.uid() = user_id`) | YES | High (health data) |
| `AUTHZ-002` | Read community posts/comments/likes | ROLE-002 (any authenticated user) | YES (`USING (true)`, intentional public read) | N/A by design | Medium |
| `AUTHZ-003` | Write community posts/comments/likes | ROLE-002 | YES (`auth.uid() = user_id`) | YES | Medium |
| `AUTHZ-004` | Read/send private messages | ROLE-002, must be a conversation participant | YES (`is_conversation_participant()` SECURITY DEFINER helper) | YES | High |
| `AUTHZ-005` | Mark a private message read | ROLE-002, recipient only | YES (`auth.uid() <> sender_id`) but **not column-scoped** — see `SEC-004` | Partial | High |
| `AUTHZ-006` | Read `flagged_conversations` | ROLE-002, self only | YES (`auth.uid() = user_id`) | YES | High (clinical/moderation data) |
| `AUTHZ-007` | Write `flagged_conversations` | ROLE-003 (service role) only, via edge function | YES (no client policy at all → default-deny) | N/A | High |
| `AUTHZ-008` | Call `dr-niswah-chat` edge function | ROLE-002 (valid Supabase JWT) | YES (`userClient.auth.getUser()` verified before any DB/Gemini call) | YES (reads/writes scoped to `userData.user.id`) | High |
| `AUTHZ-009` | Call Gemini directly from client (fiqh advisor, dream interpreter, chat fallback) | **Effectively anyone holding the extracted app key** — see `SEC-001` | NO — no backend authorization boundary exists for this path | N/A | Critical |

UI hiding was not relied upon anywhere found; every user-scoped table has a matching RLS policy in the migrations reviewed.

---

## 10. Sensitive Data Inventory

| Data | Sensitivity | Stored where | Transmitted to | Retention | Encryption |
|---|---|---|---|---|---|
| Menstrual/haid cycle entries, fiqh state | Very high (health + religious practice) | Postgres `cycle_entries` (RLS); also cached client-side in `shared_preferences` (plaintext) | Supabase only | Indefinite (no TTL/delete-flow found beyond manual delete) | In transit: TLS (Supabase default). At rest server-side: Supabase-managed. At rest client-side: **unencrypted** (`SEC-007`) |
| Pregnancy profile / milestones / postpartum status, high-risk flags | Very high | Postgres `pregnancy_profile`, `pregnancy_milestones`, `nifas_records`; cached client-side in `shared_preferences` | Supabase; **also Google Gemini directly** on the client fallback chat path (`SEC-006`) | Indefinite | Same as above |
| Chat content (Dr. Niswah, fiqh advisor, dream interpreter, general) | High (health/religious/psychological) | Postgres `chat_messages`, `dream_entries` | Supabase + Google Gemini (server-side via edge function, or **directly from client**, `SEC-001`) | Indefinite | TLS in transit; server-side Supabase-managed at rest |
| Private messages (DMs) | High | Postgres `private_messages` | Supabase (Realtime too) | Indefinite | TLS in transit; server-side Supabase-managed; integrity gap `SEC-004` |
| `flagged_conversations` (red-flag clinical excerpts) | High | Postgres, service-role write only | Supabase | Indefinite | Same |
| Auth credentials/session | Critical | Supabase Auth (server-side); session persisted client-side by `supabase_flutter` | Supabase | Session lifetime | Delegated to `supabase_flutter`/Supabase defaults — not independently reviewed at the storage-primitive level (out of the audited file set) |
| Community posts/comments | Medium (user-generated, potentially identifying if `is_anonymous=false`) | Postgres, public SELECT by design | Supabase | Indefinite | N/A (intentionally public within the app) |
| `GEMINI_API_KEY` (third-party secret) | Critical | `.env` (git-ignored) → **bundled into the compiled app as a Flutter asset** | Google API (from client and from edge function) | N/A | **Not protected — trivially extractable from the release binary (`SEC-001`)** |
| `SUPABASE_SERVICE_ROLE_KEY` | Critical | Edge function server-side env (`Deno.env.get`) only, per static review | N/A (server-side only) | N/A | No client-side reference found (grep-confirmed) |

---

## 11. Secret Inventory (names only — no values printed)

| Secret ID | Name | Used by | Storage location | Client exposed? | Rotatable? |
|---|---|---|---|---|---|
| `SECRET-001` | `SUPABASE_URL` | Flutter client, edge function | `.env` (client), edge function env | YES (by design — public project URL) | YES |
| `SECRET-002` | `SUPABASE_ANON_KEY` | Flutter client, edge function's `userClient` | `.env` (client), edge function env | YES (by design — client-safe key, RLS-scoped) | YES |
| `SECRET-003` | `SUPABASE_SERVICE_ROLE_KEY` | Edge function only (`dr-niswah-chat/index.ts:216`) | Edge function env only | NOT FOUND client-side (grep-confirmed across `lib/`) | YES (assumed — not verified live) |
| `SECRET-004` | `GEMINI_API_KEY` | Flutter client (`gemini_service.dart`) **and** edge function (`callGemini`) | `.env`, which is **listed under `pubspec.yaml`'s `flutter: assets:`** and therefore compiled into the app bundle | **YES — confirmed exposed (`SEC-001`)** | Rotatable at Google Cloud console, but rotation does not fix the architectural exposure |
| `SECRET-005` | `OPENAI_API_KEY` / `NISWAH_AI_API_KEY` / `DREAM_INTERPRETER_API_KEY` | **Declared and validated in `AppEnvironment` but never read/used anywhere else in `lib/`** (grep-confirmed dead code) | `.env` (optional; validation only runs if non-empty) | N/A — unused | N/A |

---

## 12. API Surface Inventory

| Endpoint / Route | Method | Auth required? | Role restriction | Sensitive data? | Rate limit? |
|---|---|---|---|---|---|
| Supabase PostgREST (`/rest/v1/<table>`) for every user table | GET/POST/PATCH/DELETE | YES (anon key + user JWT) | RLS-enforced per table (see AUTHZ table) | YES | Supabase project-level defaults only (not independently configured in source; UNKNOWN live value) |
| Supabase Realtime (`private_messages` channel) | WS | YES (session-scoped) | RLS applies to Realtime too (Supabase default) | YES | UNKNOWN |
| Edge Function `dr-niswah-chat` | POST | YES (`Authorization` bearer JWT, verified via `auth.getUser()`) | Self-scoped to caller's `userId` | YES (health context, chat content) | **NO application-level rate limit found (`SEC-005`)** |
| Google Generative Language API (`generativelanguage.googleapis.com/v1beta/interactions`) — called directly from client | POST | Google API key only (`x-goog-api-key` header) — **no Niswah-side auth gate at all** | None | YES | **NO — unlimited given the exposed key (`SEC-001`)** |

---

## 13. File Upload Inventory

No file/image upload surface was found in the audited `lib/` tree (no Supabase Storage `upload()` calls, no multipart form endpoints). PDF reports (`doctor_report`, `husband_report`) are generated **locally on-device** with the `pdf`/`printing` packages and handed to the OS share sheet — they are not uploaded to any backend or object storage. This significantly narrows the file-upload attack surface; File Upload Audit (§30) is **N/A** for this release candidate.

---

## 14. External Integration Inventory

| Integration | Purpose | Auth method | Sensitive data sent? | Webhook? | Critical? |
|---|---|---|---|---|---|
| Supabase (Auth/Postgres/Edge Functions/Realtime) | Backend of record | Anon key + JWT (client), service-role key (server) | YES | NO webhook surface found in-scope | YES |
| Google Generative Language API ("Gemini") | AI Advisor (fiqh), Dream Interpreter, Dr. Niswah chat, general assistant | API key (`x-goog-api-key`) — **client-side for 3 of 4 call sites** | YES (see Sensitive Data Inventory) | NO | YES |
| Google OAuth | Social login | OAuth, delegated to Supabase | Identity only | NO | Medium |
| `geolocator` (device location) | Prayer-time calculation (`adhan_dart`) | Device permission (`ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION`) | Location coordinates — used locally for prayer calc; also persisted to `users.location_lat/lng` per `schema.sql` | NO | Low-Medium (location is health-adjacent/PII) |

---

## 15. Security-Control Inventory (presence/absence)

| Control | Status |
|---|---|
| Rate limiting / brute-force protection | Supabase Auth defaults (UNKNOWN live config); **absent at the application layer** for the edge function and entirely absent/moot for the exposed-key direct-Gemini path |
| CSRF protection | N/A — no cookie-based session auth found; mobile app uses bearer JWTs |
| CORS policy | Edge function uses `Access-Control-Allow-Origin: '*'` (wildcard) — acceptable given bearer-token (non-cookie) auth model, but not origin-restricted |
| CSP | N/A (native mobile app, not a web app in the audited surface) |
| Secure cookies | N/A (no cookie auth) |
| Token expiry / refresh | Delegated to `supabase_flutter` (`autoRefreshToken: true`) — standard, not independently re-implemented |
| Input validation | Present at DB layer via CHECK constraints (e.g. `community_posts_content_length`, `wellbeing_logs` mood/energy/sleep ranges, `pregnancy_profile.manual_week_value BETWEEN 1 AND 42`); client-side trimming/empty-checks present in most repositories |
| Output encoding | N/A — Flutter renders text via widgets, not HTML; no `dangerouslySetInnerHTML`-equivalent found in `lib/` |
| DB parameterization | YES — all data access goes through the Supabase client's structured query builder (`.eq()`, `.insert()`, etc.); no raw/concatenated SQL found in `lib/` or `supabase/functions/`. One instance of raw-string PostgREST `.or()` filter interpolation noted (`SEC-009`, low severity, RLS-backstopped) |
| SSRF prevention | N/A — no user-controlled URL fetch surface found in the edge function or client |
| Webhook verification | N/A — no webhook receiver found in-scope |
| Upload restrictions | N/A — no upload surface (see §13) |
| Audit logging | `flagged_conversations` serves as a narrow clinical audit log for red-flag chat content on the edge-function path only; the client-side direct-Gemini fallback path does **not** write to this log (`SEC-006`) |

---

## 16. Discovery Exit Gate

- [x] Architecture mapped.
- [x] Trust boundaries identified.
- [x] Roles identified.
- [x] Auth methods identified.
- [x] Authorization-sensitive actions mapped.
- [x] Sensitive data identified.
- [x] Secrets inventoried (names only).
- [x] API surface mapped.
- [x] Upload surfaces mapped (found: N/A).
- [x] External integrations mapped.
- [x] Critical unknowns listed (see `SEC_findings.md` — `SEC-010`, `SEC-011`).

Discovery phase complete. Proceed to `SEC_findings.md` for Phase 2A static verification findings.
