# Niswah — Period Tracking: 200 Acceptance Cases

Source: the original 200-case list in this conversation. Scenario and expected-behavior text preserved; PT identifiers added for traceability.

These are proposed requirements, not verified functionality. Initial status for every case: NOT ASSESSED. Medical and fiqh conclusions require appropriate specialist-reviewed specifications. Safe restrictions must be verified where approval is unavailable.

Agent handoff: copy this document into the repository as PERIOD_TRACKING_200_CASES.md. Assess every PT identifier against current code and tests. Maintain a coverage register recording preconditions, reproducible steps, stored result, UI result, downstream effects, priority, code locations, evidence, status, and external dependencies. Do not mark a case verified solely because general CI passes. Do not silently omit any case.

## 1. First use and historical information

| ID | Case | Expected behavior / UX |
|---|---|---|
| PT-001 | Knows her last period’s exact dates | Enter start and end with a clear calendar preview. |
| PT-002 | Knows the start but not the end | Save an unknown end; do not invent duration. |
| PT-003 | Remembers only an approximate date | Preserve uncertainty and explain its effect on estimates. |
| PT-004 | Has no previous records | Start tracking immediately without fabricating history. |
| PT-005 | Knows usual duration but not dates | Store it as a reported typical duration, separate from recorded episodes. |
| PT-006 | Does not know her usual cycle length | Offer «لست متأكدة» without blocking onboarding. |
| PT-007 | Reports irregular cycles | Avoid forcing her into a regular-cycle assumption. |
| PT-008 | Has several historical periods | Allow efficient entry with duplicate and overlap checks. |
| PT-009 | Imports another app’s records | Preview dates, sources, and conflicts before confirmation. |
| PT-010 | Skips optional questions | Keep core tracking available. |

## 2. Recording the start of bleeding

| ID | Case | Expected behavior / UX |
|---|---|---|
| PT-011 | Bleeding starts today | Offer a prominent, quick recording action. |
| PT-012 | Bleeding started yesterday | Allow retrospective entry without extra friction. |
| PT-013 | Bleeding started weeks ago | Accept historical observations and recalculate dependent views. |
| PT-014 | Tries to record an actual start in the future | Offer a prediction/planning distinction; reject a future observation. |
| PT-015 | Knows the exact start time | Save time and timezone when provided. |
| PT-016 | Knows the date only | Save date-level precision without assuming midnight. |
| PT-017 | Remembers “morning” or “evening” | Preserve approximate timing if supported. |
| PT-018 | Unsure whether it is spotting or period bleeding | Allow the observation without forcing classification. |
| PT-019 | Records bleeding while another episode is ongoing | Offer to update the existing episode or review a separate observation. |
| PT-020 | Taps the recording button repeatedly | Save one observation. |

## 3. Recording the end and observed purity

| ID | Case | Expected behavior / UX |
|---|---|---|
| PT-021 | Bleeding ends today | Record the observation and show the updated episode. |
| PT-022 | Bleeding ended earlier | Allow retrospective correction. |
| PT-023 | End date precedes start | Explain the conflict beside the fields. |
| PT-024 | Start and end occur on the same date | Support the observation; do not silently expand it. |
| PT-025 | She forgets to mark the end | Keep it ongoing/unknown; do not auto-complete as fact. |
| PT-026 | Predicted end passes | Ask gently if she wants to update; preserve uncertainty. |
| PT-027 | Marks the end accidentally | Provide immediate undo and later editing. |
| PT-028 | Unsure when bleeding ended | Preserve uncertain timing. |
| PT-029 | Records observed purity | Keep the observation distinct from an automated fiqh conclusion. |
| PT-030 | Records purity and bleeding at conflicting times | Ask her to review the timeline without deleting either silently. |

## 4. Flow, spotting, and daily observations

| ID | Case | Expected behavior / UX |
|---|---|---|
| PT-031 | Records light, medium, or heavy flow | Use understandable labels and an optional explanation. |
| PT-032 | Flow changes during the day | Support updates without creating duplicate episodes. |
| PT-033 | Enters several observations in one day | Preserve their sequence where timing is available. |
| PT-034 | Records spotting only | Do not automatically mark an entire period. |
| PT-035 | Spotting precedes heavier bleeding | Preserve both observations and their dates. |
| PT-036 | Spotting follows the apparent end | Retain the distinction for later interpretation. |
| PT-037 | Records brown or unusual-colored discharge | Store her observation without diagnosing or classifying it automatically. |
| PT-038 | Records no bleeding today | Distinguish this explicit observation from an unanswered day. |
| PT-039 | Changes yesterday’s flow entry | Update relevant summaries without changing unrelated dates. |
| PT-040 | Does not want detailed flow tracking | Let her use start/end tracking alone. |

