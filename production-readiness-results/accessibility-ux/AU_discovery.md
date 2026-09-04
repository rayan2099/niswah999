# Accessibility & UX Audit — Phase 1: Discovery

| Field | Value |
|---|---|
| System | Niswah |
| Repository | `/Users/rynadalsabh/Niswah` |
| Branch | `main` |
| Commit | `13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f` |
| Phase | 1 — Discovery |
| Audit date | 2026-09-04 |
| Environment | Local static repository review only. No dev/staging/production access. |
| Platform(s) | iOS + Android (Flutter mobile app in `lib/`) |
| Supported languages | English, Arabic (in-house `_l(en, ar)` / `_tr(en, ar)` per-screen helper pattern, not Flutter ARB/gen-l10n) |
| RTL support | YES — `Directionality` wired at `MaterialApp.builder` level in `lib/main.dart`, driven by `AppLocaleController.instance.textDirection` |
| Accessibility target/standard | Not formally defined by the project. No WCAG level, platform accessibility policy, or legal standard is named in any repo doc. This audit therefore evaluates against WCAG 2.1 AA as a **reference bar for technical findings only** (per §5 of the template) — this is **not** a claim of formal WCAG conformance. |
| Restrictions | **No live device, emulator, or screen reader (TalkBack/VoiceOver) was available.** This is a Static/Documentation-tier review only — Phase 2B (Controlled Interaction Validation) could not be executed. All findings below are code-pattern inference (🟧/🟨), not interaction-confirmed (🟥) unless explicitly noted. |
| Report created | `AU_discovery.md` |

---

## 1. Scope note

`src/` is a separate React/Vite reference-only web app (per project memory: "never edit `src/`; it's a design reference for the Flutter port") — **out of scope**. This audit covers only `lib/` (154 Dart files).

---

## 2. User / Role Inventory

| User ID | Role / User type | Primary goals | Critical journeys | Accessibility considerations |
|---|---|---|---|---|
| `USR-001` | Authenticated user (primary persona) | Log cycle/haid data, check fiqh (prayer/fasting) state, track pregnancy, use AI assistant, read community posts | Daily dashboard check, cycle logging, fiqh-state lookup | Core persona for a religious-observance app — misread state text has real-world religious consequence |
| `USR-002` | New/onboarding user | Complete signup, set initial cycle/madhhab profile | Onboarding wizard, sign-in | Multi-step form; back/forward icon-only nav observed |
| `USR-003` | Mobile user, small-screen/low dexterity | Operate app one-handed | All journeys | Touch-target sizing relevant (44×44 iOS / 48×48 Android baseline used per task brief) |
| `USR-004` | Low-vision user | Read state labels, use larger OS text size | Dashboard fiqh-state read, forms | Contrast and text-scaling relevant — see AU-003, AU-006 |
| `USR-005` | Screen-reader user (TalkBack/VoiceOver) | Complete all critical journeys non-visually | All journeys, especially icon-only controls | **UNKNOWN / NOT VERIFIED** — no live AT testing possible. Static semantics inspection only (see AU-001, AU-002). |
| `USR-006` | Arabic-speaking / RTL user | Use entire app mirrored, correct Arabic strings | All journeys in Arabic | Only 6 of 25 screens have any automated RTL layout verification — see AU-007 |
| `USR-007` | Colorblind / color-vision-deficient user | Distinguish state and severity by non-color means | Cycle logging (symptom severity), fiqh-state read | Color-only-dependency risk found — see AU-004 |

---

## 3. Critical Journey Inventory

