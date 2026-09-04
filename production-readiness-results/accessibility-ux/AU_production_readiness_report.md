# Accessibility & UX — Production Readiness Report

| Field | Value |
|---|---|
| System | Niswah |
| Repository | `/Users/rynadalsabh/Niswah` |
| Branch | `main` |
| Commit / Version | `13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f` |
| Phase | FINAL — Production Readiness Report |
| Audit date | 2026-09-04 |
| Environment | Local static repository review only |
| Platform(s) | iOS + Android (Flutter mobile app, `lib/`) |
| Supported languages | English, Arabic |
| RTL support | YES (structurally wired; verified only for 6/25 screens — see AU-007) |
| Accessibility target/standard | Not formally defined by the project. WCAG 2.1 AA used as a technical reference bar only — **this is not a formal compliance claim** (see §5/Standards Boundary below). |
| Restrictions | **No live device, emulator, or screen reader (TalkBack/VoiceOver) was available. Phase 2B (Controlled Interaction Validation) was NOT executed.** This report is built entirely from Phase 1 (Discovery) and Phase 2A (Static Verification). |
| Report created | `AU_production_readiness_report.md` |

---

## Executive Summary

### System
Niswah — bilingual (EN/AR, RTL) Flutter mobile app for menstrual/fiqh-state cycle tracking, pregnancy tracking, and related religious-practice guidance.

### Version / Commit
`13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f` on `main`.

### Platforms tested
None tested via live interaction (no device/emulator/AT available). Static code review covers iOS and Android equally (Flutter is a shared codebase; no platform-specific accessibility divergence was found or excluded from review).

### Critical journeys tested
**0 / 8** critical journeys (UXJ-001 through UXJ-008, per `AU_discovery.md` §3) were interaction-tested. All 8 were statically reviewed to varying depth.

### Open findings
- AU0 (Critical): **0**
- AU1 (High / pre-launch blocker): **1** — `AU-001` (icon-only controls lacking accessible names, 15+ confirmed sites)
- AU2 (Medium): **5** — `AU-002`, `AU-003`, `AU-004`, `AU-006`, `AU-007`
- AU3 (Low): **2** — `AU-005`, `AU-008`
- AU4 (Observation): **1** — `AU-010`

*(Full detail, evidence, and file:line citations for every finding are in `AU_findings.md`.)*

