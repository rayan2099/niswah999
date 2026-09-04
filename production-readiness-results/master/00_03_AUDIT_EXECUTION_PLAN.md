# 00_03 — Audit Execution Plan

Following `00_PRODUCTION_READINESS_MASTER.md` §29 wave structure, adapted to this repository's architecture (no deviation from default wave composition required).

## Execution Model

Each specialist audit is executed by a dedicated sub-agent that:
1. Reads its full template from `production-readiness/MDs/`.
2. Performs Discovery + Static Verification against the actual `lib/`, `supabase/`, `android/`, `ios/`, `test/` trees (the locked release candidate — see `00_01_RELEASE_CANDIDATE_BASELINE.md`).
3. Performs Controlled Validation only where safe (local static analysis, local test runs, `flutter analyze`, reading — never destructive actions, never against live production Supabase project, never network calls with live secrets).
4. Writes native-ID findings, a remediation plan marked **PROPOSED — NOT IMPLEMENTED**, and one verdict (GO / CONDITIONAL GO / NO-GO / BLOCKED / N/A) to `production-readiness-results/<domain>/`.
5. Does not modify `lib/`, `supabase/`, `android/`, `ios/`, config, or dependencies.
6. Treats `src/` as reference-only unless a finding specifically concerns whether the mobile app and web reference share a live backend/config (routed to Security/Dependencies).

Findings use each domain's native prefix (SEC, FQ, CQ, DI, AB, PF, RR, OB, PC, AU, DC, BR, RD, AE, PJ, PL) per master §16.

## Waves

### Wave 1 — Foundations (parallel, dispatched now)
- Security discovery/static verification → `SEC-xxx`
- Code Quality → `CQ-xxx`
- Dependencies & Configuration → `DC-xxx`
- Database discovery/static verification → `DI-xxx`
- API/Backend discovery/static verification → `AB-xxx`

### Wave 2 — Core System Behavior (after Wave 1 consolidated)
- Functional QA → `FQ-xxx`
- Database controlled validation (extends `DI-xxx`)
- API/Backend controlled validation (extends `AB-xxx`)
- Performance → `PF-xxx`
- Reliability & Resilience → `RR-xxx`

### Wave 3 — Production Operability
- Observability → `OB-xxx`
- Backup & Recovery → `BR-xxx`
- Release & Deployment → `RD-xxx`

### Wave 4 — User & Business Readiness
- Privacy & Compliance → `PC-xxx`
- Accessibility & UX → `AU-xxx`
- Analytics & Business Events → `AE-xxx` (must independently confirm or refute provisional N/A lean)

### Wave 5 — Final Cross-System Validation
- Final Pre-Launch User Journey → `PJ-xxx` (only after Waves 1–4 evidence is sufficiently complete; reconciles UI → Supabase API → DB → Edge Function/AI provider → Notification → Observability for each critical journey)

### Wave 6 — Launch Operations
- Post-Launch Monitoring plan (authored against master §§16.6/38/49/50 due to missing dedicated template — see `00_02_AUDIT_APPLICABILITY_MATRIX.md`) → `PL-xxx`

## Environment & Testing Constraints (recorded up front per master §14/§Step 8)

- No CI environment, no staging Supabase project, and no live production credentials are available to this audit session beyond whatever is in the local `.env` (not to be exfiltrated or used for live network calls against a possibly-production Supabase project without explicit authorization).
- No physical/simulator iOS or Android device confirmed available in this environment — `flutter analyze`/`flutter test`/static review are the primary evidence sources unless a device/emulator is confirmed reachable.
- No destructive testing, no production data mutation, no live payment/AI-provider spend beyond what's unavoidable for minimal read-only verification will be performed.
- Any test requiring credentials/access not available will be marked **UNKNOWN / NOT VERIFIED** with exactly what is missing — never silently upgraded to PASS.

## Progress Tracking

Live status is maintained in `00_04_MASTER_FINDING_REGISTER.md` and the dashboard section of the final report. This file (`00_03`) is not re-issued per wave; wave completions are reported in-conversation and reflected in the finding register and applicability matrix as they close.
