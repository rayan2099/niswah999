# Accessibility & UX Audit — Reusable Master Template

> **Purpose:** A reusable production-readiness audit for verifying that an application is accessible, understandable, operable, responsive, and usable across supported users, devices, interaction modes, and critical journeys before launch.
>
> This template is designed for applications built manually or with AI coding agents. It is intentionally evidence-driven: **do not mark accessibility or UX PASS because the interface looks polished, because a component library claims accessibility, or because one happy-path journey feels intuitive. Critical behavior must be verified through structured inspection and controlled interaction tests.**
>
> **Important boundary:** This audit can identify accessibility and usability gaps and can assess implementation against documented product expectations and accessibility standards used by the project. It must not claim formal legal accessibility compliance unless the applicable standard, jurisdiction, testing scope, and authorized review process have been explicitly defined.

---

# 0. Operating Rules

## 0.1 Audit objective

Determine whether the current user experience is production-ready by verifying:

- Critical journeys are understandable and completable.
- Important actions are discoverable.
- Users can recover from mistakes.
- Forms communicate requirements and validation clearly.
- Loading, empty, error, permission-denied, offline, and success states are understandable.
- Keyboard navigation works where applicable.
- Focus order and focus visibility are logical.
- Screen-reader semantics are meaningful where applicable.
- Images/icons/control labels are accessible.
- Text and interactive elements have sufficient visual clarity.
- Touch targets are usable on supported mobile devices.
- Responsive layouts do not hide or break critical functionality.
- Content remains usable at larger text/zoom settings where applicable.
- Motion/animation does not unnecessarily block use.
- Language, localization, RTL/LTR layout, dates, times, numbers, and currencies are consistent.
- Critical workflows do not depend solely on color, hover, gesture, sound, or visual position.
- Error messages are actionable.
- Confirmation and destructive actions are appropriately designed.
- User state is preserved when recoverable errors occur.
- Users are not trapped in modal/dialog/navigation states.
- AI-generated UI has not introduced inaccessible custom controls, inconsistent interaction patterns, misleading buttons, hidden actions, or visually complete but non-functional states.

## 0.2 Non-goals

This audit does **not** replace:

- Functional QA.
- Security audit.
- Privacy/legal review.
- Formal usability study with representative research participants.
- Formal accessibility certification.
- Product-market-fit research.
- Visual brand review.
- Performance/load testing.

Where findings overlap those areas, cross-reference the specialist audit.

---

# 1. Mandatory Methodology

Use these stages in order:

| Stage | Name | What happens | Required output |
|---|---|---|---|
| 1 | **Discovery** | Map users, supported devices, critical journeys, UI states, interaction patterns, accessibility mechanisms, localization, and design conventions | UX/accessibility map |
| 2A | **Static Verification** | Inspect implementation and UI structure for accessibility/usability risks | Evidence matrix |
| 2B | **Controlled Interaction Validation** | Execute critical journeys using relevant keyboard, screen-reader, zoom, mobile, responsive, and failure-state tests | PASS / FAIL / INCONCLUSIVE matrix |
| 3 | **Remediation Design** | Design root-cause fixes — **design only unless separately authorized** | Remediation plan |
| Final | **Production Readiness Report** | Consolidate evidence and issue launch recommendation | GO / CONDITIONAL GO / NO-GO |

### Golden rule

**Visual polish is not proof of usability or accessibility.**

Every material conclusion must be tied to:

- a critical user journey,
- a supported interaction method,
- an explicit expected behavior,
- and observed evidence.

---

# 2. Report Header

Use this header in every phase report:

| Field | Value |
|---|---|
| System | `{SYSTEM_NAME}` |
| Repository | `{REPOSITORY_NAME}` |
| Branch | `{BRANCH}` |
| Commit / Version | `{COMMIT_OR_VERSION}` |
| Phase | `{PHASE_NAME}` |
| Audit date | `{DATE}` |
| Environment | `{Local / Dev / Staging / Production}` |
| Platform(s) | `{Web / iOS / Android / Desktop / etc.}` |
| Supported languages | `{LANGUAGES}` |
| RTL support | `{YES / NO / N/A}` |
| Accessibility target/standard | `{WCAG VERSION/LEVEL / PROJECT STANDARD / NOT DEFINED}` |
| Restrictions | `{WHAT_WAS_NOT_DONE}` |
| Report created | `{THIS_FILENAME}` |

---

# 3. Evidence and Confidence Key

| Symbol | Meaning |
|---|---|
| 🟥 **Confirmed by Interaction Test** | Proven through actual user-interface interaction in an approved environment |
| 🟧 **Confirmed by Code / UI Structure** | Proven from implementation, semantics, styles, or component structure |
| 🟨 **Likely** | Strong inference but direct interaction test incomplete |
| 🟦 **Requires Controlled Interaction Test** | Must be tested before conclusion |
| ⬜ **Not Applicable / False Positive** | Does not apply or was disproven |

