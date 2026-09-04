# Accessibility & UX Audit — Phase 3: Remediation Plan

> ⚠️ **This remediation plan is PROPOSED and NOT IMPLEMENTED.** No code has been changed as part of this audit. It requires technical/product/design review and, where noted, live accessibility (screen-reader/device) verification before anything below may be described as fixed. This auditor acted in an audit-only capacity and made no application-code changes.

| Field | Value |
|---|---|
| System | Niswah |
| Phase | 3 — Remediation Design |
| Audit date | 2026-09-04 |
| Status | PROPOSED — NOT IMPLEMENTED |

---

## Root-Cause Map

| Finding | Symptom | Root cause | Confidence | Related findings | Remediation phase |
|---|---|---|---|---|---|
| `AU-001` | 15/20 icon buttons unlabeled | No shared accessible `IconButton`/close-button primitive; each screen hand-rolls its own, and the correct `tooltip:`/`Semantics` pattern is applied inconsistently even within single files (e.g. `dr_niswah_chat_screen.dart` gets it right at lines 638/649 but not 476/560) | CONFIRMED | AU-002 (same root pattern: custom widgets built ad hoc without a shared accessible-by-default primitive) | R1 |
| `AU-002` | Phase-timeline nodes unlabeled | Same as AU-001 — `_PhaseNode` was built as a pure visual widget with no accessibility pass | CONFIRMED | AU-001 | R1 |
| `AU-003` | `tahara`/`nifas` fail AA text contrast | Color palette (`app_theme.dart`) was chosen to match the web reference design's visual palette without a contrast check against WCAG AA for text usage | CONFIRMED | — | R2 |
| `AU-004` | Severity color-only + small touch target | `_symptomsCard`'s chip widget was designed as a compact visual "heat" indicator without an accessibility pass; padding was sized for visual density, not touch-target minimums | CONFIRMED | AU-001/002 (same "no accessibility pass on custom widget" root cause) | R3 |
| `AU-005` | SnackBar-only error handling in cycle-log form | `cycle_log_form_sheet.dart` predates or was built independently of the `Form`/`validator` pattern later used correctly in `community_composer_sheet.dart` — no shared form-validation component exists to enforce consistency | CONFIRMED | — | R4 |
| `AU-006` | Fixed-dimension widgets not scale-proofed | Same root cause as AU-001/002/004 — custom pixel-perfect widgets built to match a fixed 390×844 web reference capture, without a pass for OS text-scale variance | CONFIRMED | AU-001, AU-002, AU-004 | R5 |
| `AU-007` | No ARB catalog; 24% RTL test coverage | Deliberate architectural choice (per-screen `_l`/`_tr` helpers) made early in the project, plus golden-test suite built incrementally and never extended past the 5-6 "MANIFEST.md" priority screens | CONFIRMED | AU-008 | R6 |
| `AU-008` | RTL padding bug in `common_widgets.dart` | Direct instance of AU-007's root cause: no lint/CI rule catches physical `EdgeInsets.only(left/right)` in a codebase that has `Directionality` as a first-class requirement | CONFIRMED | AU-007 | R6 |
| `AU-009` | No live AT/device testing performed | Environmental — no device/emulator/screen-reader tooling was available in this audit session | N/A (scope constraint, not a code defect) | AU-001 | R7 |
| `AU-010` | No `ExcludeSemantics` anywhere | Same root cause as AU-001/002 — no accessibility pass on custom decorative widgets | 🟨 Likely | AU-001, AU-002 | R1 (low priority) |

---

## Remediation Principles Applied

| Principle | Application here |
|---|---|
| Native/semantic first | Prefer Flutter's built-in `tooltip:` on `IconButton` over ad hoc `Semantics` wrapping wherever the control is a true `IconButton` — it's cheaper and handles both accessible name and visible-tooltip-on-long-press for free |
| One interaction pattern | R1 proposes a single shared `NiswahIconButton`/`NiswahCloseButton` primitive so future screens can't repeat AU-001's inconsistency |
| Make state explicit | R3 proposes adding a visible severity indicator (text/number), not just relying on remediated color contrast |
| Preserve user work | R4's `Form`/`validator` migration must preserve the "don't pop the sheet on error" behavior already correct in the current code |
| Accessible by default | R1's shared primitive becomes the default for all new icon-only controls |
| Responsive by design | R5's `FittedBox` wrapping is scoped to the specific fixed-dimension widgets identified, not a blanket change |
| Localize intentionally | R6 proposes both a lint rule (prevent recurrence) and a scoped fix (the one confirmed instance) rather than a full ARB migration, which is out of proportion to the confirmed defect count |
| Test real interactions | R7 is a process recommendation: live AT verification before or immediately after this app is submitted to app-store review |

