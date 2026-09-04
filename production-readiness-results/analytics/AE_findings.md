# Analytics & Business Events Audit — Findings Register (AE)

## Why this register is minimal

This audit's Discovery phase (`AE_discovery.md`) exhaustively and independently confirmed — not merely re-accepted from the applicability matrix's provisional lean — that:

1. No analytics/telemetry SDK (third-party or homegrown) exists anywhere in `pubspec.yaml`, `pubspec.lock` (including transitively), or `lib/`.
2. No monetization/business-event surface exists: the app has zero payment/IAP SDK, zero wired paywall, and zero application-code reference to the dormant `premium_status`/`premium_expires_at` schema columns.

Per the template's own methodology (Phase 2A "Static Verification," Phase 2B "Controlled Event Validation"), those phases exist to validate *instrumentation that is claimed to exist*. There is no instrumentation of any kind here to statically verify or to controlled-event-test — running those phases against a nonexistent system would either produce a meaningless "empty pass" or fabricated findings. Per template §76 instruction 2 ("Do not invent KPI definitions") and the master framework's evidence-based N/A rule, the correct action is to close Discovery, register the N/A determination with full rationale (see `AE_production_readiness_report.md`), and register only the findings actually produced by the exhaustive search — below.

This is consistent with how an N/A-eligible audit should behave: **N/A is a conclusion reached after doing the work, not a shortcut that skips it.**

---

## Finding Register

| Finding ID | Category | Severity | Event/KPI | Summary | Evidence | Business impact | Launch blocker? | Status |
|---|---|---|---|---|---|---|---|---|
| `AE-001` | AI-xx (AI-agent-specific defect, §41.4/41.8 "fake coverage" / placeholder feature) | **AE4 — Observation** | N/A (not an event/KPI — a dead monetization UI stub) | `_PaywallSheet`/`_PaywallSheetState` in `lib/features/auth/presentation/screens/profile_screen.dart` (~lines 1807–2020) renders a fully-priced "Niswah Plus" paywall (Monthly $9.99, Annual $79.99, "Start free trial" CTA, "RESTORE PURCHASE" footer) but is never instantiated or shown anywhere in the app (`grep -rn "_PaywallSheet" lib/` returns only its own declaration), and its primary CTA's `onPressed` is `() => Navigator.pop(context)` — it does not call a purchase API, does not touch Supabase, and does not set any premium flag even if triggered. No `in_app_purchase`/payment SDK exists to back it. | `lib/features/auth/presentation/screens/profile_screen.dart:1807-2020`; `grep -rn "_PaywallSheet" lib/`; absence of `in_app_purchase` in `pubspec.yaml`/`pubspec.lock`; zero hits for `premium_status`/`isPremium`/`premium_expires` in `lib/` | None currently reachable by users (dead code) — but represents unfinished/placeholder monetization work that, if ever wired up without an analytics/revenue-event layer, would ship with **zero** ability to measure trial starts, plan selection, or conversion (this audit's core concern). Flagged now so it is addressed *before* — not after — any future monetization launch. | **NO** — not launch-blocking; the code is unreachable, so it has no runtime effect | OPEN (informational — recommend Code Quality audit also register as dead-code cross-reference; recommend Product decide whether to build this out with proper `KPI-xxx`/`EV-xxx` instrumentation before ever wiring it live, or remove it) |

No `AE0`, `AE1`, `AE2`, or `AE3` findings were identified, because there is no live analytics or business-event instrumentation whose naming, triggers, properties, identity handling, duplication behavior, financial accuracy, funnels, or reconciliation could be defective — the defect categories the template's severity model (§4) is built to catch (AE0–AE3) presuppose *existing* instrumentation that is wrong. Here, nothing exists to be wrong. This is not being used as a shortcut to avoid finding real problems — see `AE_discovery.md` §1–2 for the exhaustive search that produced this conclusion.

---

## Cross-reference note (not a new AE finding, per audit brief)

The Observability audit's `OB-008` already registered: *"No analytics or telemetry SDK exists anywhere... removes even the weakest possible secondary signal."* This audit independently confirms that finding from the dependency-tree and custom-code angle (see `AE_discovery.md` §1) and sharpens its practical consequence for `ROOT-001` (possible broken Gemini endpoint on `dr-niswah-chat`):

- The only DB-level substitute for business/usage visibility is raw ad hoc SQL against `chat_threads`/`chat_messages` (both have `created_at`), which would show *that* messages are being written, but not whether the Gemini call inside `dr-niswah-chat` is actually succeeding — a written `chat_messages` row does not imply a successful AI response, only an attempted one.
- This means `ROOT-001`, if real, is invisible both to formal analytics (none exists) and to the informal DB-fallback (which cannot distinguish success from failure without inspecting message content row-by-row).

This is logged here as context for the master's cross-audit synthesis, not as a new numbered `AE-xxx` finding, per the audit brief's explicit instruction to treat it as an `OB-008` cross-reference.
