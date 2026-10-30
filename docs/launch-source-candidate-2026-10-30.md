# Launch source integration candidate — 2026-10-30

Status: draft integration, behavioral verification pending; public launch remains NO-GO.

## Included source

| Source | Exact head | Scope |
| --- | --- | --- |
| #78 | `12bfbba8fc8475a399b5f505bca20d8e39328be3` | Combined account, recovery, export, interrupted/deleted drafts, history cutoff, completed canonical timing, local-save/report/sync ownership |
| #73 | `fc222a6c4bff0caeaef28e3a9f9164976036b9c6` | #60 corrections/removal/unknown end, #71 split/join, #72 unique migration versions, community SQL and nine disposable SQL security checks |
| #70 | `a2ae377fb644685bf8097ffa1742089456711229` | Community and private-message filtering, report/block, terms gate and moderation UI |
| #63 | `499f5631bbc5aebe3213312e749dab94f5f72146` | Signup email guidance, paced resend, auto-advance and actionable refusal copy |

Current main is `5a88cd7753914c4dfa5260d0e1950bd622a7ea04`; password recovery #44 and security #40/#41 are already merged. The original #45 run 40548587989 remains historical failure evidence; subsequent main fixes and the retained 11 concurrency cases supersede its two original failures. PR #26 is not wholesale merged; its applicable safeguards are being reconciled with the newer implementation.

PR #78 passed [CI 41025776182](https://github.com/rayan2099/niswah999/actions/runs/41025776182): 1,640 tests passed, 7 skipped, all jobs green, including the real route-boundary/entry-sheet deletion interaction and both native compilation checks. That evidence applies to #78, not this larger candidate.

## Integration finding and repair

The #68 historical cutoff reconstructs canonical timing before calculation. Combining it with #60's unknown-end representation exposed that the reconstruction omitted `endUnknown`. An ended period with no known date became an open span in this derived view and suppressed a later log-derived cycle. Preserve the flag when rebuilding the timing. Two added cases in [the cutoff tests](../test/cycle_calculation_asof_boundary_test.dart) distinguish an unknown-ended period (later cycle retained) from a genuinely open one (existing span policy retained), while excluding future observations. No stored observations, end date or clinical/religious classification is invented.

All implementation merges otherwise resolved automatically. Generated navigation conflicts were regenerated from the staged final inventory. The uniquely named split migration remains `20261030012106_bleeding_episode_split_merge.sql`; the community migration remains `20261030090000_community_ugc_safety.sql`. No migration SQL is altered by this integration. Existing test gates and skips are retained.

## Verification and launch gates

Local Dart parsing/formatting, whitespace, unique migration versions, generated navigation and six Python vault/migration tests pass. Combined Flutter, SQL, schema, bootstrap and native compilation verification is pending in CI. Local Flutter dependencies were not installed. Historical coverage registers are included as dated evidence; they are not automatically promoted to new passes by an integration commit.

Fresh read-only checks on October 30: staging has correction/removal RPCs but no unknown-end support, split or community-report RPCs. Production lacks those correction/removal, unknown-end, split and community-report capabilities. Both environments deny anonymous execution of the four reviewed security-definer RPCs. This confirms specific rollout/security facts, not whole-environment acceptance. No database writes occurred.

This is the first source combination of the branches listed above, not a declaration of a final release artifact. Outstanding work includes applicable #26 concerns (exact revisions, A→B→A fences, signed-out ownership and broader canonical conflicts), review of other open relevant fixes such as #58 prayer-location ownership and #49 sign-in layout, remaining journey implementation and scope decisions, approved staging/production rollout, real email recovery/delivery, signed-device acceptance and specialist evidence. Community requires configured support contact, a moderator and an operating response process; those are not proved by app/SQL tests. No GO, medical/scholarly approval, prediction accuracy, device validation or deployment is claimed. No main merge or production change was made.

Navigation: [tracking](../project-hub/generated/feature-cycle_tracking.md), [community](../project-hub/generated/feature-community.md), [auth](../project-hub/generated/feature-auth.md), [quality](../project-hub/generated/Quality-and-Release.md).
