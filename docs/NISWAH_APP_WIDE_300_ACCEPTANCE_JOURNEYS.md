# Niswah — 300 app-wide acceptance journeys

Version: 1.0 · Prepared: 2026-10-29 · Language: English with Arabic UX examples

## Purpose and evidence status

This register expands the original 60 app-wide journeys to 300 distinct acceptance requirements. NJ-001–NJ-060 retain their original scenario identities and intent; wording is normalized for execution. It complements, and does not replace or renumber, `PERIOD_TRACKING_200_CASES.md` (PT-001–PT-200). The original 200 cases are not reproduced in this file. This document was prepared from the agreed product discussion, not from a fresh repository inspection.

**Initial status for every NJ case: NOT ASSESSED. No case in this document has been executed or verified by creating this file.** Rows are acceptance seeds: the implementation owner must add reproducible setup, concrete data, steps, and evidence before claiming verification. A case covering several outcomes must exercise all of them or be split into stable child IDs, such as NJ-050.a.

The number 300 is a coverage inventory, not a guarantee of robustness or a launch criterion by itself. Add discovered cases without deleting or renumbering existing IDs.

## Product decisions and boundaries

- Prioritize period-observation integrity and all 200 PT cases. Manual qadha follows; period-linked automation follows dependable tracking and reviewed rules.
- Qadha, community, messaging, pregnancy/postpartum, subscriptions, biometrics, and other conditional capabilities must be mapped to the actual launch scope. Their presence in this register is not a claim that Niswah implements them or authorization to build every feature.
- Out-of-scope behavior requires an explicit decision, inaccessible dependent actions, and retained requirements for its eventual release. Never silently omit it or label it verified.
- Do not invent clinical thresholds, religious rulings, retention periods, billing terms, performance targets, or platform promises. Identify an approved specification or retain a blocker; verified safe restrictions may be implemented independently.
- Synthetic records and dedicated test accounts are the default. Do not use production health data as test fixtures.
- Reversible engineering work may proceed under existing authorization. This file does not authorize production changes, release, merge, external messages, purchases, or access to private accounts.

## Non-negotiable invariants

1. Separate observations, predictions, medical interpretation, fiqh classification, and confirmed qadha ledger entries.
2. Never treat missing input as no bleeding, a prediction as an observation, or a date-only entry as an exact timestamp.
3. Preserve identity, original local-date context, precision, provenance, and traceable corrections.
4. Preserve account boundaries across reads, writes, local queues, files, notifications, location callbacks, AI responses, and A→B→A session transitions.
5. Confirm durable save only for the location actually saved: distinguish local pending synchronization from server acknowledgment.
6. Make retries idempotent; prevent deleted data from returning through old devices or delayed operations.
7. Keep Today, Calendar, Insights, reminders, and dependent suggestions consistent with the same authoritative records.
8. Require explicit review before AI mutations or suggestions alter confirmed debt.
9. Preserve uncertainty and use approved safe restrictions when specialist evidence is missing.
10. Protect privacy in lock-screen text, exports, support, telemetry, and shared-device behavior.

## Required execution record for every ID

| Field | Required content |
|---|---|
| Requirement ID and title | Stable NJ ID and mapped PT IDs where genuinely related |
| Scope | Included, conditional, or explicitly out of scope; decision owner and date |
| Preconditions | App commit, backend migration versions, flags, account state, device/OS, locale, permissions, dataset |
| Steps | Numbered reproducible actions; include timing or fault injection where relevant |
| Expected storage | Exact creates, edits, deletes, unchanged records, account owner, precision, version, operation identity |
| Expected UI | Screen, wording, pending/error/recovery state, accessibility announcements |
| Downstream effects | Today, Calendar, Insights, predictions, reminders, guidance, AI, qadha, entitlement where relevant |
| Verification method | Unit, widget, integration, DB/security, multi-connection, end-to-end, signed-device, specialist, usability |
| Evidence | Test path and assertions, command/run, commit, date, result; device steps and redacted artifacts where needed |
| Evidence dimensions | Automated, staging integration, signed iPhone, signed Android, specialist review; record each separately |
| Severity | Critical, high, medium, or low with rationale |
| Status and owner | Current status, accountable owner, next action, blocker |

Statuses: **NOT ASSESSED**, **IMPLEMENTATION REQUIRED**, **IMPLEMENTED — UNVERIFIED**, **VERIFIED**, **BLOCKED — EXTERNAL EVIDENCE REQUIRED**, **OUT OF SCOPE — EXPLICIT DECISION**. A verified automated assertion does not establish device or specialist approval. Overall VERIFIED requires all applicable evidence dimensions; otherwise report partial evidence explicitly.

## Execution variants

Apply relevant variants based on risk, not an unmanageable full Cartesian product. For critical ownership and data-loss behavior, test relevant combinations rather than only one variant at a time.

| Dimension | Variants |
|---|---|
| Account | New, returning, unconfirmed, expired session, A→B, A→B→A, deleted, two devices |
| Data | Empty, ordinary, approximate, missing context, conflicting, legacy, years of history |
| Connectivity | Online, slow, offline, request rejected, response lost after commit, intermittent |
| Lifecycle | Cold start, background, force close, restart, reinstall, app upgrade |
| Presentation | Arabic RTL, English, English numerals, large text, screen reader, reduced motion |
| Time | Midnight, month/year boundary, leap day, timezone change, DST, date line, incorrect clock |
| Platform | Signed iPhone and Android; minimum/current supported OS; actual permission states |
| Dependencies | Available, slow, unavailable, stale response, duplicated/out-of-order event |

