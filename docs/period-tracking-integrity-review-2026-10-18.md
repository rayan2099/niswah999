# Period-tracking integrity review — 2026-10-18

Status: confirmed calculation defects fixed and core regressions verified. This is a scoped
engineering review, not a zero-defect, clinical, performance or release certification.

Related: [Cycle Tracking](../project-hub/generated/feature-cycle_tracking.md),
[history safeguards](prediction-history-review.md),
[prediction research](prediction-accuracy-program.md),
[release criteria](../DEFINITION_OF_DONE_BEFORE_LAUNCH.md).

## Confirmed findings and implemented fixes

| Finding | Before | After |
|---|---|---|
| Completed duration lost during timing merge | A projected start without a projected end hid the canonical episode's known duration; a 5-day and a 9-day period could average to 9 instead of 7 | Durations stay attached to their episode; a canonical measured duration fills an absent log pair, once per episode |
| Compatibility copy overrode canonical timing | A partial or conflicting projection could move the recorded start by a day or replace its known duration | Supplied canonical start/end timing takes precedence; the copy only supplements missing durations |
| Date boundary differed by input type | A canonical start or end on the as-of civil date could be dropped merely because its timestamp was after midnight | Canonical timing uses civil-date boundaries consistently with flat-log statistics; later dates remain excluded |
| Ring offsets used elapsed hours | A 23-hour day could shift the estimated fertile segment by a day | Ring offsets use the shared calendar-day helper |
| Rolling reminders duplicated a date at autumn clock change | Adding 24 hours repeatedly could produce two plans with the same day/id and omit the final day | Scheduling and cancellation enumerate distinct calendar dates with matching ids |
| Date controls and missed-check-in ranges used 24-hour shifts | Yesterday, custom date presets, range boundaries and the next missing day could drift at a clock change | Those period-tracking controls now use the same calendar-day helper |

Start deduplication retains the existing within-one-day episode matching. Supplied canonical
start dates and known durations now take precedence over the compatibility projection.
A paired log can still supplement a duration unknown in canonical timing. This does not resolve
contradictory source histories or establish that
nearby starts are medically one episode. No missing end, observation or period is invented.
The canonical store remains authoritative; this fix changes derived statistics, not stored records.

Calendar arithmetic applies to dates. Exact elapsed-duration comparisons in the fiqh evaluator
were not converted to day counts; those have a different meaning and still require review.
The forecast default and the religious rule matrix were not changed by this work.

## Verification

- Six initial canonical-statistics regressions failed before the first fix and passed afterward.
  Three canonical-authority scenarios then failed before the precedence correction and passed afterward.
- The New York spring ring regression and autumn rolling-reminder regression also failed
  before their respective fixes. Spring/fall companion checks cover both transitions.
- Ten canonical-statistics cases plus two ring and two reminder cases were added.
- **220 pure Dart tests passed in each of Asia/Riyadh and America/New_York** across fifteen
  selected test files. Scratch copies change only Flutter test imports to `package:test`
  and resolve script imports; app logic and assertions are unchanged.
- Re-exporting the original minimized development histories with the updated real controller
  produced a JSON-equivalent fold artifact: all **9,263** issued baseline/median/trimmed
  predictions, targets, features and withholding decisions remain identical. The previous
  development accuracy result is unchanged; these fixes do not establish higher accuracy.
- Changed Dart files were parsed by the formatter. Git whitespace and project-map checks pass.

The UI date-helper substitutions are source-reviewed; Flutter analyzer/widget/integration,
notification-plugin delivery, signed builds, device performance and end-to-end database
writes were not executed in this environment. Earlier core successes do not replace them.
No production backend, database migration or health record was modified.

## Required release-build acceptance checks

Use synthetic accounts and record the exact build, backend environment, device/OS and timezone.
These are pending checks, not claimed passes.

| Journey | Required result |
|---|---|
| Start, daily check-in, end, reopen | One canonical episode; truthful start/end; matching dates and statistics across Today, tracking, calendar and reports |
| Correct and backfill | Only effective corrections affect displayed facts; original audit history remains available; no duplicate episode or inflated duration |
| Onboarding timing with uncertain flow | Known start/end dates contribute once to timing; unknown flow is not invented |
| Offline save, process termination, reconnect and retry | Locally saved versus server-confirmed state is explicit; replay does not duplicate the operation; no silent loss |
| Rapid taps and overlapping refreshes | One intended operation; older loads do not overwrite newer facts |
| Sign out, switch account and delete | No prior-account health data, prediction review or reminder leaks into the next account |
| Spring/autumn clock change and travel | Yesterday and date ranges remain correct; one daily reminder per eligible date; ending or disabling cancels the entire planned window |
| Midnight rollover and stale foreground | Day counts and prediction state refresh to the new date without inventing a new period |
| Missing, degraded or uncertain history | No confident prediction from incomplete evidence; clear retry/review path |
| Long and irregular cycles | No fabricated repeat periods or forced 28-day cycle; original dates remain intact; forecasting safeguards remain visible |
| Arabic/English and large text | Recording, corrections, uncertainty and sync state stay understandable and usable |

Measure loading, saving, scrolling and notification refresh on real devices with representative
synthetic history sizes before claiming performance improvements. No latency or resource target
was invented or measured in this pass. Independent prediction validation and clinical review
remain separate from engineering correctness; scholarly approval remains separate again.

Publication: [draft PR #26](https://github.com/rayan2099/niswah999/pull/26) runs the full
repository CI. Keep it draft and unmerged pending required checks and owner review.

Initial remote run [39111173878](https://github.com/rayan2099/niswah999/actions/runs/39111173878)
passed schema rebuild, local bootstrap, secret-redaction and project-map checks. Its analyzer
reported zero errors but 35 notices against a 27-notice ceiling, preventing full tests/builds
from running. The new missing-block notices were corrected without changing the threshold;
the subsequent run, rather than that initial run, must establish full-suite success.

### Full-suite follow-up

Run [39111427547](https://github.com/rayan2099/niswah999/actions/runs/39111427547)
passed the analyzer (24 notices, zero errors, below the unchanged ceiling of 27), database
rebuild, local bootstrap and navigation. The full Flutter test step executed and reported
1,290 passes, 32 failures and two skips; builds were consequently skipped.

Triage identified two runtime coordination issues: saving a history review triggered both
a broadcast reload and a directly awaited reload, allowing the save to return before the
winning refresh completed; and local daily-reminder cancellation ran after an unrelated
forecast history read. The former now performs one awaited save refresh; the latter now
cancels local check-in reminders before starting forecast reads. A new blocked-request
regression requires cancellation to complete while the forecast request is still unresolved.

The existing active-check-in suite now explicitly disables the separate cycle-forecast
preference while asserting zero forecast-history reads, then enables it in the blocked-read
regression. Other tests now require honest failed-load states, unknown fiqh state for empty
history, current estimated-date wording, and a genuinely future calendar estimate rather
than an overdue one. No withholding, empty-history or CI acceptance gate was relaxed.
These full-suite follow-up changes require the next remote run to verify them.
