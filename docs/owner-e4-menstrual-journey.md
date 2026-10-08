# Owner Live-Device Retest Script — Menstrual Data Integrity (PR #4)

**What this is**: a script for trying the new period-tracking rebuild
(PR #4, `feat/menstrual-data-integrity`) yourself, on a real phone,
whenever you're ready to review it. It is committed as a plain file in
the repository so the link can never go stale or expire — not a
webview/preview link tied to one session.

**Not needed yet**: this PR is still in draft and has not been merged,
so nothing below is due right now. It's here and ready for whenever you
decide to look at this work.

**How to use it**: every step below is something you do with your own
hands on the app's real screens — tap this, type that, wait this long,
check what you see. Nothing asks you to open a database, read a log
file, or compare technical output; anywhere this session needed to
verify something more technical (that a background sync retried
correctly, that a security rule blocked an unauthorized request, that a
migration replays cleanly), that check has already been done
automatically and is reported separately in
`docs/menstrual-data-integrity-contract.md`. Your job here is only to
confirm the app *behaves* the way a real user would expect it to.

Use a build compiled from this exact branch/PR, on a real device (not
only a simulator) wherever the step says so. Write down the **exact
step and screen** where anything doesn't match, rather than "it didn't
work" — that's what turns a real problem into something fixable.

---

## Before you start

- A phone with the app fresh-installed (or a new test account), and
  another minute to set up: notifications allowed at the OS level when
  the app asks, and the device's location/timezone set to wherever you
  actually are.
- Real elapsed time is required for several steps (multi-day reminders,
  timezone travel simulation) — these are called out explicitly. You
  can space this script out over more than one sitting.
- A second device or a way to change your phone's timezone/date
  (Settings → General → Date & Time) is needed for two steps.

---

## 1. Fresh onboarding

1. Install fresh (or sign up as a new account) and go through
   onboarding.
2. When asked about your Madhhab (school of Fiqh), choose **"I don't
   know"** rather than picking one.

**Expected**: onboarding completes without forcing a Madhhab choice;
the app offers to help you figure it out (a short question or two)
without ever silently assuming a specific school for you.
**Failure signal**: onboarding is blocked without an answer, or a
specific Madhhab appears selected that you never chose.

## 2. First factual bleeding record

1. From the dashboard, tap **"Start bleeding"**.
2. Answer honestly: when it started, and how it is right now.

**Expected**: the app records this as a plain fact ("bleeding
started"), never as a religious ruling ("Haid started") — the wording
should describe what happened, not tell you what it means religiously.
**Failure signal**: the app states a Fiqh ruling (Haid/Tahara/Istihadah)
immediately, before you've even confirmed your Madhhab.

## 3. Daily check-in — all three answers

Over the next three real days (or as close together as you can manage,
opening the app once per day), answer the daily "are you still
bleeding today?" prompt three different ways: **Yes** one day, **No**
(ending the episode) another, and — start a new episode first —
**I'm not sure** on a third occasion.

**Expected**: "Yes" keeps tracking going and asks again tomorrow. "No"
ends the episode cleanly (Quick Actions changes to "Start bleeding"
again). "I'm not sure" keeps the episode open without recording a
guessed flow level for that day — it should never look like a blank
error, and it should never silently record a specific flow level you
didn't actually report.
**Failure signal**: any of the three answers crashes, silently does
nothing, or "I'm not sure" ends up shown as a real recorded flow.

## 4. Missed check-in banner

Start a new episode, then skip checking in for 2 full real days.

**Expected**: on day 3, the dashboard shows a banner naming which
specific day(s) you missed — not a vague "you missed something."
**Failure signal**: no banner appears, or it names the wrong day(s).

## 5. Backfill a missed day

From the missed-check-in banner (or the calendar — see step 7), add an
entry for a day you missed.

**Expected**: you can pick that specific past day and record what
happened; it then shows up correctly wherever the app displays your
history.
**Failure signal**: you can't pick the day you meant, or the entry
doesn't appear afterward.

## 6. Correct an existing entry

Pick any day you've already recorded and change what you reported for
it (e.g. change the flow level).

**Expected**: the day now shows your corrected answer. This is the one
step where a technical check already confirms something for you
(your *original* answer is kept, not erased, in case anything needs
to be reviewed later) — you don't need to verify that part yourself.
**Failure signal**: the correction doesn't stick, or the app behaves
oddly (crashes, shows two conflicting values at once) after you save it.

## 7. Calendar

1. From the dashboard, tap the calendar icon (top of the screen).
2. Flip forward and back a few months, then back to the current month.
3. Tap a day you've recorded something for. Then tap a day you
   haven't.
4. From a day you've recorded, tap **"Correct this entry"**. From an
   empty day inside an active/past period, tap **"Add missing entry"**.

**Expected**: month navigation is smooth and lands back on today's
month correctly; tapping a recorded day shows what you reported for
it (and, if you corrected something in step 6, both the corrected
value and the fact that it *was* corrected are visible); tapping an
empty day either lets you add an entry (if it's within a period) or
tells you honestly that day isn't part of any recorded period (if it
isn't) — never a broken or fabricated action either way; after
correcting or adding from the calendar, closing back out to the
calendar reflects the change immediately, without needing to reopen
the app.
**Failure signal**: the calendar doesn't reflect a save without a full
app restart; a date you tap does nothing; navigation gets stuck or
shows the wrong month.

## 8. Sync interruption / recovery

1. Turn on airplane mode.
2. Record a check-in, a backfill, or a correction while offline.
3. Leave airplane mode **on** and reopen the app a few times over the
   next several minutes.
4. Turn airplane mode back off, then look at the dashboard.

**Expected**: while offline, the dashboard shows a "sync needs
attention" banner with a real **"Retry now"** button — never a claim
that something is lost, and never silence about the problem either.
Once back online, tapping "Retry now" (or simply reopening the app)
clears the banner and confirms the entry synced.
**Failure signal**: the banner never appears, the retry button does
nothing, or your entry appears to have vanished at any point.

## 9. Notification permission (contextual, not cold-start)

Uninstall and fresh-install the app, then start a new bleeding episode
for the first time.

**Expected**: the app's *own* "remind you daily?" question appears
first, in-app; the real OS permission popup only appears after you tap
"Enable daily reminder" — not immediately on first launch, before
you've even had a reason to want reminders.
**Failure signal**: the OS permission prompt appears at app launch,
before you've done anything that would need it.

## 10. Notification delivery — five real days, uninterrupted

This step is about delivery only — do not tap any notification during
this run (that would reopen the app and change what this step is
actually testing). Tapping is its own separate step 11, done
afterward, on different notifications.

1. With reminders enabled and a period being tracked, **force-quit the
   app** (not just background it) and do not reopen it, and do not tap
   any notification, for **at least 5 real days**.
2. Each day, just glance at whether a reminder notification appeared at
   your chosen time — do not open it, do not tap it, do not open the
   app.
3. After the 5 days, reopen the app normally.

**Expected**: a reminder appears every one of those 5 days, without
ever reopening the app or tapping anything in between.
**Failure signal**: reminders stop after day 1 or 2, or skip a day.

## 11. Notification tap — three app states

A separate, later run from step 10 — using fresh notifications, not
the ones from that 5-day stretch (those may already be several days
old by the time you get here).

With a reminder currently arriving, tap one while the app is
**closed/terminated**. On another day (or a second test run), tap one
while the app is **backgrounded**. On a third, tap one while the app is
**already open and on-screen**.

**Expected**: tapping — in any of the three states — opens the correct
daily check-in, as long as you tap it the same day it arrived.
**Failure signal**: tapping in any of the three states fails to open
the check-in, or opens the wrong day.

## 12. Timezone change mid-window

With a reminder currently scheduled, travel (or simulate travel by
changing your phone's timezone in Settings) to a different timezone —
ideally one with a different UTC offset by a few hours, or across a
daylight-saving change if one is currently active anywhere.

**Expected**: reopen the app once after the change. The still-upcoming
days in your reminder window should reschedule to match your new local
time (Settings should still show the same clock-time preference, e.g.
"6:00 PM," now interpreted in the new zone).
**Failure signal**: a reminder fires at your old zone's clock time
instead of the new one, well after you've reopened the app at least
once since the change.

## 13. Process-kill recovery

1. Start a check-in, backfill, or correction.
2. The instant you tap "Save," force-kill the app before you could
   possibly see a result on screen.
3. Reopen the app.

**Expected**: the entry is neither missing nor duplicated — exactly
one save went through, and the app reflects it correctly once reopened
(it may briefly show "syncing" first).
**Failure signal**: the entry is missing, or it appears twice.

## 14. UNKNOWN Madhhab — Fiqh state genuinely unavailable

With your Madhhab still set to "I don't know" (from step 1, or reset it
in Settings), look at the dashboard's prayer-status area during an
active or recent period.

**Expected**: the app tells you plainly it can't give a Fiqh ruling
until you choose a Madhhab (or complete the "I don't know" assistance
flow) — it never guesses a ruling on your behalf, and it never silently
picks a specific school for you.
**Failure signal**: a specific ruling (Haid/Tahara/Istihadah) appears
anyway, with no Madhhab ever selected.

## 15. Account switch

1. Sign out of the account you've been testing with.
2. Sign into a **different** account (or create a new one) on the same
   device.
3. Check the dashboard, calendar, and notification settings.

**Expected**: nothing from the first account is visible — no leftover
period data, no leftover reminders scheduled for the first account's
episodes.
**Failure signal**: any data, reminder, or notification meant for the
first account shows up under the second.

---

## Reporting back

For each numbered step above, a simple **PASS** or **FAIL** (with the
exact screen/moment, for any FAIL) is all that's needed. You don't need
to explain *why* something failed — that's the next step for whoever
picks this up, once you've reported what you actually saw.
