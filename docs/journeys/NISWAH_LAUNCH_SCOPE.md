# Niswah launch scope for the 300 app-wide journeys

Status: **proposed, awaiting rayan's decision** (2026-10-29).

The 300-journey register (`docs/NISWAH_APP_WIDE_300_ACCEPTANCE_JOURNEYS.md`)
lists journeys for features the app does not have. Their presence in the
register does not authorize building them. This page records which features
ship today, which are conditional, and which need a scope decision. The
per-journey scope is in `docs/journeys/NISWAH_JOURNEY_COVERAGE.csv`.

## Included: the feature ships in the current app (213 journeys)

Sign-up, sign-in, recovery, onboarding, period tracking (episodes,
observations, corrections, removal, restore), calendar, predictions,
insights, fiqh guidance with uncertainty states, AI chat, reports and
export, settings, privacy, account deletion, offline and sync behavior.

## Operations / release process (34 journeys)

Migrations, release builds, store review, monitoring, rollback. These are
evidenced by release records, not app code.

## Conditional: exists in code, launch scope to confirm (16 journeys)

| Feature | Journeys | Finding | Proposed decision |
|---|---|---|---|
| Community / messaging | NJ-181..NJ-190 | No block (NJ-183) or report (NJ-184). App Store guideline 1.2 requires both for user-generated content. | Hide community for launch, or build block and report first. Decision needed. |
| Push notifications | NJ-162, NJ-167 | Push is disabled in the launch builds. | Out of scope for launch; local reminders only. |
| Pregnancy / postpartum mode | NJ-032, NJ-132, NJ-133, NJ-274 | Exists; medical wording needs specialist review. | Keep, with specialist sign-off listed as external evidence. |

## Not implemented: scope decision required (19 journeys)

| Feature | Journeys | Proposed decision |
|---|---|---|
| Subscriptions and purchases | NJ-049..NJ-052, NJ-191..NJ-200, NJ-272, NJ-277, NJ-287 | Out of scope: the app has no paid tier. |
| Biometric lock | NJ-075 | Out of scope for launch. |
| Medication / contraception records | NJ-134 | Out of scope for launch. |

## Deferred by product decision (18 journeys)

Qadha ledger and period-linked qadha suggestions (NJ-039..NJ-044,
NJ-150..NJ-160, NJ-275). rayan's standing instruction: period tracking comes
before qadha, and no period-linked qadha automation is added.

Until rayan decides, these rows stay **BLOCKED — EXTERNAL EVIDENCE REQUIRED**
with the decision as the blocker. None is marked OUT OF SCOPE without that
decision.
