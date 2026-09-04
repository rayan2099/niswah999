> ⚠️ **PROPOSED — NOT IMPLEMENTED.** This remediation plan is a design only. It requires technical/product review and, where marked, legal/compliance approval before execution. Nothing in this document should be treated as fixed or compliant until implementation and retesting are complete.

# Privacy & Compliance Audit — Phase 3: Remediation Design

| System | Niswah (Flutter) | Commit | 13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f |
|---|---|---|---|

## Root-Cause Map

| Finding | Symptom | Root cause | Confidence | Legal dependency | Remediation phase |
|---|---|---|---|---|---|
| PC-001 | Consent checkbox exists but doesn't gate sign-up | Checkbox state (`_agreed`) was never wired into the auth button handlers — a UI/logic disconnect, likely introduced when the checkbox was added without also gating the buttons | High | Legal must define what "adequate consent" means for this product before the gate is re-implemented | R1 |
| PC-002 | No account-deletion feature | Feature was never built — `AuthRepository` interface has no deletion method, and no screen calls one | High | Legal/product must confirm deletion semantics (immediate hard-delete vs. grace-period soft-delete) before build | R1 |
| PC-003 | AI/Gemini data sharing undisclosed | No privacy policy exists to disclose it in, and no in-app supplementary notice was added when the Gemini integration shipped | High | Legal must confirm required disclosure language once a policy exists (or independently, via an in-app AI notice) | R1 (depends on R1 policy work) |
| PC-004 | No privacy policy document | Never authored/published; tracked upstream as RD-007 | High | Must be legal-authored or legal-reviewed, not engineering-authored | R0 (prerequisite to R1) |
| PC-005 | Onboarding step 9 mislabeled "Privacy" | Step was likely originally scoped as a real privacy/consent step and was implemented instead as an anonymity toggle, with the label left unchanged | Medium | None — pure product/copy fix | R2 |
| PC-006 | "Data Export" only offers curated PDFs | Feature was built to solve a different problem (sharing reports with doctors/husbands) and was placed under an export-sounding heading | Medium | Legal must confirm whether a full-export right applies before scoping a real export feature | R2 (pending legal scope) |
| PC-007 | No retention policy | Never defined by product; no purge jobs built | High | Legal/compliance to set retention periods per data category before enforcement is built | R2 |
| PC-008 | No DPA evidence for Supabase/Google | Vendor contracting is outside engineering's control/visibility | N/A (not a code defect) | Fully a legal/procurement task | R0 (parallel, non-blocking of engineering work) |
| PC-009 | No age-gate | Never scoped as a requirement | High | Legal must determine if an age floor applies before an age-gate is engineered | R3 (pending legal determination) |
| PC-010 | Cross-border transfer unconfirmed | Region config lives in Supabase/Google project settings, not in this repo | N/A | Legal/compliance + infra owner to confirm regions and any required transfer mechanism | R0 (parallel) |
| PC-011 | Dormant `secret_vault_entries` table | Schema was added ahead of a feature that was never wired into the client | Low (assumption: intentionally deferred, not accidentally exposed) | None unless/until the feature ships | R3 (confirm-and-close, low effort) |

---

## Remediation Principles Applied

| Principle | Application here |
|---|---|
| Collect intentionally | Do not add new fields; fix consent/disclosure/deletion around what's already collected |
| Minimize | Add expiry to locally-cached precise location (PC-007) |
| Respect choice | Make the consent checkbox (once policy exists) actually gate sign-up (PC-001) |
| Delete honestly | Build a real account-deletion path that exercises the schema's existing (correct) cascade design (PC-002) |
| Disclose reality | Publish a real privacy policy (R0) and add an explicit AI-sharing notice (PC-003) before claiming any of this is solved |
| Limit vendor data | Confirm/obtain DPA text for Supabase and Google (PC-008) — non-engineering |
| Separate legal decisions | Nothing below invents a retention period, age threshold, or lawful basis — each such item routes to legal/compliance review first |

---

## Remediation Phase Table