## 5. Interrupted and ambiguous bleeding

| ID | Case | Expected behavior / UX |
|---|---|---|
| PT-041 | Bleeding stops for one day and resumes | Preserve the gap and both bleeding intervals. |
| PT-042 | Several stop/start gaps occur | Show a readable timeline rather than flattening the episode. |
| PT-043 | Spotting occurs during a gap | Preserve it as spotting. |
| PT-044 | New bleeding occurs shortly after an episode | Avoid confidently deciding whether it is a new period without sufficient support. |
| PT-045 | She chooses to split an episode | Preview the resulting records and downstream effects. |
| PT-046 | She chooses to merge episodes | Preserve observations and prevent double counting. |
| PT-047 | Unsure whether episodes belong together | Save the observations with classification pending. |
| PT-048 | Two records describe the same interval | Offer reconciliation. |
| PT-049 | App classification disagrees with her record | Let her review the reasoning and correct observations. |
| PT-050 | New information changes classification | Explain the change; preserve the original observation history. |

## 6. Editing, deleting, and correcting

| ID | Case | Expected behavior / UX |
|---|---|---|
| PT-051 | Corrects a start date | Preview the affected interval. |
| PT-052 | Corrects an end date | Recompute dependent summaries consistently. |
| PT-053 | Moves an episode across months | Update both calendar months. |
| PT-054 | Edit creates an overlap | Ask for reconciliation before committing incompatible records. |
| PT-055 | Deletes one daily observation | Do not delete the whole episode unintentionally. |
| PT-056 | Deletes a complete episode | Explain what is removed and what derived results may change. |
| PT-057 | Undoes a deletion | Restore a consistent record without duplication. |
| PT-058 | Edits a record containing symptoms | Preserve symptoms unless she explicitly removes them. |
| PT-059 | Corrects several historical episodes | Recalculate from the final valid state. |
| PT-060 | Opens an old edit form after another update | Detect the stale revision instead of overwriting newer data. |

## 7. Symptoms and wellbeing

| ID | Case | Expected behavior / UX |
|---|---|---|
| PT-061 | Records cramps without bleeding | Allow it without starting a period. |
| PT-062 | Records symptoms after bleeding ends | Keep them on their actual dates. |
| PT-063 | Records mood, energy, and sleep | Use the agreed visual language without implying a diagnosis. |
| PT-064 | Records several symptoms together | Support quick multi-selection and easy removal. |
| PT-065 | Changes symptom severity | Preserve the intended latest state or explicit timeline. |
| PT-066 | Adds a private note | Keep it optional and clearly private. |
| PT-067 | Wants to track only selected symptoms | Allow customization without overwhelming setup. |
| PT-068 | Skips the daily check-in | Record nothing; do not assume wellbeing or absence of symptoms. |
| PT-069 | Records a symptom repeatedly | Avoid duplicate counts from repeated taps. |
| PT-070 | Reviews symptom patterns | Separate observed associations from causal or diagnostic claims. |

## 8. Predictions and uncertainty

| ID | Case | Expected behavior / UX |
|---|---|---|
| PT-071 | Has only one recorded episode | Explain limited evidence rather than imply a personalized reliable prediction. |
| PT-072 | Has several consistent cycles | Show an estimate with an understandable uncertainty range. |
| PT-073 | Has variable cycle lengths | Reflect wider uncertainty. |
| PT-074 | Period begins earlier than estimated | Record the actual event and update future estimates. |
| PT-075 | Period begins later than estimated | Do not rewrite the earlier prediction as though it was correct. |
| PT-076 | Predicted date passes without bleeding | Keep “no record” distinct from “confirmed no bleeding.” |
| PT-077 | Unusual episode appears in history | Apply a defined, transparent handling policy. |
| PT-078 | Historical record is deleted | Recompute using remaining valid evidence. |
| PT-079 | Prediction cannot be supported | Show «لا تتوفر بيانات كافية للتوقع» instead of a fabricated date. |
| PT-080 | Prediction algorithm changes | Version results and evaluate changes without altering observations. |