## Acceptance register

Each row below starts at NOT ASSESSED. These rows define expected outcomes; they do not assert existing behavior.

### Original journeys: discovery and access

| ID | User journey / trigger | Required outcome |
|---|---|---|
| NJ-001 | First opening | Explain the main purpose and expose an understandable next action. |
| NJ-002 | Privacy before registration | Make accurate sensitive-data and privacy information accessible before signup. |
| NJ-003 | Valid signup | Show the destination email, confirmation requirement, and recovery actions. |
| NJ-004 | Confirmation in Spam | Show «البريد غير المرغوب فيه (Spam)» guidance without claiming inbox delivery. |
| NJ-005 | Mistyped registration email | Provide a correction flow without trapping the user. |
| NJ-006 | Repeated resend or expired confirmation | Explain limits and provide recovery without duplicate accounts. |
| NJ-007 | Confirmation on another device | Complete confirmation and provide a clear return to Niswah. |
| NJ-008 | Already registered email | Provide a usable sign-in or recovery route with privacy-conscious wording. |
| NJ-009 | Sign in after confirmation | Resume the correct onboarding step or existing account. |
| NJ-010 | Repeated wrong passwords | Explain failures and temporary limits while keeping recovery accessible. |

### Original journeys: recovery and onboarding

| ID | User journey / trigger | Required outcome |
|---|---|---|
| NJ-011 | Forgotten password | Complete recovery and allow sign-in with the new credential. |
| NJ-012 | Expired or reused recovery link | Reject invalid links and offer a fresh recovery path. |
| NJ-013 | Session expires during entry | Protect account content and recover appropriate input after authentication. |
| NJ-014 | Sign out then another account signs in | Clear previous records, drafts, notifications, and AI context. |
| NJ-015 | Known cycle dates | Complete onboarding and show a dashboard consistent with those answers. |
| NJ-016 | Unknown cycle dates | Allow uncertainty without inventing observations or precise predictions. |
| NJ-017 | Stopped bleeding with unknown end | Preserve the known start and uncertain end. |
| NJ-018 | Approximate onboarding dates | Preserve approximation in storage, display, and calculations. |
| NJ-019 | Unknown madhhab | Allow continuation without assigning an unsupported classification. |
| NJ-020 | Resume and revise onboarding | Restore progress and reconcile dependent answers after edits. |

### Original journeys: daily tracking

| ID | User journey / trigger | Required outcome |
|---|---|---|
| NJ-021 | Switch onboarding language | Preserve answers and dates while updating direction and controls. |
| NJ-022 | Deny location and notification permissions | Keep core tracking usable and avoid repetitive permission pressure. |
| NJ-023 | Today with no observations | Distinguish not recorded from explicitly absent and offer a clear action. |
| NJ-024 | Record start then visit Calendar and Insights | Show the same observation everywhere and distinguish predictions. |
| NJ-025 | Record spotting, symptoms, mood, energy, or notes | Save supported inputs without forcing medical or religious classification. |
| NJ-026 | Record bleeding stop | Update the episode and relevant predictions and reminders consistently. |
| NJ-027 | Undo accidental stop | Restore the intended ongoing state without duplicates. |
| NJ-028 | Correct historical date or delete daily entry | Change only intended records and refresh dependent views. |
| NJ-029 | Bleeding stops then resumes | Preserve the timeline and clarify uncertainty without an unsupported verdict. |
| NJ-030 | Predicted date passes without bleeding | Keep it an estimate and never manufacture an observation. |

### Original journeys: insights, guidance, and qadha

| ID | User journey / trigger | Required outcome |
|---|---|---|
| NJ-031 | Explore several months of Insights | Explain calculations and source records or state insufficient evidence. |
| NJ-032 | Change supported pregnancy or postpartum mode | Preserve history and update relevant guidance, predictions, and reminders. |
| NJ-033 | Ask meaning of an observation | Separate observation from interpretation and show uncertainty. |
| NJ-034 | Ask madhhab question with incomplete timing | Ask relevant clarification and withhold unsupported certainty. |
| NJ-035 | Trigger an approved urgent-guidance rule | Show reviewed safety wording without an unsupported diagnosis. |
| NJ-036 | Use dialect or ambiguous voice dates | Clarify meaning and dates before proposing changes. |
| NJ-037 | AI proposes a record change | Require an explicit structured preview and confirmation. |
| NJ-038 | AI unavailable or missing current records | Disclose limitations and keep ordinary tracking usable. |
| NJ-039 | Enter qadha opening balance | Confirm amount and year without inventing historical dates. |
| NJ-040 | Record a qadha completion | Apply the completion once and show the correct balance. |

### Original journeys: reminders and subscriptions