For every material finding include:

- Finding ID.
- Screen/journey.
- User/role.
- Platform/device.
- Interaction mode.
- Expected behavior.
- Actual behavior.
- Evidence.
- Severity.
- Launch-blocker status.
- Confidence.

---

# 4. Severity Model

| Level | Classification | Accessibility / UX meaning | Launch treatment |
|---|---|---|---|
| **AU0** | Critical | A core journey is impossible for a meaningful supported user group, destructive action is dangerously misleading, or the interface can cause severe irreversible error | **Mandatory NO-GO** |
| **AU1** | High | Core task is materially blocked, inaccessible, confusing, or error-prone with no safe workaround | **Pre-launch blocker** |
| **AU2** | Medium | Important usability/accessibility issue with a bounded workaround | Explicit acceptance required |
| **AU3** | Low | Minor inconsistency or localized friction | Backlog acceptable |
| **AU4** | Observation | Improvement opportunity | Backlog |

## 4.1 Severity factors

Evaluate:

- Criticality of journey.
- Number/types of users affected.
- Whether workaround exists.
- Whether user can recover.
- Whether issue causes irreversible action.
- Whether issue is discoverability vs true blocking.
- Device/platform prevalence.
- Repetition frequency.
- Cognitive complexity.
- Accessibility impact.
- Localization/RTL impact.
- Whether misleading feedback can create operational harm.

---

# 5. Standards / Legal Boundary

Classify each standards-related conclusion as:

| Classification | Meaning |
|---|---|
| **TECHNICAL ACCESSIBILITY FINDING** | Can be evaluated from implementation/interaction |
| **PRODUCT UX FINDING** | Depends on product-design expectations |
| **FORMAL STANDARD REVIEW REQUIRED** | Requires explicit testing against a named standard |
| **LEGAL INTERPRETATION REQUIRED** | Requires legal/accessibility counsel or authorized owner |

Do not claim legal compliance merely from automated scans or partial manual review.

---

# PHASE 1 — DISCOVERY

# 6. Objective

Understand who uses the interface, how they interact with it, and what must remain usable.

### Mandatory restrictions

During discovery:

- Prefer read-only review.
- Do not redesign UI.
- Do not rewrite components.
- Do not change copy.
- Do not alter color tokens.
- Do not add accessibility attributes while auditing.
- Do not treat framework defaults as verified behavior.

---

# 7. User / Role Inventory

| User ID | Role / User type | Primary goals | Critical journeys | Accessibility considerations |
|---|---|---|---|---|
| `USR-001` | `{ROLE}` | `{GOALS}` | `{JOURNEYS}` | `{}` |

Include:

- guest,
- authenticated user,
- admin/staff,
- provider/driver,
- customer,
- user with limited permissions,
- mobile user,
- keyboard-only user,
- screen-reader user where applicable,
- low-vision user,
- user with temporary impairment,
- RTL-language user where applicable.

---

# 8. Critical Journey Inventory

Use stable IDs:

- `UXJ-001`, `UXJ-002`, ...

| Journey ID | Journey | Role | Platform | Criticality | Key interaction risks |
|---|---|---|---|---|---|
| `UXJ-001` | `{JOURNEY}` | `{ROLE}` | `{}` | `{Critical/High/Normal}` | `{}` |

Typical journeys:

- sign up,
- login,
- reset password,
- onboarding,
- search,
- checkout,
- booking,
- order creation,
- upload,
- payment,
- cancellation,
- admin approval,
- messaging,
- account deletion.

---

# 9. Screen / Route Inventory

| Screen ID | Route / Screen | Purpose | Primary action | Secondary actions | Critical states |
|---|---|---|---|---|---|
| `SCR-001` | `{}` | `{}` | `{}` | `{}` | `{Loading/Error/Empty/etc.}` |

---

# 10. Interaction Pattern Inventory

Document:

- buttons,
- links,
- forms,
- dropdowns,
- tabs,
- accordions,
- modals,
- drawers,
- menus,
- tooltips,
- drag-and-drop,
- swipe/gesture,
- hover interactions,
- keyboard shortcuts,
- date pickers,
- file uploads,
- maps,
- custom controls.

Flag custom controls that replace native/standard patterns.

---

# 11. Design System / Component Inventory

Document:

- UI library.
- design system.
- component library.
- typography.
- spacing.
- color tokens.
- focus styles.
- form components.
- alert/toast components.
- modal/dialog components.
- accessibility primitives.

Flag duplicate competing component implementations.

---

# 12. Supported Device / Browser Matrix

