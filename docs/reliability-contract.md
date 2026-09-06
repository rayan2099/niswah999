# Niswah Reliability Contract

**Status:** Reflects actual implementation as of 2026-09-06 (Reliability Evidence Closure wave). This document describes what the code currently does, not an aspiration — if a section here stops matching the code, the code is the source of truth and this document is stale and must be corrected, not the other way around.

**Origin:** `RR-001`/`RR-004` (Reliability & Resilience specialist audit, `production-readiness-results/reliability/RR_findings.md`). `RR-004`'s original defect was that offline/degraded-network behavior was "inconsistent by accident, not by design" — different features behaved differently because no one had made an explicit choice, not because each choice was deliberate. This document is that choice, made explicit, and verified against the code that implements it.

**Ground rule:** automatic background retry is *not* a universal requirement. The correct question for any write path is not "does this retry automatically?" but: *is failure detected, surfaced truthfully, recoverable in a way appropriate to what the data is, observable to the operator, and protected against creating duplicate/corrupt records?* Two models below answer that question differently, and both are correct for the paths they're applied to.

---

## Model 1 — `LOCAL_AUTHORITATIVE_WITH_SYNC`

**When this applies:** personal, high-frequency, journal-style data where the user's own device is the thing that must never lose their entry, and a remote copy is a backup/sync convenience, not the primary record at the moment of writing.

**Contract:**
- The local, on-device save happens first and always succeeds (or the write genuinely failed and that's surfaced as a real error, not a sync concern).
- The UI's "saved" state reflects the *local* save, immediately — the user is never kept waiting on the network to see their entry.
- A remote sync attempt follows. A retryable failure (network blip, backend 5xx) leaves the record in a `pending` state — never hidden, never silently dropped. A non-retryable failure (validation, RLS rejection) is marked `failed` and is not retried again.
- Every failure — retryable or not — is reported via `AppErrorReporter`.
- A bounded, one-pass automatic retry sweep runs at two triggers: app start and app resume. It is not a timer and does not loop — it runs once per trigger and stops, whether it found pending work or not.
- The write to the remote table is an `upsert` keyed on a stable id, so running the retry sweep any number of times, or having two triggers fire close together, can never create a duplicate remote row. A record that reaches `synced` is never replayed again.

**User-facing state:** "Saved on this device. It will back up to your account automatically the next time you're online" (pending) vs. "Saved on this device, but could not be backed up to your account" (failed) — never a bare "saved" that hides a sync problem, and never an error that implies the local save itself failed when it didn't.

**Niswah example:** cycle/haid logging (`CycleTrackingRepositoryImpl`, `CycleLogFormData`, `NiswahHomeShell`'s `retryPendingSync()` in `main.dart`). This is currently the only active feature using this model — every other write in the app is either remote-authoritative, dual-authority, or purely local with no sync concept at all (see Models 2–4).

---

## Model 2 — `REMOTE_AUTHORITATIVE`

**When this applies:** everything where the backend's copy is the only copy that matters — account/profile data, community content, private messages, wellbeing check-ins. There is no meaningful "saved locally, syncing later" state for these; the write either reaches the server or it didn't happen.

**Contract:**
- The user's action attempts a remote write directly. Nothing is shown as "saved" until the backend confirms it.
- A failure is surfaced honestly — an error message, never a false success. Wherever the UI structure allows it, the user's input is preserved (a composer sheet stays open with the typed text still in the field; a form doesn't clear on failure) so retrying doesn't mean retyping.
- Recovery is user-controlled: the user decides whether and when to retry by repeating the action. There is no automatic background replay of a stale request.
- Every create-type write (a new post, comment, message) is protected against duplication on retry: the client generates a stable id once, before the first attempt, and reuses that same id on every retry of the same logical action; the write is an `upsert` on that id, not a blind `insert`. A retry after a client-side timeout — where the caller can't tell whether the first attempt actually reached the server — either no-ops (it did) or genuinely creates the row (it didn't); it never creates two rows. The id resets only after a confirmed success, so a later, genuinely new post/comment/message never collides with a prior one.
- Every failure is reported via `AppErrorReporter` for operator-side visibility, in addition to the user-facing error message.

**User-facing state:** an honest, specific error message on failure; a real success confirmation only after the backend has actually accepted the write.

**Niswah examples:** pregnancy profile (`PregnancyProfileRepository`), profile/account edits (`ProfileViewModel.updateProfile`), community posts and comments (`CommunityFeedViewModel`/`PostDetailViewModel`, `CommunityRepositoryImpl`), private messages (`ChatDetailViewModel`/`PrivateMessagingRepository`), wellbeing check-ins (`WellbeingRepository.upsertToday`), account deletion (see the note on destructive actions below).