| ID | User journey / trigger | Required outcome |
|---|---|---|
| NJ-041 | Duplicate or undo qadha completion | Prevent duplicate reduction and preserve correction traceability. |
| NJ-042 | Allocate qadha across Ramadan years | Show understandable allocations and consistent totals. |
| NJ-043 | Period-linked missed-fast suggestion | Keep suggestions separate from confirmed debt and require review. |
| NJ-044 | Edit evidence linked to confirmed qadha | Request reconciliation rather than silently changing debt. |
| NJ-045 | Observation makes reminder obsolete | Update scheduling and open current state from stale notifications. |
| NJ-046 | Notification on a locked or shared phone | Use discreet default wording without unnecessary sensitive detail. |
| NJ-047 | Open notification signed out or as another account | Authenticate and enforce ownership before showing private content. |
| NJ-048 | Travel after recording or scheduling | Preserve original date context and apply the defined reminder timezone policy. |
| NJ-049 | Compare subscription plans | Show price, billing period, features, and renewal terms before purchase. |
| NJ-050 | Successful, failed, cancelled, or interrupted purchase | Grant access only from verified purchase status and prevent duplicate retry effects. |

### Original journeys: account lifecycle and resilience

| ID | User journey / trigger | Required outcome |
|---|---|---|
| NJ-051 | Restore purchases after reinstall or phone change | Restore supported entitlement without exposing another account's records. |
| NJ-052 | Subscription expires or renewal is cancelled | Update access clearly while preserving observations under the stated policy. |
| NJ-053 | Export history or contact support | Explain shared content and minimize sensitive disclosure. |
| NJ-054 | Delete account during an in-flight operation | Prevent delayed operations from restoring deleted data. |
| NJ-055 | Record offline, restart, then reconnect | Preserve supported pending work and sync without duplication. |
| NJ-056 | Edit one record on two devices | Merge only under a defined policy and reconcile incompatible edits. |
| NJ-057 | Server saves but response disappears | Retry idempotently and converge on the durable saved state. |
| NJ-058 | Use RTL, large text, screen reader, or reduced motion | Keep primary journeys and errors understandable and operable. |
| NJ-059 | Update with history and pending writes | Preserve record identity, history, and queue integrity with recovery on failure. |
| NJ-060 | Run signed iPhone and Android journeys | Capture separate device evidence for links, permissions, notifications, purchases, restart, and account transitions. |

### Registration and email delivery depth

| ID | User journey / trigger | Required outcome |
|---|---|---|
| NJ-061 | Email contains leading or trailing spaces | Apply documented normalization before sending and show the intended destination. |
| NJ-062 | Email contains a typographical domain error | Offer correction without silently rewriting the address. |
| NJ-063 | Signup service rejects the request | Retain safe input and explain that signup did not complete. |
| NJ-064 | Signup response is lost | Recover account state without creating duplicate identities. |
| NJ-065 | Resend pressed rapidly | Send at most the allowed number and announce the actual result. |
| NJ-066 | Email provider delays delivery | Explain waiting and retry options without promising delivery time. |
| NJ-067 | Old confirmation arrives after a newer request | Handle token validity coherently and offer recovery. |
| NJ-068 | Confirmation link is malformed | Reject safely without leaking tokens into diagnostics. |
| NJ-069 | Confirmation completes while the waiting screen is open | Refresh session state and advance once. |
| NJ-070 | User returns after confirming externally | Provide a clear recheck or sign-in route rather than an endless waiting screen. |

### Authentication and session boundaries

| ID | User journey / trigger | Required outcome |
|---|---|---|
| NJ-071 | A to B to A during a delayed history response | Reject the original session's response even when the user ID matches again. |
| NJ-072 | Sign out while a save is pending | Apply the secure queue policy and prevent writes from entering another account. |
| NJ-073 | Password reset completes on another device | Apply documented session invalidation behavior and show a recoverable state. |
| NJ-074 | Recovery link opens while another account is signed in | Prevent cross-account credential or record confusion. |
| NJ-075 | Biometric access is cancelled where supported | Keep private content locked and offer the intended alternative. |
| NJ-076 | App returns from background after session revocation | Revalidate before showing protected content or accepting writes. |
| NJ-077 | Two authentication callbacks arrive | Process the resulting session once without duplicate navigation. |
| NJ-078 | Token refresh fails temporarily | Avoid destroying recoverable work or presenting cached data as newly authorized. |
| NJ-079 | User taps Back during recovery | Avoid a dead end and never expose the reset token. |
| NJ-080 | Account is suspended or disabled | Explain available support or recovery without granting protected access. |

### Consent, onboarding, and preferences depth

| ID | User journey / trigger | Required outcome |
|---|---|---|
| NJ-081 | User declines optional analytics | Respect the decision and keep essential functions available. |
| NJ-082 | Consent text changes | Handle versioned consent under the approved policy without silently expanding scope. |
| NJ-083 | Back navigation after many onboarding steps | Preserve answers and show correct previous selections. |
| NJ-084 | App terminates during onboarding save | Resume at a coherent checkpoint without claiming unsaved answers persisted. |
| NJ-085 | Impossible date or inconsistent cycle input | Explain the specific correction without clearing the form. |
| NJ-086 | Changing a prior answer invalidates later input | Show what needs review and preserve unaffected answers. |
| NJ-087 | Skip optional questions | Continue without defaulting skipped answers into facts. |
| NJ-088 | Change preferred language after onboarding | Preserve records, preferences, and navigation context. |
| NJ-089 | Change calendar display preference | Change presentation without changing stored date identity. |
| NJ-090 | Permission setting changes in the operating system | Refresh actual permission status when the app resumes. |

### Observation capture and correction depth