| Platform | Browser/OS | Screen class | Required? | Notes |
|---|---|---|---|---|
| `{}` | `{}` | `{Mobile/Tablet/Desktop}` | `{YES/NO}` | `{}` |

Do not claim broad support if product owner has not defined supported targets.

---

# 13. Localization Inventory

Document:

- supported languages,
- default language,
- locale selection,
- RTL support,
- translated strings,
- fallback language,
- date formats,
- time formats,
- currency,
- number formatting,
- pluralization.

---

# 14. RTL Inventory

Where relevant verify design support for:

- direction,
- alignment,
- icon direction,
- arrows,
- chevrons,
- progress indicators,
- carousels,
- tables,
- breadcrumb direction,
- input alignment,
- mixed Arabic/English content,
- phone/email fields,
- numbers.

---

# 15. Form Inventory

| Form ID | Form | Fields | Required fields | Validation method | Destructive/financial? |
|---|---|---|---|---|---|
| `FORM-001` | `{}` | `{}` | `{}` | `{}` | `{YES/NO}` |

---

# 16. State Inventory

For every critical screen identify:

- initial,
- loading,
- success,
- empty,
- validation error,
- backend error,
- permission denied,
- offline,
- timeout,
- session expired,
- disabled,
- partial data,
- retry/recovery.

---

# 17. Content / Copy Inventory

Review:

- labels,
- headings,
- instructions,
- helper text,
- errors,
- confirmations,
- empty states,
- destructive-action warnings,
- success messages.

Flag placeholder/lorem/demo copy.

---

# 18. Accessibility Mechanism Inventory

Where applicable:

- semantic HTML/native controls,
- ARIA,
- labels,
- headings,
- landmarks,
- focus management,
- keyboard support,
- alt text,
- screen-reader announcements,
- reduced motion,
- text scaling,
- contrast tokens.

---

# 19. Discovery Execution Log

### Fully reviewed
`{AREAS}`

### Partially reviewed
`{AREAS}`

### Structurally scanned only
`{AREAS}`

### Could not inspect
`{AREAS + REASON}`

### Actions performed
| Action | Purpose | Result |
|---|---|---|

### Actions deliberately avoided
| Action avoided | Reason |
|---|---|

---

# 20. Discovery Exit Gate

Phase 1 passes only when:

- [ ] User roles identified.
- [ ] Critical journeys identified.
- [ ] Critical screens inventoried.
- [ ] Interaction patterns mapped.
- [ ] Supported devices/platforms identified.
- [ ] Localization/RTL requirements identified.
- [ ] Forms inventoried.
- [ ] Critical UI states identified.
- [ ] Accessibility mechanisms identified.
- [ ] Unknown/unreviewed UX areas listed.

---

# PHASE 2A — STATIC VERIFICATION

# 21. Objective

Inspect implementation for accessibility and UX risks before runtime interaction testing.

Use stable prefixes:

| Prefix | Category |
|---|---|
| `SEM-xx` | Semantics |
| `KEY-xx` | Keyboard |
| `FOCUS-xx` | Focus |
| `SR-xx` | Screen reader |
| `VIS-xx` | Visual clarity |
| `CONTR-xx` | Contrast |
| `TOUCH-xx` | Touch target |
| `FORM-xx` | Forms |
| `ERR-xx` | Error UX |
| `NAV-xx` | Navigation |
| `RESP-xx` | Responsive |
| `ZOOM-xx` | Zoom/text scaling |
| `MOTION-xx` | Motion |
| `STATE-xx` | Loading/empty/error states |
| `RTL-xx` | RTL |
| `LOC-xx` | Localization |
| `COPY-xx` | Copy/content |
| `DESTRUCT-xx` | Destructive actions |
| `COGN-xx` | Cognitive load |
| `AI-xx` | AI-agent-specific UX defects |

---

# 22. Semantic Structure Audit

Inspect:

- meaningful headings,
- heading hierarchy,
- landmarks,
- semantic buttons,
- semantic links,
- lists,
- tables,
- labels,
- fieldsets/groups,
- dialogs.

Flag clickable `<div>` / `<span>` patterns where semantic controls are appropriate.

---

# 23. Accessible Name Audit

Verify interactive elements have meaningful accessible names.

Examples:

- icon-only buttons,
- close buttons,
- menu buttons,
- search,
- floating actions,
- social icons,
- controls inside tables.

Flag duplicated ambiguous labels like several buttons all named `"Edit"` without useful context where context is lost.

---

# 24. Keyboard Audit

Inspect:

- tab reachability,
- logical order,
- Enter/Space activation,
- Escape handling,
- menu navigation,
- dialog focus trap,
- no keyboard trap,
- skip links where needed,
- visible focus.