## 9. Life stages and changing circumstances

| ID | Case | Expected behavior / UX |
|---|---|---|
| PT-081 | Recently started menstruating | Provide age-appropriate tracking with cautious estimates. |
| PT-082 | Reports pregnancy possibility | Offer the reviewed pathway without treating a late period as proof. |
| PT-083 | Reports confirmed pregnancy | Apply an explicit pregnancy-mode policy to predictions and reminders. |
| PT-084 | Records bleeding during pregnancy | Use the separately reviewed health-safety pathway. |
| PT-085 | Returns after childbirth | Support postpartum observations without assuming ordinary cycles. |
| PT-086 | Breastfeeds and has no periods | Avoid repeatedly labeling periods overdue. |
| PT-087 | Periods resume while breastfeeding | Restart estimates cautiously from actual records. |
| PT-088 | Reports pregnancy loss | Offer sensitive, reviewed tracking behavior without celebratory or routine prompts. |
| PT-089 | Reports perimenopause | Support irregular patterns without false regularity. |
| PT-090 | Changes or stops hormonal contraception | Preserve context and reassess whether existing predictions remain appropriate. |

## 10. Health-safety interactions

| ID | Case | Expected behavior / UX |
|---|---|---|
| PT-091 | Reports concerning bleeding | Trigger specialist-reviewed questions and escalation wording. |
| PT-092 | Reports severe pain | Use a reviewed response; do not dismiss it as normal menstruation. |
| PT-093 | Reports dizziness or fainting with bleeding | Follow the appropriate reviewed urgency pathway. |
| PT-094 | Reports prolonged bleeding | Present reviewed next steps without diagnosing. |
| PT-095 | Reports an unusual change from her pattern | Acknowledge the change and offer appropriate reviewed advice. |
| PT-096 | Gives incomplete safety information | Ask focused questions without delaying urgent advice where indicated. |
| PT-097 | Dismisses a safety message | Keep guidance accessible and avoid repetitive obstructive prompts. |
| PT-098 | Reports the same concern again | Reassess current information rather than assuming the old status still applies. |
| PT-099 | Safety guidance service is unavailable | Provide an approved fallback rather than an invented answer. |
| PT-100 | Asks whether tracking proves she is healthy | Clearly explain the limits of tracking and predictions. |

## 11. Fiqh-related interactions

| ID | Case | Expected behavior / UX |
|---|---|---|
| PT-101 | Knows her madhhab | Use applicable reviewed guidance and show its basis. |
| PT-102 | Does not know her madhhab | Keep tracking available without assigning one invisibly. |
| PT-103 | Changes her madhhab preference | Preserve observations; review affected interpretations. |
| PT-104 | Asks “Can I pray?” with insufficient information | Ask for necessary details and preserve uncertainty. |
| PT-105 | Asks about interrupted bleeding | Use reviewed case-specific handling rather than a universal shortcut. |
| PT-106 | App has evidence but no approved rule | Do not equate source availability with specialist approval. |
| PT-107 | Guidance changes after review | Identify affected interpretations without rewriting her observations. |
| PT-108 | She disagrees with a classification | Offer correction and review, with a clear distinction between observation and interpretation. |
| PT-109 | AI contradicts the deterministic result | Flag the inconsistency; do not silently change the record. |
| PT-110 | Guidance is unavailable | Continue tracking and show a clear unavailable state. |

## 12. Ramadan and qadha integration

| ID | Case | Expected behavior / UX |
|---|---|---|
| PT-111 | Actual episode overlaps Ramadan | Suggest affected dates for review. |
| PT-112 | Only predicted bleeding overlaps Ramadan | Add no qadha debt. |
| PT-113 | Start occurs near Maghrib | Preserve timing precision and request clarification if needed. |
| PT-114 | Purity occurs near Fajr | Use the separately reviewed boundary pathway. |
| PT-115 | Period edit affects confirmed qadha | Request reconciliation; never silently change debt. |
| PT-116 | Episode deletion affects a qadha suggestion | Withdraw or revise the suggestion with explanation. |
| PT-117 | Episode deletion affects confirmed debt | Preserve the confirmed ledger until reviewed. |
| PT-118 | Bleeding overlaps a recorded qadha completion | Flag a conflict without issuing an unsupported verdict. |
| PT-119 | Manual qadha balance already includes the dates | Link evidence without adding debt twice. |
| PT-120 | User disables Ramadan suggestions | Continue ordinary tracking without repeated requests. |

