# Accessibility & UX Audit — Phase 2A: Static Verification & Findings

| Field | Value |
|---|---|
| System | Niswah |
| Repository | `/Users/rynadalsabh/Niswah` |
| Branch | `main` |
| Commit | `13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f` |
| Phase | 2A — Static Verification (Phase 2B Controlled Interaction Validation **NOT executed** — no live device/screen-reader available) |
| Audit date | 2026-09-04 |
| Environment | Local static repository review only |
| Platform(s) | iOS + Android (Flutter) |
| Restrictions | No live TalkBack/VoiceOver, no emulator, no device. All findings are 🟧 (confirmed by code/UI structure) or 🟨 (likely, strong inference) unless marked 🟦 (requires controlled interaction test). No finding in this report is 🟥 (interaction-confirmed). |

Evidence key: 🟥 Confirmed by Interaction Test · 🟧 Confirmed by Code/UI Structure · 🟨 Likely · 🟦 Requires Controlled Interaction Test · ⬜ N/A/False positive

---

## AU-001 — Icon-only interactive controls lack accessible names on 15 of 20 `IconButton` sites, plus several bare `GestureDetector`/close-button patterns

- **Severity:** AU1 (High) — pre-launch blocker.
- **Category:** `SEM-xx` / `SR-xx` (Semantic Structure / Screen Reader Audit)
- **Screens/journeys:** Sign-in (`UXJ-001`), Onboarding (`UXJ-002`), Profile/pregnancy-week stepper, `dr_niswah_chat_screen.dart`, `dream_interpreter_screen.dart`, `ghusl_guide_screen.dart`, `guided_journeys_screen.dart`, `pregnancy_tracking_screen.dart`, `cycle_tracking_screen.dart`, `cycle_log_form_sheet.dart` close button.
- **User/role:** `USR-005` (screen-reader user).
- **Platform/device:** iOS (VoiceOver) / Android (TalkBack) — behavior is deterministic from Flutter's semantics tree, not device-specific.
- **Interaction mode:** Screen reader / assistive technology.
- **Expected behavior:** Every actionable, icon-only control exposes a non-empty accessible name so a screen-reader user knows what the control does before activating it (Flutter derives an `IconButton`'s accessible name from its `tooltip:` property; without one, and without an icon `semanticLabel` or wrapping `Semantics(label:)`, the control's accessible name is empty).
- **Actual behavior:** Of 20 `IconButton(` call sites in `lib/`, only 5 (25%) set `tooltip:`. The other 15 render icon-only with no `tooltip:`, no `Semantics` wrapper, and no `Icon(semanticLabel:)`. Concretely:
  - `lib/features/fiqh/presentation/screens/ghusl_guide_screen.dart:126` — `leading: IconButton(icon: Icon(Icons.close), onPressed: () => Navigator.pop(context))` — no tooltip.
  - `lib/features/auth/presentation/screens/sign_in_screen.dart:1047` — password show/hide toggle `IconButton` — no tooltip. A screen-reader user cannot tell this button exists to reveal their typed password, nor what state ("shown"/"hidden") it's currently in.
  - `lib/features/auth/presentation/screens/profile_screen.dart:775, 794, 975` — pregnancy-week +/- steppers and "add high-risk flag" button — no tooltip.
  - `lib/features/education/presentation/screens/guided_journeys_screen.dart:72, 162` — close buttons — no tooltip.
  - `lib/features/pregnancy_tracking/presentation/screens/pregnancy_tracking_screen.dart:44` — refresh milestones button — no tooltip.
  - `lib/features/ai_assistant/presentation/screens/dr_niswah_chat_screen.dart:476, 560` — delete-thread and close buttons — no tooltip (lines 638, 649 in the same file **do** correctly set `tooltip:`, showing the pattern is known but inconsistently applied within one file).
  - `lib/features/dream_interpreter/presentation/screens/dream_interpreter_screen.dart:378, 629` — delete-entry and close buttons — no tooltip (same file's lines 672, 683 correctly do).
  - `lib/features/cycle_tracking/presentation/screens/cycle_tracking_screen.dart:817` — custom icon button — no tooltip.
  - `lib/features/onboarding/presentation/screens/onboarding_screen.dart:92` — wizard back-step button — no tooltip.
  - Separately, `lib/features/cycle_tracking/presentation/widgets/cycle_log_form_sheet.dart:446-457` implements its close control as a bare `GestureDetector(onTap: ..., child: SizedBox(child: Icon(Icons.close_rounded)))` — not even an `IconButton`, and with no `Semantics` wrapper at all, so it has no accessible name or announced role ("button").
  - By contrast, `community_composer_sheet.dart:131` and `community_board_screen.dart:391` **do** set `tooltip:` correctly, and `community_engagement_bar.dart` uses `semanticLabel:` on its icons — proving the team knows the correct pattern; it is simply not applied consistently.
- **Evidence:** 🟧 Confirmed by code — Flutter's accessible-name derivation for `IconButton`/`GestureDetector` is deterministic and does not require a live test to establish that these controls currently expose no name.
- **Severity factors:** No workaround exists for a screen-reader user (an unlabeled icon button is either silently skipped or announced as "button" with no purpose) on core actions: revealing a password, closing modals/guides, deleting AI-chat/dream-journal entries, navigating an onboarding wizard. Repetition frequency is high (present on nearly every screen sampled). Accessibility impact is direct and blocking.
- **Confidence:** CONFIRMED (static code inspection; framework behavior is deterministic).
- **Launch-blocker status:** YES.
- **Cross-reference:** Overlaps Code Quality's CQ-008 observation about `dashboard_screen.dart` size/inconsistency risk — this finding shows the same "some files got it right, most didn't" inconsistency pattern the Code Quality audit flagged structurally.

---

## AU-002 — The dashboard's custom cycle-phase "stepper" visualization (`_PhaseTimeline`/`_PhaseNode`) has no semantic grouping or labels

- **Severity:** AU2 (Medium) — bounded by a partial mitigation (see below), explicit acceptance recommended.
- **Category:** `SEM-xx` / `SR-xx`
- **Screen/journey:** Dashboard (`UXJ-003`) — `lib/features/dashboard/presentation/screens/dashboard_screen.dart`, classes `_PhaseTimeline` (line 2732) and `_PhaseNode` (line 2831).
- **User/role:** `USR-001`, `USR-005`.
- **Platform/device:** iOS/Android, screen reader.
- **Interaction mode:** Screen reader.
- **Expected behavior:** A multi-segment custom visualization representing the user's cycle phases (Haid → Tahara → ... with an active "YOU ARE HERE" node) should expose one coherent semantic node per phase (e.g., "Haid, day 3 of 5, current phase") so a screen-reader user gets the same structured information a sighted user reads visually.
- **Actual behavior:** `_PhaseNode.build()` renders three separate, unwrapped `Text` widgets (`value`, `unit`, `label`) plus a conditional "YOU ARE HERE" `Text`/`Icon` pair, with **no `Semantics`, `MergeSemantics`, or `ExcludeSemantics`** anywhere in either class. A screen reader would traverse this as a sequence of disconnected text fragments per phase node (e.g., "3", "of 5", "Haid", possibly "YOU ARE HERE") rather than one meaningful grouped announcement, for all 4-5 phase nodes in the strip.
  - **Partial mitigation confirmed:** the cycle ring immediately above the timeline (same screen, line 1459) **is** correctly wrapped: `Semantics(button: true, label: '${_l('Cycle day', ...)} $cycleDay، ${_stateLabel(state)}', child: GestureDetector(...))`. This means the single most important fact (current cycle day + current fiqh state) **is** available to a screen-reader user via the ring; the phase-timeline strip beneath it is the secondary/detail visualization that lacks equivalent treatment.
- **Evidence:** 🟧 Confirmed by code (full read of `_PhaseTimeline`/`_PhaseNode`, lines 2732-2924, and the ring's `Semantics` wrapper at line 1459).
- **Severity factors:** Bounded — the primary state information is redundantly available via the ring's label, so this is a "loss of secondary detail," not a full journey block. Cognitive complexity for AT users navigating the fragmented node text is real but not journey-blocking.
- **Confidence:** CONFIRMED (code), announcement *experience* is 🟦 (would benefit from live-test confirmation of exactly how fragmented it sounds).
- **Launch-blocker status:** NO (bounded by ring mitigation), but recommended pre-launch given this is the task brief's specifically flagged "complex custom visualization."

---

## AU-003 — Two of the four core semantic fiqh-state colors (`tahara`, `nifas`) fail WCAG AA 4.5:1 contrast for normal text when used as text/label color, and are used as text color in production code

- **Severity:** AU2 (Medium) — explicit acceptance required; borderline AU1 given the clinical/religious significance of correctly reading these state labels.
- **Category:** `CONTR-xx` (Visual Contrast Audit)
- **Screen/journey:** Dashboard (`UXJ-003`), Insights, Cycle tracking legend.
- **User/role:** `USR-004` (low-vision user).
- **Platform/device:** All.
- **Interaction mode:** Visual/low-vision.
- **Expected behavior:** Text conveying critical state information (the fiqh state name itself) should meet WCAG AA 4.5:1 contrast against its background for normal-size text (≥3:1 is the lower bar, applicable only to large text ≥18pt/14pt-bold or non-text UI components).
- **Actual behavior — contrast ratios calculated directly from the hex values in `lib/core/theme/app_theme.dart` using the WCAG relative-luminance formula (no live rendering available; calculation shown for reproducibility):**

  | Color | Hex | vs. white (`#FFFFFF`) | vs. `brandBackground` (`#FDFCFB`) | AA normal text (4.5:1)? | AA large text/UI (3:1)? |
  |---|---|---|---|---|---|
  | `brandPrimary` / `haid` | `#BE123C` | 6.28:1 | 6.14:1 | **PASS** | PASS |
  | `istihadah` | `#4F46E5` | 6.29:1 | 6.14:1 | **PASS** | PASS |
  | `tahara` | `#0D9488` | **3.74:1** | ~3.66:1 | **FAIL** | PASS (barely) |
  | `nifas` | `#D97706` | **3.19:1** | ~3.12:1 | **FAIL** | PASS (just clears 3.0) |

  (Method: linearize each sRGB channel per the WCAG 2.x formula, compute relative luminance `L = 0.2126R + 0.7152G + 0.0722B`, contrast `= (L_lighter + 0.05) / (L_darker + 0.05)`.)

  This is not theoretical — `AppColors.tahara` is used **directly as `Text` color** at, among other sites: `lib/features/dashboard/presentation/screens/dashboard_screen.dart:1858` (a `labelSmall`-styled, 9px "Mental state check-in" label — normal text, well under the 18pt large-text threshold) and `lib/features/insights/presentation/screens/insights_screen.dart:331` (a `_PredictionValue` label color). `AppColors.nifas` is used as the fill/label color in the fiqh-state legend card in `lib/features/cycle_tracking/presentation/screens/cycle_tracking_screen.dart:1015`.
- **Evidence:** 🟧 Confirmed by direct calculation from theme source values + confirmed real `Text(color:)` usage sites via `grep`.
- **Severity factors:** Bounded because state is also conveyed redundantly by icon, position, and (for the ring) an accessible-name string — but the *visual text label itself*, which is what a low-vision sighted user actually reads, fails the standard bar for two of four states. Given this app's core purpose is determining a religious-practice state (prayer/fasting obligation), misreading "Tahara" for a similarly-shaped word, or simply being unable to read a low-contrast 9px label, has above-average real-world consequence for the affected user segment.
- **Standards classification:** TECHNICAL ACCESSIBILITY FINDING (directly calculable from implementation; not a formal WCAG conformance claim — see §5 boundary).
- **Confidence:** CONFIRMED (calculation is deterministic; verified against real usage sites, not just palette definition).
- **Launch-blocker status:** Recommended acceptance-required (AU2), not a hard blocker on its own.

---

## AU-004 — Cycle-log symptom severity is conveyed by color-alpha alone (no text/numeric indicator), and the severity chip touch target is below the 44/48dp minimum

- **Severity:** AU2 (Medium).
- **Category:** `TOUCH-xx` (Touch Target Audit) + Color Dependency (template §28)
- **Screen/journey:** Cycle/haid log form (`UXJ-004`) — `lib/features/cycle_tracking/presentation/widgets/cycle_log_form_sheet.dart:564-630` (`_symptomsCard`).
- **User/role:** `USR-007` (colorblind/CVD user), `USR-004` (low-vision), general mobile users (touch-target).
- **Platform/device:** iOS/Android.
- **Interaction mode:** Visual + touch.
- **Expected behavior:** A 3-level severity control (mild/moderate/severe, per the on-screen instruction "Tap repeatedly to move from mild to severe") should communicate its current level through more than color alone (WCAG 1.4.1, template §28 Color Dependency Audit), and touch targets for repeated-tap controls should meet the commonly-cited 44×44 (iOS) / 48×48 (Android) minimum.
- **Actual behavior:**
  - Severity is rendered purely as `const Color(0xFFF43F5E).withValues(alpha: .25 + severity * .22)` background fill (lines 601-605) and a two-tone text color (`0xFF6B7280` inactive vs `0xFF9F1239` active, line 618-620) — there is no numeral, word ("mild"/"moderate"/"severe"), or icon indicating which of the 3 levels is currently set. A colorblind or low-vision user tapping "Cramps" three times has no non-color way to confirm which severity was actually recorded before saving.
  - No `Semantics`/`semanticLabel` on the `InkWell` (line 587) announces the current severity level either — a screen-reader user gets the same gap.
  - Touch target: the chip is `width: (MediaQuery.sizeOf(context).width - 94) / 3` (≈90-100px on a 390px-wide device — fine) but `padding: EdgeInsets.symmetric(horizontal: 6, vertical: 11)` around ~9px text with no explicit `height:` — estimated rendered height is **~33-35px**, below both the 44dp (iOS) and 48dp (Android) minimums cited in the audit brief.
- **Evidence:** 🟧 Confirmed by code (full read of lines 564-630).
- **Severity factors:** Workaround exists (user can visually estimate progression through repeated taps by watching color darken, if not colorblind), but the state is genuinely ambiguous/unrecoverable-without-vision. Repetition is high (9 symptom chips per log entry, used on every cycle-log journey).
- **Confidence:** CONFIRMED (code) for the color-only pattern; 🟨 Likely (not pixel-measured) for the exact rendered height — recommend confirming with a live layout inspector before treating the touch-target sub-claim as final.
- **Launch-blocker status:** NO (bounded workaround exists for sighted non-CVD users), acceptance recommended.

---

## AU-005 — Inconsistent form-error UX: `cycle_log_form_sheet.dart` surfaces save/validation errors only via a global `SnackBar`, while `community_composer_sheet.dart` correctly uses a field-anchored `TextFormField` validator

- **Severity:** AU3 (Low) as a standalone finding; flagged because it demonstrates the inconsistent-pattern risk the audit template's §46.3/AI-xx section calls out explicitly.
- **Category:** `FORM-xx` / `ERR-xx`
- **Screen/journey:** Cycle/haid log form (`UXJ-004`) vs. community composer (`UXJ-005`).
- **User/role:** `USR-001`, `USR-005`.
- **Platform/device:** iOS/Android.
- **Interaction mode:** Visual + screen reader.
- **Expected behavior:** Error messages should be associated with the specific field/action they relate to (template §30/§31), not solely rely on a transient global toast a screen-reader/low-vision user could miss.
- **Actual behavior:**
  - `cycle_log_form_sheet.dart:695-712` — on save success, pops the sheet then shows `SnackBar(content: Text('Log saved.'))`; on failure (catch block), shows `SnackBar(content: Text(message))` with no field highlighting, no inline `errorText`, and the sheet's fields are not individually validated before submit (no `Form`/`validator` usage found in this file at all).
  - `community_composer_sheet.dart:169-191` — by contrast, uses a proper `TextFormField(validator: (value) => ... ? 'Write a message before posting.' : null)`, giving Flutter's standard `Form` infrastructure an inline, field-anchored `errorText` that a screen reader announces in context.
  - Flutter's Material `SnackBar` does wrap its content in an accessibility live region by default, so the message is not necessarily *unannounced* to AT — but it remains untethered to the specific field, time-limited, and easy to miss if the user has already moved focus/attention elsewhere (e.g., immediately after the sheet is popped on the success path).
- **Evidence:** 🟧 Confirmed by code (both files read in full/targeted detail).
- **Severity factors:** Bounded — no data loss (form input isn't cleared on error in the cycle-log path since the sheet stays open), but confirms an inconsistent pattern across the app's two main "compose" forms with no shared validation component.
- **Confidence:** CONFIRMED (code); the *actual* live-announcement behavior of the SnackBar's live region is 🟦 (requires interaction test) to confirm on both TalkBack and VoiceOver.
- **Launch-blocker status:** NO.

---

## AU-006 — Several fixed-pixel-dimension custom widgets are not proofed against large OS text-scale settings, risking clipping/overlap

- **Severity:** AU2 (Medium).
- **Category:** `ZOOM-xx` (Zoom / Text Scaling Audit)
- **Screen/journey:** Dashboard (`UXJ-003`, `UXJ-008`).
- **User/role:** `USR-004` (low-vision, uses large OS font size).
- **Platform/device:** iOS/Android.
- **Interaction mode:** Visual, large Dynamic Type / font-scale setting.
- **Expected behavior:** Content should remain usable (no lost information, no overlapping/clipped text) at larger OS text-scale settings (template §35), especially since this app never disables/clamps `textScaleFactor`/`TextScaler` (confirmed 0 occurrences anywhere in `lib/` — a positive baseline finding, since disabling user text scaling is itself an accessibility anti-pattern).
- **Actual behavior:** Because scaling is never clamped, the app *will* pass through large system font sizes into layouts that were not all built to absorb them:
  - `_PhaseNode` (dashboard, lines 2890-2906) renders `value`/`unit` text directly inside a **fixed 32×32 / 42×42px** circular `Container` with no `FittedBox`/`AutoSizeText` wrapper — at large Dynamic Type settings this text will clip or overflow the circle. The same widget's `unit` text is already set to `fontSize: 5` at 100% scale (an unusually small base size independent of scaling — a baseline readability concern on its own).
  - The cycle ring's center content (`SizedBox.square(dimension: 280)`, lines 1466-1479) sizes the ring itself as a fixed 280×280px square; the headline/subtitle text inside is not wrapped in `FittedBox` either, though `Padding(horizontal: 26)` gives it some breathing room.
  - By contrast, `_PhaseNode`'s "YOU ARE HERE" label (line 2855-2866) **is** correctly wrapped in `FittedBox(fit: BoxFit.scaleDown)` — showing the team is aware of the technique but has not applied it to the value/unit text in the same widget.
- **Evidence:** 🟧 Confirmed by code (full read of `_PhaseNode`, `_AnimatedCycleRing` usage).
- **Severity factors:** Bounded to specific widgets, not a whole-journey block — the surrounding scrollable page layout itself is not fixed-height, so the phase timeline and ring are the concentrated risk areas rather than the whole dashboard.
- **Confidence:** 🟨 Likely (fixed-dimension layout + unwrapped text is a strong, well-established Flutter overflow pattern) — actual overflow/clipping at a specific scale factor (e.g., 200%) is 🟦 (requires controlled interaction test at defined OS scale steps, per template §56).
- **Launch-blocker status:** NO, acceptance recommended; cheap to fix (wrap in `FittedBox`) if accepted as a remediation item.

---

## AU-007 — No centralized localization catalog, and only 6 of 25 screens (24%) have any automated RTL/localization visual verification

- **Severity:** AU2 (Medium) as a static-architecture finding; the coverage gap itself elevates the overall audit's residual-unknown count (see AU_production_readiness_report.md).
- **Category:** `LOC-xx` / `RTL-xx`
- **Screen/journey:** All (`UXJ-007` specifically).
- **User/role:** `USR-006` (Arabic/RTL user).
- **Platform/device:** iOS/Android.
- **Interaction mode:** Visual, Arabic locale.
- **Expected behavior:** Given the project's own stated first-class RTL requirement (per `MANIFEST.md` and the wired-in `Directionality`), and that ~60+ files independently choose their own Arabic strings via ad hoc per-file helper functions (`_l`, `_tr`, `_ai`, `_dr`, `_cl`, `_in`, `_t`, `_co`, etc.) rather than one ARB/gen-l10n catalog, there is elevated risk of (a) missed or inconsistent translations for the same concept across screens, and (b) undetected RTL layout regressions on screens outside the tested set.
- **Actual behavior:**
  - `lib/core/localization/app_locale_controller.dart` is 29 lines — it tracks only the `isArabic`/locale boolean state, confirming no central string table exists.
  - `test/goldens/` contains 12 PNGs covering exactly 6 distinct screens in both languages: Dashboard, Calendar (cycle tracking), Insights, Community, Profile, plus one sub-screen pair (`cycle_log_sheet`/`today_lower`). Against **25** total screen files under `lib/features/**/presentation/screens/`, that is **24% screen coverage** for any automated Arabic/RTL visual regression check. The remaining 19 screens — including sign-in, onboarding, AI chat, dream interpreter, doctor/husband/wellbeing/fiqh PDF-report screens, notifications (×2), prayer tracking, pregnancy tracking, private messaging (×2), settings, education, ghusl guide — have **zero** automated RTL verification.
  - A structural caveat that limits even the covered 24%: the golden tests are **pixel self-consistency** tests (`matchesGoldenFile`) — they catch *regressions* from whatever image was captured as the baseline, not *correctness* against an external spec. If an RTL layout defect was already present when a given golden PNG was captured, the test will pass forever without ever flagging it. (Concrete example: AU-008 below is exactly such a defect, present in a widget used on the golden-covered Insights screen, that the golden suite would not necessarily catch.)
- **Evidence:** 🟧 Confirmed — file count via direct enumeration, localization architecture via direct read of `app_locale_controller.dart` and the `_l`/`_tr`-style helper pattern present in the sampled screens.
- **Severity factors:** High blast radius (60+ files each independently prone to translation drift) but no single confirmed user-facing translation inconsistency was found in the files actually sampled this pass — this is a **process/architecture risk finding**, not a confirmed-broken-string finding, and should be read as such.
- **Standards classification:** PRODUCT UX FINDING (architecture risk) with one TECHNICAL ACCESSIBILITY FINDING component (AU-008, confirmed).
- **Confidence:** CONFIRMED (coverage numbers, architecture) / 🟨 Likely (that untested screens contain undetected RTL bugs — plausible given AU-008 proves the pattern exists, but not exhaustively verified for all 19 untested screens).
- **Launch-blocker status:** NO on its own, but contributes to the "critical accessibility/UX unknown" consideration in the final verdict — cross-reference `AU_production_readiness_report.md`.
- **Cross-reference:** Code Quality's implicit scope on the same localization pattern (per the brief's prior-wave context) — this finding assesses it from the UX-consistency/RTL-risk angle specifically, not code-maintainability.

---

## AU-008 — Confirmed RTL padding-side bug in a shared widget (`common_widgets.dart`), live on the golden-tested Insights screen

- **Severity:** AU3 (Low) — confirmed but low visual/functional severity; cited as concrete proof for AU-007's broader risk claim.
- **Category:** `RTL-xx` / `AI-xx` (§46.7 RTL breakage)
- **Screen/journey:** Insights (`UXJ-007`), and any other current/future consumer of `StatCard`.
- **User/role:** `USR-006`.
- **Platform/device:** iOS/Android, Arabic locale.
- **Interaction mode:** Visual.
- **Expected behavior:** Spacing between a numeric value and its unit label (and between an icon and adjacent text) should use direction-aware padding (`EdgeInsetsDirectional`) so the gap renders on the correct side regardless of `Directionality`.
- **Actual behavior:**
  - `lib/core/widgets/common_widgets.dart:217` — inside `StatCard`'s `Row` (children: value `Text`, then conditionally a unit `Text`), the unit's wrapping `Padding` uses **physical** `EdgeInsets.only(left: 8.0)`. In RTL, Flutter's `Row` reverses child paint/hit-test order for `Directionality.rtl`, but a physical `left:` padding does **not** flip with it — the 8px gap stays glued to the physical left edge instead of following the value→unit reading-order gap, which in RTL should be `EdgeInsetsDirectional.only(start: 8.0)`.
  - `lib/core/widgets/common_widgets.dart:271` — `NiswahListTile`'s icon-to-text gap uses `EdgeInsets.only(right: 12)` for the same reason; however this widget has **zero usages elsewhere in `lib/`** (confirmed via `grep -rln "NiswahListTile" lib` returning only its own definition file), so it is currently dead code with no live blast radius.
  - `StatCard` (the line-217 bug), by contrast, **is** actively used in `lib/features/insights/presentation/screens/insights_screen.dart` — a screen with an existing Arabic golden-test pair (`insights_ar_390x844.png`). Per AU-007's caveat, whether this defect is visible in that golden image (and thus silently baked into the "passing" baseline) or happens to be visually unnoticeable at this specific font/value combination was not independently re-rendered in this static-only audit.
- **Evidence:** 🟧 Confirmed by code (`common_widgets.dart:195-230`, `:233-278`) and by `grep`-confirmed absence of other `NiswahListTile` consumers.
- **Severity factors:** Low — misplaced 8-12px padding is a cosmetic asymmetry, not a content-loss or blocking defect; no information is hidden or unreadable.
- **Confidence:** CONFIRMED for the code defect itself (deterministic Flutter `Row` + physical-`EdgeInsets` interaction); 🟦 (requires live/rendered comparison) for whether it is currently visible in the existing Arabic golden capture or already-accepted as-is.
- **Launch-blocker status:** NO.

---

## AU-009 — Phase 2B (Controlled Interaction Validation) could not be executed: no live screen-reader, keyboard, zoom, or device testing was performed for any journey

- **Severity:** Flagged per template as a **critical unknown**, not assigned an AU-severity number itself (it is a scope/process finding, not a defect) — but it is treated as launch-relevant in the final verdict per template §77.
- **Category:** Cross-cutting (`SR-xx`, `KEY-xx`, `ZOOM-xx`, `RESP-xx` Controlled Interaction categories).
- **Screen/journey:** All.
- **User/role:** `USR-005` (screen-reader user) most acutely; also `USR-004`, `USR-003`.
- **Platform/device:** All.
- **Interaction mode:** All controlled-interaction modes.
- **Expected behavior:** Per template §49-§65, critical journeys must be proven through actual keyboard/screen-reader/zoom/touch interaction on a real or emulated environment before a GO/CONDITIONAL GO can be issued for those modes.
- **Actual behavior:** No device, emulator, or assistive-technology tooling was available in this audit environment. Every screen-reader/keyboard/zoom-behavior claim in this report is inference from static code (🟧/🟨), never interaction-confirmed (🟥). This is stated explicitly per the task's instruction and the template's §84 instruction #7 ("Do not assume screen-reader behavior from DOM/code inspection alone when runtime testing is required").
- **Evidence:** Environmental constraint, stated at the outset of this audit; not a code defect.
- **Confidence:** N/A (this is a scope statement, not an inferential finding).
- **Launch-blocker status:** See `AU_production_readiness_report.md` — per template §77, "Critical accessibility/UX behavior remains unknown" is an explicit NO-GO criterion, and this finding is the primary driver of that classification alongside AU-001.

---

## AU-010 — Observation: no screen ever explicitly excludes decorative elements from the semantics tree

- **Severity:** AU4 (Observation).
- **Category:** `SEM-xx`.
- **Evidence:** `grep -rn "ExcludeSemantics\|excludeSemantics\|MergeSemantics" lib` returns 0 results app-wide.
- **Actual behavior:** Purely decorative elements (dividers, background shapes, the small circular "current" marker dot in `_PhaseNode`, etc.) are never wrapped in `ExcludeSemantics`, meaning a screen reader may announce more visual-noise nodes than necessary when traversing screens with many small decorative `Container`/`Icon` widgets. This is a minor AT ergonomics issue, not a blocker.
- **Confidence:** 🟨 Likely to add some verbosity; exact AT behavior is 🟦 (requires interaction test — Flutter's default semantics merging sometimes absorbs purely-decorative leaf nodes without explicit exclusion, so real-world impact could be smaller than the raw code pattern suggests).
- **Launch-blocker status:** NO.

---

## Positive findings (for balance and to avoid over-stating risk)

These are not defects, but are recorded because the audit template requires evidence-based conclusions in both directions:

1. **Where `Semantics(` is used, it is used well.** All 9 instances (5 files) provide meaningful, localized, state-aware labels — e.g., the dashboard cycle ring (`'Cycle day $cycleDay، ${_stateLabel(state)}'`), the floating nav bar's per-tab `selected:`/`label:` semantics, and the community engagement bar's `semanticLabel:` on like/comment/message icons. The gap is *coverage breadth*, not competence.
2. **Reduced-motion preference is respected everywhere animation exists.** Both `AnimationController` instances in the entire app (`dashboard_screen.dart`, `cycle_calendar.dart`) check `MediaQuery.disableAnimationsOf(context)` and stop/zero the animation accordingly.
3. **Text scaling is never disabled or clamped.** `textScaleFactor`/`TextScaler`/`textScalerOf` occur 0 times in `lib/` — the app does not fight the OS accessibility text-size setting, which is a common and harmful anti-pattern this app avoids (see AU-006 for the layout-readiness caveat on that same fact).
4. **`community_composer_sheet.dart` implements textbook field-anchored form validation** via `TextFormField.validator`, correctly contrasting with AU-005's finding on the cycle-log form.
5. **The team is broadly RTL-literate.** 10 files use `EdgeInsetsDirectional`/`PositionedDirectional`/`AlignmentDirectional`; 0 non-directional `Icons.arrow_back` usages were found; the floating nav bar explicitly branches on `Directionality.of(context)` for its custom positioning math.

---

## Static Verification Matrix

| Check ID | Category | Screen / Journey | Expected condition | Evidence | Result |
|---|---|---|---|---|---|
| SEM-01 | Semantics | App-wide | Icon-only controls have accessible names | 15/20 `IconButton` sites + close-button `GestureDetector`s lack tooltip/label | FAIL (AU-001) |
| SEM-02 | Semantics | Dashboard phase timeline | Complex custom visualization has grouped semantics | `_PhaseNode` has none; ring above it does | FAIL (AU-002, bounded) |
| SEM-03 | Semantics | Nav bar, calendar, engagement bar | Custom controls are labeled | Confirmed well-labeled | PASS |
| CONTR-01 | Contrast | Dashboard/Insights/Cycle legend | Semantic state text ≥4.5:1 on background | `tahara` 3.74:1, `nifas` 3.19:1 | FAIL (AU-003) |
| CONTR-02 | Contrast | Buttons/brand text | Brand/haid/istihadah ≥4.5:1 | 6.1-6.3:1 measured | PASS |
| TOUCH-01 | Touch target | Cycle log symptom chips | ≥44/48dp | Estimated ~33-35px height | FAIL (AU-004) |
| TOUCH-02 | Touch target | Nav bar, FAB, close buttons | ≥44/48dp | 56-60px / 52×52px measured | PASS |
| COLOR-01 | Color dependency | Symptom severity chips | Not color-only | Color-alpha-only, no text/number | FAIL (AU-004) |
| FORM-01 | Form UX | Community composer | Field-anchored validation | `TextFormField.validator` present | PASS |
| FORM-02 | Form UX | Cycle log form | Field-anchored validation | SnackBar-only, no `Form`/`validator` | FAIL (AU-005) |
| ZOOM-01 | Text scaling | App-wide | textScale not clamped | 0 occurrences of clamping | PASS |
| ZOOM-02 | Text scaling | Dashboard ring/phase nodes | Fixed-dimension widgets tolerate large scale | No `FittedBox` on value/unit text | FAIL (AU-006) |
| MOTION-01 | Motion | Dashboard/calendar animations | Respect reduced-motion | Both controllers check `disableAnimationsOf` | PASS |
| RTL-01 | RTL | App-wide directionality wiring | `Directionality` correctly wired | Confirmed at `MaterialApp.builder` | PASS |
| RTL-02 | RTL | `common_widgets.dart` | Directional padding used consistently | Physical `EdgeInsets.only(left/right)` found | FAIL (AU-008) |
| LOC-01 | Localization | App-wide | Centralized catalog / test coverage | No ARB catalog; 24% screen RTL-test coverage | FAIL (AU-007) |
| SR-ALL | Screen reader (interaction) | All | Verified via live AT | Not tested — no device available | INCONCLUSIVE (AU-009) |

---

## Static Verification Exit Gate

- [x] Semantics reviewed.
- [x] Keyboard/focus risks reviewed — reviewed to the extent code allows; **no keyboard-specific focus-order implementation was found or expected** for this mobile-only app; marked N/A rather than tested (external-keyboard-on-tablet scenario is UNKNOWN, not verified either way).
- [x] Screen-reader semantics reviewed (statically) — see AU-001, AU-002, AU-010.
- [x] Visual clarity/contrast reviewed — see AU-003.
- [x] Forms/error UX reviewed — see AU-004, AU-005.
- [x] Navigation reviewed — floating nav bar and RTL positioning reviewed; no dead-end or unpredictable-back-behavior pattern found in the files sampled.
- [x] Responsive behavior reviewed — golden tests are fixed at 390×844 only; no tablet/landscape verification exists (`UNKNOWN`, noted in Discovery §7).
- [x] Zoom/text-scaling reviewed — see AU-006.
- [x] Loading/empty/error states reviewed — bounded to AU-005's scope; full state-matrix cross-referenced to Functional QA rather than re-derived.
- [x] Localization/RTL reviewed — see AU-007, AU-008.
- [x] AI-generated UX risks reviewed — see AU-001 (inconsistent-pattern evidence), AU-008 (§46.7 RTL breakage example).
- [x] AU0/AU1 candidates have evidence — AU-001 is the sole AU1; fully evidenced above with exact file:line citations. No AU0 candidate was found.

---

## Finding Register

| Finding ID | Category | Severity | Screen / Journey | Summary | Launch blocker? | Status |
|---|---|---|---|---|---|---|
| `AU-001` | SEM/SR | AU1 | App-wide (15+ sites) | Icon-only controls lack accessible names | YES | OPEN |
| `AU-002` | SEM | AU2 | Dashboard | Phase-timeline stepper lacks semantic grouping | NO | OPEN |
| `AU-003` | CONTR | AU2 | Dashboard/Insights/Cycle legend | `tahara`/`nifas` fail AA 4.5:1 as text color | NO | OPEN |
| `AU-004` | TOUCH/Color | AU2 | Cycle log form | Symptom severity color-only + sub-44px chips | NO | OPEN |
| `AU-005` | FORM/ERR | AU3 | Cycle log form | SnackBar-only errors, inconsistent with composer's field-level validation | NO | OPEN |
| `AU-006` | ZOOM | AU2 | Dashboard | Fixed-dimension ring/phase nodes not scale-proofed | NO | OPEN |
| `AU-007` | LOC/RTL | AU2 | App-wide | No ARB catalog; 24% screen RTL-test coverage | NO (contributes to unknown count) | OPEN |
| `AU-008` | RTL | AU3 | `common_widgets.dart` → Insights | Confirmed physical-EdgeInsets RTL padding bug | NO | OPEN |
| `AU-009` | SR/KEY/ZOOM (process) | N/A (unknown) | All | Phase 2B never executed — no live AT/device testing | Drives final NO-GO | OPEN |
| `AU-010` | SEM | AU4 | App-wide | No `ExcludeSemantics` for decorative elements | NO | OPEN |