---

# 25. Focus Management Audit

Verify focus behavior after:

- route change,
- modal open,
- modal close,
- validation failure,
- form submission,
- deleting item,
- dynamic content load,
- toast/error.

---

# 26. Screen Reader Audit

Inspect:

- meaningful order,
- labels,
- status announcements,
- error announcements,
- expanded/collapsed state,
- selected state,
- modal semantics,
- table headers,
- decorative images hidden.

---

# 27. Visual Contrast Audit

Review:

- body text,
- secondary text,
- buttons,
- links,
- form borders,
- disabled states,
- focus indicators,
- error/success states,
- charts where applicable.

If a formal target is defined, use it.

Do not claim formal standard conformance from subjective inspection alone.

---

# 28. Color Dependency Audit

Verify critical meaning does not rely only on color.

Examples:

- validation,
- status,
- selected state,
- chart meaning,
- availability,
- required fields.

---

# 29. Touch Target Audit

Inspect mobile/touch controls for:

- target size,
- spacing,
- overlap,
- edge placement,
- accidental activation risk.

Critical actions should not be difficult to tap.

---

# 30. Form UX Audit

Verify:

- visible labels,
- required fields clear,
- input type appropriate,
- autocomplete where appropriate,
- helper text useful,
- errors near fields,
- errors understandable,
- valid input preserved,
- server errors surfaced,
- submit state clear,
- duplicate submission prevented.

---

# 31. Validation Message Audit

Error messages should answer:

- What is wrong?
- Where?
- How can user fix it?

Flag messages like:

- `"Invalid input"`
- `"Error"`
- `"Something went wrong"`

when more actionable information is safely available.

---

# 32. Destructive Action Audit

For actions such as:

- delete account,
- delete record,
- cancel booking,
- refund,
- remove payment method,
- revoke access,

verify:

- intent is clear,
- destructive action visually distinguishable,
- confirmation appropriate to impact,
- user knows consequence,
- undo/restore exists where appropriate,
- success/failure is clear.

---

# 33. Navigation Audit

Verify:

- current location understandable,
- back behavior predictable,
- breadcrumbs where appropriate,
- navigation labels consistent,
- deep links land correctly,
- protected route redirects understandable,
- no dead ends.

---

# 34. Responsive Layout Audit

Inspect:

- mobile,
- tablet,
- desktop,
- narrow width,
- landscape where relevant.

Flag:

- hidden primary action,
- horizontal overflow,
- overlapping content,
- clipped text,
- unusable tables,
- modal larger than viewport,
- keyboard covering critical mobile input.

---

# 35. Zoom / Text Scaling Audit

Where platform supports it:

- browser zoom,
- OS font scaling,
- dynamic type,
- large text.

Verify content remains usable without losing critical controls.

---

# 36. Motion Audit

Inspect:

- autoplay animation,
- parallax,
- flashing,
- long transitions,
- motion required for understanding,
- reduced-motion preference.

---

# 37. Loading State Audit

Verify:

- user knows work is happening,
- primary action cannot unintentionally duplicate,
- indefinite loading has timeout/error path,
- skeletons do not imply false data,
- progress shown for long operations where useful.

---

# 38. Empty State Audit

Empty state should explain:

- why empty,
- what user can do next,
- whether this is normal or error.

---

# 39. Error State Audit

Verify:

- clear failure,
- actionable retry,
- preserved input,
- no false success,
- support/reference ID where useful,
- no raw technical error exposed.

---

# 40. Offline / Connectivity UX Audit

Where applicable:

- offline state visible,
- actions disabled or queued intentionally,
- retry clear,
- unsaved work preserved where possible,
- user knows whether action completed.

---

# 41. Session Expiry UX Audit

Verify:

- user understands session expired,
- re-authentication possible,
- unsaved work handled appropriately,
- no confusing permission error.

---

# 42. Content Clarity Audit

Inspect:

- jargon,
- ambiguous labels,
- inconsistent terminology,
- overly long instructions,
- misleading CTA text,
- duplicate names for same concept.

---

# 43. Cognitive Load Audit

Look for:

- too many simultaneous choices,
- unnecessary fields,
- long forms without grouping,
- multiple primary actions,
- unclear hierarchy,
- dense dashboards,
- hidden dependencies between steps.

Do not convert design preference into a severity finding without user/task impact.

---

# 44. Localization Audit

Verify:

- no untranslated strings,
- no concatenated sentence fragments that break translation,
- date/time localized,
- numbers localized,
- currency correct,
- pluralization,
- text expansion tolerance,
- language persists.

---

# 45. RTL Audit

For RTL languages verify:

- layout mirrors appropriately,
- text alignment intentional,
- navigation direction correct,
- arrows/chevrons correct,
- tables readable,
- mixed LTR fields remain sensible,
- icons with directional meaning flip appropriately.

---

# 46. AI-Agent-Specific Accessibility / UX Audit

Mandatory when AI agents were used.

Actively search for:

## 46.1 Visually complete but unusable controls

- button has no handler,
- disabled action without explanation,
- fake link,
- hover-only interaction.

## 46.2 Custom inaccessible controls

- custom dropdown,
- custom checkbox,
- clickable div,
- custom modal,
- custom tabs with no keyboard semantics.

## 46.3 Inconsistent patterns

- different modal behavior across features,
- different form validation styles,
- duplicated button components,
- conflicting loading patterns.

## 46.4 Placeholder UX

- TODO copy,
- lorem ipsum,
- `"Coming soon"` on production path,
- generic `"Error"`.

## 46.5 Bad focus behavior

- modal opens without focus,
- focus disappears,
- route change leaves focus deep in old DOM.

## 46.6 Hardcoded layout assumptions

- fixed pixel widths,
- absolute positioning,
- desktop-only dimensions,
- text clipping under translation.

## 46.7 RTL breakage

- CSS `left/right` hardcoded instead of logical properties where appropriate,
- directional icons wrong,
- nested LTR/RTL issues.

## 46.8 Duplicate success/error feedback

- toast + modal + inline message for same event,
- success shown before backend confirmation.

## 46.9 Excessive AI copy

- verbose instructions,
- repetitive labels,
- technical wording presented to ordinary users.

---

# 47. Static Verification Matrix

| Check ID | Category | Screen / Journey | Expected condition | Evidence | Result |
|---|---|---|---|---|---|
| `{ID}` | `{}` | `{}` | `{}` | `{}` | `{PASS/FAIL/INCONCLUSIVE}` |

---

# 48. Static Verification Exit Gate

Phase 2A passes only when:

- [ ] Semantics reviewed.
- [ ] Keyboard/focus risks reviewed.
- [ ] Screen-reader semantics reviewed.
- [ ] Visual clarity/contrast reviewed.
- [ ] Forms/error UX reviewed.
- [ ] Navigation reviewed.
- [ ] Responsive behavior reviewed.
- [ ] zoom/text-scaling reviewed where applicable.
- [ ] loading/empty/error states reviewed.
- [ ] localization/RTL reviewed where applicable.
- [ ] AI-generated UX risks reviewed.
- [ ] AU0/AU1 candidates have evidence.

---

# PHASE 2B — CONTROLLED INTERACTION VALIDATION

# 49. Objective

Prove critical UX/accessibility behavior through controlled interaction tests.

### Mandatory restrictions

- Use test/staging when actions modify state.
- Use synthetic users/data.
- Do not perform destructive actions against real accounts.
- Record device/browser/assistive technology.
- Do not claim screen-reader compatibility without actual testing where required.

---

# 50. Test Categories

| Prefix | Category |
|---|---|
| `UX-KEY-xx` | Keyboard |
| `UX-FOCUS-xx` | Focus |
| `UX-SR-xx` | Screen reader |
| `UX-FORM-xx` | Forms |
| `UX-ERR-xx` | Error recovery |
| `UX-RESP-xx` | Responsive |
| `UX-ZOOM-xx` | Zoom/text scaling |
| `UX-RTL-xx` | RTL |
| `UX-LOC-xx` | Localization |
| `UX-STATE-xx` | UI states |
| `UX-TOUCH-xx` | Touch |
| `UX-JOURNEY-xx` | Critical journey |

---

# 51. Controlled Interaction Matrix

| Test ID | Journey / Screen | Interaction mode | Device/browser | Expected result | Actual result | Evidence | Result |
|---|---|---|---|---|---|---|---|
| `{ID}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{PASS/FAIL/INCONCLUSIVE}` |

---

# 52. Keyboard-Only Test

For critical web journeys:

- enter page without mouse,
- traverse controls,
- operate primary actions,
- open/close modal,
- submit forms,
- recover from errors,
- complete journey.

Verify no trap and logical focus.

---

# 53. Screen Reader Test

Where required/available:

- verify page title/heading,
- landmarks,
- form labels,
- errors,
- buttons,
- state changes,
- modal announcements,
- success/error status.

Record screen-reader/platform used.

---

# 54. Focus Test

Verify:

- visible focus,
- focus moves into dialog,
- returns after close,
- validation sends/helps user reach error,
- route transition does not leave focus lost.

---

# 55. Responsive Test

Test supported widths/devices.

For each critical screen verify:

- content visible,
- no overflow,
- primary action accessible,
- navigation works,
- forms usable,
- dialogs fit.

---

# 56. Zoom / Text Scaling Test

