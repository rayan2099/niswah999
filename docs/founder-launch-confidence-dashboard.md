# Niswah Launch Confidence Dashboard

**As of**: 2026-09-14 (updated same day, Post-Reconciliation Governance Correction pass — incorporates your fresh-install iOS retest results). This is written so you can understand where things stand without reading code. It's the result of a full pass checking whether everything that was ever agreed on has actually been built — not just re-checking what was already flagged.

**🟢 GREEN** = proven working, matches production. **🟡 YELLOW** = built, but not fully proven yet, or needs your decision. **🔴 RED** = missing, broken, or blocking launch. **⚪ GRAY** = deliberately postponed, with a reason on record.

**Update, same day**: you retested on a freshly reinstalled iOS build and reported all 9 checklist items PASS. The two sign-in bugs below (and the Arabic-locale bug) are now confirmed fixed on a real device and have moved from RED to GREEN. Everything else on this page is unchanged from the version issued earlier today.

---

## The headline finding

You were right to ask for this check. The Madhhab example you found is real, and it's not the only one of its kind. The pattern across all of them is consistent: **the hard, safety-relevant part was built and tested — the last step of actually turning it on for real users was not finished.** Nothing was found that looks like it was hidden or glossed over; every gap below is one the project's own paperwork already, honestly, describes as "not wired in yet" — it just never got revisited.

---

## Your example, in full

**🔴 A woman who doesn't know her Madhhab (school of Islamic jurisprudence) has no way to say so.** (Now formally tracked as finding **`AUTH-010`** — not launch-blocking on its own, because every current user who completes onboarding explicitly picks one of the 4 real schools, so nobody is being given wrong guidance today.) Onboarding only offers the 4 named schools. What we found digging in: the harder half of this was actually built — a real "suggest a likely school based on your country" engine, tested and working, sitting unused in the code. It was never connected to the actual sign-up screen. The two missing pieces are: (1) adding the "I don't know" button itself, and (2) once someone picks it, showing the suggestion. Neither is done. On top of that: **even for the 4 women who DO know their school and pick it correctly, that choice is only saved on their phone** — if she deletes and reinstalls the app, or gets a new phone, the app forgets which school she follows and asks again, and quietly defaults her to the Hanbali school with no notice. This is a separate, second bug in the same area (tracked as **`AUTH-005`**, open since 2026-09-11) — and we now believe it deserves a harder look than we originally gave it: we traced the exact code path and confirmed that for an already-onboarded woman who reinstalls, that silent default genuinely can change the religious guidance and AI answers she's shown, not just a cosmetic setting. We're flagging this for your judgment on whether it should now count as launch-blocking, rather than deciding that for you.

---

## Everything else this pass found, grouped by how serious it is

### 🟢 Fixed and now confirmed on your own device (moved from RED today)

- **The "you got signed in twice" bug** (`AUTH-008`) — you retested on a freshly reinstalled iOS build and reported: no second Sign In/Sign Up during onboarding, Sign Out returns to Sign In, and signing back in goes straight to the dashboard. **Closed.** The full history of this bug (including the earlier retest that still showed it failing) is kept on record, not deleted, in case it's ever useful — but the current status is fixed and confirmed.
- **The "onboarding asks for your language twice" bug** (`AUTH-009`) — your retest confirmed language is selected before sign-in and never asked again afterward. **Closed.**
- **The Arabic onboarding switching languages mid-flow** (`AUTH-007`) — your retest confirmed Arabic onboarding now stays in Arabic throughout. **Closed.**

### 🟡 Built, needs a decision or hasn't been fully wired up

- **Madhhab "I don't know" option** (`AUTH-010`) — as above. The suggestion engine exists and works in isolation; needs the actual screen built and connected, plus a call on whether to reorder onboarding (right now it asks your school before it asks where you live, which is backwards for a location-based suggestion to work). Not launch-blocking, since no current user is affected.
- **Madhhab only saved on your phone, silently defaults to Hanbali on reinstall** (`AUTH-005`) — flagged above for your reconsideration on blocking status, given the confirmed path to affecting live religious guidance.
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
- Full religious sign-off on the underlying fiqh rules — a review packet is ready and waiting for a qualified scholar; nobody has reviewed it yet.

---

## What's holding back a "ready to launch" verdict right now (rebuilt today, not carried over unchanged)

1. **`AUTH-001`** — the confirmation email fully works now; the only remaining piece is a nicer landing page for people who click the link from a different device than the one with the app on it (currently shows a blank page in that one specific case). Needs your domain (niswah.app) connected to a website — a DNS step only you can do.
2. **`AUTH-005`, the Madhhab silent-default/persistence bug** — newly flagged today as a candidate blocker, not automatically added as one. We confirmed it can genuinely affect the religious guidance an already-onboarded, reinstalling user sees, with no warning to her. This is your call to make, not ours.
3. **A couple of older, previously-known items** (device build signing, one owner-only privacy-policy hosting step) — unchanged by this pass, still waiting on you.

**Removed from the blocker list today**: the two sign-in bugs (`AUTH-008`, `AUTH-009`) and the Arabic-locale bug (`AUTH-007`) — all three confirmed fixed on your freshly reinstalled device retest.

**Still tracked, but explicitly not blockers**: Madhhab "I don't know" UX (`AUTH-010`), the unreachable Journeys screen (`PJ-007`), marital-status persistence, the data-export/account-deletion gaps, notification and wellbeing-cache test coverage. Each is real and worth doing, but none currently puts an actual user at risk or breaks a promised feature for someone using the app normally today (Journeys is the closest exception, and it's flagged above as worth fixing before launch even though it's not a hard gate).

---

## Overall verdict

**Still NO-GO, but with real progress** — three of the previous blockers are now confirmed fixed on your own device. What remains is `AUTH-001`'s landing-page step (needs your DNS action), the older device-signing/privacy-hosting items, and your decision on whether the Madhhab persistence bug should count as a launch blocker. Nothing here should come as a surprise later.

## What happens next

This session was told explicitly: reconcile the gaps and fix the paperwork, don't touch the app's code. So nothing above has been changed in the app. The next conversation can go through this list with you and fix whichever ones you want tackled first — starting, most likely, with your call on `AUTH-005`.
