# Performance — Production Readiness Report

**Verdict: 🟡 CONDITIONAL GO**

## Basis

No PF0 (Critical) or PF1 (High) finding was identified: no evidence of core-system unusability, crashes, resource exhaustion, or a critical journey being materially too slow was found in static review. Three PF2 (Medium) findings were identified — unparallelized startup awaits, a synchronously-loaded full timezone database on the startup path, and non-isolate-offloaded PDF generation — none of which are launch-blocking on their own per this template's severity model (PF2 requires explicit acceptance, not remediation-before-launch).

**This CONDITIONAL GO is issued primarily because this audit had zero access to live profiling, a real device/emulator, or any APM tooling.** Per master evidence rules (§3.3, "Unknown is not PASS"), the complete absence of measured performance data is recorded as an explicit limitation, not converted into a clean GO. All findings above are code-pattern-level risk assessments; actual startup time, frame-render times, and PDF-generation latency on a representative device are all **UNKNOWN / NOT VERIFIED**.

## Scope Limitation Register

| Limitation | Reason | Risk | Compensating evidence |
|---|---|---|---|
| No live device/emulator profiling | Not available in this audit environment; no CI exists to have produced historical performance data either (cross-reference DC-006) | Cannot confirm or deny whether PF-001/002/003's theoretical risk manifests as user-perceptible jank/slow-start in practice | Code-pattern review found no PF0/PF1-class anti-pattern (unbounded lists, N+1 network amplification, missing virtualization) — see positive controls in `PF_findings.md` |
| No load-testing tooling or backend traffic simulation | Out of scope for a mobile-client-focused, no-backend-infra-access audit pass | Backend-side performance under concurrent load is unassessed here (cross-reference API/Backend audit, which also had no live access) | N/A |

## Conditions for closing this CONDITIONAL GO

| Condition ID | Requirement | Owner |
|---|---|---|
| `PF-COND-01` | Measure actual cold-start time on at least one representative low/mid-tier Android device and one iOS device before launch; confirm it is within acceptable UX bounds | Release owner / mobile engineer |
| `PF-COND-02` | Measure actual PDF-generation latency for a realistic "full" report (all sections populated) on a representative device; confirm the existing loading-state UX is sufficient or offload via `compute()` if not | Release owner / mobile engineer |

## Remediation Plan — **PROPOSED, NOT IMPLEMENTED**

No code was modified during this audit.

- **R1 (PF-001):** Parallelize the six independent `SharedPreferences`-backed controller loads in `main.dart` via `Future.wait`.
- **R2 (PF-002):** Defer `NotificationService.instance.initialize()` to a post-first-frame callback.
- **R3 (PF-003):** Offload PDF generation via `compute()` if `PF-COND-02` measurement shows unacceptable jank; otherwise accept as-is given the existing `PdfPreview` loading-state mitigation.

None of R1–R3 are launch-blocking; they are backlog-eligible improvements unless live measurement (the two conditions above) reveals a materially worse result than this static review's risk assessment predicts.