Where applicable test defined scale/zoom levels.

Verify:

- no loss of content,
- no overlapping text,
- controls reachable,
- critical actions visible.

---

# 57. RTL Test

For supported RTL language:

- complete one or more critical journeys,
- inspect directionality,
- mixed-content fields,
- arrows/icons,
- dates/numbers,
- navigation.

---

# 58. Localization Test

Switch languages and verify:

- all critical strings translated,
- layout supports expansion,
- values formatted,
- selected language persists,
- no mixed-language surprises unless intentional.

---

# 59. Form Error Recovery Test

Submit:

- empty required fields,
- invalid formats,
- backend-rejected data,
- timeout/failure.

Verify:

- error understandable,
- input preserved,
- focus/announcement appropriate,
- correction possible,
- no duplicate action.

---

# 60. Loading / Timeout Test

Simulate slow operation.

Verify:

- user sees progress,
- action cannot accidentally duplicate,
- timeout/error path exists,
- retry is understandable.

---

# 61. Offline Test

Where supported/relevant:

- disconnect network,
- attempt action,
- restore network,
- verify clear completion/non-completion state.

---

# 62. Destructive Action Test

Using synthetic data:

- initiate destructive action,
- verify consequence clear,
- cancel,
- repeat,
- confirm,
- verify result and recovery option if designed.

---

# 63. Touch Test

On supported mobile device/emulation:

- primary controls easily tappable,
- no overlap,
- keyboard behavior acceptable,
- gestures have alternatives where necessary.

---

# 64. Controlled Validation Summary

| Metric | Count |
|---|---:|
| Interaction tests planned | `{}` |
| Executed | `{}` |
| PASS | `{}` |
| FAIL | `{}` |
| INCONCLUSIVE | `{}` |
| AU0 findings | `{}` |
| AU1 findings | `{}` |
| AU2 findings | `{}` |
| Formal-standard review items | `{}` |

---

# 65. Controlled Interaction Exit Gate

Phase 2B passes only when:

- [ ] Critical journeys tested on required platforms.
- [ ] Keyboard behavior tested where applicable.
- [ ] Focus behavior tested.
- [ ] Screen-reader behavior tested where required.
- [ ] Form/error recovery tested.
- [ ] Responsive layout tested.
- [ ] Zoom/text scaling tested where applicable.
- [ ] RTL/localization tested where applicable.
- [ ] Destructive actions tested.
- [ ] Every FAIL has finding ID.
- [ ] No critical accessibility claim is based only on component-library documentation.

---

# 66. Finding Register

| Finding ID | Category | Severity | Screen / Journey | Summary | Evidence | User impact | Launch blocker? | Status |
|---|---|---|---|---|---|---|---|---|
| `AU-001` | `{}` | `{AU0-AU4}` | `{}` | `{}` | `{}` | `{}` | `{YES/NO}` | `OPEN` |

---

# PHASE 3 — REMEDIATION DESIGN

# 67. Mandatory Notice

> ⚠️ **This remediation plan is proposed and not yet implemented.** It requires technical/product/design review and, where applicable, formal accessibility review. Nothing below should be described as fixed until implementation and controlled interaction validation are completed.

---

# 68. Objective

Design fixes around task completion, clarity, operability, and inclusive interaction.

Avoid cosmetic-only patches when the root problem is:

- bad semantics,
- confusing information architecture,
- inconsistent component behavior,
- inaccessible custom control,
- missing state,
- unclear copy,
- unsupported responsive pattern.

---

# 69. Root-Cause Map

| Finding | Symptom | Root cause | Confidence | Related findings | Remediation phase |
|---|---|---|---|---|---|
| `AU-001` | `{}` | `{}` | `{}` | `{}` | `R1` |

---

# 70. Remediation Principles

| Principle | Application |
|---|---|
| Native/semantic first | Prefer proven controls and semantics |
| One interaction pattern | Avoid competing behaviors for same component |
| Make state explicit | Loading, errors, empty, success |
| Preserve user work | Recoverable errors should not wipe input |
| Accessible by default | Keyboard/focus/screen-reader considerations built into shared components |
| Responsive by design | Critical actions remain available at supported widths |
| Localize intentionally | No hardcoded direction/format assumptions |
| Test real interactions | Visual inspection alone is insufficient |

---

# 71. Remediation Phase Table