| Journey ID | Journey | Role | Platform | Criticality | Key interaction risks |
|---|---|---|---|---|---|
| `UXJ-001` | Sign in / sign up | USR-002 | iOS/Android | Critical | Password-visibility icon button has no accessible name (AU-001) |
| `UXJ-002` | Onboarding wizard | USR-002 | iOS/Android | Critical | Icon-only back-step button has no accessible name (AU-001) |
| `UXJ-003` | Dashboard — read current fiqh state (Tahara/Haid/Istihadah/Nifas) | USR-001, USR-004, USR-005 | iOS/Android | Critical (religious-practice-determining) | Custom ring + phase-timeline "stepper" is a complex, largely un-labeled visualization (AU-002); tahara/nifas state-label text fails AA contrast (AU-003) |
| `UXJ-004` | Log a cycle/haid entry (flow, blood color, symptoms, notes) | USR-001 | iOS/Android | Critical | Symptom severity conveyed by color alpha only (AU-004); save/validation errors are SnackBar-only, not field-anchored (AU-005) |
| `UXJ-005` | Community — post, like, comment | USR-001, USR-005 | iOS/Android | High | Engagement bar icon buttons are well-labeled (positive finding); composer form uses a correct field-anchored validator (positive finding) |
| `UXJ-006` | Notifications, close/dismiss modals across the app | All | iOS/Android | High | Repeated bare `GestureDetector`/`IconButton` close controls with no tooltip/Semantics across many screens (AU-001) |
| `UXJ-007` | Read app in Arabic / RTL | USR-006 | iOS/Android | Critical | Only 6/25 screens golden-tested for RTL; one confirmed RTL padding-side bug in a shared widget (AU-007, AU-008) |
| `UXJ-008` | Increase OS text size and continue using the app | USR-004 | iOS/Android | High | No text-scale clamping (positive), but several fixed-pixel custom widgets (cycle ring, phase-timeline nodes) risk clipping/overlap at large scale (AU-006) |

---

## 4. Screen / Route Inventory

25 screen files found under `lib/features/**/presentation/screens/*_screen.dart`, plus `lib/features/settings/settings_screen.dart`:

```
ai_assistant/dr_niswah_chat_screen.dart
auth/account_settings_screen.dart, profile_screen.dart, sign_in_screen.dart
community/community_board_screen.dart, post_detail_screen.dart
cycle_tracking/cycle_tracking_screen.dart
dashboard/dashboard_screen.dart  (3,213 lines — see CQ-008 cross-reference below)
doctor_report/doctor_report_screen.dart
dream_interpreter/dream_interpreter_screen.dart
education/guided_journeys_screen.dart
educational_library/resource_library_screen.dart
fiqh/ghusl_guide_screen.dart
fiqh_report/fiqh_report_screen.dart
husband_report/husband_report_screen.dart
insights/insights_screen.dart
notifications/notification_feed_screen.dart, notification_settings_screen.dart
onboarding/onboarding_screen.dart
prayer_tracking/prayer_tracking_screen.dart
pregnancy_tracking/pregnancy_tracking_screen.dart
private_messaging/chat_detail_screen.dart, conversations_screen.dart
settings/settings_screen.dart
wellbeing/wellbeing_report_screen.dart
```

Of these, only **5 distinct screens have golden/pixel-parity test coverage** (`test/goldens/`: `dashboard`, `calendar` [=cycle_tracking], `insights`, `community`, `profile`, plus a `cycle_log_sheet` and `today_lower` sub-screen capture — 12 PNGs total, EN+AR pairs). That is **6 of 25 screens (24%)** with any automated RTL/localization visual verification. See AU-007.

---

## 5. Interaction Pattern Inventory

| Pattern | Usage in `lib/` | Notes |
|---|---|---|
| `IconButton(` | 20 occurrences, 12 files | Only 5/20 (25%) carry a `tooltip:` |
| `GestureDetector(` | 12 occurrences | Custom tap targets — no automatic semantics unless manually wrapped in `Semantics(...)` |
| `InkWell(` | 34 occurrences | Same — relies on ambient `Material`/`Semantics` from parent or manual wrapping |
| `Semantics(` | 9 occurrences, 5 files total (`floating_nav_bar.dart`, `profile_screen.dart`, `dashboard_screen.dart`, `community_engagement_bar.dart`, `cycle_calendar.dart`) | Where used, labels are well-formed (meaningful, localized, combine state+value) — see AU-002 discussion of coverage gaps elsewhere |
| `semanticLabel:` | 3 occurrences, 1 file (`community_engagement_bar.dart`) | Like/comment/message icons — correctly labeled |
| `ExcludeSemantics` / `excludeSemantics` | 0 occurrences | Decorative icons/dividers are never explicitly hidden from AT — see AU-010 (observation) |
| `MergeSemantics` | 0 occurrences | No composite-widget semantic grouping anywhere |
| `TextField`/`TextFormField` with `validator:` | Present in `community_composer_sheet.dart` (field-anchored `errorText`) | Positive pattern |
| Bottom sheets (custom modal forms) | `cycle_log_form_sheet.dart`, `community_composer_sheet.dart` | Different validation-feedback strategies between the two — see AU-005 |
| Animated custom visualizations | Cycle ring (`_AnimatedCycleRing`/`_CycleRingPainter`), phase timeline (`_PhaseTimeline`/`_PhaseNode`) in `dashboard_screen.dart` | Ring has a Semantics wrapper; the phase-timeline nodes beneath it do not — see AU-002 |
| `MediaQuery.disableAnimationsOf` (reduced motion) | 2 occurrences (`dashboard_screen.dart`, `cycle_calendar.dart`) — the **only** 2 `AnimationController`s in the whole app | Both respect the OS reduced-motion preference. Positive finding. |
| `textScaleFactor` / `TextScaler` / `textScalerOf` | 0 occurrences anywhere | Text scaling is never disabled or clamped — positive from an accessibility standpoint, but see AU-006 for the flip side (fixed-dimension layouts not proofed against large scale) |