| ID | User journey / trigger | Required outcome |
|---|---|---|
| NJ-091 | Double tap record-start | Create one intended episode and provide coherent feedback. |
| NJ-092 | Record a start in the future | Apply the defined validation using trusted context and explain inconsistencies. |
| NJ-093 | Historical record overlaps another episode | Show the conflict and preserve existing observations until reconciled. |
| NJ-094 | Date-only observation later gains a known time | Preserve provenance and precision without inventing earlier precision. |
| NJ-095 | Remove a time from a previously exact entry | Represent the changed precision explicitly and refresh dependent behavior. |
| NJ-096 | Start entry before midnight and save afterward | Keep the intended local date visible and stable. |
| NJ-097 | Add multiple observations on one day | Preserve individual identities and expose a readable daily timeline. |
| NJ-098 | Edit a private note without changing dates | Avoid unrelated episode or prediction mutations. |
| NJ-099 | Delete one day from a multi-day episode | Preserve remaining entries and reconcile episode boundaries explicitly. |
| NJ-100 | Undo after another device changes the episode | Detect version conflict rather than overwriting newer work. |

### Episodes, history, and reconciliation

| ID | User journey / trigger | Required outcome |
|---|---|---|
| NJ-101 | Split one episode into two | Preview resulting boundaries and preserve observation provenance. |
| NJ-102 | Merge two episodes | Show affected observations and require confirmation under a defined merge policy. |
| NJ-103 | Cancel a split or merge preview | Leave durable records unchanged. |
| NJ-104 | Partial failure during split or merge | Apply atomically or expose a recoverable state without half a result. |
| NJ-105 | Legacy episode contains contradictory boundaries | Show reconciliation without silently deleting information. |
| NJ-106 | Open an episode spanning a year boundary | Display one continuous history across both years. |
| NJ-107 | Search or filter long history | Return correct records without leaking stale account results. |
| NJ-108 | Open a history item deleted on another device | Explain removal and refresh rather than recreate it. |
| NJ-109 | Repeated undo request | Apply restoration once and explain current state. |
| NJ-110 | Undo retention window has passed | Explain unavailable restoration without pretending recovery succeeded. |

### Calendar, Today, and Insights depth

| ID | User journey / trigger | Required outcome |
|---|---|---|
| NJ-111 | Observed and predicted dates coincide | Use distinct labels and accessible visual meaning. |
| NJ-112 | Select a day without an entry | Show not recorded rather than no bleeding. |
| NJ-113 | Prediction recalculation is pending | Show updating and avoid stale certainty. |
| NJ-114 | Change a historical observation while Insights is open | Refresh contributions or clearly mark stale results. |
| NJ-115 | Chart point is selected | Show its contributing records and calculation meaning. |
| NJ-116 | Insufficient complete history | Explain why a trend cannot yet be shown. |
| NJ-117 | Very long or irregular history | Apply the approved calculation eligibility rules and disclose limitations. |
| NJ-118 | Month navigation crosses leap day | Keep dates and selected records correct. |
| NJ-119 | Calendar uses Arabic and English labels | Keep week layout, navigation direction, and selected-day announcements coherent. |
| NJ-120 | Today changes at local midnight | Refresh the current day without moving historical observations. |

### Prediction integrity and evaluation

| ID | User journey / trigger | Required outcome |
|---|---|---|
| NJ-121 | Prediction engine has no eligible history | Show unavailable estimates rather than fabricated dates. |
| NJ-122 | Prediction version changes | Preserve observations and retain version metadata needed for evaluation. |
| NJ-123 | User edits history after a prediction | Recalculate future estimates without rewriting past evaluation snapshots. |
| NJ-124 | User records a period earlier than predicted | Update future estimates and retire obsolete reminders. |
| NJ-125 | User records a period later than predicted | Preserve the prediction as an estimate and update from actual evidence. |
| NJ-126 | Approximate records enter calculation | Apply the explicit uncertainty eligibility policy. |
| NJ-127 | Imported data lacks required context | Exclude or qualify it rather than treating it as fully precise. |
| NJ-128 | User disables predictions | Stop associated presentation and reminders according to the stated setting. |
| NJ-129 | Prediction rollout performs poorly | Roll back independently of observation storage. |
| NJ-130 | Accuracy is reported internally or publicly | Use defined metrics, eligible samples, held-out evaluation, and uncertainty rather than claiming universal accuracy. |

### Medical guidance and life stages

| ID | User journey / trigger | Required outcome |
|---|---|---|
| NJ-131 | Unreviewed medical rule is reached | Show approved uncertainty or unavailable behavior and retain review dependency. |
| NJ-132 | Pregnancy status is uncertain | Avoid presenting unsupported confirmation or fertility certainty. |
| NJ-133 | User changes postpartum status | Keep historical records and reconcile mode-dependent suggestions. |
| NJ-134 | User records medication or contraception where supported | Apply only approved effects and explain limits. |
| NJ-135 | User reports severe symptoms in a note | Use reviewed escalation behavior where supported without implying continuous monitoring. |
| NJ-136 | Safety content is withdrawn | Stop serving the withdrawn version and show an approved replacement or unavailable state. |
| NJ-137 | Guidance exists only in one language | Avoid presenting an unreviewed translation as approved. |
| NJ-138 | User repeatedly receives the same safety notice | Follow the approved acknowledgment policy without suppressing relevant new events. |
| NJ-139 | User asks for a diagnosis | Explain capability limits and provide reviewed next steps. |
| NJ-140 | Device is offline during a guidance update | Distinguish available reviewed cached content from withdrawn or expired content under an explicit policy. |

