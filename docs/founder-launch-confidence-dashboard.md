# Niswah Launch Confidence Dashboard

**As of**: 2026-09-14 (updated same day, Post-Reconciliation Governance Correction pass — incorporates your fresh-install iOS retest results). This is written so you can understand where things stand without reading code. It's the result of a full pass checking whether everything that was ever agreed on has actually been built — not just re-checking what was already flagged.

**🟢 GREEN** = proven working, matches production. **🟡 YELLOW** = built, but not fully proven yet, or needs your decision. **🔴 RED** = missing, broken, or blocking launch. **⚪ GRAY** = deliberately postponed, with a reason on record.

**Update, same day**: you retested on a freshly reinstalled iOS build and reported all 9 checklist items PASS. The two sign-in bugs below (and the Arabic-locale bug) are now confirmed fixed on a real device and have moved from RED to GREEN.

**Update, later the same day (Fiqh Remediation Wave 1)** — both Madhhab blockers below are now actually fixed in the code and the database, not just planned: the "I don't know" option is real and working, and your madhhab now genuinely survives a reinstall instead of quietly resetting. This was tested thoroughly in an automated way (39 new checks covering the whole new flow in both languages, plus 10 more proving the "never silently becomes Hanbali" guarantee, plus a real test write against your actual production database). What's still needed is you trying it yourself on a real phone — see the new acceptance script waiting for you in the owner checklist. Both items move from 🔴 to 🟡 below, not yet 🟢, until that happens.

**Update, 2026-09-15 — the loading-spinner issue you reported (tiny white dot instead of a visible spinner, worst on the Create Account button) is fixed and confirmed on your own device.** You tested the build and reported: the Create Account spinner is now clearly visible; it's a real animated spinner, not a dot; the button doesn't change size while loading; and a second loading state (profile save) also worked correctly. **Closed** (tracked as `UI-001`). One honest note kept on record, not smoothed over: this session could never actually reproduce the original tiny-dot problem in its own testing — every place in the code that shows a spinner was already sized correctly when checked directly. The fix went ahead anyway (one standard, consistent way of showing a loading spinner everywhere, replacing several different one-off versions), and your test is what actually confirms it works — not a guess that the investigation found the exact cause. A number of older-style spinners elsewhere in the app (community, messaging, notifications) were checked and are already fine — switching them to the new standard one is a nice-to-have for later, not something blocking anything.

---

## The headline finding

You were right to ask for this check. The Madhhab example you found is real, and it's not the only one of its kind. The pattern across all of them is consistent: **the hard, safety-relevant part was built and tested — the last step of actually turning it on for real users was not finished.** Nothing was found that looks like it was hidden or glossed over; every gap below is one the project's own paperwork already, honestly, describes as "not wired in yet" — it just never got revisited.

---

## Your example, in full

**🟡 A woman who doesn't know her Madhhab (school of Islamic jurisprudence) now has a real way to say so — fixed, pending your test.** (Tracked as finding **`AUTH-010`**.) Onboarding used to offer only the 4 named schools. It now has a genuine 5th option, a calm explanation, a real "help me choose" path built on the suggestion engine that was already sitting unused in the code, and a real "I'll decide later" path — none of it forces a guess or silently assumes anything. On top of that: **the second bug we found, where even a correctly-picked school was only saved on the phone and quietly reset to Hanbali on reinstall** (tracked as **`AUTH-005`**, open since 2026-09-11), is also fixed — your choice now saves to the server, and we found and removed the actual root cause: a spot in the database itself that had been quietly writing "Hanbali" for every single new signup since the day that column was created, which we only discovered while tracing this down. Both fixes are built, deployed to your real production database, and covered by 49 new automated tests — but neither is marked fully done until you've tried it yourself on a real phone. See the new test script waiting for you in the owner checklist.

---

## Everything else this pass found, grouped by how serious it is

### 🟢 Fixed and now confirmed on your own device (moved from RED today)

