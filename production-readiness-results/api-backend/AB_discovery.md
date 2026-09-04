# API & Backend Audit — Phase 1: Discovery

| Field | Value |
|---|---|
| System | Niswah (Flutter mobile app + Supabase backend) |
| Repository | Niswah (local repo) |
| Branch | main |
| Commit / Version | 13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f |
| Backend framework | Supabase (managed Postgres + PostgREST auto-API + RLS) plus one custom Deno Edge Function (`dr-niswah-chat`) |
| API style | REST (PostgREST auto-generated) + one RPC-style Edge Function + Supabase Realtime (Postgres changes) |
| Phase | 1 — Discovery |
| Audit date | 2026-09-04 |
| Environment | Local (static source review only) |
| Environment status | 🧪 Controlled — no live calls made |
| Restrictions | No live/staging Supabase project available; no deployed Edge Function invoked; no real Gemini API key used. Read-only static review only, per audit brief. |
| Report created | `AB_discovery.md` |

---

## 1. Backend Architecture Inventory

| Component | Purpose | Entry point | Dependencies | Criticality | Evidence |
|---|---|---|---|---|---|
| Supabase Postgres + PostgREST | Auto-generated REST API over all app tables, access controlled entirely by RLS policies | `supabase/schema.sql`, `supabase/migrations/*.sql` | Postgres, RLS policies | Critical (single source of truth for all persisted data) | `supabase/migrations/*.sql` |
| `dr-niswah-chat` Edge Function | Owns the "طبيبة" (Dr. Niswah) persona prompt, pregnancy-context lookup, red-flag detection, and the server-side Gemini call for the pregnancy chat feature | `supabase/functions/dr-niswah-chat/index.ts` | Supabase Auth (JWT), `pregnancy_profile`/`chat_threads`/`chat_messages`/`flagged_conversations` tables, Google Gemini REST API | Critical (only server-mediated AI feature; also the only place red-flag/urgent-symptom detection is enforced) | `supabase/functions/dr-niswah-chat/index.ts` |
| `pregnancy_status.ts` | Pure date-math helper: derives pregnancy week/trimester/postpartum status from a `pregnancy_profile` row, recomputed on every read | `supabase/functions/dr-niswah-chat/pregnancy_status.ts` | None (pure function) | High (feeds chat personalization and red-flag context) | same file |
| `supabase_flutter` client (`NiswahSupabase`) | Initializes the singleton Supabase client used by every feature repository | `lib/core/network/supabase_client.dart` | `AppEnvironment` (`.env`-sourced URL/anon key) | Critical (all client↔backend traffic funnels through this) | `lib/core/network/supabase_client.dart` |
| `ChatRepositoryImpl` / `DrNiswahBackendService` | Client-side data layer for AI-assistant chat threads/messages and the Dr. Niswah edge-function call | `lib/features/ai_assistant/data/...` | `chat_threads`, `chat_messages` tables; `dr-niswah-chat` function | High | see files below |
| `CycleTrackingRepositoryImpl` | Local-first cycle log storage with best-effort remote sync to `cycle_entries` | `lib/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart` | Local datasource + `cycle_entries` table | High (core health-tracking feature) | same file |
| `PrivateMessagingRepository` | 1:1 direct messaging backed by `private_conversations`/`private_messages` + Realtime | `lib/features/private_messaging/data/repositories/private_messaging_repository.dart` | Supabase Realtime channel, RLS | Medium-High | same file |
| `CommunityRepositoryImpl` | Community feed (posts/comments/likes) with batched count hydration and hardcoded fallback content on failure | `lib/features/community/data/repositories/community_repository_impl.dart` | `community_posts`/`community_comments`/`community_likes` | Medium | same file |
| `GeminiService` (direct client→Gemini) | Calls Google's Generative Language API **directly from the Flutter client**, no backend involved | `lib/core/services/gemini_service.dart` | Client-bundled `GEMINI_API_KEY` (via `flutter_dotenv`, `.env` shipped as an app asset) | Critical — architecture/cost/abuse concern (see AB-002) | `lib/core/services/gemini_service.dart`, `pubspec.yaml:73` |
| `AiAdvisorService` (fiqh advisor) | Consumes `GeminiService` directly for fiqh Q&A with Google Search grounding | `lib/features/ai_advisor/ai_advisor_service.dart` | `GeminiService` | High (no server mediation) | same file |
| Dream Interpreter | Consumes `GeminiService` directly | `lib/features/dream_interpreter/presentation/viewmodels/dream_interpreter_view_model.dart` | `GeminiService` | High (no server mediation) | grep confirmed `GeminiService` import |