| # | Action | Findings closed | Data affected | Code/config | Policy/disclosure impact | Vendor impact | Legal review | Rollback | Retest |
|---|---|---|---|---|---|---|---|---|---|
| R0-1 | Author and publish a real Privacy Policy + Terms of Use (web-hosted, linked from the app) | Prerequisite for PC-001, PC-003, PC-004, PC-006 | All categories | None (content/infra, not app code) — but app-side `url_launcher` wiring is required once the doc exists (tracked as RD-007's fix, cross-referenced not duplicated here) | Full | None | **Mandatory legal authorship/review** | N/A (additive) | Re-run POLICY-xx reality-check once published |
| R0-2 | Obtain/confirm DPA or equivalent processing terms with Supabase and Google (Gemini API usage) | PC-008 | Supabase/Gemini-processed categories | None | Referenced in privacy policy once available | Vendor/procurement | **Mandatory legal/contractual** | N/A | Confirm DPA references in policy doc |
| R0-3 | Confirm hosting/processing regions for Supabase project and Gemini API calls; determine if a transfer mechanism (SCCs etc.) is needed | PC-010 | All Supabase/Gemini-processed categories | Supabase project config (non-repo) | Referenced in privacy policy | Vendor/procurement | **Mandatory legal** | N/A | Document region + mechanism in Legal Review Register |
| R1-1 | Wire `_agreed` checkbox state into the Email/Phone/Google sign-up handlers so unchecked = disabled action; make the "Privacy Policy"/"Terms of Use" spans tappable via `url_launcher` (coordinate with RD-007's fix rather than duplicating it) | PC-001 (jointly with RD-007) | Account creation flow | `lib/features/auth/presentation/screens/sign_in_screen.dart` | Requires R0-1 to exist first (linking to nothing defeats the purpose) | None | Legal to approve consent-checkbox wording once R0-1 exists | Straightforward revert of the gating logic | Manual test: attempt sign-up with box unchecked → blocked; with box checked → allowed; tapping policy text opens the doc |
| R1-2 | Add a distinct, explicit consent step for special-category health/religious data (cycle, pregnancy, madhhab) — e.g. a single clear onboarding screen before step 4, replacing/supplementing the current generic checkbox, with its own timestamp+policy-version persisted server-side (new `consent_events` table or `profiles` columns) | PC-001 (heightened-consent aspect) | PD-002, PD-003, PD-004 | New onboarding screen; new Supabase table/columns; `AuthRepositoryImpl` write | Content drafted with/approved by legal | None | **Mandatory legal** (wording, and whether this is even required) | Feature-flaggable | Verify consent event is persisted with timestamp + policy version; verify withdrawal path (see R1-2b) |
| R1-2b | Define and build a withdrawal path for the R1-2 consent (e.g. a toggle in Privacy Settings that, when withdrawn, is documented to stop specific processing — exact behavior to be defined with product/legal) | PC-001 | Same as above | `profile_screen.dart` Privacy Settings section | Legal to define what "withdrawal" changes in practice | None | **Mandatory legal** | N/A | Toggle off → verify defined behavior actually occurs |
| R1-3 | Build a real in-app "Delete my account" flow: confirmation screen → calls a new Supabase Edge Function (using the service-role key server-side, never client-side) that invokes `auth.admin.deleteUser`, letting the existing `ON DELETE CASCADE` schema do the rest; sign the user out and route to sign-in on success | PC-002 | All categories | New `AuthRepository.deleteAccount()` method + implementation; new Edge Function; new UI in `account_settings_screen.dart`/`profile_screen.dart` | Must state clearly what deletion does to the OTHER participant's copy of shared private messages (cross-ref DI-012) | None (uses existing infra) | Legal to confirm hard-delete vs. grace-period approach, and to approve user-facing deletion-confirmation copy | Feature-flaggable rollout | Controlled test (Phase 2B, synthetic account): create → populate → delete → verify primary + related tables + local cache all cleared |
| R1-4 | Add an explicit in-app disclosure, surfaced at first use of any AI feature (Dr. Niswah, Fiqh advisor, Dream Interpreter), stating that message content is processed by a third-party AI provider (Google) — short in-context notice, not just buried in the policy | PC-003 | PD-008, PD-009 | New first-use notice component in `dr_niswah_chat_screen.dart`, `dream_interpreter_screen.dart`, fiqh advisor entry point | Legal to approve exact wording | None (disclosure only) | Legal to approve wording | Trivial to remove | Manual test: fresh account → open each AI feature → notice appears once, not repeatedly |
| R2-1 | Re-scope onboarding step 9: either restore a real privacy/consent purpose to a step actually titled "Privacy," or rename it to "Community Identity"/"Anonymous Mode" to match its actual function | PC-005 | UX only | `lib/features/onboarding/presentation/screens/onboarding_screen.dart` (`_Privacy` widget + step comment) | Minor copy change | None | No | Trivial | Visual/manual review |
| R2-2 | Scope and build a genuine "export my data" feature (structured JSON/PDF containing account, cycle, pregnancy, madhhab, messages, community content, AI transcripts) separate from the existing curated-report PDFs, once legal confirms an export right applies | PC-006 | All categories | New export screen/service | Legal to confirm scope of what must be included | None | Legal to confirm before scoping | Feature-flaggable | Controlled test: synthetic account → request export → verify completeness and no other-user data leakage |
| R2-3 | Define retention periods per data category with product/legal, then implement: (a) expiry on the locally cached `PrayerLocationController` coordinates (e.g. clear on sign-out, or after N days of inactivity), (b) a scheduled purge/anonymization job in Supabase for categories legal designates | PC-007 | PD-005 (immediate, low-risk fix) + all Supabase categories (pending legal input) | `prayer_location_controller.dart` (clear-on-logout is a safe, non-legal-dependent first step); Supabase scheduled functions for the rest | Retention periods stated in privacy policy once defined | None | Legal to set periods; engineering can ship the location-cache clear-on-logout immediately without waiting | Location fix: trivial. Purge jobs: dry-run first | Verify location cache cleared after sign-out; verify purge job (once built) against synthetic expired records only |
| R3-1 | Confirm `secret_vault_entries` is intentionally dormant/deprecated; if a future release activates it, route through this same remediation process (consent, disclosure, retention) before shipping | PC-011 | PD-010 | None now; process note for future work | N/A now | N/A | No (until activated) | N/A | Confirm with product owner and close as "acknowledged, dormant" |
| R3-2 | Legal/product to determine whether an age-gate is required for target markets; if yes, scope minimum-age declaration/self-attestation at sign-up | PC-009 | Account creation | New onboarding field if required | Legal-defined | None | **Mandatory legal** | N/A | N/A until scoped |

---

## Deletion Remediation Requirements (for R1-3)

Per template §69, the account-deletion fix must explicitly cover:

- **Primary record**: `auth.users` row (via `auth.admin.deleteUser`, server-side only).
- **Related records**: confirmed by schema to cascade — `profiles`, `chat_threads`/`chat_messages`, `community_posts`/`comments`/`likes`, `cycle_entries`, `symptoms_log`, `prayer_entries`, `adah_ledger`, `istihadah_episodes`, `nifas_records`, `ramadan_records`, `pregnancy_milestones`, `pregnancy_profile`, `secret_vault_entries`, `dream_entries`, `private_conversations`/`private_messages`.
- **Files**: none identified as stored in Supabase Storage in this review (PDF reports appear locally rendered) — **confirm this explicitly during implementation**, do not assume.
- **Caches**: local `shared_preferences` (cycle/pregnancy cache, prayer location, madhhab, marital status) must be cleared on-device at deletion time, not just server-side rows.
- **Third parties**: Google Gemini API does not offer a per-conversation deletion callback in the paths reviewed — document this limitation explicitly to legal/users rather than silently omitting it (i.e., disclose "AI chat content already sent to our AI provider may not be retrievable/deletable from their systems" if that is confirmed true by legal/vendor terms).
- **Backups**: cross-reference BR-006 — OS-level device backups of local caches, and Supabase's own backup retention, are separate from this fix and must be documented as a distinct, known residual-retention window rather than implied as solved by this change.
- **DI-012 cross-reference**: deleting a user must not silently corrupt the OTHER participant's message history in a confusing way — decide and document (with legal/product) whether the other participant sees a tombstone ("this user deleted her account") or the conversation simply vanishes, before shipping R1-3.
- **Verification**: a post-deletion query across all listed tables for the deleted `user_id` must return zero rows in the synthetic-account controlled test before this is marked closed.

---

## Remediation Exit Gate Status

- [x] Root cause documented for every open finding.
- [x] Technical fix defined for every PC0/PC1/PC2 finding.
- [x] Product/policy impact identified.
- [x] Legal-review dependency identified per item.
- [x] Vendor impact identified (Supabase, Google).
- [x] Data migration/deletion impact understood (see Deletion Remediation Requirements).
- [x] Retest defined per action.
- [x] No compliance conclusion is based on unsupported assumption — every legal-dependent item is explicitly routed to LEGAL/COMPLIANCE OWNER REVIEW REQUIRED rather than resolved here.

This plan is a design artifact only. No code in this repository has been modified as part of this audit.
