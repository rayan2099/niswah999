# AI Context Trust-Boundary Remediation

Status: IMPLEMENTED ON BRANCH — VALIDATION/CI PENDING  
Branch: `feat/ai-context-trust-boundary`  
Base: PR #4 head `c79fb78be31acd6fb4923666a9d4daafbe94fb76`  
Related KB review: PR #6 (research/review only; must remain separate)

## Implementation checkpoint

Implemented on `feat/ai-context-trust-boundary` on top of PR #4's canonical
menstrual-data branch.

Current implementation now:

- uses `bleeding_episodes` as the sole AI authority for current bleeding;
- keeps `cycle_entries` only as a temporary informational source for legacy
  symptom/note fields;
- distinguishes successful empty reads from unavailable/failed reads;
- reads Madhhab authority from `public.users` server-side and ignores client
  Madhhab claims at the Fiqh endpoint;
- preserves `UNKNOWN`, `UNSET`, and server `UNAVAILABLE` separately;
- removes the legacy silent Shafi'i parser fallback;
- exposes TTC as enabled/disabled only after an explicit user-scoped preference,
  otherwise UNKNOWN;
- removes the pregnancy engine's hardcoded postpartum-to-Nifas phase;
- exposes Nifas as UNKNOWN unless a legitimate Fiqh authority exists;
- adds provenance labels to derived pregnancy and canonical bleeding values;
- closed-enum validates any legacy client Fiqh classification and labels it
  `client_computed_unverified`;
- stops the current app client from sending its legacy
  `cycle_entries`-derived Fiqh classification;
- quotes/escapes user-authored notes so they cannot create trusted context
  delimiters.

A separate pre-existing product-level Nifas authority was discovered in
`PregnancyStatusController`; it remains outside this engineering PR and is
tracked in `docs/NIFAS_AUTHORITY_FOLLOWUP.md` pending qualified review.

Validation is not yet claimed because this stacked branch does not currently
trigger the repository's main-target-only CI workflow.

## 1. Purpose

Make every AI feature consume an explicit, canonical, provenance-preserving user-state contract.

The target architecture is:

```text
User observations / persisted profile state
        ↓
Deterministic canonical domain state
        ↓
Server-assembled UserAiContext
        ↓
Scope-specific formatter
        ↓
AI feature
```

The AI must never become the authority that reconstructs factual health state, invents a Madhhab, collapses uncertainty, or treats a derived estimate as a direct observation.

## 2. Current verified problems

### AICTX-TB-01 — bleeding context still depends on legacy cycle_entries

`supabase/functions/_shared/ai_user_context.ts` currently queries:

```text
cycle_entries(date, flow, symptoms, notes)
```

and independently reconstructs:

- `isCurrentlyBleeding`
- `daysIntoCurrentEpisode`
- last entry date
- recent symptoms / cycle notes

The current-bleeding calculation scans the latest legacy flow rows.

PR #4 already introduced the canonical model:

- `bleeding_episodes`
- `bleeding_observations`
- `CanonicalBleedingStatusResolver`

The canonical model explicitly exists so a successful canonical write remains authoritative even if the best-effort `cycle_entries` projection fails.

Therefore the AI context is currently behind the product's canonical data model and can disagree with the dashboard / real stored state.

### AICTX-TB-02 — unavailable reads can collapse into apparent empty history

The current assembly code reads `result.data ?? []` for `cycle_entries` without representing query availability.

A backend/auth/network read failure can therefore become:

```text
hasHistory = false
```

instead of:

```text
state unavailable / not verified
```

Unknown must never be converted into "no history".

### AICTX-TB-03 — Madhhab is still accepted from the client at the AI boundary

The app now has server-authoritative Madhhab state in:

- `public.users.madhhab`
- `public.users.madhhab_selection_state`

and the client controller correctly distinguishes:

- `unset`
- `unknown`
- `selected`

However `buildUserAiContext` still accepts `clientMadhhab` and `clientMadhhabState`.

The AI boundary should read the canonical server state directly. A client may be stale, buggy, modified, or operating with old local storage.

UNKNOWN and UNSET must remain first-class states all the way to the prompt.

### AICTX-TB-04 — legacy Madhhab parser still contains a silent default

`lib/core/models/madhhab_type.dart` currently contains an invalid-value fallback to `MadhhabType.shafii`.

No invalid, missing, legacy, or unknown Madhhab representation may resolve to a real school by default.

