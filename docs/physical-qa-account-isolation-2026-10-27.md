# Physical-device QA and local account isolation — 2026-10-27

Status: implemented locally, not released. Public-launch recommendation: NO-GO.

Related map: [Cycle Tracking](../project-hub/generated/feature-cycle_tracking.md).

## Reproduced privacy defect

Based on current-main regression PR #45 (ee10bb185487c01ec4199605659bd68a3477c9cb; main ce4b82551dd5629f0c31b60c01328d2ce4bed7bf), two of seven synthetic tests failed locally and in CI 40548587989. Starting a pending-operation save or cycle-log upsert as A, then switching to B before the queued callback executes, wrote A's payload into B's encrypted storage bucket.

Capture the owner synchronously at each local operation entry, then pass it through reads, writes and migration. Pending saves, acknowledgments and failure updates also retain their starting owner. Legacy migration verifies and rolls back under the same captured owner. No server or production changes.

64 focused tests passed after the fix: concurrency (11), pending-operation store, secure storage and account-deletion resilience. The original two failures are green. Added tests cover pending clear/update, cycle deletion and legacy migration during account changes. This is automated local evidence, not a physical-device pass. Does not repair previously misplaced data or establish safety of upstream calls that begin only after an account switch, deletion overlapping active retries, remote replay authorization, or cross-device concurrency.

## Physical access

Finder directly identifies iPhone 11, iOS 15.6.1. Xcode 27.1 on macOS 27.0.1 sees unsupported CoreDevice pairing and cannot list its apps. Unlocking did not resolve that. Interactive iPhone Mirroring failed with an iCloud sync error; the phone also lacks its required iOS 18 baseline. QuickTime USB preview successfully shows the physical screen, but a Mac click on TestFlight Open did not forward a touch. User taps are required.

Observed TestFlight listing: Niswah 1.0.0 (4), Open available. Installed build 4's backend is UNKNOWN. The separately preserved local 1.0.0 (2) archive's staging provenance cannot establish build 4's environment. No app data was entered. No purchases, account deletion, production mutation, distribution upload or App Store submission.

Mac disk exhaustion blocks broader compilation: the first journey suite stopped copying its compiled output with errno 28. Do not count it as product failure or as a pass. Physical app launch, auth, account persistence, onboarding, Arabic/RTL, accessibility, bleeding/history/predictions, fiqh, notifications, privacy/export/deletion, payments and offline recovery remain pending.

## Current launch work and limitations

- PR #44 password recovery has successful CI 40486442243 but remains draft/unmerged and needs real email/deep-link device verification.
- PR #45 has two actual tracking failures; vault map staleness is separate; DB reproducibility failed at registry image pulls, not schema assertions.
- Sentinel 40545319143 is INCONCLUSIVE: RPC HTTP 401/42501. This does not prove an outage or missing function.
- PR #26 documents wider tracking hardening and unresolved durable/offline/cross-device gates; no merge performed.
- PR #40/#41 concern RPC grants/RLS/cleanup. Their descriptions' deployment claims require current independent verification; no migration applied here.
- Issue #17 retains store/legal/exact-artifact smoke-test gates.
- Existing launch definition and fiqh source registry still require qualified review evidence; older dashboard checkboxes cannot establish current clinical/scholarly approval.

Next: confirm build 4 provenance/backend; user opens the app while USB preview runs; verify only synthetic staging account; execute the physical journeys and record evidence. Review/merge and release the fix separately, then verify the actual processed TestFlight artifact. Free sufficient Mac storage before native build or broad test retry.

## Follow-up verification

After disk capacity recovered to about 8 GB, 165 additional synthetic journey tests passed: auth routing, RTL, onboarding validation/errors, accessibility semantics/text scale, local sync, prediction estimates, madhhab controller/history, iOS permission abstraction, notification account transition/settings races, data-export resilience and network error classification. These use mocked/local dependencies; no physical or live-backend pass is implied. Focused changed-file analysis now reports no issues.

Read-only connected Supabase inspection at 2026-10-27 20:54 Asia/Riyadh: production and staging are ACTIVE_HEALTHY. Production has ai_rate_limit_counters and check_and_increment_ai_rate_limit. Catalog privileges show anon EXECUTE=false and authenticated EXECUTE=true on that function, delete_my_account, retrieve_knowledge_v1 and get_active_kb_snapshot. Thus the CI sentinel's anonymous HTTP401 is inconclusive, not evidence that the function is missing. This inspection supersedes any inference from the older open PR40 deployment description. No RPC was invoked and no live row changed. Staging still has neither cron.job nor notification_private.dispatch_worker(), so the documented automatic dispatch setup remains incomplete.

Production security advisories still include leaked-password protection disabled and mutable can_access_user search_path; anon-executable is_admin/is_conversation_participant require contextual review, not blanket revocation (RLS may depend on them). RLS-enabled tables without policies are not automatically an exposure; some are intentionally RPC/server-only. No advisor-driven production changes were made.