---

## Remediation Phase Table

| # | Action | Findings closed | Components/screens | Copy impact | Design-system impact | Platform impact | Risk | Rollback | Retest |
|---|---|---|---|---|---|---|---|---|---|
| **R1** | Add `tooltip:`/`Semantics(label:)` to every unlabeled icon-only control; introduce one shared accessible close-button/icon-button primitive for future use; wrap purely decorative leaf nodes (e.g. `_PhaseNode`'s "current" marker dot) in `ExcludeSemantics` | AU-001, AU-002, AU-010 | `sign_in_screen.dart`, `profile_screen.dart`, `guided_journeys_screen.dart`, `pregnancy_tracking_screen.dart`, `dr_niswah_chat_screen.dart`, `dream_interpreter_screen.dart`, `cycle_tracking_screen.dart`, `onboarding_screen.dart`, `ghusl_guide_screen.dart`, `cycle_log_form_sheet.dart`, `dashboard_screen.dart` (`_PhaseNode`) | Adds ~15-20 new EN+AR tooltip strings (each a 1-3 word label, e.g. "Close"/"إغلاق" — several already exist elsewhere in the codebase and should be reused verbatim for consistency rather than retranslated per-site) | Establishes a reusable accessible icon-button pattern — recommend promoting to `common_widgets.dart` | iOS + Android (VoiceOver/TalkBack) | Low — purely additive, no visual change (tooltip text doesn't render visibly unless long-pressed) | Trivial — revert the added properties | Static: re-grep for `IconButton(` without `tooltip:`. Live: VoiceOver + TalkBack pass over every remediated screen confirming each control announces a meaningful name (Phase 2B) |
| **R2** | Either (a) darken `tahara`/`nifas` slightly to clear 4.5:1 against their actual usage backgrounds, keeping hue recognizable, or (b) restrict the existing colors to large-text/icon/UI-component contexts only (≥18pt or bold ≥14pt) and introduce a separate, darker "text-safe" variant for small-text usage like `dashboard_screen.dart:1858`'s 9px label | AU-003 | `app_theme.dart` (`AppColors`), all `Text(color: AppColors.tahara/nifas)` sites | None (color-only change) | Direct `AppColors` palette change — **requires design sign-off**, since this affects brand-adjacent semantic colors shown throughout the golden-tested screens; will likely require re-capturing affected goldens | iOS + Android | Medium — visual change to a recognizable brand color; must be reviewed against the web reference (`src/`) design intent before altering, since `src/` is the design source of truth per project convention | Revert to original hex values | Re-run manual contrast calculation against every confirmed text-usage site; re-run golden tests for Dashboard/Insights/Cycle-tracking (screens using these colors) |
| **R3** | Add a visible non-color severity indicator to the symptom chips (e.g. a small numeral badge "1/2/3" or filled-dot-count, in addition to the existing color shift) and increase chip vertical padding so total rendered height reaches ≥44dp | AU-004 | `cycle_log_form_sheet.dart` (`_symptomsCard`) | Possibly a new short label per severity level if word-based rather than numeral-based | Localized change to one widget — no shared-component impact since this chip is local to this file | iOS + Android | Low-Medium — layout change may shift wrap/row heights on the symptoms grid; needs visual re-check | Revert padding/add-back removed indicator | Live: confirm color-vision-deficiency simulation renders the level distinguishably; measure rendered touch-target height on-device |
| **R4** | Migrate `cycle_log_form_sheet.dart` to Flutter's `Form`/`GlobalKey<FormState>` + `TextFormField.validator` pattern already used correctly in `community_composer_sheet.dart`, keeping the SnackBar for save-success/save-failure (network/server) messages but adding field-level validation for anything that should block submission (if any fields are in fact required — needs product confirmation, since no required-field enforcement was found in the current code at all) | AU-005 | `cycle_log_form_sheet.dart` | None | Should reuse the same validator-message copy conventions established in `community_composer_sheet.dart` | iOS + Android | Low — additive validation logic; must confirm no currently-optional field becomes wrongly blocking | Revert to prior try/catch+SnackBar-only flow | Live: submit the form with each field left empty/invalid on both platforms; confirm error is announced and associated with the right field |
| **R5** | Wrap `_PhaseNode`'s `value`/`unit` text in `FittedBox(fit: BoxFit.scaleDown)` (matching the existing "YOU ARE HERE" treatment in the same widget); review the cycle-ring center headline/subtitle for the same treatment; raise the 5px base `unit` font size to a more legible minimum if design allows | AU-006 | `dashboard_screen.dart` (`_PhaseNode`, `_AnimatedCycleRing` center content) | None | Local widget change | iOS + Android | Low | Revert `FittedBox` wrapper | Live: set OS text scale to its maximum (iOS Dynamic Type "AX5" / Android "Largest") and confirm no clipping/overlap in the ring and phase timeline (Phase 2B §56) |
| **R6** | (a) Fix the confirmed `common_widgets.dart:217` (`StatCard`) padding to `EdgeInsetsDirectional.only(start: 8.0)`; also fix the dead-code `NiswahListTile:271` for consistency even though currently unused; (b) add a lightweight CI/lint check (e.g. a `grep`-based pre-commit hook or a custom `analysis_options.yaml` rule) that flags new `EdgeInsets.only(left:`/`right:` additions outside explicitly-reviewed exceptions, to prevent recurrence; (c) **separately and at larger scope** (recommend as its own follow-up project, not bundled into this pre-launch remediation): evaluate migrating to Flutter's ARB/`gen-l10n` system to establish one translation source of truth, and expand golden-test coverage to the remaining 19 untested screens, prioritized by journey criticality | AU-007, AU-008 | `common_widgets.dart`; CI config; (c) is repo-wide | (c) requires re-auditing every existing `_l`/`_tr` string pair for consistency across files — a translation-QA pass, likely warranting native-Arabic-speaker review, out of scope for a code-only remediation | (a)/(b) local; (c) is a significant architecture initiative | iOS + Android | (a) Low. (c) High — full localization-system migration is a multi-week effort and should be scoped/prioritized separately from pre-launch blockers | (a) trivial revert. (c) N/A — a phased migration, not a single revertible commit | (a) Re-render Insights screen in Arabic and visually confirm gap placement. (c) Re-run full golden suite after any catalog migration |
| **R7** | Perform a live Phase 2B pass: VoiceOver on iOS + TalkBack on Android, at minimum for the critical journeys UXJ-001 through UXJ-005, before or immediately after R1-R5 land; re-run at 200% OS text scale for UXJ-003/UXJ-008; re-run in Arabic for UXJ-007 | AU-009 (resolves the "critical unknown" status, does not itself fix any defect) | All critical-journey screens | None | None | iOS + Android, real devices strongly preferred over simulator for AT fidelity | N/A — this is a test activity, not a code change | N/A | This *is* the retest — see Controlled Interaction Matrix template §51 |

