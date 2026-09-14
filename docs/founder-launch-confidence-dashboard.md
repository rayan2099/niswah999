# Niswah Launch Confidence Dashboard

**As of**: 2026-09-14 (updated same day, Post-Reconciliation Governance Correction pass — incorporates your fresh-install iOS retest results). This is written so you can understand where things stand without reading code. It's the result of a full pass checking whether everything that was ever agreed on has actually been built — not just re-checking what was already flagged.

**🟢 GREEN** = proven working, matches production. **🟡 YELLOW** = built, but not fully proven yet, or needs your decision. **🔴 RED** = missing, broken, or blocking launch. **⚪ GRAY** = deliberately postponed, with a reason on record.

**Update, same day**: you retested on a freshly reinstalled iOS build and reported all 9 checklist items PASS. The two sign-in bugs below (and the Arabic-locale bug) are now confirmed fixed on a real device and have moved from RED to GREEN. Everything else on this page is unchanged from the version issued earlier today.

---

## The headline finding

You were right to ask for this check. The Madhhab example you found is real, and it's not the only one of its kind. The pattern across all of them is consistent: **the hard, safety-relevant part was built and tested — the last step of actually turning it on for real users was not finished.** Nothing was found that looks like it was hidden or glossed over; every gap below is one the project's own paperwork already, honestly, describes as "not wired in yet" — it just never got revisited.

---

## Your example, in full

**🔴 A woman who doesn't know her Madhhab (school of Islamic jurisprudence) has no way to say so.** (Tracked as finding **`AUTH-010`** — **corrected today, later the same day, to a real Fiqh-feature launch blocker**: forcing a guess isn't harmless, since our own test cases show the 4 schools can genuinely disagree on identical facts, so a wrong guess can produce a confidently wrong answer.) Onboarding only offers the 4 named schools. What we found digging in: the harder half of this was actually built — a real "suggest a likely school based on your country" engine, tested and working, sitting unused in the code. It was never connected to the actual sign-up screen. The two missing pieces are: (1) adding the "I don't know" button itself, and (2) once someone picks it, showing the suggestion. Neither is done. On top of that: **even for the 4 women who DO know their school and pick it correctly, that choice is only saved on their phone** — if she deletes and reinstalls the app, or gets a new phone, the app forgets which school she follows and asks again, and quietly defaults her to the Hanbali school with no notice. This is a separate, second bug in the same area (tracked as **`AUTH-005`**, open since 2026-09-11) — **also corrected today to a formal Fiqh-feature launch blocker, not just a flag for your judgment**: we traced the exact code path and confirmed that for an already-onboarded woman who reinstalls, that silent default genuinely does change the religious guidance and AI answers she's shown, not just a cosmetic setting. Both are still scoped to the Fiqh-guidance features specifically, not the whole app.

---

## Everything else this pass found, grouped by how serious it is

### 🟢 Fixed and now confirmed on your own device (moved from RED today)

- **The "you got signed in twice" bug** (`AUTH-008`) — you retested on a freshly reinstalled iOS build and reported: no second Sign In/Sign Up during onboarding, Sign Out returns to Sign In, and signing back in goes straight to the dashboard. **Closed.** The full history of this bug (including the earlier retest that still showed it failing) is kept on record, not deleted, in case it's ever useful — but the current status is fixed and confirmed.
- **The "onboarding asks for your language twice" bug** (`AUTH-009`) — your retest confirmed language is selected before sign-in and never asked again afterward. **Closed.**
- **The Arabic onboarding switching languages mid-flow** (`AUTH-007`) — your retest confirmed Arabic onboarding now stays in Arabic throughout. **Closed.**

### 🔴 Fiqh-feature blockers (reclassified today, later the same day — see the Fiqh readiness section above for full detail)

