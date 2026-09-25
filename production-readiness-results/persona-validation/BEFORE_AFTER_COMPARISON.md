# Before/After Comparison — PR #4 vs. `main`

**PR #4 SHA at time of this comparison**: see `TEST_EXECUTION_REPORT.md`
for the exact final SHA (this document is not re-dated per commit).
**`main` SHA**: `e4cc02e28c8df7220ed21090e3634311e1a3a28d` (frozen —
confirmed via `gh repo view --json defaultBranchRef` in an earlier
wave; unrelated to this session's own work).

## Structural comparison (verified via `git diff`/`git show`, not
screenshots)

`main` has **none** of the menstrual-tracking rebuild this PR
introduces:

```
$ git show e4cc02e28c8df7220ed21090e3634311e1a3a28d:lib/features/cycle_tracking/presentation/screens/canonical_calendar_screen.dart
fatal: path '...' does not exist in 'e4cc02e...'

$ git show e4cc02e28c8df7220ed21090e3634311e1a3a28d:lib/features/cycle_tracking/presentation/widgets/start_bleeding_sheet.dart
fatal: path '...' does not exist in 'e4cc02e...'
```

34 files changed, 9,569 insertions, 335 deletions between the true
merge base and this PR's `lib/` tree (`git diff --stat`). This is an
additive rebuild, not a modification of existing menstrual-tracking UI
— `main`'s own dashboard uses the flat `cycle_entries` table exclusively,
with no episode model, no daily check-in, no backfill, no correction/
revision history, no canonical calendar, and no "Daily check-in
reminder" row in notification settings.

## What a user would see differently, in plain terms

| Area | `main` (before) | PR #4 (after) |
|---|---|---|
| Recording a period | A single flat "log an entry" form | "Start Bleeding" → an open episode, with a daily check-in question each day it's open |
| Missed a day | No concept of a "missed day" | "Add a missing day" — the app tells you which day it's missing |
| Made a mistake | Editing overwrites silently, no history | "Correct this entry" — the original is kept, the correction is a new, linked revision |
| Multiple reports same day | Not supported | Supported — two independent same-day observations both persist |
| Viewing history | One calendar (`cycle_entries`-based) | Two: the original one is unchanged, plus a new canonical calendar with observed/backfilled/predicted/unverified provenance shown visually and to screen readers |
| Reminders | A single daily reminder | A dedicated "Daily check-in reminder," enable/disable and time independently of other reminder types, reconciled promptly against what's actually pending with the OS (not merely stopped from growing) |
| First-ever period | N/A (flat model has no "insufficient history" concept) | Now (after D-001, this wave) an honest "not enough history yet," never a fabricated data-failure message |

## Live, screenshot-based side-by-side

**Not produced this wave.** Building and running `main` on the same
simulator, with the same synthetic data and device dimensions, was not
completed given the time this wave's live persona work and defect
fixes already consumed. The structural absence documented above is
unambiguous and independently reproducible by anyone with repository
access (`git show main:<path>` for any of the new files) — it does not
require a live screenshot pair to establish that the feature simply
does not exist on `main`. A true paired-screenshot comparison remains a
real gap, listed in `TEST_EXECUTION_REPORT.md`'s own deferred-work
section.

## Acceptance-program fixes: what changes for a user relative to `main`

Verified against `origin/main` source (`git show origin/main:<path>`), so
"main has it" is a fact, not an assumption.

| Defect | On `main`? | Before (main) | After (PR #4 head) |
|---|---|---|---|
| D-007 messaging title | **Yes** — `conversations_screen.dart` renders `otherParticipant(...)` (the raw id) | Inbox and chat header show the other person's UUID | Their published name, else "Private conversation"; never an id |
| D-008 community failure text | **Yes** — the feed/detail view models store `error.toString()` (3 sites) | A failed post shows `ClientException ... uri=http://.../rest/v1/community_posts` | A friendly, localized "couldn't complete that — check your connection" |
| D-009 English pregnancy card | **Yes** — Arabic-only stage/size strings in `_PregnancyOverview` | English UI shows "مرحلة المضغة · بحجم حبة الليمون" | English stage/size text; Arabic unchanged |
| D-010 legend after language switch | **Yes** — the legend chips are `const` | After switching to Arabic the legend keeps "Haid / Expected Haid / Tahara" until restart | Follows the switch immediately |
| D-004 legacy screens vs onboarding history | No — onboarding history capture does not exist on `main` | n/a | Calendar/Insights agree with Today for a period reported in onboarding |
| D-006 offline replay | No — the offline pending/replay path is a PR #4 feature | n/a | Replayed save refreshes Today/prayer card/legacy model with no manual step |
| D-005 deletion retention | **Yes** — `ai_rate_limit_counters` never had a foreign key | Account deletion leaves the user's rate-limit counter rows | Removed with the account (trigger + one-time cleanup) |

The live paired-screenshot comparison against a running `main` build is
still **not produced**; the table above is source-verified and the
regression tests fail on the old code and pass on the new (proved for
D-009 and D-010 by running the new tests against the reverted file).

## What is internal-only (no user-visible difference)

- The `cycle_entries` projection bridge itself — invisible to a user;
  only its correctness (this wave's D-002 fix) is user-visible, as "the
  Calendar tab/Insights eventually agreeing with a correction."
- `BuildInfo`/`DiagnosticsBanner` — a QA-only banner, compiled in only
  with `--dart-define=ENABLE_DIAGNOSTICS_SCREEN=true`; absent from any
  normal build a real user would ever install.
- `NotificationService.pendingActiveBleedingReminders()` and the OS
  pending-set reconciliation logic (earlier wave, this same PR) —
  invisible directly; its effect ("a disabled reminder actually stops,
  even offline") is user-visible but was not re-demonstrated with a
  fresh screenshot this specific wave (already covered by that earlier
  wave's own report).