---

## 6. Design System / Component Inventory

- No third-party accessibility-audited component library; the app is built from Material widgets plus a hand-rolled shared library, `lib/core/widgets/common_widgets.dart` (`NiswahCard`, `StatCard`, `NiswahListTile`, etc.) and many per-feature custom widgets (cards, chips, rings).
- `lib/core/theme/app_theme.dart` defines `AppColors` (brand + 4 semantic fiqh-state colors: `tahara`, `haid`, `istihadah`, `nifas`) and `AppTypography`, plus `AppTheme.lightTheme`/`darkTheme` `ThemeData`.
- `lib/core/widgets/floating_nav_bar.dart` — the app's persistent 5-tab bottom navigation + center FAB. Manually computes RTL-mirrored item positions (`_rtlItemCenters`) rather than using `PositionedDirectional` throughout, but does branch on `Directionality.of(context)` correctly and is Semantics-wrapped.
- No dedicated design-tokens file for spacing/typography scale beyond the `ThemeData.textTheme`; many screens hardcode font sizes directly on `Text(style: TextStyle(fontSize: ...))` rather than using theme text styles (seen throughout `dashboard_screen.dart`, `cycle_log_form_sheet.dart`).

---

## 7. Supported Device / Browser Matrix

| Platform | OS | Screen class | Required? | Notes |
|---|---|---|---|---|
| iOS | Not pinned in repo docs | Mobile | Presumed YES | `ios/` directory present |
| Android | Not pinned in repo docs | Mobile | Presumed YES | `android/` directory present |
| Tablet | — | Tablet | **UNKNOWN** | No tablet-specific layout code found; golden tests fixed at 390×844 only |

No product document defines a formal supported-device/OS-version matrix. This audit does not claim broad device support.

---

## 8. Localization Inventory

- Supported languages: English, Arabic.
- Mechanism: **no ARB / `gen-l10n` catalog.** Each screen defines its own local helper (commonly `_l(en, ar)`, or feature-specific names like `_ai(...)`, `_dr(...)`, `_cl(...)`, `_in(...)`, `_t(...)`, `_co(...)`) that returns one of two hardcoded literals based on `AppLocaleController.instance.isArabic`.
- `lib/core/localization/app_locale_controller.dart` is 29 lines — it only tracks the boolean/locale state, not any string table.
- Default language / fallback: English (locale controller defaults `isArabic = false` unless changed).
- No centralized translation memory: the same concept (e.g., "Close", "History") is independently retranslated in every file that needs it, with no single source of truth or lint/CI check for missing/inconsistent translations.
- Numbers/dates: no dedicated locale-aware `intl` `NumberFormat`/`DateFormat` usage was inventoried in this pass; cycle-day counters, denominators ("of 5"), and week counters (pregnancy) appear to be built as raw string interpolation with the `_l`-style literal wrapping around the digits. Not independently verified beyond the dashboard's `'${_l('of $denominator', ...)}'` pattern.

---

## 9. RTL Inventory