**Destructive-action addendum (account deletion):** the same model, applied at its strictest. The remote action (the `delete_my_account` RPC) must succeed before anything else runs — a failure here touches no local state and the app must never claim the account was deleted. Once remote deletion is confirmed, local cleanup is best-effort: a failure is reported, not thrown, and must never block sign-out or be misreported as the deletion itself having failed. A local cleanup failure is retried automatically at the next app start (a `LOCAL_AUTHORITATIVE_WITH_SYNC`-style recovery applied specifically to this one, already-committed side effect) until it succeeds, without ever re-attempting the remote deletion itself. See `lib/features/auth/domain/account_deletion_orchestrator.dart`.

---

## Model 3 — `DUAL / SPLIT AUTHORITY`

**When this applies:** AI chat. There are two genuinely separate concerns with separate failure semantics, and conflating them was the actual historical bug this model exists to prevent.

**Contract, defined per concern:**
- **Response delivery** is authoritative and immediate: the AI-generated reply is shown to the user the moment it's received, regardless of whether the separate, best-effort attempt to persist it (and the user's own message) to durable chat history succeeds. A history-persistence failure must never hide, delay, or roll back an already-delivered reply.
- **Durable persistence** (`chat_messages`) is best-effort, protected the same way Model 2's create-writes are: a stable, caller-generated id reused across retries of the same persist attempt, `upsert` instead of `insert`, and every failure reported via `AppErrorReporter`. A silently-swallowed persistence failure here means a message vanishes from history forever with zero trace — this was a real, previously-live defect (`RR-007`), not a hypothetical one.
- **Safety-relevant signals** (the Dr. Niswah red-flag banner) are independent of both of the above — they run and display based on local detection, not gated behind the reliability of the backend call at all.

**User-facing state:** the reply is always visible immediately; persistence failures are never surfaced to the user directly (there is nothing actionable for them to do about a background history-save failing) but are always observable to the operator.

**Niswah examples:** Dr. Niswah / Fiqh Advisor / general assistant / dream interpreter chat (`ChatViewModel`, `ChatRepositoryImpl`).

---

## Model 4 — `LOCAL_ONLY`

**When this applies:** data that never leaves the device at all — no sync concept, no remote copy, nothing to reconcile.

**Contract:**
- A write's success is verified by the underlying storage/plugin call actually completing without throwing.
- A failure is reported via `AppErrorReporter` — there is no "false success" risk in the network sense (no remote round-trip to lie about), but a silent local failure is still a real defect (a reminder that silently never gets scheduled, for instance).

**Niswah example:** notification scheduling and preferences (`NotificationService`, `NotificationRepositoryImpl`) — `RR-002`/`RR-003` cover this model's own historical defects and their fixes.

---

## Explicitly out of scope for this document

- **Dormant/unreachable code** (the retired pregnancy-tracking feature; `PrayerTrackingScreen`'s `savePrayer`, confirmed unreachable from any navigation route) is not mapped to a model — a write path nothing can trigger has no live reliability behavior to contract.
- **Read paths** are not covered — this document is about writes. Read-failure fallback behavior (e.g., an empty list instead of a crash) is covered by each feature's own established, already-audited error-classification pattern (`mapRepositoryError`), not restated here.
- **Edge Function-internal persistence** (e.g., `dr-niswah-chat`'s own two `chat_messages` inserts, server-side) is a separate reliability surface with its own, already-tracked finding (`AB-003`) — this document covers the Flutter client's own write paths only.

## Active write-path → model map

| Path | Model |
|---|---|
| Cycle/haid logging | `LOCAL_AUTHORITATIVE_WITH_SYNC` |
| Pregnancy profile | `REMOTE_AUTHORITATIVE` |
| Profile/account edits | `REMOTE_AUTHORITATIVE` |
| Community posts/comments | `REMOTE_AUTHORITATIVE` |
| Community likes | `REMOTE_AUTHORITATIVE` (natural-key idempotency, no client-generated id needed) |
| Private messages | `REMOTE_AUTHORITATIVE` |
| Wellbeing check-ins | `REMOTE_AUTHORITATIVE` |
| Account deletion | `REMOTE_AUTHORITATIVE` (destructive-action addendum) |
| Dr. Niswah / Fiqh Advisor / general assistant / dream interpreter chat | `DUAL / SPLIT AUTHORITY` |
| Notifications/preferences | `LOCAL_ONLY` |

## Verification

This document's claims are backed by, and must stay consistent with:
- `production-readiness-results/master/00_09_PHASE1_ROOT_CAUSE_REMEDIATION_PLAN.md` §29–30 (the reliability audits that established and then evidenced this contract).
- `test/community_repository_idempotency_test.dart`, `test/ai_chat_persistence_resilience_test.dart`, `test/data_export_resilience_test.dart`, `test/account_deletion_resilience_test.dart`, `test/secure_local_store_test.dart` (executable evidence for the idempotency/observability/recovery claims above).