## 13. Travel and time handling

| ID | Case | Expected behavior / UX |
|---|---|---|
| PT-121 | Travels to another timezone | Preserve the original recorded local dates and context. |
| PT-122 | Crosses the international date line | Avoid duplicate or missing observations caused by repeated/skipped dates. |
| PT-123 | Records bleeding during a flight | Support uncertain local timing. |
| PT-124 | Phone timezone is manually incorrect | Detect or explain relevant inconsistencies where possible. |
| PT-125 | Device clock is advanced | Do not accept future observations solely because of the device clock. |
| PT-126 | Daylight-saving change occurs | Preserve event order and timestamps. |
| PT-127 | Starts entry before midnight and saves afterward | Keep the intended date explicit. |
| PT-128 | Location permission is denied | Basic tracking remains usable. |
| PT-129 | Changes Hijri/Gregorian display | Change presentation without changing stored event identity. |
| PT-130 | Views history after returning home | Do not shift old period dates to the current timezone. |

## 14. Calendar, Today, and Insights consistency

| ID | Case | Expected behavior / UX |
|---|---|---|
| PT-131 | Records a start from Today | Calendar and Insights update from the same record. |
| PT-132 | Edits through Calendar | Today and episode history reflect the edit. |
| PT-133 | Observed and predicted dates overlap | Use clearly distinguishable styles and labels. |
| PT-134 | Selected day has no record | Show “not recorded,” not “no bleeding.” |
| PT-135 | Episode spans a year boundary | Display one continuous episode across both years. |
| PT-136 | Multiple observations exist on one date | Open a readable daily timeline. |
| PT-137 | Derived calculation is pending | Label it as updating; do not display stale certainty. |
| PT-138 | Insights use incomplete episodes | State the limitation or exclude them according to a defined policy. |
| PT-139 | Opens a chart point | Show the contributing records and calculation meaning. |
| PT-140 | No meaningful trend exists | Show insufficient evidence rather than an empty or misleading chart. |

## 15. Offline use and synchronization

| ID | Case | Expected behavior / UX |
|---|---|---|
| PT-141 | Records an episode offline | Save securely and show pending synchronization. |
| PT-142 | Restarts before sync | Restore the pending record. |
| PT-143 | Server saves but response is lost | Retry without duplication. |
| PT-144 | Edits an unsynced observation | Synchronize the final intended state. |
| PT-145 | Deletes an unsynced episode | Prevent it from reappearing later. |
| PT-146 | Two devices add the same episode | Detect and reconcile duplicates. |
| PT-147 | Two devices edit different fields | Merge only when safely compatible under an explicit policy. |
| PT-148 | Two devices make incompatible date edits | Request reconciliation rather than silently choosing. |
| PT-149 | Old device reconnects | Respect newer edits and deletions. |
| PT-150 | Storage or sync fails | Do not claim success; retain input and provide recovery. |

## 16. Accounts, deletion, and privacy

| ID | Case | Expected behavior / UX |
|---|---|---|
| PT-151 | Switches accounts during save | Bind the operation to the initiating account. |
| PT-152 | Switches accounts during history load | Reject stale results and clear previous account data. |
| PT-153 | Switches A→B→A | Detect session transitions, including returning to the same account. |
| PT-154 | Signs out with pending writes | Follow an explicit secure queue policy and explain pending status. |
| PT-155 | Session expires during editing | Preserve an appropriate draft and request authentication. |
| PT-156 | Deletes account while a write is in flight | Prevent delayed operations from restoring deleted data. |
| PT-157 | Installs on a new phone | Restore only authorized synced records. |
| PT-158 | Uses shared device | Offer discreet display and notification options. |
| PT-159 | Exports history | Explain scope and sensitive contents before sharing. |
| PT-160 | Diagnostics are collected | Avoid unnecessary health observations and private notes in telemetry. |

## 17. Notifications and reminders