- `Directionality` is wired once at `MaterialApp.builder` in `lib/main.dart` — app-wide RTL mirroring is structurally correct at the root.
- `EdgeInsetsDirectional` / `PositionedDirectional` / `AlignmentDirectional` used in 10 files — team is generally RTL-aware.
- 3 occurrences of physical (non-directional) `EdgeInsets.only(left:/right:)` found, one of which (`common_widgets.dart`) sits in a **shared component** used on a screen with RTL golden coverage (Insights) — see AU-008.
- No non-directional `Icons.arrow_back` usage found (0 occurrences) — the app consistently avoids the one icon most commonly broken in RTL ports.
- `floating_nav_bar.dart` hand-computes RTL item centers via a literal reversed-order constant list rather than `Directionality`-relative layout primitives — functionally correct per the code read, but fragile to future edits (a five-tab assumption is hardcoded via `assert(items.length == 5)`).

---

## 10. Form Inventory

| Form ID | Form | Fields | Required fields | Validation method | Destructive/financial? |
|---|---|---|---|---|---|
| `FORM-001` | Cycle/haid log (`cycle_log_form_sheet.dart`, 848 lines) | Flow intensity, blood color, symptoms (severity 0-3 each), energy, sleep, mood, notes | None enforced via visible required markers found | Try/catch around `saveLog()`; success and error both surfaced via `ScaffoldMessenger.showSnackBar` — no field-level `errorText` | No (data logging) |
| `FORM-002` | Community post composer (`community_composer_sheet.dart`) | Post content, topic/category, anonymity toggle | Content (non-empty) | `TextFormField.validator` → inline field `errorText` (correct pattern) | No |
| `FORM-003` | Sign-in | Email, password | Presumed yes (not independently traced this pass) | Not traced this pass | No |
| `FORM-004` | Onboarding wizard | Multi-step profile setup | Not traced this pass | Not traced this pass | No |

---

## 11. State Inventory

Loading/empty/error states were not exhaustively re-derived in this pass (would duplicate Functional QA scope); spot-checked only where directly relevant to a form/error finding (AU-005). Cross-reference Functional QA and Reliability audits for full state-coverage claims.

---

## 12. Content / Copy Inventory

No placeholder/lorem/"Coming soon" copy was found in the files sampled for this audit. Copy is consistently bilingual and domain-specific (fiqh/religious terminology handled carefully, e.g., `'Salah is lifted'` for the Haid state).

---

## 13. Accessibility Mechanism Inventory

| Mechanism | Present? | Evidence |
|---|---|---|
| Semantic widget wrapping (`Semantics(`) | Sparse — 9 instances / 5 files out of 154 Dart files | See §5 above |
| `semanticLabel:` on icon-conveyed actions | Rare — 3 instances, 1 file | `community_engagement_bar.dart` only |
| `tooltip:` on `IconButton` | 5 / 20 (25%) | See AU-001 |
| Reduced motion (`disableAnimationsOf`) | Yes, both `AnimationController` usages | Positive |
| Text-scale clamping | Absent (not disabled anywhere) | Positive by omission, but see AU-006 |
| Landmarks / heading hierarchy | Not applicable in the Flutter semantics tree the same way as web; not separately audited | — |
| Focus management (external keyboard) | Not audited — mobile-first app, no evidence of keyboard-specific focus traversal design | **UNKNOWN / NOT VERIFIED** |
| Alt text equivalent (image `semanticLabel`) | Not inventoried this pass — no `Image.asset`/`Image.network` semantic-label sweep performed | **UNKNOWN / NOT VERIFIED**, flagged as gap in §19 |

---

## 14. Discovery Execution Log

### Fully reviewed
- `lib/core/theme/app_theme.dart` (full read)
- `lib/core/widgets/floating_nav_bar.dart` (full read)
- `lib/main.dart` (MaterialApp/builder/Directionality section)
- `lib/features/dashboard/presentation/screens/dashboard_screen.dart` — targeted deep read of the fiqh-state ring, `_PhaseTimeline`/`_PhaseNode` stepper, `_AnimatedCycleRing`, and all 4 `Semantics(` call sites
- `lib/features/cycle_tracking/presentation/widgets/cycle_log_form_sheet.dart` (full read)
- `lib/features/community/presentation/widgets/community_composer_sheet.dart` (targeted, validator section)
- `lib/features/community/presentation/widgets/community_engagement_bar.dart` (Semantics section)
- `lib/features/cycle_tracking/presentation/widgets/cycle_calendar.dart` (Semantics section)
- `lib/core/widgets/common_widgets.dart` (targeted, `StatCard`/`NiswahListTile` padding)
- `MANIFEST.md`, `test/parity_insights_test.dart` (golden-test structure)