### Fiqh guidance boundaries

| ID | User journey / trigger | Required outcome |
|---|---|---|
| NJ-141 | User switches madhhab | Recalculate supported interpretations separately and preserve observations and prior provenance. |
| NJ-142 | Madhhab is unknown | Do not assign a default ruling as if selected by the user. |
| NJ-143 | Timing is near a reviewed religious boundary | Use the reviewed boundary pathway and preserve timing uncertainty. |
| NJ-144 | Bleeding interruption has unresolved scholarly treatment | Request clarification or withhold classification without altering observations. |
| NJ-145 | Rule requires missing evidence | Explain which relevant fact is missing without inventing it. |
| NJ-146 | Scholar-approved rule changes | Version the interpretation and identify affected outputs without rewriting observations. |
| NJ-147 | Fiqh automation is disabled remotely | Keep core tracking available and remove unsupported automated conclusions. |
| NJ-148 | User challenges a displayed ruling | Show the applicable reviewed basis and a correction or support route. |
| NJ-149 | Two guidance sources appear contradictory | Avoid merging them into an invented verdict; expose the relevant review dependency. |
| NJ-150 | Religious guidance affects a reminder or qadha suggestion | Propagate only approved interpretation and preserve confirmed user decisions. |

### Qadha ledger depth: later workstream

| ID | User journey / trigger | Required outcome |
|---|---|---|
| NJ-151 | Opening balance includes dates already suggested | Link evidence without adding debt twice. |
| NJ-152 | Completion exceeds remaining balance | Apply the explicit ledger rule and explain the conflict. |
| NJ-153 | Backdated completion changes yearly allocation | Preview affected balances and preserve a traceable correction. |
| NJ-154 | Offline completion retries after reconnect | Apply once using a stable operation identity. |
| NJ-155 | Two devices complete the same intended day | Detect duplicate or conflict and reconcile without silent double counting. |
| NJ-156 | Bleeding overlaps a recorded completion | Flag review without issuing an unsupported verdict. |
| NJ-157 | User disables period-linked suggestions | Keep manual ledger usable and stop repeated prompts. |
| NJ-158 | Episode deletion removes suggestion evidence | Withdraw or revise the suggestion while preserving confirmed debt. |
| NJ-159 | Year or calendar display changes | Preserve ledger identity and allocations independently of formatting. |
| NJ-160 | Qadha feature is outside current launch scope | Hide or clearly gate unavailable actions and retain all acceptance requirements for its release. |

### Notifications and reminders depth

| ID | User journey / trigger | Required outcome |
|---|---|---|
| NJ-161 | User denies permission permanently | Offer an optional settings route and keep tracking usable. |
| NJ-162 | Token rotates after reinstall | Register the current token and retire obsolete delivery targets safely. |
| NJ-163 | Account switches on the same device | Prevent previous-account private notifications or destinations from persisting. |
| NJ-164 | A scheduled notification fires after record deletion | Open current state and avoid asserting obsolete facts. |
| NJ-165 | Quiet hours are configured | Apply the stated local-time policy and test travel transitions. |
| NJ-166 | Several categories fire together | Group or deduplicate without hiding essential information. |
| NJ-167 | Push provider retries delivery | Avoid duplicated user-visible actions where supported and make opening idempotent. |
| NJ-168 | Notification destination no longer exists | Show a safe explanation and valid route. |
| NJ-169 | User disables one category | Stop that category without silently changing others. |
| NJ-170 | Android or iOS restricts background activity | Explain relevant limitations honestly and verify actual platform behavior. |

### AI privacy, grounding, and mutations

| ID | User journey / trigger | Required outcome |
|---|---|---|
| NJ-171 | AI receives stale context after account switch | Discard the response and clear previous-account context. |
| NJ-172 | User asks AI to access another user's records | Deny access through server authorization rather than prompt wording alone. |
| NJ-173 | Retrieved content contains malicious instructions | Treat it as untrusted data and preserve tool and privacy boundaries. |
| NJ-174 | AI mutation preview is edited by user | Execute only the final confirmed structured change. |
| NJ-175 | Record changes after AI preview but before confirmation | Revalidate current version and request reconciliation. |
| NJ-176 | User cancels an AI proposal | Make no record mutation and acknowledge cancellation. |
| NJ-177 | AI times out after executing a confirmed mutation | Recover the operation outcome without repeating it. |
| NJ-178 | Conversation spans midnight and says yesterday | Resolve intended date explicitly where ambiguous. |
| NJ-179 | User deletes AI conversation where supported | Apply the stated retention policy without deleting unrelated observations. |
| NJ-180 | AI generates unsupported source claims | Avoid fabricated authority and use reviewed content or explicit uncertainty. |

### Messaging, community, and safeguarding: conditional scope

