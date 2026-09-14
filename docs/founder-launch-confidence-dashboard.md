# Niswah Launch Confidence Dashboard

**As of**: 2026-09-14. This is written so you can understand where things stand without reading code. It's the result of a full pass checking whether everything that was ever agreed on has actually been built — not just re-checking what was already flagged.

**🟢 GREEN** = proven working, matches production. **🟡 YELLOW** = built, but not fully proven yet, or needs your decision. **🔴 RED** = missing, broken, or blocking launch. **⚪ GRAY** = deliberately postponed, with a reason on record.

---

## The headline finding

You were right to ask for this check. The Madhhab example you found is real, and it's not the only one of its kind. The pattern across all of them is consistent: **the hard, safety-relevant part was built and tested — the last step of actually turning it on for real users was not finished.** Nothing was found that looks like it was hidden or glossed over; every gap below is one the project's own paperwork already, honestly, describes as "not wired in yet" — it just never got revisited.

---

## Your example, in full

**🔴 A woman who doesn't know her Madhhab (school of Islamic jurisprudence) has no way to say so.** Onboarding only offers the 4 named schools. What we found digging in: the harder half of this was actually built — a real "suggest a likely school based on your country" engine, tested and working, sitting unused in the code. It was never connected to the actual sign-up screen. The two missing pieces are: (1) adding the "I don't know" button itself, and (2) once someone picks it, showing the suggestion. Neither is done. On top of that: **even for the 4 women who DO know their school and pick it correctly, that choice is only saved on their phone** — if she deletes and reinstalls the app, or gets a new phone, the app forgets which school she follows and asks again. This is a separate, second bug in the same area.

---

## Everything else this pass found, grouped by how serious it is

### 🔴 Needs your attention before launch

- **The "you got signed in twice" bug you retested and reported still happening.** We rebuilt the app from scratch and traced every single place it could show a sign-in screen — there are only two, and both are correct. New tests that walk through your exact steps (pick language, sign in for real) show it working correctly now. The most likely explanation is the copy on your test device was one step behind the latest fix. **This is marked as still open, not fixed** — your word is what matters here, not our tests, so it stays open until you retest on a **freshly reinstalled** copy of the app. We could not get a working test device set up to check it ourselves this time — a technical problem with the testing tool, not the app.
- **The "onboarding asks for your language twice" bug** — this one is fixed, following the same principle: the language screen inside onboarding is now gone entirely, since you already pick your language on the very first screen. Also pending your retest.

### 🟡 Built, needs a decision or hasn't been fully wired up

- **Madhhab "I don't know" option** — as above. The suggestion engine exists and works in isolation; needs the actual screen built and connected, plus a call on whether to reorder onboarding (right now it asks your school before it asks where you live, which is backwards for a location-based suggestion to work).
- **Your onboarding "Privacy" screen isn't really about privacy** — it only has the "hide my identity in the community" toggle. Your actual privacy/data-consent agreement happens one screen earlier, during sign-up. Not broken, just possibly not what the name promises.
- **A "Journeys" feature is advertised to every new user on the very last onboarding screen** — but the screen for it doesn't connect to anything. It looks fully built in the code, just not switched on.
- **"Download all my data" is missing several categories** — it currently gives someone their cycle logs, account info, prayer log, and community posts, but not their wellbeing check-ins, private messages, dream-interpreter history, or community comments/likes. Not a security issue, just incomplete.
- **Deleting your account doesn't clean up everything on your phone** — the server-side deletion works correctly, but your phone still remembers things like your language, marital status, and notification settings after "deletion." Cycle and prayer data specifically ARE cleaned up correctly.
- **Marital status has the same "only saved on your phone" issue as prayer location** (which was already known). Lower stakes than Madhhab, but same shape of bug.

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
- Full religious sign-off on the underlying fiqh rules — a review packet is ready and waiting for a qualified scholar; nobody has reviewed it yet.

---

## The 3 things holding back a "ready to launch" verdict right now

1. **`AUTH-001`** — the confirmation email fully works now; the only remaining piece is a nicer landing page for people who click the link from a different device than the one with the app on it (currently shows a blank page in that one specific case). Needs your domain (niswah.app) connected to a website — a DNS step only you can do.
2. **The two sign-in bugs above** — pending your retest on a freshly reinstalled app.
3. **A couple of older, previously-known items** (device build signing, one owner-only privacy-policy hosting step) — unchanged by this pass, still waiting on you.

Nothing NEW was found this pass that rises to "must fix before anyone can use the app" — the new findings (Madhhab, the duplicate old screens, the export/deletion gaps) are real and worth fixing, but they're "important, not on fire."

---

## Overall verdict

**Still NO-GO** — same as before this pass, not worse. This pass's job was to find out if anything was quietly missing, and the honest answer is: yes, a handful of things, all now written down precisely, none of them hidden or ignored on purpose. Nothing here should come as a surprise later.

## What happens next

This session was told explicitly: find the gaps, don't fix them yet. So nothing above has been changed in the app. The next conversation can go through this list with you and fix whichever ones you want tackled first.