- **Madhhab "I don't know" option** (`AUTH-010`) — as above. The suggestion engine exists and works in isolation; needs the actual screen built and connected, plus a call on whether to reorder onboarding (right now it asks your school before it asks where you live, which is backwards for a location-based suggestion to work). **Reclassified from "not launch-blocking" to a real Fiqh-feature blocker** — forcing a guess risks a materially wrong answer, not just an awkward UX moment.
- **Madhhab only saved on your phone, silently defaults to Hanbali on reinstall** (`AUTH-005`) — **reclassified from "flagged for your judgment" to a formal Fiqh-feature blocker** — confirmed to genuinely change the religious guidance shown, not just a cosmetic setting.
- **No real scholar-approved knowledge base exists yet, and zero scholar sign-off on anything built so far** (`FIQH-8`/`FIQH-9`) — see the Fiqh readiness table above. Blocks any claim that guidance is scholar-approved; doesn't block a launch that's honest about being AI-generated guidance that defers to a real scholar.

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
| Picking your madhhab | Yes, 4 schools offered | n/a | n/a | Yes | 🔴 No "I don't know" option — forces a guess |
| Remembering your madhhab | Only on your phone | n/a | n/a | Confirmed reaches real answers | 🔴 Silently resets to Hanbali if you reinstall, with no warning |
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

**Fiqh-feature blockers** (only apply if the Madhhab dashboard card, Fiqh Report, and Fiqh Advisor chat launch turned on) — **corrected today, no longer left as "your call, not ours"**:
3. **`AUTH-005`, the Madhhab silent-default/persistence bug — now formally a blocker for the Fiqh features specifically, not just a flag.** We confirmed it can genuinely change the religious guidance an already-onboarded, reinstalling woman is shown, with zero warning to her — that crosses the line from "worth fixing" to "should not ship enabled as-is."
4. **`AUTH-010`, the "I don't know my madhhab" gap — also now a Fiqh-feature blocker, reversed from this morning's "not blocking."** Forcing a guess isn't harmless: our own test cases show the 4 schools can genuinely disagree on the same facts, so a wrong guess can produce a wrong answer stated with full confidence.
5. **No real scholar-approved source library yet, and zero scholar sign-off on anything** — both described in the table above. Blocking specifically for any claim that the guidance is "scholar-approved"; not blocking if you launch with honest framing that it's AI-generated guidance that defers to a real scholar (which the app's own wording mostly already does).

**Removed from the blocker list today**: the two sign-in bugs (`AUTH-008`, `AUTH-009`) and the Arabic-locale bug (`AUTH-007`) — all three confirmed fixed on your freshly reinstalled device retest.

**Still tracked, real but not blockers**: the unreachable Journeys screen (`PJ-007`), marital-status persistence, the data-export/account-deletion gaps, notification and wellbeing-cache test coverage, a couple of smaller fiqh-content refinements (source page references, a test-coverage gap or two). Each is worth doing, none currently forces a NO-GO on its own.

**One option worth knowing about, not a recommendation**: if you wanted to launch the non-fiqh parts of Niswah (cycle tracking, pregnancy tracking, community) before the Fiqh features are ready, that's possible in principle by turning those specific features off at launch — but nothing in the app today has an on/off switch built for that, so it would take a small amount of real engineering work, not just a decision. Flagging it as an option, not proposing it as the plan.

---

## Overall verdict

**Whole app: still NO-GO, but with real progress** — three of the previous blockers are now confirmed fixed on your own device. What remains is `AUTH-001`'s landing-page step (needs your DNS action) and the older device-signing/privacy-hosting items.

**Fiqh guidance features specifically: NO-GO**, corrected today from "your call" to a real blocker list — the Madhhab persistence bug, the forced-guess gap, and the missing scholar review all need resolving (or an explicit, informed decision from you to launch without them, with honest framing) before those features should go live. Nothing here should come as a surprise later.

## What happens next

This session was told explicitly: reconcile the gaps and fix the paperwork, don't touch the app's code or start building the knowledge base. So nothing above has been changed in the app. The next conversation can go through this list with you and fix whichever ones you want tackled first.