| ID | User journey / trigger | Required outcome |
|---|---|---|
| NJ-181 | Send message with unstable connectivity | Show pending, sent, or failed accurately and retry without duplication. |
| NJ-182 | Open a conversation after account change | Authorize membership and reject stale content. |
| NJ-183 | Block another user | Apply the documented messaging and visibility restrictions consistently. |
| NJ-184 | Report abusive content | Capture the intended report and provide a clear acknowledgment without exposing reporter identity. |
| NJ-185 | A blocked sender triggers push delivery | Enforce the approved block policy in delivery and display. |
| NJ-186 | Delete or edit a message where supported | Apply permissions and preserve the intended recipient-visible state. |
| NJ-187 | Upload unsupported or oversized attachment | Reject clearly before claiming successful upload. |
| NJ-188 | Open a private attachment URL as another account | Deny unauthorized access and prevent durable public exposure. |
| NJ-189 | Moderator takes an action | Enforce role permissions and record an appropriate audit event. |
| NJ-190 | Community feature is not in launch scope | Keep its entry points unavailable and record explicit scope rather than pretending verification. |

### Subscriptions, purchases, and entitlements depth

| ID | User journey / trigger | Required outcome |
|---|---|---|
| NJ-191 | Payment succeeds but app closes before acknowledgment | Recover entitlement from verified store or provider state. |
| NJ-192 | Payment pending or requires additional approval | Show pending without prematurely granting paid access. |
| NJ-193 | Renewal callback arrives twice | Apply the event idempotently. |
| NJ-194 | Billing events arrive out of order | Resolve entitlement from authoritative state and event policy. |
| NJ-195 | Refund or revocation occurs | Update access under the published policy without erasing observations. |
| NJ-196 | User buys on one platform and signs in on another | Apply the documented cross-platform entitlement policy. |
| NJ-197 | Restore is attempted using another store account | Prevent ownership confusion and provide clear recovery. |
| NJ-198 | Plan changes from monthly to annual | Show effective timing and verified resulting entitlement. |
| NJ-199 | Price or currency differs by locale | Show actual purchase-sheet terms and avoid stale promotional prices. |
| NJ-200 | Subscription backend is temporarily unavailable | Apply a defined entitlement-cache policy and provide recovery without inventing purchase success. |

### Offline, queues, and multi-device synchronization

| ID | User journey / trigger | Required outcome |
|---|---|---|
| NJ-201 | Create and edit an entry before first synchronization | Sync final intended state with stable identity. |
| NJ-202 | Delete an unsynced entry | Prevent later resurrection by queued creates. |
| NJ-203 | Old device reconnects after deletion | Respect tombstones and newer versions. |
| NJ-204 | Two devices edit different fields | Merge only when the defined policy proves compatibility. |
| NJ-205 | Two devices edit incompatible dates | Show reconciliation and retain recoverable versions. |
| NJ-206 | Queue storage is full or unavailable | Retain input where possible and never claim durable save. |
| NJ-207 | Network repeatedly disconnects during batch sync | Track per-operation outcomes and avoid duplicates. |
| NJ-208 | Session expires while queue is uploading | Stop unauthorized work and resume only under the initiating account's policy. |
| NJ-209 | App update changes queue format | Migrate pending operations without losing identity or ordering dependencies. |
| NJ-210 | Remote deletion arrives while editing | Warn about conflict and never silently recreate the deleted record. |

### Time, location, and prayer-context boundaries

| ID | User journey / trigger | Required outcome |
|---|---|---|
| NJ-211 | International date line repeats or skips a date | Preserve recorded event identity and original context. |
| NJ-212 | Daylight-saving transition repeats an hour | Preserve event order and explicit time context. |
| NJ-213 | User records while flying with uncertain timezone | Support uncertainty without fabricating precision. |
| NJ-214 | Phone clock is wrong | Avoid accepting inconsistent future observations solely from device time. |
| NJ-215 | Location request completes after account switch | Discard stale results and prevent cross-account writes. |
| NJ-216 | Location save partially fails | Avoid falsely reporting complete success and preserve a recovery route. |
| NJ-217 | Location is unavailable or permission denied | Keep basic tracking usable and expose supported manual alternatives. |
| NJ-218 | Prayer calculation inputs change where supported | Recalculate using reviewed settings and show applicable context. |
| NJ-219 | Travel changes fasting-boundary context | Preserve original timing and require reviewed handling for dependent suggestions. |
| NJ-220 | Historical entry lacks timezone | Mark missing context rather than converting it using the current timezone. |

### Accessibility, localization, and interaction depth

| ID | User journey / trigger | Required outcome |
|---|---|---|
| NJ-221 | Largest supported text size on smallest supported screen | Keep dates, balances, errors, and primary actions visible or reachable. |
| NJ-222 | Screen reader selects a calendar date | Announce date, selection, and observed versus predicted status. |
| NJ-223 | Error appears after save | Announce it accessibly and move focus appropriately without losing input. |
| NJ-224 | User cannot distinguish colors | Provide labels, icons, patterns, or accessible descriptions. |
| NJ-225 | Reduced motion is enabled | Keep success and error feedback understandable without animation. |
| NJ-226 | Keyboard covers the form | Keep the active input and save or next action reachable. |
| NJ-227 | External keyboard or switch access is used | Provide logical focus order and operable controls. |
| NJ-228 | Mixed Arabic text, email, and numbers | Render bidirectional content correctly with English numerals where specified. |
| NJ-229 | Translation is missing | Use a controlled fallback rather than exposing localization keys. |
| NJ-230 | Back or swipe-dismiss occurs with unsaved changes | Preserve the draft or clearly confirm discard across supported platforms. |

### Exports, support, and personal-data lifecycle