- **The "you got signed in twice" bug** (`AUTH-008`) — you retested on a freshly reinstalled iOS build and reported: no second Sign In/Sign Up during onboarding, Sign Out returns to Sign In, and signing back in goes straight to the dashboard. **Closed.** The full history of this bug (including the earlier retest that still showed it failing) is kept on record, not deleted, in case it's ever useful — but the current status is fixed and confirmed.
- **The "onboarding asks for your language twice" bug** (`AUTH-009`) — your retest confirmed language is selected before sign-in and never asked again afterward. **Closed.**
- **The Arabic onboarding switching languages mid-flow** (`AUTH-007`) — your retest confirmed Arabic onboarding now stays in Arabic throughout. **Closed.**
- **The loading spinner collapsing into a tiny white dot** (`UI-001`) — your device test confirmed the Create Account spinner (and a second, separate loading state) now render as a clearly visible, animated spinner, with the button staying the same size throughout. **Closed.** The original mechanism was never pinned down with certainty (disclosed above, not hidden), but the fix and your confirmation both stand regardless.

### 🟡 Fixed today, waiting on your real-device test (moved from 🔴, Fiqh Remediation Wave 1)

- **Madhhab "I don't know" option** (`AUTH-010`) — **now really there.** Onboarding's madhhab question has a genuine 5th option in both languages, with a calm explanation, a real "help me choose" path (asks your country, suggests a likely school, and only saves it once you say yes — never on its own), and a real "I'll decide later" path. You can also change your mind later in Settings. Not yet closed — needs your own test on a real phone before we call it done.
- **Madhhab only saved on your phone, silently defaults to Hanbali on reinstall** (`AUTH-005`) — **now really fixed.** Your madhhab choice is saved to the server, not just your phone, and the exact spot in the code that used to quietly assume "Hanbali" whenever nothing was saved — including a spot in the database itself that did this for every single new signup since day one, which we only found while fixing this — has been removed everywhere we could find it. Reinstalling should now bring your real choice back, not reset it. Not yet closed — needs your own test on a real phone before we call it done.
- **No real scholar-approved knowledge base exists yet, and zero scholar sign-off on anything built so far** (`FIQH-8`/`FIQH-9`) — unchanged today, deliberately out of scope for this fix (a separate, later piece of work). See the Fiqh readiness table above. Blocks any claim that guidance is scholar-approved; doesn't block a launch that's honest about being AI-generated guidance that defers to a real scholar.

### 🟡 Built, needs a decision or hasn't been fully wired up

- **Your onboarding "Privacy" screen isn't really about privacy** — it only has the "hide my identity in the community" toggle. Your actual privacy/data-consent agreement happens one screen earlier, during sign-up. Not broken, just possibly not what the name promises. Not launch-blocking, but worth fixing before launch.
- **A "Journeys" feature is advertised to every new user on the very last onboarding screen** (`PJ-007`) — but the screen for it doesn't connect to anything. It looks fully built in the code, just not switched on. This is treated differently from the other "not switched on yet" items below, because it's actively promised to every new user rather than quietly held back — worth fixing before launch even though it's not a hard blocker.
- **"Download all my data" is missing several categories** — it currently gives someone their cycle logs, account info, prayer log, and community posts, but not their wellbeing check-ins, private messages, dream-interpreter history, or community comments/likes. Not a security issue, just incomplete. Not launch-blocking, but should be completed before "full data export" is claimed to users.
- **Deleting your account doesn't clean up everything on your phone** — the server-side deletion works correctly, but your phone still remembers things like your language, marital status, and notification settings after "deletion." Cycle and prayer data specifically ARE cleaned up correctly. Not launch-blocking, but recommended before launch.
- **Marital status has the same "only saved on your phone" issue as prayer location** (which was already known). Lower stakes than Madhhab — we checked and nothing downstream currently misbehaves because of it — but same shape of bug, so we're calling it out as unsafe-by-pattern rather than intentional.

### 🟢 Confirmed solid this pass (worth knowing what IS working)