| # | Action | Findings closed | Components/screens | Copy impact | Design-system impact | Platform impact | Risk | Rollback | Retest |
|---|---|---|---|---|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` |

---

# 72. Shared Component Remediation Requirements

If a problem appears in repeated components:

- fix shared primitive rather than every screen independently,
- identify all usages,
- validate regression risk,
- retest representative screens.

Examples:

- Button,
- Input,
- Select,
- Modal,
- Toast,
- Tabs,
- Table,
- Date picker.

---

# 73. Content Remediation Requirements

For copy changes document:

- original issue,
- new intent,
- affected languages,
- translation requirement,
- product/legal review if wording affects consent or destructive actions.

---

# 74. Remediation Exit Gate

Implementation-ready only when:

- [ ] Root cause identified.
- [ ] Shared component impact understood.
- [ ] Product/design decision identified where needed.
- [ ] Localization/RTL impact reviewed.
- [ ] Accessibility impact reviewed.
- [ ] Regression interaction tests defined.
- [ ] No cosmetic-only patch proposed for structural issue.

---

# FINAL — ACCESSIBILITY & UX PRODUCTION READINESS REPORT

# 75. Objective

Produce one release decision for the exact audited version.

---

# 76. Executive Summary

### System
`{SYSTEM_NAME}`

### Version / Commit
`{VERSION}`

### Platforms tested
`{PLATFORMS}`

### Critical journeys tested
`{PASS}/{EXECUTED}`

### Open findings
- AU0: `{COUNT}`
- AU1: `{COUNT}`
- AU2: `{COUNT}`
- AU3: `{COUNT}`

### Formal accessibility/legal review items
`{COUNT + SUMMARY}`

### Critical unknowns
`{COUNT + SUMMARY}`

### Final technical accessibility/UX recommendation
`{🟢 GO / 🟡 CONDITIONAL GO / 🔴 NO-GO}`

---

# 77. Launch Decision Rules

## 🟢 GO

Use **GO** only when:

- Zero open AU0.
- Zero open AU1.
- Critical journeys are completable on supported platforms.
- Critical keyboard/focus behavior works where applicable.
- Critical screen-reader behavior is acceptable where required.
- Forms and error recovery are understandable.
- Responsive layouts preserve critical functionality.
- Supported RTL/localized flows work where applicable.
- No destructive action is dangerously misleading.
- Critical loading/error/empty states are usable.
- No critical accessibility/UX unknown remains.

A GO does not equal formal legal accessibility certification unless separately documented.

## 🟡 CONDITIONAL GO

Use only when:

- Zero AU0.
- Zero launch-blocking AU1.
- Core journeys remain usable.
- Remaining issues are bounded AU2 findings.
- Release owner accepts residual risk.
- No critical interaction unknown remains.

## 🔴 NO-GO

Use if:

- Any AU0 remains.
- Core journey cannot be completed on a required platform.
- Keyboard/screen-reader users are blocked from a critical journey where those modes are in scope.
- Critical action is hidden/inaccessible on supported mobile layout.
- Form errors make completion effectively impossible.
- Destructive behavior is misleading or easy to trigger accidentally.
- RTL/localization breaks a critical supported journey.
- Critical UI state falsely communicates success/failure.
- Critical accessibility/UX behavior remains unknown.

---

# 78. Launch Gate Table

| Gate | Requirement | Evidence | Status |
|---|---|---|---|
| `LG-AU-01` | Zero open AU0 | `{REGISTER}` | `{PASS/FAIL}` |
| `LG-AU-02` | Zero launch-blocking AU1 | `{REGISTER}` | `{PASS/FAIL}` |
| `LG-AU-03` | Critical journeys usable | `{TESTS}` | `{PASS/FAIL}` |
| `LG-AU-04` | Keyboard/focus behavior verified | `{TESTS}` | `{PASS/FAIL/N/A}` |
| `LG-AU-05` | Screen-reader critical behavior verified | `{TESTS}` | `{PASS/FAIL/N/A}` |
| `LG-AU-06` | Forms/error recovery usable | `{TESTS}` | `{PASS/FAIL}` |
| `LG-AU-07` | Responsive layout verified | `{TESTS}` | `{PASS/FAIL}` |
| `LG-AU-08` | Zoom/text scaling verified | `{TESTS}` | `{PASS/FAIL/N/A}` |
| `LG-AU-09` | RTL/localization verified | `{TESTS}` | `{PASS/FAIL/N/A}` |
| `LG-AU-10` | Destructive actions safe | `{TESTS}` | `{PASS/FAIL}` |
| `LG-AU-11` | Critical states usable | `{TESTS}` | `{PASS/FAIL}` |
| `LG-AU-12` | No critical unknowns | `{OPEN ITEMS}` | `{PASS/FAIL}` |

Any mandatory FAIL prevents GO.

---

# 79. Formal Review Register

| Item ID | Topic | Why formal review required | Technical evidence available | Owner | Status |
|---|---|---|---|---|---|
| `FORMAL-AU-001` | `{TOPIC}` | `{REASON}` | `{}` | `{}` | `{OPEN/CLOSED}` |

Examples:

- formal WCAG conformance,
- jurisdiction-specific accessibility law,
- representative usability study,
- assistive-technology certification.

---

# 80. Residual Risk Register

| Risk ID | Finding | Severity | Probability | Production impact | Mitigation | Owner | Required before launch? |
|---|---|---|---|---|---|---|---|
| `RISK-AU-001` | `{REF}` | `{AU}` | `{LOW/MED/HIGH}` | `{}` | `{}` | `{}` | `{YES/NO}` |

---

# 81. Out-of-Scope / Not Verified

Explicitly list:

- assistive technology not available,
- certain browser/device not tested,
- formal WCAG conformance not performed,
- representative user research not performed,
- localization language not available,
- RTL language not supported,
- native mobile platform excluded,
- tablet layout excluded,
- color-vision simulation not performed,
- anything intentionally excluded.

Do not convert lack of access into PASS or FAIL.

---

# 82. Final One-Sentence Recommendation

### GO example

> Accessibility & UX technical recommendation: **GO for production** for `{VERSION}` because all mandatory accessibility/UX launch gates passed and all critical supported journeys are operable, understandable, and recoverable across the tested interaction modes and platforms.

### CONDITIONAL GO example

> Accessibility & UX technical recommendation: **CONDITIONAL GO** for `{VERSION}`, subject to explicit acceptance of the documented AU2 residual risks; all critical supported journeys remain usable.

### NO-GO example

> Accessibility & UX technical recommendation: **NO-GO** for `{VERSION}` until findings `{AU-xxx...}` are remediated and the associated keyboard, focus, form, responsive, localization, and critical-journey interaction tests pass.

---

# 83. Required Deliverables

A complete Accessibility & UX Audit should produce:

1. `01_ACCESSIBILITY_UX_DISCOVERY_REPORT.md`
2. `02_ACCESSIBILITY_UX_STATIC_VERIFICATION_REPORT.md`
3. `03_ACCESSIBILITY_UX_INTERACTION_TEST_REPORT.md`
4. `04_ACCESSIBILITY_UX_REMEDIATION_PLAN.md`
5. `05_ACCESSIBILITY_UX_PRODUCTION_READINESS_REPORT.md`

Optional supporting files:

- `CRITICAL_UI_JOURNEY_MAP.md`
- `FORM_INVENTORY.md`
- `RESPONSIVE_TEST_MATRIX.md`
- `KEYBOARD_FOCUS_MATRIX.md`
- `RTL_LOCALIZATION_MATRIX.md`
- `ACCESSIBILITY_UX_FINDINGS.csv`
- `FORMAL_REVIEW_REGISTER.md`

---

# 84. Instructions to the AI Auditor

When this template is supplied to an AI coding agent:

1. Read this template completely before starting.
2. Do not redesign or modify UI during Discovery or Verification.
3. Do not claim formal legal/accessibility compliance without the required scope and authorized review.
4. Do not assume a component library guarantees accessibility.
5. Do not assume visible labels equal accessible names.
6. Do not assume clickable elements work with keyboard.
7. Do not assume screen-reader behavior from DOM inspection alone when runtime testing is required.
8. Test critical flows on actual supported breakpoints/devices where feasible.
9. Inspect focus after dialogs, errors, and route changes.
10. Inspect all critical loading, empty, error, and success states.
11. Inspect destructive actions carefully.
12. Inspect localization and RTL behavior where supported.
13. Inspect AI-generated custom controls and duplicate component patterns.
14. Separate aesthetic preference from user-blocking usability issues.
15. Cite exact component/screen paths for static findings.
16. Preserve stable finding IDs.
17. Cross-reference Functional QA, Privacy, Performance, and Code Quality where relevant.
18. Retest interactions before marking findings Verified Closed.
19. End with exactly one technical recommendation: **GO, CONDITIONAL GO, or NO-GO**.
20. State formal accessibility/legal review status separately.

---

# 85. Completion Standard

This audit is complete only when an independent reviewer could answer:

- Who are the critical users?
- What are the critical UI journeys?
- Which platforms/devices are supported?
- Can users complete core tasks with the required interaction modes?
- Does keyboard/focus behavior work?
- Are screen-reader semantics adequate where in scope?
- Are forms and errors understandable?
- Do responsive layouts preserve critical actions?
- Does zoom/text scaling remain usable where applicable?
- Are RTL/localization flows correct where supported?
- Are loading/empty/error states understandable?
- Are destructive actions safe?
- What interaction tests were actually executed?
- What remains unknown?
- Which items require formal standards/legal review?
- What remediation is proposed versus verified?
- Can this exact version be launched from a **technical accessibility and UX** standpoint?

If those questions cannot be answered from the audit outputs, the audit is not complete.
