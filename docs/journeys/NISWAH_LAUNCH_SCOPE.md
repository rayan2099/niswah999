# Niswah launch scope for the 300 app-wide journeys

Status: community decided by rayan on 2026-10-29 (ships, with App Store 1.2 block and report). The rest is **proposed, awaiting rayan's decision**.

The 300-journey register (`docs/NISWAH_APP_WIDE_300_ACCEPTANCE_JOURNEYS.md`)
lists journeys for features the app does not have. Their presence in the
register does not authorize building them. This page records which features
ship today, which are conditional, and which need a scope decision. The
per-journey scope is in `docs/journeys/NISWAH_JOURNEY_COVERAGE.csv`.

## Included: the feature ships in the current app (207 journeys, including community since 2026-10-29)

Sign-up, sign-in, recovery, onboarding, period tracking (episodes,
observations, corrections, removal, restore), calendar, predictions,
insights, fiqh guidance with uncertainty states, AI chat, reports and
export, settings, privacy, account deletion, offline and sync behavior.

## Operations / release process (34 journeys)

Migrations, release builds, store review, monitoring, rollback. These are
evidenced by release records, not app code.

## Conditional: exists in code, launch scope to confirm (6 journeys; community moved to Included)

| Feature | Journeys | Finding | Proposed decision |
|---|---|---|---|
| Community / messaging | NJ-181..NJ-190 | **Decided 2026-10-29 by rayan: community ships.** It must meet App Store guideline 1.2, so block (NJ-183), report (NJ-184) and moderation are being built in a separate thread. | In scope. |
| Push notifications | NJ-162, NJ-167 | Push is disabled in the launch builds. | Out of scope for launch; local reminders only. |
| Pregnancy / postpartum mode | NJ-032, NJ-132, NJ-133, NJ-274 | Exists; medical wording needs specialist review. | Keep, with specialist sign-off listed as external evidence. |

## Out of launch scope (decided by rayan, 2026-10-30)

rayan chose to defer nine features that do not exist in the app (34 journeys)
and to keep one, the remote fiqh switch-off, in launch scope.

| Feature | Journeys | Decision | Consequence of deferring |
|---|---|---|---|
| Subscriptions and purchases | NJ-049..NJ-052, NJ-191..NJ-200, NJ-272, NJ-277, NJ-287 | Out of scope | No paid tier at launch; adding one later needs store review and receipt handling. |
| Biometric lock | NJ-075 | Out of scope | Anyone holding her unlocked phone can open the app. |
| Medication / contraception records | NJ-134 | Out of scope | They cannot be logged; predictions do not account for them. |
| AI that changes records | NJ-174..NJ-178, NJ-273 | Out of scope | The AI only answers questions; she edits her records herself. |
| Attachments and shareable links | NJ-187, NJ-188, NJ-246, NJ-257 | Out of scope | Community and messages stay text-only. |
| Data import | NJ-127 | Out of scope | History from another app is entered by hand. |
| History search, chart drill-down | NJ-107, NJ-115 | Out of scope | She browses by month. |
| Predictions-off setting | NJ-128 | Out of scope | Predictions stay on; they are labelled as estimates. |
| Calendar display preference | NJ-089 | Out of scope | The Hijri month is already shown beside the Gregorian label. |
| Remote guidance disable | NJ-280 | **In scope** | Built with the fiqh kill switch (PT-196) so a wrong rule can be turned off without a release. |

## Deferred by product decision (18 journeys)

Qadha ledger and period-linked qadha suggestions (NJ-039..NJ-044,
NJ-150..NJ-160, NJ-275). rayan's standing instruction: period tracking comes
before qadha, and no period-linked qadha automation is added.

Until rayan decides, these rows stay **BLOCKED — EXTERNAL EVIDENCE REQUIRED**
with the decision as the blocker. None is marked OUT OF SCOPE without that
decision.