| ID | User journey / trigger | Required outcome |
|---|---|---|
| NJ-231 | Export spans many years | Produce complete scoped data without truncation or app lockup. |
| NJ-232 | Export starts on account A then account changes | Prevent A's file from appearing in B's session. |
| NJ-233 | Export fails midway | Avoid sharing a partial file as complete and provide retry. |
| NJ-234 | Share sheet is cancelled | Do not treat export as delivered to another person. |
| NJ-235 | Support diagnostics are generated | Redact tokens, private notes, and unnecessary health detail. |
| NJ-236 | Support staff views a user record | Enforce least privilege and appropriate auditability. |
| NJ-237 | Deletion request requires recent authentication | Explain verification and preserve the request through recovery. |
| NJ-238 | Deletion has legally required retention exceptions | Explain the approved policy accurately and minimize retained data. |
| NJ-239 | Delete account then reinstall | Do not restore deleted records through caches or backup behavior. |
| NJ-240 | User requests data correction | Provide traceable correction without silently overwriting unrelated evidence. |

### Backend authorization and security acceptance

| ID | User journey / trigger | Required outcome |
|---|---|---|
| NJ-241 | Client submits another account's record ID | Reject reads and mutations server-side. |
| NJ-242 | Client sends a forged owner identifier | Bind authorization to the authenticated identity. |
| NJ-243 | Direct database access bypasses the UI | Enforce equivalent constraints and row-level security. |
| NJ-244 | Anonymous request reaches a protected function | Reject without exposing private existence or content. |
| NJ-245 | Unprivileged role calls administrative operation | Deny and record appropriate security evidence. |
| NJ-246 | Attachment URL or export link leaks | Apply the intended expiration and authorization protections. |
| NJ-247 | Sensitive data reaches logs or crash reports | Redact or exclude it and verify representative failure paths. |
| NJ-248 | Malicious text appears in notes or messages | Render safely without executing supplied markup or scripts. |
| NJ-249 | Rate limits trigger under abusive traffic | Protect service availability without exposing other users' information. |
| NJ-250 | Secrets accidentally enter an app build | Release checks detect them; use public client configuration only where appropriate. |

### Performance and resource pressure

| ID | User journey / trigger | Required outcome |
|---|---|---|
| NJ-251 | New user loads Today on a slow connection | Show useful loading and recovery rather than blank or false-empty state. |
| NJ-252 | Returning user has years of records | Meet defined load and interaction budgets with correct pagination. |
| NJ-253 | Rapid navigation launches overlapping requests | Cancel or reject stale results and keep screen state coherent. |
| NJ-254 | Low-memory device terminates the app | Recover durable work and handle unsaved drafts under the documented policy. |
| NJ-255 | Phone storage is nearly full | Explain failed local persistence without losing recoverable input. |
| NJ-256 | Long AI conversation or history list grows | Remain responsive under a defined retention and pagination policy. |
| NJ-257 | Image or attachment upload is interrupted | Resume or retry safely without orphaned private assets. |
| NJ-258 | Repeated background and foreground transitions | Avoid duplicate subscriptions, requests, and notifications. |
| NJ-259 | Network changes from Wi-Fi to mobile data | Recover requests without duplicate mutations. |
| NJ-260 | Backend becomes slow during peak use | Apply bounded waits, useful feedback, and safe retry behavior. |

### Release, migration, and operational recovery

| ID | User journey / trigger | Required outcome |
|---|---|---|
| NJ-261 | Old app connects after backend migration | Honor compatibility policy and fail safely where unsupported. |
| NJ-262 | Migration runs over existing observations | Preserve identities, ownership, precision, and recoverability. |
| NJ-263 | Migration is partly applied | Detect capability state and avoid exposing unusable writes. |
| NJ-264 | Migration is rerun | Follow tested idempotency or explicit migration-history rules. |
| NJ-265 | New release introduces tracking regression | Roll back safely without corrupting newer records or queues. |
| NJ-266 | Feature flag disables a faulty dependent capability | Keep core observations available and explain unavailable behavior. |
| NJ-267 | Backup restoration is exercised | Demonstrate approved recovery objectives and authorization after restore. |
| NJ-268 | Health guidance requires urgent replacement | Version content, stop withdrawn behavior, and verify rollout. |
| NJ-269 | Production monitoring detects an anomaly | Identify scope using minimal data and connect it to an actionable recovery procedure. |
| NJ-270 | Release evidence is stale after a code change | Invalidate affected acceptance results and rerun relevant checks. |

### Cross-feature collision journeys

| ID | User journey / trigger | Required outcome |
|---|---|---|
| NJ-271 | Edit episode while reminder delivery is in flight | Save correct data and make the notification destination reflect current state. |
| NJ-272 | Purchase completes during account switch | Bind entitlement to verified ownership and prevent accidental transfer. |
| NJ-273 | Delete account while AI mutation is pending | Reject delayed mutation and clear private response content. |
| NJ-274 | Change life stage while a prediction calculation runs | Discard obsolete results and update affected reminders. |
| NJ-275 | Correct period dates while qadha suggestion preview is open | Invalidate stale preview without changing confirmed debt. |
| NJ-276 | Switch language during an unsaved complex edit | Preserve intent, dates, uncertainty, and draft state. |
| NJ-277 | Restore purchase while session expires | Recover authentication and verify entitlement without granting another account's access. |
| NJ-278 | Export starts during a historical correction | Use a defined snapshot or disclose scope; avoid inconsistent totals. |
| NJ-279 | New remote record arrives during split or merge | Revalidate versions and prevent silent loss. |
| NJ-280 | Disable guidance while AI is answering a related question | Prevent the response from presenting withdrawn guidance as active. |