- **Production Supabase (your backend) matches what the code expects** — we checked the live database, security rules, and email/login configuration directly, not just the code. No surprises found. Every table has the right security lock on it.
- **The email confirmation & branding work from the last two sessions is genuinely live** — re-confirmed directly against production just now, not just trusted from memory. All 13 possible security email types are branded correctly.
- **~35 previously "fixed" issues were spot-checked against the actual current code** (not just trusted because a report once said "done") — every single one still holds up. The one time something did regress in the past (a database piece vanishing after a deploy), the team already caught it, fixed it, and put a permanent automatic watchdog in place so it can't happen silently again.
- **A few pieces of leftover, unused, non-dangerous code were found** — old, abandoned versions of the Settings screen, cycle-log saving, and prayer-tracking screen, none of which are connected to anything real users see. They're not currently causing problems, but they're the exact kind of "looks real, isn't" trap that caused the Madhhab confusion — worth cleaning out at some point so nobody edits the wrong one by mistake.

### ⚪ Deliberately postponed, with a reason already on record

- A formal, dated "I agreed to X privacy terms" record (separate from just having a checkbox) — flagged as a real next step, not started.
- How long the app keeps your data — genuinely undecided; nobody has picked a number yet, and none should be invented without you.
- Legal agreements with Supabase and Google about how your data is handled by them — this needs a lawyer, not an engineer.
- Whether the app needs an age restriction — same, needs a legal/product call, not a technical one.
- Full religious sign-off on the underlying fiqh rules — a review packet is ready and waiting for a qualified scholar; nobody has reviewed it yet. **Correction, later today: this is now also tracked as a formal Fiqh-feature blocker (`FIQH-9`), not only a deferred item** — see the 🔴 Fiqh-feature blockers section above. It's listed here too because the "postponed, not started" framing is still accurate for describing where things stand; it's the launch-status framing that changed.

---

## Fiqh readiness — the full picture (new, 2026-09-14)

You asked specifically whether Niswah can safely launch its Islamic-guidance features today. Short answer: **not yet, if those features are turned on.** Here's every piece, plainly:

| Area | Is it built? | How much is source-backed? | Has a scholar checked it? | Tested for real? | Can it launch today? |
|---|---|---|---|---|---|
| Picking your madhhab | Yes, 5 choices including "I don't know" (**fixed today**) | n/a | n/a | 39 new automated checks, both languages | 🟡 Built and deployed — needs your real-phone test before 🟢 |
| Remembering your madhhab | Now saved to the server, not just your phone (**fixed today**, including the database itself no longer defaulting new signups to Hanbali) | n/a | n/a | 10 new automated checks + a real test write proven against your live database | 🟡 Built and deployed — needs your real-phone test before 🟢 |
| The "knowledge base" behind AI answers | **Doesn't exist as a real, checkable library yet** — today it's the AI's own memory plus a live web search, filtered to 2 trusted websites | 16 draft source entries, none page-checked | 0 of 16 reviewed | Fails safely when unsure (says "ask a scholar," never guesses) | 🔴 Real gap vs. what was originally planned — see below |
| Keeping the 4 schools separate | Yes, verified in code and tests | n/a | Rule table not yet reviewed | Yes | 🟢 Solid |
| AI staying "in its lane" (not pretending to be the religious authority) | Yes, built into every prompt | n/a | n/a | 3 of 4 adversarial tests passed live; 1 blocked by a Google billing issue | 🟡 Mostly solid, one gap |
| Scholar sign-off overall | A complete, ready-to-send review packet exists | — | **0% reviewed — nobody has signed off on anything yet** | — | 🔴 Nothing here is scholar-approved yet |
| Testing against tricky real-world cases | 12 real test scenarios exist | — | None reviewed | Covers most cases; missing a few (e.g., time-zone edge cases, a true pregnancy-bleeding case) | 🟡 Good start, not complete |

**The headline correction from earlier today**: our original plan for the Fiqh feature was "a real library of scholar-approved religious sources → the AI answers from that library → never from its own memory." What's actually built today is a good-faith substitute — the AI answers from its own knowledge plus a live web search, restricted to two trusted Islamic websites, and it's been tested to correctly refuse when it can't find a trustworthy source. That's a reasonable safety net, but it is not the same thing as the real source library we originally planned, and it shouldn't be described as one.

