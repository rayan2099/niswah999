# 04 — Security Remediation Plan — Niswah

> ⚠️ **This remediation plan is PROPOSED — NOT IMPLEMENTED.** No code, configuration, dependency, or database change described below has been made as part of this audit. This audit was conducted in a strict read-only, findings-only capacity. Every action item below requires separate authorization, implementation, and a controlled security regression test (Phase 2B) before the corresponding finding may be marked closed.

---

## Root-Cause Map

| Finding | Symptom | Root cause | Confidence | Related findings | Remediation phase |
|---|---|---|---|---|---|
| SEC-001 | `GEMINI_API_KEY` extractable from release binary; unrestricted direct client→Google calls | `.env` bundled as a Flutter asset; 3 of 4 AI features never migrated to the server-side edge-function pattern the team already built for Dr. Niswah | High | SEC-002, SEC-005, SEC-006 | R1 |
| SEC-002 | Validated env vars are unused; real key is unvalidated | Config module validates a set of variable names that were superseded by `GEMINI_API_KEY` without cleanup | High | SEC-001 | R1 |
| SEC-003 | Release APK/AAB signed with debug keystore | `TODO` left unresolved in `android/app/build.gradle.kts`; no release keystore was ever generated/wired in | High | — | R1 |
| SEC-004 | Recipient can rewrite private-message `content`/`sender_id` | RLS `UPDATE` policy scoped to rows only, not columns; no trigger/column-grant enforcing the "read-flag only" intent | High | — | R1 |
| SEC-005 | No cap on Gemini-backed edge-function calls per user | No abuse-control layer was built into the edge function | Medium | SEC-001 | R2 |
| SEC-006 | Health context sent client-side to Google on a fallback path; audit log skipped | `isAvailable` check only verifies SDK initialization, not actual edge-function reachability, and the fallback re-implements (rather than refuses) the AI call | Medium | SEC-001 | R1 (closes automatically once SEC-001's fix removes all direct-Gemini client paths) |
| SEC-007 | Health data cached in plaintext locally | `shared_preferences` chosen for local cache convenience; no secure-storage requirement was set for health-sensitive local caches | Medium | — | R2 |
| SEC-009 | Raw PostgREST filter string interpolation | Convenience string-building instead of the Supabase client's structured filter API | Low | — | R2 |
| SEC-010, SEC-011 | Live-config state unverifiable from source | No access to the live Supabase project/dashboard was granted for this audit | N/A (unknown, not a code defect) | — | R0 (verification action, not a code fix) |

---

## Remediation Principles Applied

| Principle | Application in this plan |
|---|---|
| Enforce server-side | R1.1 moves all AI calls behind the existing edge-function pattern; no client-side AI key remains reachable |
| Least privilege | R1.3 restricts the `private_messages` UPDATE policy to exactly the `is_read` column |
| Deny by default | R1.3's redesigned policy denies any column change other than the one explicitly intended |
| Validate at trust boundary | R1.1 keeps AI-provider validation server-side only |
| Minimize sensitive data | R1.1 removes health-context transmission to Google from the client entirely |
| Centralize auth controls | R1.1 consolidates all 4 AI features onto one server-side proxy pattern instead of 1-of-4 |
| Use trusted crypto/auth providers | R2.2 proposes `flutter_secure_storage` (Keychain/Keystore-backed) instead of a custom encryption scheme |
| Fail safely | R1.1's fallback removal means an edge-function outage degrades to "AI feature unavailable," not "fall back to an insecure direct call" |
| Retest exploit path | Every phase below ends with an explicit regression-test requirement |

---

## R1 — Pre-Launch Blockers (closes SEC-001, SEC-002, SEC-003, SEC-004, SEC-006)

### R1.1 — Eliminate all client-side direct-to-Gemini call paths (closes SEC-001, SEC-002, SEC-006)

- **Finding(s) closed:** SEC-001, SEC-002, SEC-006
- **Root cause:** `.env` (with `GEMINI_API_KEY`) is bundled as a Flutter asset and read client-side by `GeminiService`; 3 of 4 AI features (`AiAdvisorService`, `DreamInterpreterViewModel`, and the `_sendViaDirectModel` fallback in `ChatViewModel`) call it directly instead of proxying through a server-side boundary.
- **Exact components:**
  - `pubspec.yaml` — remove `.env` from `flutter: assets:`.
  - `lib/core/services/gemini_service.dart` — remove entirely, or repurpose as a thin client of new server-side proxy edge functions (mirroring `DrNiswahBackendService`).
  - `lib/features/ai_advisor/ai_advisor_service.dart` — route `askFiqh()` through a new edge function (e.g. `fiqh-advisor-chat`) analogous to `dr-niswah-chat`.
  - `lib/features/dream_interpreter/presentation/viewmodels/dream_interpreter_view_model.dart` — route `sendMessage()` through a new edge function (e.g. `dream-interpreter-chat`).
  - `lib/features/ai_assistant/presentation/viewmodels/chat_view_model.dart` — remove `_sendViaDirectModel`'s Gemini call entirely; either route the `general` thread type through a new lightweight edge function, or, if `drNiswah`'s backend is ever unavailable, fail the request with a clear "temporarily unavailable" error rather than falling back to a direct client call.
  - `lib/features/ai_assistant/domain/services/dr_niswah_persona.dart` — the client-side `buildSystemInstruction` (which fetches `pregnancy_profile` client-side) becomes dead code once the fallback path is removed; delete it, keeping the server-side copy in the edge function as the single source of truth.
  - New Supabase Edge Functions modeled directly on `supabase/functions/dr-niswah-chat/index.ts`'s existing pattern (JWT verification via `userClient.auth.getUser()`, `GEMINI_API_KEY` read only from `Deno.env`, never returned to the client).
  - `lib/core/config/app_environment.dart` — remove the now-fully-dead `OPENAI_API_KEY`/`NISWAH_AI_API_KEY`/`DREAM_INTERPRETER_API_KEY` validation and getters (SEC-002), or repoint them at whatever real config is actually needed server-side only.
- **Auth/session impact:** None — the existing bearer-JWT pattern from `dr-niswah-chat` is reused as-is.
- **Data impact:** No schema change required; `chat_messages`/`dream_entries` writes continue as today, just always via server-side functions.
- **Compatibility risk:** Medium — requires new edge function deployments and app-side wiring changes across 3 features; must be shipped together with a client update (old app versions calling Gemini directly would need to be considered end-of-life or force-updated, since simply revoking the key breaks them without a fallback UX).
- **Migration/config need:** Provision `GEMINI_API_KEY` as an edge-function environment secret for each new function (already the pattern for `dr-niswah-chat`); rotate the current `GEMINI_API_KEY` value after the client-bundled version is confirmed fully retired from all distributed builds (rotation before full rollout would break the old build's fallback UX, so sequence rotation *after* the fixed build is the primary distribution channel — coordinate with release management).
- **Rollback:** Revert edge function routing to the previous direct-call code is **not** an acceptable rollback (it reopens SEC-001); if a regression is found, roll back to the previous *app* release only after confirming the previous key has already been rotated, accepting temporary feature unavailability over reopening the exposure.
- **Regression test:** `SEC-SECRET-01` — build a release APK/IPA equivalent (or inspect the build output/asset manifest) and confirm no `.env`/API key material is present in the bundle. `SEC-AUTHN-0x`/`SEC-RATE-0x` — confirm each new edge function rejects missing/invalid JWTs and confirm no client code path references `GEMINI_API_KEY` (`grep -rn "GEMINI_API_KEY" lib/` should return zero results post-fix).
- **E2E journeys affected:** AI Advisor (fiqh Q&A), Dream Interpreter, Dr. Niswah chat (all thread types), general assistant chat — all four must be manually re-verified end-to-end post-fix.

### R1.2 — Fix Android release signing (closes SEC-003)

- **Finding(s) closed:** SEC-003
- **Root cause:** No dedicated release keystore was ever generated/wired into `android/app/build.gradle.kts`; the `TODO` was left in place.
- **Exact components:** `android/app/build.gradle.kts` (`buildTypes.release.signingConfig`), a new `signingConfigs.release` block reading from a securely-stored keystore (via `key.properties`/CI secrets, never committed), and — while in this file — enable `isMinifyEnabled`/`isShrinkResources` with ProGuard/R8 rules as a companion hardening step (observed missing during this audit; not independently scored as a separate finding but should be addressed alongside since it's the same file/same release-readiness gap).
- **Auth/session impact:** None.
- **Data impact:** None.
- **Compatibility risk:** Low for a pre-launch app (no existing production users to break an update chain for); would be higher-risk if any release build has already been distributed under the debug-signed configuration — verify with the release owner before treating this as a simple swap.
- **Migration/config need:** Generate and securely store a production release keystore; wire signing credentials via CI secrets or a git-ignored `key.properties`, never hardcoded.
- **Rollback:** Keep the previous (debug-signed) build path available in a non-production CI lane only, never for store submission.
- **Regression test:** Build a release AAB/APK and verify (`apksigner verify` / `jarsigner -verify`) it is signed with the new release key, not the debug key; confirm Play Console (or equivalent) accepts the artifact.
- **E2E journeys affected:** None functionally — build/release pipeline only.

### R1.3 — Column-scope the `private_messages` "mark as read" RLS policy (closes SEC-004)

- **Finding(s) closed:** SEC-004
- **Root cause:** RLS `UPDATE` policy governs row visibility, not column mutability; the "recipients can mark read" intent was never enforced at the column level.
- **Exact components:** New migration replacing the policy in `supabase/migrations/20260822210000_private_messaging.sql` (lines 86-92). Two standard approaches, either acceptable:
  1. A `BEFORE UPDATE` trigger on `private_messages` that raises an exception (or silently reverts) if any column other than `is_read` differs between `OLD` and `NEW` when the policy's `USING` condition applies to a non-sender.
  2. Split `is_read` into a separate table (`private_message_read_state(message_id, reader_id, read_at)`) with its own narrow insert/update policy, leaving `private_messages` itself immutable post-insert for all non-owning parties (no UPDATE policy for non-senders at all).
  Recommend option 2 for durability (works even if a future column is added and someone forgets to update a trigger), but option 1 is a smaller, faster fix if timeline-constrained.
- **Auth/session impact:** None.
- **Data impact:** If option 2 is chosen, requires migrating existing `is_read` values (if any production rows exist) into the new table; if the project has no production users yet, this is a clean schema change.
- **Compatibility risk:** Low-Medium — requires updating `PrivateMessagingRepository.markMessagesAsRead()`/`fetchMessages()`/`fetchUnreadCount()` in `lib/features/private_messaging/data/repositories/private_messaging_repository.dart` to match the new shape if option 2 is chosen; option 1 requires no app-side change at all.
- **Migration/config need:** New SQL migration file; if option 2, an app-side repository update in the same release.
- **Rollback:** Standard migration rollback (drop trigger / drop new table), acceptable since this is an additive-safety change with no destructive effect on existing `content`/`sender_id` data.
- **Regression test:** `SEC-IDOR-0x` — using two synthetic users A (sender) and B (recipient) in a shared conversation: B can still flip `is_read` to `true`; B's attempt to `PATCH` `content` or `sender_id` on that message via a direct PostgREST call is rejected; A (sender) cannot update `is_read` on their own sent message (existing behavior, should remain unchanged).
- **E2E journeys affected:** Private messaging — "mark as read" UX must be re-verified to still function.

---

## R2 — Post-Launch / Backlog (closes SEC-005, SEC-007, SEC-009; explicit-acceptance candidates)

### R2.1 — Add abuse/rate control to AI-backed edge functions (closes SEC-005)

- **Exact components:** All edge functions from R1.1 plus the existing `dr-niswah-chat`. Add a per-user request-frequency check (e.g. a `Postgres`-backed sliding-window counter, or Supabase's platform-level rate limiting if available for Edge Functions) before invoking `callGemini()`.
- **Regression test:** `SEC-RATE-0x` — scripted burst of N+1 requests from one synthetic user within the configured window; request N+1 is rejected/throttled with a clear error, not silently billed.

### R2.2 — Move sensitive local caches to secure storage (closes SEC-007)

- **Exact components:** `lib/features/cycle_tracking/data/datasources/local_cycle_tracking_data_source.dart`, `lib/features/pregnancy_tracking/data/datasources/local_pregnancy_tracking_data_source.dart` — replace `shared_preferences` with `flutter_secure_storage` (or platform-appropriate encrypted storage) for these two caches specifically; other, non-sensitive `shared_preferences` usage (UI flags, locale, theme) is out of scope for this change.
- **Compatibility risk:** Medium — requires a one-time migration path reading the old plaintext key and rewriting it into secure storage (or accepting a one-time cache loss for existing installs, given the server-side Postgres copy remains the source of truth for synced data).
- **Regression test:** Confirm cycle/pregnancy data round-trips correctly through the new storage; confirm the old `shared_preferences` keys no longer contain the migrated data post-upgrade.

### R2.3 — Replace raw PostgREST filter interpolation with structured filters (closes SEC-009)

- **Exact components:** `lib/features/private_messaging/data/repositories/private_messaging_repository.dart` (`fetchConversations`, `getOrCreateConversation`) — use the Supabase Dart client's structured `.or()`/filter-builder API (which handles value escaping) instead of manual string interpolation.
- **Regression test:** Existing private-messaging E2E flows (open conversation, start new conversation) continue to pass; add a unit test with a deliberately-malformed `otherUserId` (containing `,`/`(`/`)`) to confirm it is rejected/escaped rather than altering the query shape.

---

## R0 — Verification Actions (not code fixes — closes/downgrades SEC-010, SEC-011)

These are not remediation items in the traditional sense; they are the runtime verification steps needed to convert this audit's Declared/Implemented findings into Enforced/Tested ones, per the template's Golden Rule. Recommended before or immediately after R1 ships:

1. Run `supabase db diff` (or equivalent) against the linked production project to confirm every migration in `supabase/migrations/` is actually applied and no live-schema drift exists beyond what's captured in source.
2. Review the Supabase Auth dashboard configuration: rate limits, leaked-password protection, mandatory email confirmation, and the redirect-URL allow-list (confirm `niswah://login-callback` is present).
3. Confirm Realtime RLS enforcement is enabled for `private_messages`.
4. Confirm the live `SUPABASE_SERVICE_ROLE_KEY` is only ever configured as an Edge Function secret, never in any client-distributable config.
5. After R1.1 ships, confirm (via Google Cloud console) the previous client-bundled `GEMINI_API_KEY` value has been rotated/revoked.

---

## Remediation Phase Table

| # | Action | Findings closed | Components | Security impact | Regression risk | Rollback | Retest |
|---|---|---|---|---|---|---|---|
| R1.1 | Remove all client-side direct-Gemini calls; proxy via edge functions | SEC-001, SEC-002, SEC-006 | `pubspec.yaml`, `gemini_service.dart`, `ai_advisor_service.dart`, `dream_interpreter_view_model.dart`, `chat_view_model.dart`, `dr_niswah_persona.dart`, `app_environment.dart`, new edge functions | Removes the SEC0 finding entirely | Medium (3 features re-plumbed) | No safe rollback to old behavior (reopens SEC0) | `SEC-SECRET-01`, full AI-feature E2E |
| R1.2 | Proper release signing (+ enable minification while in the file) | SEC-003 | `android/app/build.gradle.kts` | Restores release/update integrity | Low | Keep debug path for non-prod CI only | Signature verification of built artifact |
| R1.3 | Column-scope `private_messages` UPDATE policy | SEC-004 | New migration (+ optional repository update) | Closes message-tampering IDOR-adjacent gap | Low-Medium | Standard migration rollback | `SEC-IDOR-0x` two-user test |
| R2.1 | Rate-limit AI edge functions | SEC-005 | All AI edge functions | Reduces abuse/cost-runaway risk | Low | Remove limiter | `SEC-RATE-0x` burst test |
| R2.2 | Secure local storage for health caches | SEC-007 | `local_cycle_tracking_data_source.dart`, `local_pregnancy_tracking_data_source.dart` | Reduces local data-at-rest exposure | Medium (migration path) | Revert to `shared_preferences` | Round-trip storage test |
| R2.3 | Structured PostgREST filters | SEC-009 | `private_messaging_repository.dart` | Removes fragile query-construction pattern | Low | Revert to interpolation | Malformed-input unit test |
| R0 | Live-config verification | SEC-010, SEC-011 | Supabase dashboard/project | Converts UNKNOWNs to confirmed evidence | N/A | N/A | N/A |

---

## Remediation Exit Gate

- [x] Root cause identified for every open finding.
- [x] Each fix enforces an authoritative (server-side/database-side) control, not a client-only or cosmetic change.
- [x] Related routes/components identified per fix.
- [x] Regression risk assessed per fix.
- [x] Rollback defined per fix.
- [x] Security retest defined per fix.
- [x] Related E2E journeys identified per fix.
- [x] No cosmetic/client-only fix proposed for a server-side security issue (R1.1 and R1.3 are both server/build-side; R2.2 is a genuine client-storage fix, appropriately scoped to a client-storage finding).

This plan is ready for implementation authorization. **No part of it has been implemented as part of this audit.**