| ID | Case | Expected behavior / UX |
|---|---|---|
| PT-161 | Declines notification permission | Tracking remains fully usable. |
| PT-162 | Enables period prediction reminders | Label them as estimates. |
| PT-163 | Records a period before its reminder fires | Cancel obsolete reminders where possible. |
| PT-164 | Deletes the record that affected reminders | Recalculate scheduled reminders consistently. |
| PT-165 | Forgets to end an episode | Offer an optional neutral check-in. |
| PT-166 | Travels after scheduling | Apply a defined timezone policy. |
| PT-167 | Opens an old notification | Display current state, not outdated assumptions. |
| PT-168 | Receives reminders from multiple categories | Deduplicate or group them without overwhelming her. |
| PT-169 | Pregnancy/postpartum mode changes | Remove inappropriate routine period prompts. |
| PT-170 | Notification appears on lock screen | Use discreet wording by default. |

## 18. Accessibility and interaction quality

| ID | Case | Expected behavior / UX |
|---|---|---|
| PT-171 | Uses Arabic RTL | Correct reading order, calendar navigation, and controls. |
| PT-172 | Switches to English mid-entry | Preserve input and selected dates. |
| PT-173 | Uses large text | Avoid clipped dates, totals, and action buttons. |
| PT-174 | Uses a screen reader | Announce selected dates, observed/predicted status, and save outcomes. |
| PT-175 | Has difficulty distinguishing colors | Add labels, patterns, or icons with accessible descriptions. |
| PT-176 | Has reduced motor precision | Use generous touch targets and forgiving interactions. |
| PT-177 | Enables reduced motion | Keep all feedback understandable without animation. |
| PT-178 | Presses Back during editing | Preserve draft or clearly confirm discard. |
| PT-179 | Opens a long episode history | Keep navigation responsive and support filtering. |
| PT-180 | Makes an input error | Explain how to fix it without clearing the form. |

## 19. AI interactions

| ID | Case | Expected behavior / UX |
|---|---|---|
| PT-181 | Says «نزل علي شيء بني» | Ask relevant clarifying questions; avoid unsupported classification. |
| PT-182 | Says «وقف يومين ورجع» | Clarify the timeline and distinguish observation from interpretation. |
| PT-183 | Uses Saudi dialect, typos, or voice transcription | Confirm the interpreted dates and meaning before changing records. |
| PT-184 | Uses “yesterday” in a conversation spanning midnight | Resolve the intended date explicitly when ambiguous. |
| PT-185 | Refers to “it” or “the same thing” | Use available context cautiously and ask when unclear. |
| PT-186 | AI cannot access her latest records | Disclose the limitation; do not pretend to have reviewed them. |
| PT-187 | AI proposes a record change | Show a structured preview requiring explicit confirmation. |
| PT-188 | Sends unrelated or misleading instructions | Preserve privacy and prevent unauthorized record access or mutation. |
| PT-189 | AI service is unavailable | Keep tracking and reviewed static guidance available. |
| PT-190 | Switches account during an AI response | Prevent previous-account context from appearing in the new session. |

## 20. Migration, monitoring, and release resilience

| ID | Case | Expected behavior / UX |
|---|---|---|
| PT-191 | Older records lack timezone information | Preserve known precision and mark missing context. |
| PT-192 | Legacy records contain overlaps | Reconcile without silently losing data. |
| PT-193 | Old app connects to newer backend | Enforce compatibility and fail safely. |
| PT-194 | App updates during pending synchronization | Preserve queue integrity and record identity. |
| PT-195 | Prediction update performs poorly | Roll back the prediction version without altering observations. |
| PT-196 | Fiqh automation needs disabling | Disable interpretation independently of core tracking. |
| PT-197 | Data discrepancy is detected | Identify affected records and provide a recovery path. |
| PT-198 | Health guidance needs urgent revision | Version and replace guidance with a controlled rollout. |
| PT-199 | User reports a wrong calendar or balance | Provide contextual support diagnostics without unnecessary sensitive data. |
| PT-200 | Acceptance tests pass but devices behave differently | Treat signed iPhone/Android verification as a separate release requirement. |

## Core invariant

Her observations stay intact and traceable. Predictions, guidance, reminders, and qadha suggestions may change as evidence improves; they must never silently rewrite what she actually recorded.