---

## 2. Endpoint / Operation Inventory

There is no hand-written REST controller layer — the "API surface" is (a) PostgREST table access scoped by RLS, and (b) one Edge Function. Inventory below is expressed in those terms.

| API ID | Method | Route / Operation | Purpose | Auth required? | Roles | Request model | Response model | Criticality |
|---|---|---|---|---|---|---|---|---|
| API-001 | POST (Edge Function) | `dr-niswah-chat` | Send a message in a Dr. Niswah pregnancy chat thread; persists user+assistant messages, runs red-flag detection, calls Gemini server-side | YES (Supabase JWT via `Authorization` header, verified via `auth.getUser()`) | authenticated user | `{ threadId: string, content: string }` | `{ reply, urgent, messageId }` or `{ error }` | Critical |
| API-002 | PostgREST | `chat_threads` (select/insert/update/delete) | AI-assistant thread management (general/drNiswah/dreamInterpreter/fiqhAdvisory) | YES (RLS: `auth.uid() = user_id`) | owner | table row | table row(s) | High |
| API-003 | PostgREST | `chat_messages` (select/insert) | Chat history persistence | YES (RLS: ownership + thread-ownership EXISTS check) | owner | table row | table row(s) | High |
| API-004 | PostgREST (service role, server-side only) | `flagged_conversations` (insert only, from Edge Function) | Clinical-review log of red-flag chat messages | Service role only — RLS enabled, **zero client policies** (deny-all to anon/authenticated) | none (backend-only) | insert payload | — | High (safety feature) |
| API-005 | PostgREST | `cycle_entries` (select/upsert/delete) | Cycle-tracking data, local-first with remote sync | YES (RLS assumed `user_id` scoped; not independently re-verified this pass — see cross-ref to schema.sql) | owner | table row | table row(s) | High |
| API-006 | PostgREST | `private_conversations` / `private_messages` (select/insert/update) + Realtime channel `private-messages-{id}` | 1:1 direct messaging | YES (RLS: participant check) | participant | table row | table row(s) | Medium-High |
| API-007 | PostgREST | `community_posts` / `community_comments` / `community_likes` (select/insert/delete) | Community feed, comments, likes | YES for writes (RLS: `auth.uid() = user_id`); reads appear open to any authenticated user (`Users can read all ...`) | owner (write), any authenticated (read) | table row | table row(s) | Medium |
| API-008 | External (direct from client) | `https://generativelanguage.googleapis.com/v1beta/interactions` (Gemini) | AI Advisor (fiqh) and Dream Interpreter text generation | Client-side API key only; no Supabase auth involved | any app user | `{ model, input, system_instruction, tools? }` | `{ steps/outputs: [...] }` (per app's own hallucination-suspect shape — see AB-001) | Critical — see AB-001/AB-002 |

No admin, legacy/v1-v2, or debug endpoints were found reachable from the client. No pagination/versioning scheme is used for the Edge Function (single operation, no versioned route).

---

## 3. Authentication Map

| Actor | Auth mechanism | Token/session source | Backend validation | Expiry | Revocation | Evidence |
|---|---|---|---|---|---|---|
| Flutter app user | Supabase JWT (email/password or other configured provider), persisted via `supabase_flutter` | `FlutterAuthClientOptions(persistSession: true, autoRefreshToken: true)` | For PostgREST: Supabase platform validates JWT signature/expiry before RLS evaluates `auth.uid()` (platform-level, not app code — not independently re-verified this pass). For `dr-niswah-chat`: explicitly re-verified server-side via `userClient.auth.getUser()` (`index.ts:224-230`), which calls Supabase Auth to confirm the token is live, not just present | Standard Supabase JWT TTL (project-config, not in repo — UNKNOWN) | Standard Supabase session revocation (project-level — UNKNOWN, not verified) | `lib/core/network/supabase_client.dart`, `supabase/functions/dr-niswah-chat/index.ts:206-231` |
| `dr-niswah-chat` → Postgres (user-scoped) | Forwarded user JWT | `Authorization` header passed through to a `createClient(..., { global: { headers: { Authorization: authHeader } } })` | RLS enforced per-user for every read/write this client makes | Same as above | Same as above | `index.ts:220-222` |
| `dr-niswah-chat` → Postgres (service role) | Supabase service-role key (server-side secret) | `Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')` | Bypasses RLS entirely — used **only** to insert into `flagged_conversations` | N/A (never expires; must never leave the Edge Function runtime) | N/A | `index.ts:247` |
| Direct-to-Gemini client calls (AI Advisor, Dream Interpreter) | Raw Gemini API key, no Supabase auth at all | Bundled `.env` → `flutter_dotenv` at build time (`.env` shipped as an app **asset**, `pubspec.yaml:73`) | None — no server in the loop | N/A (static key) | Requires manual key rotation in Google Cloud console; app has no revocation mechanism | `lib/core/services/gemini_service.dart:38-49`, `pubspec.yaml:73` |

---

## 4. Authorization Map

| API ID | Role(s) allowed | Resource ownership check? | Admin override? | Server enforced? | Evidence |
|---|---|---|---|---|---|
| API-001 (`dr-niswah-chat`) | authenticated user | Implicit — all reads/writes go through the user-scoped `userClient`, so RLS applies transitively | No admin path | YES (JWT re-verified + RLS on every table op) | `index.ts:220-293` |
| API-002/003 (`chat_threads`/`chat_messages`) | owner | YES — `auth.uid() = user_id`, and `chat_messages` INSERT additionally requires an `EXISTS` check that the target `thread_id` belongs to the caller (prevents writing into another user's thread by guessing/reusing a `threadId`) | No | YES | `supabase/migrations/20260824115900_dr_niswah_chat_threads.sql:52-92` |
| API-004 (`flagged_conversations`) | none (client) | N/A | N/A | YES — RLS enabled with **zero** policies defined, which denies all anon/authenticated access by default; only the service-role client (used exclusively inside the Edge Function) can write | `supabase/migrations/20260824120000_dr_niswah_flagged_conversations.sql` |
| API-006 (private messaging) | participant only | YES — policies reference `participant_one`/`participant_two` | No | YES | `supabase/migrations/20260822210000_private_messaging.sql` |
| API-007 (community) | owner (write), any authenticated (read) | YES for writes | No | YES | `supabase/migrations/20260830140000_community_schema_reset.sql` |
| API-008 (direct Gemini) | N/A | N/A | N/A | **NO** — no authorization concept applies; any holder of the extracted API key has full access | `lib/core/services/gemini_service.dart` |

**Critical rule check:** No endpoint in this system relies on hidden UI as its only authorization — all reviewed authorization is RLS/JWT-backed at the database or Edge Function layer. The one exception is API-008, which has no authorization layer at all by design (see AB-002).

---

## 5. Request Validation Inventory

| API ID | Validation layer | Schema | Rejects unknown fields? | Server-side? | Notes |
|---|---|---|---|---|---|
| API-001 (`dr-niswah-chat`) | Hand-written checks in `index.ts:233-239` | `threadId` truthy, `content` is a non-empty trimmed string | No — extra JSON body fields are silently ignored, not rejected | YES | No max length on `content`; no UUID-shape check on `threadId` (a malformed value fails at the Postgres FK/type level with a raw 500, not a clean 400) — see AB-006 |
| API-002/003/005/006/007 (PostgREST tables) | Postgres column types + CHECK constraints + RLS `WITH CHECK` clauses | Table schema (`supabase/migrations/*.sql`) | Yes, implicitly — PostgREST rejects columns that don't exist on the table | YES (DB-enforced) | Standard Postgres type/constraint validation; no app-level bounds beyond what the schema encodes (e.g., no explicit max length on `chat_messages.content` / `community_posts.content` found in migrations reviewed) |
| API-008 (direct Gemini) | None found | N/A | N/A | NO (fully client-side, no server ever sees or validates the request) | See AB-002 |

---

## 6. Response Contract Inventory

- `dr-niswah-chat` success: `200 { reply: string, urgent: boolean, messageId: string|null }`.
- `dr-niswah-chat` error: non-200 `{ error: string }` for 401 (missing/invalid auth) and 400 (missing threadId/content); uncaught exceptions fall through to a generic `catch` at the bottom returning `500 { error: error.message }` (`index.ts:303-308`) — this can surface internal exception text (e.g., a Postgrest error string, or `"GEMINI_API_KEY is not configured."`) rather than a sanitized message. See AB-007.
- PostgREST responses follow standard Supabase/PostgREST JSON array/object shape; `.single()`/`.maybeSingle()` used appropriately in repositories to normalize to object vs. array.
- No pagination metadata envelope is used anywhere (see §9 below — pagination is ad hoc per-repository).

---

## 7. Status Code Inventory (`dr-niswah-chat`)

| Code | Used for | Evidence |
|---|---|---|
| 200 | OPTIONS preflight, success, and (implicitly) any thrown error text embedded in a 200 body is NOT observed — errors correctly use non-200 codes | `index.ts:200-203`, `295-301` |
| 400 | Missing/invalid `threadId`/`content` | `index.ts:234-239` |
| 401 | Missing `Authorization` header; invalid/expired session | `index.ts:206-212`, `224-230` |
| 500 | Any other uncaught exception, including upstream Gemini failures that escape the internal fallback (they should not, since `callGemini` failures are caught locally at `index.ts:269-274`, but any other exception — e.g., a Postgrest insert failure — falls through to the generic 500 handler) | `index.ts:303-308` |

No 201/202/204/403/404/409/422/429 codes are used by this function. 429 is notably absent even though no rate limiting exists (see AB-008) — a rate-limited client would simply get a 500 or hang, not a clean 429.

---

## 8. Business Rule Enforcement Map

| Rule ID | Rule | Endpoint(s) | Server enforced? | Client also enforces? | Source of truth |
|---|---|---|---|---|---|
| BR-001 | Red-flag / urgent-symptom keywords in a chat message must trigger a clinical-review log entry and an urgent banner, independent of whether the Gemini call itself succeeds | `dr-niswah-chat` | YES — `detectRedFlags()` runs before the Gemini call and its result is used regardless of Gemini's outcome (`index.ts:241-281`) | No client-side duplicate — client only renders what the server returns | Edge Function (server) |
| BR-002 | Pregnancy week/trimester/postpartum phase is always recomputed from stored dates, never trusted from a cached value | `dr-niswah-chat` | YES — `loadPregnancyProfile` + `getPregnancyStatus` run fresh on every call (`index.ts:264-266`) | A Dart mirror of the same engine exists client-side (`pregnancy_status_engine.dart`, referenced in `pregnancy_status.ts` comments) for other UI purposes — these two implementations are manually kept in sync, not shared code, which is a latent-drift risk (flagged for the Data-Integrity/Code-Quality audits, cross-referenced here) | Server, for chat personalization specifically |
| BR-003 | AI Advisor (fiqh) answers must cite only trusted domains (`islamweb.net`, `dorar.net`) or refuse to answer | `ai_advisor_service.dart` (client-side, no backend) | **NO** — this business rule is enforced entirely client-side (`_isTrustedCitation`, `ai_advisor_service.dart:44-50`); nothing prevents a modified/repackaged client from skipping this filter, and the raw Gemini call itself has zero server-side moderation | YES (only enforcement point) | Client only — flagged as client-only enforcement |

---

## 9. External Integration Inventory

| Integration ID | Service | Purpose | Auth | Timeout | Retry | Idempotency | Failure handling | Sandbox? |
|---|---|---|---|---|---|---|---|---|
| INT-001 | Google Generative Language API (Gemini), called server-side from `dr-niswah-chat` | Generate the "طبيبة" chat reply | `x-goog-api-key` header, key from `Deno.env.get('GEMINI_API_KEY')` | **None explicit** — no `AbortController`/timeout wrapped around the `fetch()` call (`index.ts:159-170`) | Bounded — loops across 2 hardcoded model names, retrying only on `429/500/503` (`index.ts:156-197`); no backoff/jitter between attempts | N/A (not a callback) | On failure, falls back to a canned Arabic "couldn't get a reply, try again" message (or just the urgent banner if red-flagged) rather than surfacing an error to the user — a deliberate, reasonable degrade, but it means a systemic Gemini outage is invisible to any monitoring that only looks at HTTP status (the function still returns 200) | No — production endpoint always targeted |
| INT-002 | Google Generative Language API (Gemini), called **directly from the Flutter client** | AI Advisor (fiqh) + Dream Interpreter text generation | Raw API key bundled in the client `.env` asset | Explicit — `18s`/`35s` via `.timeout()` (`gemini_service.dart:87-91`) — better timeout hygiene than the server-side call, ironically | Same bounded 2-model fallback pattern as INT-001 | N/A | Exceptions propagate to caller; `AiAdvisorService.askFiqh` catches and returns a canned Arabic fallback (`ai_advisor_service.dart:30-34`) | No |
| INT-003 | Supabase Realtime (Postgres changes) | Live message delivery for private messaging | Supabase client session | Not applicable (persistent WS connection) | Handled by `supabase_flutter`/Realtime client internally — not app-code-controlled, not verified this pass | N/A | Not reviewed in depth this pass (out of primary scope; flagged as partially reviewed) | No |

Both INT-001 and INT-002 target the **same** hardcoded endpoint URL and request/response shape that this audit suspects is a non-existent Gemini API surface — see AB-001 in the findings report.

---

## 10. Webhook Inventory

None found. No inbound webhook receivers exist in this codebase (no payment, SMS, or third-party callback endpoints). Not applicable.

---

## 11. Background Job Inventory

None found in the reviewed surface. `CycleTrackingRepositoryImpl.syncPendingLogs()` is a client-invoked reconciliation method, not a server-side background job/cron — it only runs when the app code calls it. No Supabase scheduled functions (`pg_cron` or Edge Function schedules) were found in `supabase/`. Not applicable / not found.

---

## 12. API Versioning Inventory

No URL or header versioning scheme exists for the Edge Function or PostgREST usage. The Gemini endpoint hardcodes `v1beta` as an API-provider version, not an app version. No deprecated/legacy endpoints found. Not applicable to this system's current scale.

---

## 13. Pagination / Filtering / Sorting Inventory

| Location | Page size | Max enforced? | Cursor/offset | Stable order | Notes |
|---|---|---|---|---|---|
| `CommunityRepositoryImpl.getPosts` | `pageSize = 15` (default param, caller-controlled) | **No upper bound enforced server-side or client-side** on `pageSize` — a caller passing a very large `pageSize` would be honored as-is via `.limit(pageSize + 1)` | Offset-style via `beforeCreatedAt` cursor on `created_at` | Yes — ordered by `created_at DESC` | See AB findings register — unbounded page size is a minor hardening gap, not exploitable beyond the caller's own RLS-visible rows |
| `ChatRepositoryImpl.getThreads`/`getMessages` | No limit at all — fetches entire history | No | N/A | Yes (`created_at`/`updated_at` order) | A very long chat history has no pagination; acceptable at current expected scale but flagged as a scalability observation |
| `CycleTrackingRepositoryImpl.getCycleLogs` | `limit = 200` (default param) | Caller-controlled, not clamped server-side | Date range filter (`from`/`to`), not cursor-based | Yes (`date DESC`) | Same pattern as above |
| `PrivateMessagingRepository.fetchMessages` | No limit — fetches entire conversation history | No | N/A | Yes (`created_at ASC`) | Same observation |

No endpoint in this system enforces a server-side maximum page size; all bounds are client-supplied defaults that a modified client could exceed. Given RLS still scopes results to the caller's own rows, the blast radius is self-limited (a user can only over-fetch their own data), so this is recorded as an AB3/AB4 observation, not a security-severity finding.

---

## 14. File Upload / Download Inventory

Not reviewed this pass — no file/storage-bucket code was encountered in the four repositories inspected. Marked **structurally scanned only / not verified** — Supabase Storage usage (if any, e.g. for profile photos or community images) should be separately confirmed by a follow-up pass; out of scope for this audit's required file list.

---

## 15. AI-Agent-Specific Signals Noted During Discovery

- `supabase/functions/dr-niswah-chat/index.ts` header comment and `20260824115900_dr_niswah_chat_threads.sql` comment both document a real, already-fixed AI-agent defect: `chat_threads` was documented in `schema.sql` but never actually migrated, and `schema.sql`'s `thread_type` CHECK values (`'dr_niswah'`, `'general'`, ...) never matched the Dart enum names actually written by the client (`'drNiswah'`, `'fiqhAdvisory'`, ...). This was caught and fixed in a later migration, but `schema.sql` itself is documented as still containing the wrong values — a live contract-drift risk if anyone re-derives migrations from `schema.sql` in the future. Flagged for cross-reference to Data-Integrity/Code-Quality audits.
- Two independent Dart/TypeScript implementations of the same pregnancy-week engine (`pregnancy_status_engine.dart` and `pregnancy_status.ts`) are manually kept in sync per the file's own comments — a classic AI-generated-code duplication risk (BR-002 above).
- Both the server-side (`dr-niswah-chat`) and 100%-independent client-side (`gemini_service.dart`) Gemini integrations use the **identical**, structurally unusual `input`/`system_instruction`/`steps`/`outputs`/`model_output` request/response shape against `v1beta/interactions` — strongly suggesting both were generated from the same (likely hallucinated) reference rather than Google's actual documented API. See AB-001.

---

## 16. Discovery Execution Log

### Fully reviewed
- `supabase/functions/dr-niswah-chat/index.ts` (complete)
- `supabase/functions/dr-niswah-chat/pregnancy_status.ts` (complete)
- `supabase/functions/dr-niswah-chat/pregnancy_status.test.ts` (complete)
- `lib/core/network/supabase_client.dart` (complete)
- `lib/core/errors/failures.dart` (complete)
- `lib/core/services/gemini_service.dart` (complete)
- `lib/features/ai_assistant/data/repositories/chat_repository_impl.dart` (complete)
- `lib/features/ai_assistant/data/services/dr_niswah_backend_service.dart` (complete)
- `lib/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart` (complete)
- `lib/features/private_messaging/data/repositories/private_messaging_repository.dart` (complete)
- `lib/features/community/data/repositories/community_repository_impl.dart` (complete)
- `lib/features/ai_advisor/ai_advisor_service.dart` (complete)
- `lib/core/config/app_environment.dart` (complete)
- Relevant RLS migrations: `20260824115900_dr_niswah_chat_threads.sql`, `20260824120000_dr_niswah_flagged_conversations.sql`, `20260822210000_private_messaging.sql`, `20260830140000_community_schema_reset.sql` (policy sections)

### Partially reviewed
- `lib/features/cycle_tracking/data/datasources/local_cycle_tracking_data_source.dart` — referenced but not fully read (local-only storage, lower backend relevance)
- `lib/features/private_messaging/data/repositories/mock_private_messaging_repository.dart` — spot-checked to confirm it's a UI-preview mock, not a production fallback wired into the same code path as the real repository (unlike `CommunityRepositoryImpl`, which inlines its fallback data directly)
- `supabase/schema.sql` — referenced via migration comments, not independently re-diffed against every migration
- `lib/features/dream_interpreter/` and `lib/features/ai_advisor/` presentation layers — confirmed to call `GeminiService`/`AiAdvisorService` via grep, not read line-by-line

### Structurally scanned only
- Supabase Storage / file upload code (not located in the four target repositories; not exhaustively searched repo-wide)
- Supabase Realtime internals (`private-messages-{id}` channel usage confirmed present; delivery/reconnect semantics not independently verified)

### Could not inspect
- Live Supabase project configuration (RLS as actually deployed, Edge Function environment variables, project-level rate limiting / WAF, JWT expiry settings, Postgres connection pooling limits) — no deployed environment or credentials available to this audit.
- Actual Gemini API behavior against the endpoint used in this codebase — no network egress / live API key available to this audit; assessed from documented knowledge of the Gemini API surface only (see AB-001).
- `pubspec.lock`-pinned `postgrest`/`gotrue`/`http` package internals (default timeout behavior) — versions identified (`supabase_flutter: ^2.8.1`) but package source was not read this pass.

### Commands/actions performed
| Action | Purpose | Result |
|---|---|---|
| Read `index.ts`, `pregnancy_status.ts`, `pregnancy_status.test.ts` in full | Understand the only custom backend endpoint | Documented above |
| Read `supabase_client.dart`, 4 feature repositories, `gemini_service.dart`, `ai_advisor_service.dart` | Assess client↔backend contract and error handling consistency | Documented above |
| Grepped for RLS policies across relevant migrations | Confirm authorization is DB-enforced, not UI-only | Confirmed for all reviewed tables |
| Grepped for retry/backoff/timeout utilities repo-wide | Confirm presence/absence of resilience patterns | Found only in `gemini_service.dart`; none elsewhere |
| Checked `pubspec.yaml` for `.env` asset bundling | Assess whether client-side API keys are shippable/extractable | Confirmed `.env` is declared as a bundled asset |

### Actions deliberately avoided
| Action avoided | Reason |
|---|---|
| Invoking the live `dr-niswah-chat` Edge Function | No approved live environment; audit brief mandates static/read-only review only |
| Making a real call to the Gemini endpoint used in the code | Would require a live API key and could incur cost; assessment made from documented API knowledge instead, explicitly marked as needing live confirmation |
| Modifying any source file | Auditor-only mandate |

---

## 17. Discovery Exit Gate

- [x] Backend architecture is mapped.
- [x] Critical endpoints are inventoried.
- [x] Authentication is mapped.
- [x] Authorization is mapped.
- [x] Request validation is understood.
- [x] Response/error contracts are understood.
- [x] Critical business rules are mapped.
- [x] External integrations are mapped.
- [x] Webhooks/jobs are mapped (none found).
- [x] Versioning and pagination are understood.
- [x] Unknown/unreviewed areas are explicitly listed (§16).