---

## What's holding back a "ready to launch" verdict right now (rebuilt today, not carried over unchanged)

This app has two separate launch questions now: can the **whole app** launch, and — separately — can the **Fiqh guidance features** launch. They have different answers.

**Whole-app blockers** (apply no matter what):
1. **`AUTH-001`** — the confirmation email fully works now; the only remaining piece is a nicer landing page for people who click the link from a different device than the one with the app on it (currently shows a blank page in that one specific case). Needs your domain (niswah.app) connected to a website — a DNS step only you can do.
2. **A couple of older, previously-known items** (device build signing, one owner-only privacy-policy hosting step) — unchanged by this pass, still waiting on you.

**Fiqh-feature blockers** (only apply if the Madhhab dashboard card, Fiqh Report, and Fiqh Advisor chat launch turned on):
3. **No real scholar-approved source library yet, and zero scholar sign-off on anything** — described in the table above. Blocking specifically for any claim that the guidance is "scholar-approved"; not blocking if you launch with honest framing that it's AI-generated guidance that defers to a real scholar (which the app's own wording mostly already does).

**Fixed today, downgraded from blockers to "needs your test" (Fiqh Remediation Wave 1)**:
4. **`AUTH-005`, the Madhhab silent-default/persistence bug — built, deployed, live-verified against your real database.** Your madhhab now saves to the server; the code (including a database default we found and removed) no longer silently assumes Hanbali for anyone. Held open only pending your own real-phone confirmation, per this finding's own evidence standard — not because we think it's broken.
5. **`AUTH-010`, the "I don't know my madhhab" gap — built and deployed.** A real 5th option, explanation, and confirmation-gated suggestion flow now exist in both languages. Same as above: held open only pending your test, not because of a known problem.

**Removed from the blocker list today**: the two sign-in bugs (`AUTH-008`, `AUTH-009`) and the Arabic-locale bug (`AUTH-007`) — all three confirmed fixed on your freshly reinstalled device retest.

**Still tracked, real but not blockers**: the unreachable Journeys screen (`PJ-007`), marital-status persistence, the data-export/account-deletion gaps, notification and wellbeing-cache test coverage, a couple of smaller fiqh-content refinements (source page references, a test-coverage gap or two). Each is worth doing, none currently forces a NO-GO on its own.

**One option worth knowing about, not a recommendation**: if you wanted to launch the non-fiqh parts of Niswah (cycle tracking, pregnancy tracking, community) before the Fiqh features are ready, that's possible in principle by turning those specific features off at launch — but nothing in the app today has an on/off switch built for that, so it would take a small amount of real engineering work, not just a decision. Flagging it as an option, not proposing it as the plan.

---

## Overall verdict

**Whole app: still NO-GO, but with real progress** — three of the previous blockers are now confirmed fixed on your own device. What remains is `AUTH-001`'s landing-page step (needs your DNS action) and the older device-signing/privacy-hosting items.

**Fiqh guidance features specifically: NO-GO, but the two biggest gaps are now fixed** — the Madhhab persistence bug and the forced-guess gap are both built and deployed, waiting only on your own real-phone test to close for good. What's left blocking the Fiqh features is narrower now: the missing scholar review, and your test of the two fixes above. Nothing here should come as a surprise later.

## What happens next

**This time, real code and database changes were made** — a different scope than the two governance-correction passes earlier today, which were documentation-only. Specifically: a new database migration (plus a same-day follow-up fixing a conflicting rule we found live in production while verifying the first one), a rewritten Madhhab-handling module, changes to 12 app screens/files, 2 of your AI backend functions, and 49 new automated tests, all passing. The knowledge-base work (the separate, bigger piece — building a real scholar-approved source library) was explicitly not started, exactly as instructed. **Your real-phone test is the one thing left before `AUTH-005`/`AUTH-010` can close** — see the new script in the owner checklist.