### Signed-device and platform acceptance depth

| ID | User journey / trigger | Required outcome |
|---|---|---|
| NJ-281 | Confirmation link opens from Gmail on iPhone | Reach the installed app or approved fallback and complete the intended flow. |
| NJ-282 | Recovery link opens from Android email app | Reach password recovery without losing token validity or exposing it. |
| NJ-283 | App is force-closed before a notification tap | Cold start into the authorized destination with current data. |
| NJ-284 | Permission is revoked outside the app | Reflect actual OS state on resume and keep core functions usable. |
| NJ-285 | App is backgrounded during a save | Recover the actual durable result after resume. |
| NJ-286 | Device is locked during sensitive activity | Apply defined screen privacy and session policies on return. |
| NJ-287 | Store sandbox purchase completes on each platform | Capture verified entitlement and restoration evidence separately. |
| NJ-288 | Real device reconnects after hours offline | Demonstrate queue persistence, correct ordering, and account safety. |
| NJ-289 | Accessibility service is active during primary journey | Verify actual spoken labels and operability on both platforms. |
| NJ-290 | Minimum and current supported OS versions are used | Record exact builds and platform-specific pass, fail, or blocker evidence. |

### Long-term use, comprehension, and acceptance governance

| ID | User journey / trigger | Required outcome |
|---|---|---|
| NJ-291 | User returns after several months | Explain current state without treating missing months as confirmed observations. |
| NJ-292 | User has a long history of irregular records | Preserve uncertainty and avoid misleading aggregate certainty. |
| NJ-293 | User changes phone and restores authorized data | Reconcile synced history and explicitly identify unsynced limitations. |
| NJ-294 | User misunderstands bleeding versus period wording | Validate comprehension with users and revise labels without forcing classification. |
| NJ-295 | User cannot find how to correct a mistake | Provide discoverable edit and undo paths tested in usability sessions. |
| NJ-296 | User believes confirmation sent means delivered | Use wording that explains the next action without asserting inbox placement. |
| NJ-297 | Feature has no implementation in current app | Record the gap and apply an explicit scope decision with inaccessible dependent actions. |
| NJ-298 | One automated test is linked to many requirements | Verify its assertions actually establish each linked outcome. |
| NJ-299 | Specialist or device evidence is unavailable | Complete independent work and record exact blockers without marking full verification. |
| NJ-300 | Final launch review is requested | Require current traceable evidence, closure of critical defects, approved scope, and explicit separation of engineering completion from launch approval. |

## Execution sequence

1. Inspect the actual app, backend, open changes, applicable repository instructions, and existing evidence. Do not infer current implementation from this register.
2. Map all 300 NJ rows and the existing 200 PT rows to actual features and dependencies. Preserve the original PT source; request it if inaccessible rather than inventing it.
3. Establish a reproducible baseline. Fix critical account isolation, unauthorized access, data loss, duplicate writes, and deletion resurrection first.
4. Complete signup, email confirmation, recovery, onboarding, observation recording/correction, and consistent daily navigation.
5. Verify offline recovery, concurrent edits, permissions, reminders, accessibility, and long histories. Expand relevant conditional features under the approved scope.
6. Execute signed-device journeys and obtain specialist review where needed. Complete independent engineering while genuine external dependencies remain.
7. Revalidate evidence after relevant code, configuration, migration, or policy changes.

## Suggested repository artifacts

- `NISWAH_APP_WIDE_300_ACCEPTANCE_JOURNEYS.md`: this requirements source.
- `NISWAH_JOURNEY_COVERAGE.csv`: one row per stable NJ ID plus evidence dimensions and linked PT IDs.
- `NISWAH_JOURNEY_VERIFICATION_REPORT.md`: current results, exact baseline, defects, and blockers.
- `NISWAH_LAUNCH_SCOPE.md`: explicit feature decisions and unavailable dependent behavior.

Do not mark cases verified merely because CI is green or a screen exists. One test may cover several requirements only when its assertions establish each required outcome. Cross-feature workflows require integration evidence; server authorization requires backend evidence; platform behavior requires signed-device evidence.

## Release gate

Launch approval remains separate from engineering completion. Require explicit launch scope, current evidence for included behavior, no unresolved critical privacy/account-isolation/data-loss defects, verified migration compatibility, appropriate device coverage, and approved medical/fiqh behavior or verified restrictions. Define service recovery objectives and performance budgets before evaluating those requirements. Missing external evidence stays visible; it does not become a pass.

## Copyable coding-agent instruction

> Adopt this register alongside the original 200 PT cases. Inspect current implementation and evidence first. Create a traceable coverage matrix for every ID; do not renumber or silently omit requirements. Prioritize core period integrity and account safety, then complete approved app-wide journeys. Implement missing behavior and meaningful tests, not documentation alone. Keep conditional features tied to explicit launch scope. Report automated, staging, signed-iPhone, signed-Android, and specialist evidence separately. Preserve uncertainty, observations, account boundaries, and confirmed ledger entries. Continue authorized reversible engineering until complete or only genuine external dependencies remain. Do not merge, release, or change production without existing authorization. Report counts by status, exact failing requirements, and the next concrete action. This file alone supplies no verification evidence.