### AICTX-TB-05 — client fiqh classification is an unverified arbitrary string

`clientFiqhState` is currently accepted as any string and inserted into the AI context as `client_computed`.

Until deterministic classification is fully server-authoritative, any client-computed classification must:

1. be limited to a closed allow-list of known enum values,
2. remain explicitly marked `client_computed_unverified`,
3. never override canonical factual state,
4. never be treated as scholar-approved knowledge,
5. fail closed to `not_provided` for unknown values.

### AICTX-TB-06 — TTC state is absent from UserAiContext

The app has `TtcModeController`, but TTC mode is not represented in `UserAiContext`.

A user's active TTC mode must be visible to the AI features that legitimately need it, with explicit provenance.

For this remediation, do not silently infer TTC from cycle behavior, pregnancy history, questions, or fertile-window use.

### AICTX-TB-07 — postpartum and Nifas are conflated

The pregnancy status layer currently has a postpartum mode and also emits a `phase` string that can say `نفاس` based on a fixed postpartum-day window.

Postpartum is a factual/product state. Nifas is a Fiqh classification and must not be manufactured from a generic postpartum timer.

The AI contract must represent them separately:

- factual postpartum state
- Nifas / Fiqh state, only when deterministically and legitimately known
- otherwise Nifas remains `unknown/not_provided`

No Madhhab-specific Nifas conclusion is to be added in this engineering PR from model memory or generic assumptions. PR #6's reviewed knowledge program remains the authority path for future production rules.

### AICTX-TB-08 — derived pregnancy/cycle values lack field-level provenance

The current pregnancy block labels the whole object as:

```text
source: pregnancy_profile_table
```

while fields such as week, trimester, month, weeks-to-due, days-postpartum, and days-into-episode are derived values.

The AI must be able to distinguish:

- directly user-entered / observed facts
- persisted profile selections
- deterministic derived values
- client-computed unverified classifications
- unavailable / unknown values

A derived estimate must never be formatted as though the user directly reported it.

## 3. Target UserAiContext v2

Bump:

```text
contextVersion: '1' → '2'
```

Recommended contract shape:

```ts
type Availability = 'available' | 'unavailable';

// Madhhab read failure/corruption is distinct from a real user UNSET answer.
type MadhhabState = 'unset' | 'unknown' | 'selected' | 'unavailable';

type ProvenanceKind =
  | 'user_observed'
  | 'user_reported_historical'
  | 'user_selected'
  | 'persisted_profile'
  | 'system_derived'
  | 'client_computed_unverified'
  | 'not_provided';

interface Provenance {
  kind: ProvenanceKind;
  source: string;
  derivedAt?: string;
  inputs?: string[];
}

interface UserAiContextV2 {
  contextVersion: '2';
  generatedAt: string;

  bleeding: {
    availability: Availability;
    factualState:
      | 'no_history'
      | 'open_confirmed'
      | 'open_uncertain'
      | 'completed_history'
      | 'unknown';
    openEpisodeId: string | null;
    startDate: string | null;
    startPrecision: string | null;
    startSource: string | null;
    daysIntoOpenEpisode: number | null;
    completedEpisodeCount: number | null;
    isDegraded: boolean;
    provenance: Provenance;
  };

  pregnancy: {
    availability: Availability;
    mode: 'pregnant' | 'postpartum' | 'not_pregnant' | 'unknown';
    week: number | null;
    trimester: number | null;
    approxMonth: number | null;
    weeksToDue: number | null;
    daysPostpartum: number | null;
    provenance: {
      mode: Provenance;
      week?: Provenance;
      trimester?: Provenance;
      approxMonth?: Provenance;
      weeksToDue?: Provenance;
      daysPostpartum?: Provenance;
    };
  };

  ttc: {
    state: 'enabled' | 'disabled' | 'unknown';
    provenance: Provenance;
  };

  fiqh: {
    madhhabState: 'unset' | 'unknown' | 'selected' | 'unavailable';
    madhhab: 'hanafi' | 'maliki' | 'shafii' | 'hanbali' | null;

    nifasState:
      | 'not_applicable'
      | 'unknown'
      | 'client_computed_unverified'
      | 'deterministic';

    classification: string | null;
    classificationSource:
      | 'client_computed_unverified'
      | 'server_deterministic'
      | 'not_provided';

    uncertainty: string;
  };

  wellbeing: { /* existing scoped fields */ };
  symptoms: { /* existing scoped fields */ };
  notes: { /* existing scoped fields */ };
  safetyFlags: string[];

  dataFreshness: {
    fetchedAt: string;
  };
}
```

