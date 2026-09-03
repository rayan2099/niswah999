# NISWAH — MASTER VERIFICATION ADDENDUM
## Part 1: Fiqh Accuracy & Cycle-Calculation Integrity — Part 2: Automated Visual Diff

Apply Part 1 to ALL logic work involving Haid/Istihadah/madhhab rules and cycle-day calculation. Apply Part 2 to ALL screen-by-screen UI/UX verification against the live web app. Both run under the same discipline: one screen/rule at a time, report before acting, human approval before implementing anything uncertain or discrepant.

---

## PART 1 — FIQH ACCURACY & CYCLE-CALCULATION INTEGRITY (MANDATORY)

This overrides "just clone what the web app does" for fiqh logic specifically — fiqh must be CORRECT, not just consistent with a possibly-buggy source.

### Fiqh research requirement
1. For each of the four madhahib (Hanafi, Maliki, Shafi'i, Hanbali), research and document the actual fiqh ruling relevant to the feature you're implementing (e.g. minimum/maximum Haid duration, Istihadah threshold, purity/tuhr period rules) — do not assume the web app already has this right.
2. Primary reference: **dorar.net/en/feqhia/58** (Dorar Al-Saniyyah, comparative fiqh by madhhab with named scholarly attribution). Cross-check against at least one additional source when a ruling seems uncertain or sources could plausibly disagree — do not rely on a single source as infallible.
3. For every fiqh rule you implement, cite the source you're basing it on (specific text, reference site, or named scholarly position) in a comment or accompanying doc. Do not state a fiqh ruling as fact without being able to name where it came from.
4. If you are not confident in a ruling, sources conflict, or you cannot find a clear authoritative answer — STOP and say so explicitly. Do not guess and present a guess as settled fiqh. This is a zero-error-accuracy requirement — an unconfident answer stated as confident is a failure, not a completed task.

### Discrepancy protocol — mandatory, no exceptions
If the web app's current behavior differs from the correct fiqh ruling you've researched:
- **STOP.** Do not implement anything yet.
- **Flag it clearly**: (a) what the web app currently does, (b) what the correct ruling appears to be per your research and cited sources, (c) that this needs a human decision.
- **Do NOT silently "fix" it** by implementing what you believe is correct without flagging.
- **Do NOT silently copy the web app's behavior** if you believe it's fiqh-incorrect, without also flagging that you believe it's wrong.
- Wait for explicit direction before proceeding on that specific rule. This applies regardless of how minor the discrepancy seems — fiqh accuracy is not a place for autonomous judgment calls.

### Single source of truth for cycle calculation
1. Cycle-day counting, phase determination, and Haid/Istihadah/madhhab-rule logic must live in ONE shared service/module (e.g. `CycleCalculationService`), never reimplemented or duplicated per screen.
2. Before writing calculation logic for any screen, check whether this shared service already exists. If it does, use it — never write a parallel implementation "for this screen only."
3. If no shared service exists yet, building it is the first priority: build it once, correctly, with the fiqh research and citations above, THEN have every screen (Dashboard, Calendar, History, Log form, etc.) consume it.
4. If two screens currently calculate the same thing differently, STOP and flag this too — do not silently pick one and apply it everywhere without confirming which (or whether neither) is correct.

### CycleCalculationService — accuracy rules (non-negotiable)
1. **No hardcoded or placeholder cycle-day values, ever.** Not `36`, not `38`, not any literal number standing in for a real calculation — in code, in demo/seed data shown to real users, or anywhere in the UI. If real log data doesn't exist yet, show an explicit empty/onboarding state ("log your cycle to see your day count") — never a fabricated number that looks real.
2. **No fixed 28-day cycle assumption.** Cycle length must be derived from the user's actual logged data (interval between confirmed Haid start dates), not assumed. Average cycle length varies by person and can vary month to month for the same person — the service must calculate it per-instance from real history, not apply a global constant.
3. **Handle irregular/insufficient data explicitly, don't guess silently.** If a user has zero or one logged cycle (not enough history to calculate an average), the service must not fabricate a length — it should state clearly that insufficient data exists yet and use a defined fallback behavior (e.g. show raw days-since-last-Haid-start without a projected total) rather than silently assuming 28 or any other number.
4. **Every calculated value shown in the UI must be traceable to real stored data.** For any cycle-day, phase, or countdown number displayed anywhere in the app, the agent must be able to state which logged data point(s) it was derived from. If it can't, that's the same class of violation as a hardcoded value and must be flagged, not shipped.
5. This applies retroactively — if the agent finds ANY existing hardcoded or fixed-28-day logic anywhere in the current codebase (not just the Dashboard), it must flag every instance found, not just the one currently being worked on.

### Required output for any fiqh/cycle-logic task
1. Sources consulted per madhhab (or confirmation the shared service already covers this and was reused, not reimplemented).
2. Any discrepancies found (web app vs correct fiqh, or between screens) — flagged per protocol, not resolved unilaterally.
3. Confirmation the logic lives in the single shared service, with the list of screens now consuming it.
4. Confirmation that no hardcoded values or fixed 28-day assumptions were used, and a list of any pre-existing instances of either found elsewhere in the codebase during this work.

---

## PART 2 — AUTOMATED VISUAL DIFF: WEB APP VS FLUTTER APP

### Goal
For every screen in the manifest, capture a screenshot from the LIVE web app and the equivalent screenshot from the FLUTTER app (running in the iOS/Android simulator), compare them, and report every visible difference — without the project owner manually taking or uploading screenshots.

### What you have available
- Live browser access to the web app (via the Chrome extension connection)
- Ability to run the Flutter app in the simulator and capture its current screen
- (If available) Flutter's golden test / screenshot testing tooling for widget-level captures

### Process — repeat for each screen in MANIFEST.md, one at a time
1. Navigate to the screen in the live web app. Capture a screenshot at the same viewport size targeted for Flutter (e.g. iPhone dimensions).
2. Run the equivalent screen in the Flutter simulator. Capture a screenshot.
3. Save both to a comparable location (e.g. `/comparison/[screen-name]/web.png` and `/comparison/[screen-name]/flutter.png`).
4. Compare and report in a table:

| Element | Web app | Flutter app | Match? |
|---|---|---|---|
| [component] | [what you see] | [what you see] | ✅/❌ |

5. For every ❌, state the specific fix needed (exact color/spacing/font/logic difference) — not just "doesn't match."
6. **Do NOT fix anything yet in this pass.** Produce the full diff report for this one screen, show it to the project owner, and wait for go-ahead before making changes.

### Efficiency rules (token/request conscious)
- Capture screenshots once per screen, not repeatedly.
- Compare RENDERED OUTPUT, not source code — don't re-read full source files in this pass. Only pull source code afterward, for the specific elements confirmed mismatched.
- Batch all screens' screenshots in one working session if possible, but still report and pause for approval one screen at a time — don't fix multiple screens before each diff report is reviewed.

### Output
After each screen's diff report is approved, apply only the confirmed fixes, then move to the next screen in the manifest.

---

## HOW PARTS 1 AND 2 INTERACT
If a visual diff (Part 2) surfaces a mismatch that turns out to be fiqh/cycle-logic related (not just cosmetic — e.g. a wrong day count, wrong enabled/disabled button state tied to Haid status), stop applying it as a simple visual fix and route it through Part 1's discrepancy protocol instead. Visual differences in calculated values are logic bugs, not styling bugs — treat them accordingly.