### Partially reviewed
- All 20 `IconButton(` call sites (context-checked for `tooltip:`/labels, not full surrounding screen logic)
- `lib/features/onboarding/presentation/screens/onboarding_screen.dart`, `sign_in_screen.dart`, `profile_screen.dart`, `pregnancy_tracking_screen.dart`, `dr_niswah_chat_screen.dart`, `dream_interpreter_screen.dart`, `community_board_screen.dart`, `cycle_tracking_screen.dart`, `ghusl_guide_screen.dart`, `guided_journeys_screen.dart` — icon-button and RTL-pattern context only

### Structurally scanned only (grep-level)
- Remaining ~130 Dart files under `lib/` — scanned via targeted `grep` for `Semantics(`, `IconButton(`, `textScaleFactor`/`TextScaler`, `EdgeInsets.only(left/right`, `AnimationController(`, `disableAnimationsOf` — not individually read line-by-line

### Could not inspect
- **Any live rendering, TalkBack/VoiceOver output, keyboard-only traversal, browser/OS zoom behavior, or actual touch-hit-testing** — no device/emulator/screen-reader tooling was available in this environment. Phase 2B (Controlled Interaction Validation) is **not executed** in this audit; every finding below is Phase 2A (Static Verification) only.
- Image/icon `alt`-equivalent (`semanticLabel` on `Image` widgets) sweep — not performed this pass.
- Keyboard/external-keyboard focus order — not applicable data found; not independently verified as N/A vs. untested.
- Full form inventory beyond `FORM-001`/`FORM-002` (sign-in, onboarding validation depth) — not traced to the same depth.

### Actions performed

| Action | Purpose | Result |
|---|---|---|
| `grep -rn "Semantics("` etc. across `lib/` | Map semantic-annotation coverage | 9 instances / 5 files found |
| `grep -rn "IconButton("` + per-call-site context read | Find icon-only controls lacking accessible names | 20 found, 5 with `tooltip:` |
| Manual WCAG contrast calculation (relative-luminance formula) for `AppColors` | Assess semantic-color contrast without live rendering | See AU-003 |
| Read `_PhaseNode`/`_PhaseTimeline` full widget tree | Assess the dashboard's complex custom "stepper" visualization named in the task brief | Confirmed no `Semantics` grouping |
| Read `cycle_log_form_sheet.dart` symptom-severity chip logic | Assess color-only dependency + touch-target sizing | Confirmed both |
| Compared `cycle_log_form_sheet.dart` vs `community_composer_sheet.dart` error/validation patterns | Assess form accessibility consistency | Confirmed divergent patterns |
| Counted screen files vs. golden-test files | Quantify RTL/localization test coverage | 6/25 (24%) |
| `grep` for hardcoded RTL-risk patterns (`EdgeInsets.only(left/right`, `Positioned(left:`, `Icons.arrow_back`) | Assess RTL architecture risk | Found 1 confirmed shared-widget bug (AU-008) |

### Actions deliberately avoided

| Action avoided | Reason |
|---|---|
| Modifying/adding `Semantics`, `tooltip`, or any accessibility attribute | Auditor-only mandate — findings only, no code changes |
| Redesigning any widget or changing copy/color tokens | Auditor-only mandate |
| Claiming live screen-reader-verified PASS on any journey | No AT tooling available — would misrepresent confidence level |
| Spawning sub-agents | Explicitly instructed not to |

---

## 15. Discovery Exit Gate

- [x] User roles identified.
- [x] Critical journeys identified.
- [x] Critical screens inventoried.
- [x] Interaction patterns mapped.
- [x] Supported devices/platforms identified (with explicit UNKNOWN for tablet/OS-version matrix).
- [x] Localization/RTL requirements identified.
- [x] Forms inventoried (2 of ~4 forms to full depth; remainder listed as partially reviewed).
- [x] Critical UI states identified (cross-referenced to Functional QA rather than re-derived).
- [x] Accessibility mechanisms identified.
- [x] Unknown/unreviewed UX areas listed (§14 "Could not inspect").

Phase 1 Discovery is complete to Static/Documentation-tier depth. Phase 2B could not be attempted; this is carried forward explicitly into Phase 2A findings and the final report.
