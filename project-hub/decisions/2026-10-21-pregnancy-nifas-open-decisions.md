---
type: decision
status: proposed
area: pregnancy_profile
owner: unassigned
reviewed_on:
---

# Pregnancy and nifas: open owner, scholar and medical decisions

## Context and sources

- Hardening wave: [contract §19](../../docs/menstrual-data-integrity-contract.md#19-pregnancy-nifas-and-reminders-hardening-2026-10-21-branch-fixpregnancy-notifications-hardening--status-proposed). Code is on branch `fix/pregnancy-notifications-hardening`.
- Feature maps: [pregnancy_profile](../generated/feature-pregnancy_profile.md), [dashboard](../generated/feature-dashboard.md), [notifications](../generated/feature-notifications.md).
- No canonical nifas engine exists. The 40-day window is not Madhhab-aware: [FOUNDER_DECISIONS.md](../../production-readiness-results/knowledge-base/FOUNDER_DECISIONS.md) (FD-1, nifas governance). [haidfigh.md](../../haidfigh.md) documents no nifas rules.
- Engine: [pregnancy_status_engine.dart](../../lib/features/pregnancy_profile/domain/services/pregnancy_status_engine.dart). Dashboard: [dashboard_screen.dart](../../lib/features/dashboard/presentation/screens/dashboard_screen.dart).

## Decision and rationale

Nothing is decided here. These four questions remain open. The hardening wave deliberately leaves the current behaviour in place and only makes every surface use one definition.

1. **Nifas window.** Today it is a flat day 0–40 after the logged birth date (`PregnancyStatusEngine.isWithinNifasWindow`). The schema's `nifas_records.madhhab_max_days` allows 40 or 60. Choosing a window, or making it Madhhab-aware, is a Fiqh judgment.
2. **Nifas day numbering.** Proposed default, not decided: every surface uses the 0-based count of elapsed calendar days since the logged birth date, which is what the reports and the reminder copy already use. The dashboard Nifas card shows "Birth day" / "يوم الولادة" on day 0, then "Day 1/40" through "Day 40/40". Its remaining-days count is 40 minus the same number, and the card is gone on day 41, so it never reads "Day 41/40". Before, the card was 1-based. The owner still decides the final convention; the "/40" denominator follows decision 1.
3. **Pregnancy loss / miscarriage.** There is no flow. Turning pregnancy off now clears tracking on the device and on the synced profile. It does not record a loss, offer support, or apply any ruling to bleeding after a loss. This needs joint scholar and medical review (see the 3 pregnancy-loss/nifas review atoms in the knowledge base).
4. **Nutfah/Alaqah/Mudghah stage labels.** The dashboard maps gestational weeks ≤4 / ≤8 / ≤12 to these stages. The mapping is a religious claim that is not documented in the repo, and it counts gestational rather than conception weeks. It is left unchanged pending scholar review.

## Impact and verification

Each decision changes the engine constant or helpers above, the dashboard nifas card, and the tests in [`test/pregnancy_notifications_hardening/`](../../test/pregnancy_notifications_hardening/). The server mirror `supabase/functions/_shared/pregnancy_status.ts` and its parity vectors in `test/fixtures/pregnancy_status_vectors.json` must change together with the engine. No expert approval is claimed.