### Formal accessibility/legal review items
**1** — see Formal Review Register below. No jurisdiction-specific accessibility law or formal WCAG conformance target was named by the project; if this app is subject to any (e.g., app-store accessibility guidelines, a target market's disability-access law), that determination requires the product/legal owner, not this audit.

### Critical unknowns
**1 category, spanning the entire interaction surface**: this audit could not perform **any** live screen-reader, keyboard, zoom, or touch-interaction test (Phase 2B, template §49-§65) because no device, emulator, or assistive-technology tooling was available in this environment. Every accessibility/UX conclusion in this report is static-code-pattern inference (🟧 confirmed-by-code or 🟨 likely), never interaction-confirmed (🟥). This is stated explicitly per the task's mandate and is treated as launch-relevant per the template's own decision rules (§77).

### Final technical accessibility/UX recommendation
**🔴 NO-GO** — for this exact commit, as detailed below.

---

## Launch Decision Rules Applied

Per template §77:

- **GO** requires zero open AU1 and "no critical accessibility/UX unknown remains." Neither condition is met: `AU-001` is an open AU1, and Phase 2B was never executed.
- **CONDITIONAL GO** requires zero AU0, zero *launch-blocking* AU1, and "no critical interaction unknown remains." `AU-001` is explicitly assessed as launch-blocking (no workaround exists for a screen-reader user encountering an unlabeled password-visibility toggle, close button, or delete button on a core journey — see `AU_findings.md` AU-001 severity factors), and the interaction-testing unknown is total, not partial. This also fails CONDITIONAL GO's bar.
- **NO-GO** applies when: "Any AU0 remains" (not the case here) **OR** "Keyboard/screen-reader users are blocked from a critical journey where those modes are in scope" (AU-001 — confirmed by deterministic Flutter semantics behavior, not requiring a live test to establish that the accessible name is currently empty) **OR** "Critical accessibility/UX behavior remains unknown" (AU-009 — Phase 2B was never executed at all).

Both of the last two NO-GO triggers are met independently. This is not a verdict driven by a single edge-case finding; it reflects (a) one confirmed, code-level, no-workaround defect affecting a named target user group (`USR-005`, screen-reader users, explicitly in scope per the app's own user inventory) on multiple core journeys, compounded by (b) the complete absence of the mandatory live-interaction verification stage for an app whose core purpose (determining religious-practice obligations from health data) makes correct comprehension by all user groups unusually consequential.

---

## Launch Gate Table

| Gate | Requirement | Evidence | Status |
|---|---|---|---|
| `LG-AU-01` | Zero open AU0 | Finding Register (`AU_findings.md`) | **PASS** (0 AU0 found) |
| `LG-AU-02` | Zero launch-blocking AU1 | `AU-001` | **FAIL** |
| `LG-AU-03` | Critical journeys usable | Static review only; not interaction-verified | **FAIL** (unverifiable — see LG-AU-12) |
| `LG-AU-04` | Keyboard/focus behavior verified | Not applicable finding for this mobile-only app's primary journeys; external-keyboard-on-tablet scenario untested | **N/A** (no keyboard-dependent journey identified; not separately verified as a gap) |
| `LG-AU-05` | Screen-reader critical behavior verified | No live AT testing possible (AU-009); static review found AU-001, AU-002 | **FAIL** |
| `LG-AU-06` | Forms/error recovery usable | `AU-004`, `AU-005` — bounded issues, not fully blocking, but not live-verified | **INCONCLUSIVE** |
| `LG-AU-07` | Responsive layout verified | Golden tests fixed at 390×844 only; no tablet/landscape coverage | **INCONCLUSIVE** |
| `LG-AU-08` | Zoom/text scaling verified | `AU-006` — static risk identified, not live-tested at large scale | **INCONCLUSIVE** |
| `LG-AU-09` | RTL/localization verified | `AU-007`, `AU-008` — 24% screen coverage, 1 confirmed defect | **FAIL** |
| `LG-AU-10` | Destructive actions safe | Not independently re-derived this pass (delete-entry buttons in AI chat/dream journal exist but were reviewed only for AU-001's labeling gap, not for confirmation-dialog adequacy) | **INCONCLUSIVE** — cross-reference Functional QA |
| `LG-AU-11` | Critical states usable | Not exhaustively re-derived; cross-referenced to Functional QA per template §0.2 | **INCONCLUSIVE** |
| `LG-AU-12` | No critical unknowns | Phase 2B entirely unexecuted | **FAIL** |

Per template §65/§78: "Any mandatory FAIL prevents GO." Multiple mandatory gates FAIL or are INCONCLUSIVE (which this audit treats as not-passing per the template's evidence-based standard — an INCONCLUSIVE gate is not affirmative evidence of readiness). This independently supports the NO-GO verdict.

---

## Formal Review Register

| Item ID | Topic | Why formal review required | Technical evidence available | Owner | Status |
|---|---|---|---|---|---|
| `FORMAL-AU-001` | Live assistive-technology (TalkBack/VoiceOver) conformance for all critical journeys | This audit is static-only; the template explicitly prohibits claiming screen-reader compatibility without actual testing (§49, §84 #7). No formal WCAG/legal target has been named by the project, so no formal *compliance* claim is pending review — but a **verification** activity (not a legal review) is required before this can be called accessible in practice. | Static findings (AU-001, AU-002, AU-010) point at specific likely failure points to prioritize during that live pass | Product/QA owner | OPEN |

No jurisdiction-specific accessibility law, formal WCAG conformance level, or representative-user usability study was identified as a project requirement. If any such requirement exists (e.g., for app-store submission, an institutional partner, or a specific target market), it should be added to this register by the release owner — this audit did not find evidence such a requirement has been defined either way, and does not assume its absence means it doesn't apply.

---

## Residual Risk Register

| Risk ID | Finding | Severity | Probability | Production impact | Mitigation | Owner | Required before launch? |
|---|---|---|---|---|---|---|---|
| `RISK-AU-001` | `AU-001` | AU1 | HIGH (confirmed by code, not probabilistic) | Screen-reader users cannot reliably operate password-visibility toggle, close/dismiss controls, or delete actions on several core screens | R1 (add tooltips/Semantics; see `AU_remediation_plan.md`) | Eng | **YES** |
| `RISK-AU-002` | `AU-009` | Process/unknown | N/A | Unknown scope of additional live-testing-only-discoverable defects across all journeys | R7 (live Phase 2B pass) | Eng/QA | **YES** (or explicit owner risk-acceptance with a defined follow-up date) |
| `RISK-AU-003` | `AU-003` | AU2 | MEDIUM | Low-vision users may misread `tahara`/`nifas` state-label text, which carries religious-practice significance | R2 (color contrast fix) | Design/Eng | Recommended, not launch-blocking on its own |
| `RISK-AU-004` | `AU-004` | AU2 | MEDIUM | Colorblind users cannot confirm logged symptom severity before saving | R3 (add non-color indicator) | Eng | Recommended |
| `RISK-AU-005` | `AU-002`, `AU-006` | AU2 | LOW-MEDIUM | Secondary dashboard detail (phase timeline) may be inaccessible/clip for AT and large-text users; primary state info remains available via the ring | R1, R5 | Eng | Recommended |
| `RISK-AU-006` | `AU-007`, `AU-008` | AU2/AU3 | MEDIUM (architecture risk), LOW (confirmed instance) | Undetected RTL/translation drift possible on 19 of 25 screens with no automated coverage; one confirmed low-severity padding bug | R6 | Eng | Recommended (confirmed instance not launch-blocking; architecture risk flagged for ongoing attention) |
| `RISK-AU-007` | `AU-005` | AU3 | LOW | Inconsistent (but not silent) error feedback on one form | R4 | Eng | Optional |
| `RISK-AU-008` | `AU-010` | AU4 | LOW | Minor AT verbosity from unexcluded decorative nodes | R1 (bundle) | Eng | Optional |

---

## Out-of-Scope / Not Verified

Explicitly listed per template §81:

- **Live TalkBack (Android) testing** — not performed, no device/emulator available.
- **Live VoiceOver (iOS) testing** — not performed, no device/emulator available.
- **Any Phase 2B controlled interaction test** (keyboard, screen reader, zoom, responsive, RTL, form-recovery, loading/timeout, offline, destructive-action, touch — template §52-§63) — none executed.
- **Formal WCAG 2.1/2.2 conformance certification** — not performed; this audit used WCAG contrast math only as a technical reference calculation, not a conformance audit.
- **Jurisdiction-specific accessibility law review** (e.g., ADA, EN 301 549, local equivalents) — not performed; no such requirement was found documented in the repository, and its absence from this report is not a determination that no such requirement exists.
- **Representative user research / usability study with actual screen-reader users, low-vision users, or Arabic-speaking users** — not performed.
- **Tablet layout / landscape orientation** — no tablet-specific layout code or test coverage was found; explicitly unverified rather than assumed unsupported.
- **Color-vision-deficiency simulation (rendered)** — contrast was assessed via direct hex-value WCAG calculation, not via a rendered CVD simulation tool.
- **19 of 25 screens' RTL/Arabic rendering** — no golden/pixel test exists for these; static code review only (see AU-007 for the full list of covered vs. uncovered screens).
- **Image/icon `alt`-text equivalent (`semanticLabel` on `Image` widgets) full sweep** — not performed this pass; noted as a discovery gap in `AU_discovery.md` §13.
- **Destructive-action confirmation-dialog adequacy** (delete AI-chat thread, delete dream-journal entry, etc.) — button labeling was reviewed (AU-001), but confirmation-flow design itself was not independently re-derived; cross-reference Functional QA.
- **Full state inventory** (loading/empty/error/offline/session-expiry per screen) — cross-referenced to Functional QA and Reliability audits per template §0.2 rather than re-derived here.

None of the above is converted into a PASS or FAIL in this report — each is recorded as genuinely unknown, per template instruction.

---

## Final One-Sentence Recommendation

> Accessibility & UX technical recommendation: **NO-GO** for `13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f` until finding `AU-001` (icon-only controls lacking accessible names, 15+ confirmed sites across sign-in, onboarding, profile, AI chat, dream journal, cycle tracking, and the cycle-log form) is remediated, **and** a live Phase 2B screen-reader/keyboard/zoom/RTL interaction pass (per `AU_remediation_plan.md` item R7) is executed and passes for the critical journeys UXJ-001 through UXJ-008 — this audit was necessarily static-only, no live TalkBack/VoiceOver/device testing was available, and per the template's own decision rules an unexecuted controlled-interaction phase is itself a NO-GO condition independent of the confirmed AU-001 defect.

**Formal accessibility/legal review status:** No formal WCAG conformance level or jurisdiction-specific accessibility law has been defined as a project requirement; this report makes no formal compliance claim and recommends the release owner explicitly determine whether one applies (see Formal Review Register).