---

## Shared Component Remediation Requirements

- **R1** touches many screens individually because there is currently no shared accessible icon-button component. Recommend, as part of R1, actually introducing `NiswahIconButton` (or equivalent) into `common_widgets.dart` so it becomes the default going forward — this converts a one-time fix into a structural improvement, consistent with template §72's "fix shared primitive rather than every screen independently" guidance. All 15+ current unlabeled sites should be migrated to it rather than patched individually with raw `tooltip:` additions, if effort allows; if not, the raw-`tooltip:` patch is an acceptable interim step.
- **R6(a)** is a genuine shared-primitive fix (`StatCard` in `common_widgets.dart`) — identify all current/future consumers (currently only `insights_screen.dart`) before and after the fix to validate no regression.

---

## Content Remediation Requirements

- **R1**: new tooltip copy needed for ~15-20 sites. Recommend reusing existing strings already present elsewhere in the codebase verbatim (e.g., "Close"/"إغلاق" already exists in `community_composer_sheet.dart` and `guided_journeys_screen.dart`'s visible copy pattern; "History"/"السجل" and "New chat"/"محادثة جديدة" already exist in `dr_niswah_chat_screen.dart`) rather than inventing new phrasing, to avoid adding to the localization-inconsistency risk flagged in AU-007. No consent/destructive-action wording is affected — legal/product review not required for this specific content change.
- **R3**: if a text/numeral severity indicator is chosen, confirm the exact wording/format (numeral vs. word) with product before implementation, since it is user-facing on every cycle-log entry.
- **R4**: reuse `community_composer_sheet.dart`'s existing validator-message tone/format for any new required-field messages in the cycle-log form, for consistency.

---

## Remediation Exit Gate

- [x] Root cause identified for every finding (see Root-Cause Map).
- [x] Shared component impact understood (R1, R6).
- [x] Product/design decision identified where needed (R2 color change, R3 wording, R4 required-field policy — all flagged as needing owner sign-off, not auditor-decided).
- [x] Localization/RTL impact reviewed (R6).
- [x] Accessibility impact reviewed (all items are accessibility-motivated).
- [x] Regression interaction tests defined per item (see "Retest" column).
- [x] No cosmetic-only patch proposed for a structural issue — R1/R6(b) explicitly propose the shared-primitive/lint-rule structural fix, not just the one-off patches, and R6(c) is explicitly carved out as a separate larger initiative rather than being falsely bundled into a "quick fix."
