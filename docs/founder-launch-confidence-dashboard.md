# Niswah Launch Confidence Dashboard

**As of**: 2026-09-15 (updated — incorporates your real-phone Madhhab retest result and the Location investigation). This is written so you can understand where things stand without reading code. It's the result of a full pass checking whether everything that was ever agreed on has actually been built — not just re-checking what was already flagged.

**🟢 GREEN** = proven working, matches production. **🟡 YELLOW** = built, but not fully proven yet, or needs your decision. **🔴 RED** = missing, broken, or blocking launch. **⚪ GRAY** = deliberately postponed, with a reason on record.

**Update, same day**: you retested on a freshly reinstalled iOS build and reported all 9 checklist items PASS. The two sign-in bugs below (and the Arabic-locale bug) are now confirmed fixed on a real device and have moved from RED to GREEN.

**Update, later the same day (Fiqh Remediation Wave 1)** — both Madhhab blockers below are now actually fixed in the code and the database, not just planned: the "I don't know" option is real and working, and your madhhab now genuinely survives a reinstall instead of quietly resetting. This was tested thoroughly in an automated way (39 new checks covering the whole new flow in both languages, plus 10 more proving the "never silently becomes Hanbali" guarantee, plus a real test write against your actual production database). What's still needed is you trying it yourself on a real phone — see the new acceptance script waiting for you in the owner checklist. Both items move from 🔴 to 🟡 below, not yet 🟢, until that happens.

**Update, 2026-09-15 — the loading-spinner issue you reported (tiny white dot instead of a visible spinner, worst on the Create Account button) is fixed and confirmed on your own device.** You tested the build and reported: the Create Account spinner is now clearly visible; it's a real animated spinner, not a dot; the button doesn't change size while loading; and a second loading state (profile save) also worked correctly. **Closed** (tracked as `UI-001`). One honest note kept on record, not smoothed over: this session could never actually reproduce the original tiny-dot problem in its own testing — every place in the code that shows a spinner was already sized correctly when checked directly. The fix went ahead anyway (one standard, consistent way of showing a loading spinner everywhere, replacing several different one-off versions), and your test is what actually confirms it works — not a guess that the investigation found the exact cause. A number of older-style spinners elsewhere in the app (community, messaging, notifications) were checked and are already fine — switching them to the new standard one is a nice-to-have for later, not something blocking anything.