Exact naming may differ if the implementation can make the same guarantees more cleanly.

## 4. Canonical bleeding implementation

### Required server read

For current factual state, query `bleeding_episodes` directly using the authenticated user's RLS-scoped client.

Do not derive "currently bleeding" from `cycle_entries`.

Minimum fields:

- id
- lifecycle_status
- continuation_certainty
- start_date
- start_precision
- start_source
- end_date
- end_precision
- end_source

If recent symptom/note data still legitimately lives in the legacy projection, it may temporarily remain a separate informational source, but:

1. it must never determine whether an episode is open,
2. it must never determine days into the canonical open episode,
3. it must be labeled as legacy/informational,
4. projection failure must not erase canonical bleeding state.

Prefer canonical `bleeding_observations` for recent factual observations where practical in this workstream.

### Required mapping

```text
no open episode + no completed episodes → no_history
open + continuation_certainty=confirmed → open_confirmed
open + continuation_certainty=uncertain → open_uncertain
no open episode + completed episodes → completed_history
read failure / inconsistent unreadable state → unknown
```

`daysIntoOpenEpisode` is derived from canonical `start_date`, with provenance:

```text
kind = system_derived
inputs = [bleeding_episodes.start_date]
```

Do not treat `open_uncertain` as confirmed active bleeding.

## 5. Madhhab authority

### Server source of truth

`buildUserAiContext` must query `public.users` for:

- `madhhab`
- `madhhab_selection_state`

The client must not be able to upgrade:

```text
unknown → selected
unset → selected
invalid value → selected
```

### Required invariants

```text
state=selected → madhhab must be one allowed value
state=unknown → madhhab must be null
state=unset → madhhab must be null
invalid DB combination → fail closed to unset/unknown + uncertainty; never choose a Madhhab
```

Remove any parser fallback that maps an invalid value to Shafi'i or another school.

## 6. TTC

Do not infer TTC.

Preferred implementation order:

1. If a server-authoritative TTC field already exists by implementation time, read it directly.
2. Otherwise accept the current user-scoped TTC preference as explicit client state, but label it `client_computed_unverified` / `user_selected` as appropriate and validate it strictly.
3. Do not represent absent/old-client TTC as `false`; use `unknown`.

Only include TTC in AI scopes that need it.

## 7. Postpartum versus Nifas

Remove any prompt-facing implication that factual postpartum status automatically equals a Fiqh Nifas classification.

Required separation:

```text
pregnancy.mode = postpartum
```

may be true while:

```text
fiqh.nifasState = unknown
```

That is an acceptable and expected state.

If a future deterministic Nifas engine is introduced, it must be separately provenance-labeled and backed by approved rules. This remediation must not invent those rules.

Update Dr Niswah wording so postpartum medical guidance does not claim a Fiqh classification merely because postpartum mode is active.

## 8. Derived-value provenance

At minimum the following fields require explicit derived provenance:

- pregnancy week
- trimester
- approximate month
- weeks to due date
- days postpartum
- days into current bleeding episode
- any predicted cycle / fertile-window values if later added to context

For each derived value preserve:

- source data set / field
- `system_derived`
- derivation timestamp
- enough input identity to audit how the number was obtained

No prompt formatter may drop the distinction between direct fact and estimate.

## 9. Error semantics

Never collapse a failed read to a valid empty state.

Examples:

```text
bleeding_episodes query error ≠ no_history
pregnancy_profile query error ≠ confirmed not pregnant
users madhhab query error ≠ unset because user never answered
```

Represent availability / uncertainty explicitly and format the AI prompt to ask or avoid relying on the unavailable state.

## 10. Scope rules

### Dr Niswah

May receive:

- pregnancy/postpartum factual state
- TTC when relevant
- canonical bleeding factual state
- recent health observations
- safety flags

Must not receive or infer a definitive Fiqh ruling from postpartum alone.

### Fiqh Advisor

May receive:

- server-authoritative Madhhab state
- canonical factual bleeding state
- pregnancy/postpartum factual state
- a strictly validated deterministic/client classification with provenance

Must not:

- default Madhhab
- upgrade UNKNOWN
- treat raw bleeding fact as a ruling
- treat a client-computed state as scholar-approved knowledge

### General Assistant

Only minimum relevant state.

### Dream Interpreter

Keep context minimal. It must never inherit medical or Fiqh authority because the state is present.

## 11. Required code changes

Expected primary touch points:

- `supabase/functions/_shared/ai_user_context.ts`
- `supabase/functions/_shared/ai_user_context.test.ts`
- `supabase/functions/_shared/pregnancy_status.ts`
- `supabase/functions/_shared/pregnancy_status.test.ts`
- `supabase/functions/fiqh-advisor-chat/index.ts`
- `supabase/functions/ai-assistant-chat/index.ts`
- `supabase/functions/dr-niswah-chat/index.ts`
- `supabase/functions/dream-interpreter-chat/index.ts`
- `lib/features/ai_advisor/client_fiqh_state_provider.dart`
- `lib/core/models/madhhab_type.dart`
- TTC client request plumbing where needed

Potential DB migration only if required to persist TTC server-side. Do not add a migration merely to avoid representing a legitimate `unknown` state.

## 12. Mandatory tests

### Canonical bleeding

1. Canonical open episode + no `cycle_entries` row → AI context still says open.
2. Canonical open episode + stale `cycle_entries.flow=none` → canonical episode wins.
3. No open episode + stale `cycle_entries.flow=heavy` → AI context does not claim an open episode.
4. Open uncertain episode → context is `open_uncertain`, not confirmed.
5. Canonical bleeding query error → `unknown/unavailable`, not `no_history`.
6. First-ever open episode is visible immediately.
7. Completed episodes remain factual history without fabricating current bleeding.

### Madhhab

8. selected+hanafi → hanafi.
9. selected+maliki → maliki.
10. selected+shafii → shafii.
11. selected+hanbali → hanbali.
12. unknown → null Madhhab, explicit unknown.
13. unset → null Madhhab, explicit unset.
14. corrupt/invalid Madhhab string → no default school.
15. client tries to send a different Madhhab than server state → server state wins.

### Fiqh classification

16. allowed classification value → accepted and provenance preserved.
17. arbitrary string / prompt-like payload → rejected to `not_provided`.
18. no client classification → no fabricated classification.

### TTC

19. enabled → explicit enabled.
20. disabled → explicit disabled.
21. old client / unavailable preference → unknown, not disabled.

### Postpartum / Nifas

22. postpartum factual state + no Fiqh classification → postpartum=true, Nifas=unknown.
23. no automatic Nifas conclusion solely from elapsed postpartum days.
24. Dr Niswah prompt does not equate postpartum mode with a definitive Fiqh ruling.

### Provenance

25. pregnancy week is marked derived.
26. trimester/month/weeks-to-due are marked derived.
27. days-postpartum is marked derived.
28. days-into-open-episode is marked derived from canonical episode start.
29. rendered context retains fact-vs-derived wording.

### Isolation / trust boundary

30. User A cannot obtain User B's bleeding, pregnancy, TTC, Madhhab, wellbeing, symptom, or notes context.
31. No `user_id` accepted from the client for server queries.
32. Every query remains on the caller's JWT-scoped Supabase client.
33. Malformed client context payload cannot insert arbitrary trusted lines into the prompt.

## 13. Acceptance gate

This workstream is PASS only when all of the following are true:

- AI current bleeding state comes from canonical `bleeding_episodes`, not legacy `cycle_entries`.
- read failures remain explicit unknown/unavailable states.
- TTC exists in UserAiContext with honest provenance.
- postpartum factual state and Nifas classification are distinct.
- UNKNOWN/UNSET Madhhab can never silently become a real Madhhab.
- server Madhhab state wins over client input.
- client Fiqh state is closed-enum validated and untrusted/provenance-labeled until server authority exists.
- derived estimates preserve field-level provenance.
- all four AI endpoints consume the v2 contract without regressions.
- automated tests cover the mandatory cases above.
- CI passes.
- no change is made to PR #6's review artifacts or review status.

## 14. Non-goals

This PR does NOT:

- approve any Fiqh atom,
- replace scholar review,
- publish PR #6 knowledge,
- implement RAG/embeddings,
- invent Nifas rules,
- rewrite the whole menstrual prediction engine,
- merge PR #4,
- merge PR #6.

It exists only to repair the production AI user-state trust boundary.
