# Insights "سجل الدورة" (TestFlight Feedback 2, page 5)

Related: [[feature-insights]], `lib/features/insights/domain/period_history.dart`, `lib/features/insights/presentation/widgets/period_history_view.dart`.

## What page 5 showed

"دورة مسجّلة: 27/10/2026 – 30/10/2026, مكتملة" and, below it, "30/10/2026, يوم الدورة 1", with no stated relationship.

## Diagnosis (from code; the tester's own rows were not read)

The old card listed canonical periods (`bleeding_episodes`) and then raw `cycle_entries` rows, one after the other. A period's `end_date` is its first clean day: `end_bleeding_episode` writes a `flow = none` observation on `end_date`, and length = end − start. That observation is mirrored into `cycle_entries` (same id). Its `cycle_day` is computed only from other `cycle_entries` rows, which never saw this period's start (a reported-history or uncertain start is not projected), so it is 1. The calculation code ignores `cycle_day == 1` on a non-bleeding row, so predictions and fiqh are unaffected.

So the 30 Oct row is the period's "stopped" record, not a duplicate and not a new period. The defect is presentation: a legacy, derived field (`cycle_day`) was shown, and the first clean day was shown as the period's end. No data change is proposed. A read-only query to confirm this for the tester account is in the project files (`testflight-feedback-2/confirm_page5_history_read_only.sql`); if it shows anything else, that is a separate data defect.

## New presentation

- One chronological list, newest first. A period shows first–last bleeding day ("27 – 29 أكتوبر 2026"), a status chip (مكتملة / مستمرة / تاريخ النهاية غير مسجّل), length and first clean day ("3 أيام نزول · طهرت في 30 أكتوبر").
- A daily record whose date falls inside a period (start to first clean day; to today while ongoing) is listed under that period, described from the record itself (flow, "توقف النزول (أول يوم طهر)", symptoms only) and its day counted from the period's own start. A record outside every period is shown on its own as "تسجيل منفصل". Every record appears exactly once; nothing is deleted, merged or reclassified.
- Tapping an entry opens its details with every linked record and "التعديل من التقويم" (opens the canonical calendar). "عرض الكل" is a real button to the full list.
- Dates follow the Hijri/Gregorian choice (`CalendarSystemController`) with English digits; RTL-aware icons; wraps at 320 pt with text at 200%; loading, error with retry, empty and "may be incomplete" states.
- `endUnknown` (PT-002, PR #60) is supported by `HistoryPeriodInput`; main's `CanonicalEpisodeTiming` has no such field yet, so pass it in `insights_screen.dart` once #60 merges.

## Evidence

Automated widget/unit tests (`test/period_history_test.dart`) and synthetic renders (`test/period_history_screenshot_test.dart`). Not checked on a physical device.