**Update, 2026-09-15 — you tested the Madhhab screen on a real phone and it still showed only the old 4 choices, with no 5th "I don't know" option. You were right to flag this, and it is a real fail, not something to explain away.** Here's what actually happened: the fix genuinely exists in the code — it was checked again, line by line, and a full set of automated tests re-run against it, both passing. But your phone was never running that code. This engagement found something bigger than the Madhhab screen: **every single fix made across this entire project — 97 separate rounds of work — has been sitting on a working copy of the code that was never sent to the place your actual app gets built from.** That "master" copy on GitHub has been frozen since before this project started. So whatever build your phone has, it's running the *original*, unfixed app — the Madhhab screen just happened to be the first place this became visible to you. This is not a new code bug to fix; it's a "get the already-fixed work actually onto your phone" problem, and it needs a decision from you on how you'd like that done (a single, one-time review-and-merge is the standard way, but there are other ways too — happy to walk through the options whenever you're ready). Until that happens, expect every other "fixed" item in this dashboard to also still look unfixed if you test it on your current build — that's the same cause, not a separate failure of each one. `AUTH-010` moves back from 🟡 to **🔴 REOPENED** below, and its evidence record is corrected to show that your test is the real result, not the earlier automated one.

**Update, 2026-09-15 (later the same day) — the delivery gap above is being closed, and the Madhhab evidence record is corrected as a result.** Two things happened: first, it turns out `main` (the "master copy" mentioned above) had already moved forward somewhat on its own since this project's own last check, though still not all the way current — so the gap was smaller than first thought, but real and still there. Second, and more directly: **a formal request (a "pull request") has now been opened to bring `main` fully current with every fix this project has made** — nothing has been merged yet; that step is still yours to approve on GitHub whenever you're ready, and this document will be updated again once it lands. Because this now proves, rather than just strongly suggests, that your Madhhab retest ran against code that never contained this fix, the honest thing to do is **correct the record, not leave it looking like the fix failed**: `AUTH-010` moves back from 🔴 to 🟡 below — your screenshot is kept on file as real, accurate evidence of what your phone showed, just relabeled as evidence from an old build rather than evidence the fix doesn't work. It stays at 🟡, not 🟢, until you retest on a build we can actually confirm came from the current code.

**Update, 2026-09-15 — the "Use Current Location" button you flagged as seeming to do nothing has been found and fixed.** What was actually happening: the button was quietly working the whole time — it really was finding your location and saving it — but the screen advanced to the next question instantly with no confirmation shown, so a successful tap looked exactly the same as a broken one. It's fixed now: tapping it shows a clear "detecting your location…" spinner, then a plain confirmation ("Location confirmed: Current location") before moving on, and the same visible confirmation now shows for tapping any of the 6 city buttons too. Tracked as a new finding, **`AUTH-011`**. This is separate from an older, already-known issue (**`AUTH-006`**) that your saved location doesn't yet survive a reinstall or new phone — that one is still open and unrelated; fixing the confirmation didn't fix that. Built and automated-tested (no real GPS hardware was available this pass, so the actual satellite-fix part is simulated in testing, not proven live) — needs your real-phone test, including a real successful location fix, before it's called done.

---

## The headline finding

You were right to ask for this check. The Madhhab example you found is real, and it's not the only one of its kind. The pattern across all of them is consistent: **the hard, safety-relevant part was built and tested — the last step of actually turning it on for real users was not finished.** Nothing was found that looks like it was hidden or glossed over; every gap below is one the project's own paperwork already, honestly, describes as "not wired in yet" — it just never got revisited.

---

## Your example, in full

**🟡 You tested this on a real phone and it failed — and that failure has since been traced to an old build, not the fix itself.** (Tracked as finding **`AUTH-010`**.) Onboarding used to offer only the 4 named schools with no way to say "I don't know." The fix for that — a genuine 5th option, a calm explanation, a real "help me choose" path, and a real "I'll decide later" path — was built and automated-tested, and is still confirmed correct in the code today. Your own real-phone test showed only the original 4 choices; that result is real, but it's now proven (not just suspected) to be because your phone wasn't running the fixed code, not because the fix is broken — see the update above. On top of that: **the second bug we found, where even a correctly-picked school was only saved on the phone and quietly reset to Hanbali on reinstall** (tracked as **`AUTH-005`**, open since 2026-09-11) — the *database* half of that fix (the hidden spot that used to write "Hanbali" for every new signup) is live on your real production database regardless of which app build you're using, since that part was changed directly on the server. But the *app* half of that fix — the part of the phone app that reads your madhhab and stops assuming Hanbali — lives in the exact same not-yet-delivered code as the Madhhab screen fix above, so it has the same problem: your phone isn't running it yet either. Both fixes need the same one thing to actually reach you: getting the already-finished work off this project's working copy and onto whatever produces your real app builds. See the new test script waiting for you in the owner checklist — and note that a real retest of either one only means something once your phone is running the current code.

---

## Everything else this pass found, grouped by how serious it is

### 🟢 Fixed and now confirmed on your own device (moved from RED today)

- **The "you got signed in twice" bug** (`AUTH-008`) — you retested on a freshly reinstalled iOS build and reported: no second Sign In/Sign Up during onboarding, Sign Out returns to Sign In, and signing back in goes straight to the dashboard. **Closed.** The full history of this bug (including the earlier retest that still showed it failing) is kept on record, not deleted, in case it's ever useful — but the current status is fixed and confirmed.
- **The "onboarding asks for your language twice" bug** (`AUTH-009`) — your retest confirmed language is selected before sign-in and never asked again afterward. **Closed.**
- **The Arabic onboarding switching languages mid-flow** (`AUTH-007`) — your retest confirmed Arabic onboarding now stays in Arabic throughout. **Closed.**
- **The loading spinner collapsing into a tiny white dot** (`UI-001`) — your device test confirmed the Create Account spinner (and a second, separate loading state) now render as a clearly visible, animated spinner, with the button staying the same size throughout. **Closed.** The original mechanism was never pinned down with certainty (disclosed above, not hidden), but the fix and your confirmation both stand regardless.

### 🟡 Your test failed, but that's now proven to be an old-build problem, not a broken fix (2026-09-15)

- **Madhhab "I don't know" option** (`AUTH-010`) — you tested it on a real phone and it still showed only the original 4 choices. The fix is genuinely in the code (re-checked and re-tested this pass) but your phone wasn't running that code — this is now proven, via a direct side-by-side comparison of what your old build actually contained, not just assumed. Back at 🟡 (not the 🔴 it briefly moved to) — your screenshot is kept on record as accurate evidence of an old build, not evidence the fix doesn't work. Needs the delivery (the pull request mentioned above) to land, then a real retest, before this can move to 🟢.
- **Madhhab only saved on your phone, silently defaults to Hanbali on reinstall** (`AUTH-005`) — the database half of this fix is live regardless; the app half has the same not-yet-delivered problem as `AUTH-010` above, since it's the same code. Also needs the same delivery to land before a real retest means anything.

### 🟡 Fixed today, waiting on your real-device test

- **"Use current location" looked like it did nothing** (`AUTH-011`, new) — it was actually working the whole time (really detecting and saving your location), it just never showed you anything, so a success looked identical to nothing happening. Now shows a clear "detecting…" spinner, then a plain "location confirmed" message, before moving on — same for tapping any of the 6 city buttons. Built and automated-tested; still needs your real-phone test (including a real successful location fix, which couldn't be tested without a real phone/GPS this pass) before it's called done. Separate from the older, still-open "location doesn't survive a reinstall" issue below (`AUTH-006`) — fixing one didn't fix the other.
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

**Held at "needs your test," 2026-09-15 — your real-phone test failed, but that's now proven to be a delivery gap, not the fix itself**:
4. **`AUTH-005`, the Madhhab silent-default/persistence bug.** The database half is genuinely live and unaffected. The app half is built and re-confirmed correct in the code today, but is sitting in the same not-yet-delivered working copy as `AUTH-010` below — your phone isn't running it.
5. **`AUTH-010`, the "I don't know my madhhab" gap.** Built, re-checked, and re-tested automatically today — and still failed your real-phone test, because your phone isn't running this code yet, now proven rather than assumed. See the update at the top of this document for the full explanation.

**Removed from the blocker list today**: the two sign-in bugs (`AUTH-008`, `AUTH-009`) and the Arabic-locale bug (`AUTH-007`) — all three confirmed fixed on your freshly reinstalled device retest.

**Still tracked, real but not blockers**: the unreachable Journeys screen (`PJ-007`), marital-status persistence, the data-export/account-deletion gaps, notification and wellbeing-cache test coverage, a couple of smaller fiqh-content refinements (source page references, a test-coverage gap or two). Each is worth doing, none currently forces a NO-GO on its own.

**One option worth knowing about, not a recommendation**: if you wanted to launch the non-fiqh parts of Niswah (cycle tracking, pregnancy tracking, community) before the Fiqh features are ready, that's possible in principle by turning those specific features off at launch — but nothing in the app today has an on/off switch built for that, so it would take a small amount of real engineering work, not just a decision. Flagging it as an option, not proposing it as the plan.

---

## Overall verdict

**Whole app: still NO-GO, but with real progress** — three of the previous blockers are now confirmed fixed on your own device. What remains is `AUTH-001`'s landing-page step (needs your DNS action) and the older device-signing/privacy-hosting items.

**Fiqh guidance features specifically: NO-GO, and the two biggest gaps are reopened as of your 2026-09-15 test** — both fixes are genuinely built, but neither has actually reached your phone yet, for a reason bigger than either bug: the working copy that has every fix this whole project has ever made has never been sent to wherever your real app is built from. Nothing further to build here until that delivery question is settled with you; once it is, both fixes are ready for a real retest.

## What happens next

**Three things were done across this pass and the reconciliation pass that followed it**: a real, working fix for the "Use Current Location" confirmation problem (`AUTH-011`); a full investigation of why your Madhhab retest failed, tracing it to this project's work never having been delivered to wherever your actual app builds come from; and, once you confirmed how you'd like that delivered, **a pull request opened on GitHub bringing everything current** — reviewed for safety first (no conflicts, no secrets, no destructive database changes, all existing checks still passing on this project's own copy of the code). **The one thing left needing your action: reviewing and merging that pull request on GitHub whenever you're ready** — nothing has been merged without you. Once it lands, `AUTH-005` and `AUTH-010` are ready for an immediate real retest (the code itself needs no further changes), and `AUTH-011` is ready for its first one.
