# Product decisions needed from the founder (F-001, F-002)

These are **product decisions, not engineering defects**. Nothing here has been
wired in or removed; each item states what exists today, what each choice would
cost, and what I recommend. Facts below were verified against the code, the
local database schema and the web reference app (`src/`), not assumed.

---

## F-001 — Screens that exist in code but that no user can reach

Reachability was established by reference analysis of `lib/` (no route, button or
`Navigator.push` opens them) and by the git history (`git log -S` finds no
commit that ever added an entry point): they were ported from the web app and
never wired in.

| Surface | Code | Backend | Web app entry point (the intent) | Reachable today |
|---|---|---|---|---|
| **Prayer logging** | `PrayerTrackingScreen` 392 lines + view model + repository (1.2k lines) | `prayer_log` table + RLS **exists** | Today's prayer widget logs prayers | **No** |
| **Guided journeys** | `GuidedJourneysScreen` 324 lines | none (static lessons) | Profile -> "Essential tools" -> Journeys | No |
| **Resource library** | `ResourceLibraryScreen` 163 lines + view model + repository | `educational_resources` table **does not exist** | Discover tab | No |
| **Ghusl guide** | `GhuslGuideScreen` 475 lines | none (static steps) | Profile -> "Essential tools" -> Ghusl guide | No |
| **Account / Settings screens** | `AccountSettingsScreen` 91 lines, `settings_screen.dart` 283 lines | `users` / profile | (superseded by Profile) | No |

### 1. Prayer logging — highest priority (Fiqh/prayer experience)

- **Status**: functional code that has never been reachable. Today shows a
  *prayer status card* (what is obligatory / lifted for the current Fiqh state)
  but a woman cannot **record** that she prayed, missed or owes a prayer.
- **What exists**: statuses `prayed | qadha_required | lifted | missed`, a
  `fiqh_state_at_time` column, per-user RLS (`prayer_log_own`), a data-export
  section, and a local data source.
- **Defects in the dormant code** (would surface the moment it is wired):
  the screen hard-codes `userId: 'demo-user'` in two places (an invalid UUID for
  the `user_id uuid` column -> every write fails); `fiqh_state_at_time` must come
  from the **canonical** Fiqh state (the same evidence Today rules on — the class
  of bug behind D-004/D-011), not from anything legacy.
- **User value**: high — qadha (make-up) tracking is directly tied to the Haid /
  Nifas rulings the app already makes; the prayer card without logging is half a
  feature.
- **Risk of shipping unreachable**: the personal-data export lists a `prayer_log`
  section that can never contain data; the feature inventory and any marketing
  copy that mentions prayer tracking overstate what a user can do; ~1.2k lines of
  code that no test exercises end to end.
- **Minimal work to wire in (S–M)**: an entry from Today's prayer card ->
  `PrayerTrackingScreen(userId: <session user>)`; replace both `'demo-user'`;
  feed `fiqh_state_at_time` from the canonical state; then acceptance coverage
  (log -> persisted row -> Today's card agrees -> deletion cascades). The RLS and
  table need no change.
- **Minimal work to remove/defer (S)**: delete the screen + view model + repository
  + tests, drop the export section, and record "no prayer logging in this release"
  in the product notes; keep the `prayer_log` table (no data, no risk).
- **Recommendation**: **wire it in** if the launch story includes prayer/qadha
  tracking; otherwise **remove it explicitly** — do not ship it dormant.

### 2. Guided journeys (static lessons)

- Content is hard-coded; "Complete today" only pops the route — **no progress is
  stored**, so as written it cannot deliver a journey. User value is
  content-dependent; wiring needs a progress model (local or server) to be more
  than a reading list.
- Wire-in (M): Profile -> Essential tools row + a progress store.
  Remove (S): delete the screen. Recommendation: **defer** (remove from the
  release scope) unless a content owner exists.

### 3. Resource library

- Reads `educational_resources`, **a table that does not exist** in the schema, so
  it silently falls back to five hard-coded English items (not localized
  Arabic). Shipping it would present placeholder content as an educational library.
- Wire-in (M–L): create the table + RLS + real content + localization, then a
  Discover/Profile entry. Remove (S). Recommendation: **defer** until real content
  exists.

### 4. Ghusl guide

- Complete, localized (EN/AR), static and **safe to ship** — no backend. Directly
  supports the app's purpose (ghusl after Haid/Nifas).
- Wire-in (S): a row on Profile -> Essential tools (as in the web app); an additional
  link from Today around the Haid -> Tahara transition is a product option. Remove (S).
- Recommendation: **wire it in** (lowest cost, clear value); the Fiqh content
  should still be reviewed by a qualified scholar before launch.

### 5. Account / Settings screens

- Superseded by Profile, which already has sign-out, account deletion, language,
  privacy policy and notification settings. `AccountSettingsScreen`'s "Privacy &
  security" tile only shows a cosmetic snackbar, and `settings_screen.dart` is a
  legacy screen that writes a madhhab through a **different model**
  (`MadhhabType`) than the tri-state (`unset / unknown / selected`) the rest of the
  app relies on — wiring it in would risk bypassing that state.
- Recommendation: **remove** both (S). Nothing user-visible is lost.

### Summary of recommended choices

| Surface | Recommendation | Cost |
|---|---|---|
| Prayer logging | Wire in (or explicitly remove — never dormant) | S–M |
| Ghusl guide | Wire in | S |
| Guided journeys | Defer / remove from scope | S |
| Resource library | Defer until real content exists | S (remove) |
| Account/Settings screens | Remove | S |

Until you decide, the coverage matrix records these five as **BLOCKED —
structurally unreachable** (a product state, not an external dependency).

---

## F-002 — "Delete conversation" (private messaging)

### What exists today (verified)

- **No delete UI and no repository method.** The conversations list has no delete
  affordance (`MSG-06` is "not implemented", not "untested").
- **Database**: `private_conversations` / `private_messages` have policies for
  INSERT, SELECT and (messages only, recipient-only) UPDATE of `is_read`. **There is
  no DELETE policy**, so RLS denies any client delete even though the role holds the
  table privilege.
- **Cascades**: both tables reference `auth.users` with `ON DELETE CASCADE`. Deleting
  an **account** deletes the whole conversation and every message for **both**
  participants — the other person silently loses that history.
- `unique_pair (participant_one, participant_two)` is an *ordered* pair: two users who
  open a conversation with each other at the same moment can each insert (A,B) and
  (B,A) — **two conversations for one pair** (not covered by any test; a small
  hardening item independent of this decision).

### The decision — semantics must be chosen, not assumed

| | What "delete" means | Other participant | Data retained | RLS / schema work |
|---|---|---|---|---|
| **A1. Hide for me (per-user soft hide)** | The conversation disappears from *my* list only | Unaffected; still sees everything | All rows kept | Add `hidden_by_one / hidden_by_two` (or a `conversation_participants` table); UPDATE policy limited to my own flag; list query filters it; a new message can un-hide (product choice) |
| **A2. Delete for both (server delete)** | Rows are removed for everyone | Loses the history without consent | Nothing (except backups) | Add DELETE policies for a participant on both tables; needs a clear confirmation and an explicit "the other person will lose it too" statement |
| **A3. Leave + anonymize** | I disappear from the conversation; my messages remain for the other person marked as "deleted user" | Keeps a readable history | Other person's copy | Larger change (nullable sender, display rules) |
| **B. Defer** | No delete anywhere | — | All | None; make sure no UI implies deletion exists |

### Privacy / retention implications to weigh

- **Sensitive content**: these are private messages between women about health and
  faith. Users will expect to be able to remove them.
- **A2** is the only option that erases data server-side but harms the other party and
  needs abuse thinking (evidence removal in a harassment case).
- **A1** protects the person who deletes without erasing evidence; retention is then
  a policy decision (how long hidden data is kept, and what account deletion does).
- **Account deletion today already erases a pair's history for both** — whichever
  option you choose, the account-deletion behaviour should be stated in the privacy
  policy.
- Nothing above is implemented or "invented"; each option is a starting point for
  your decision.

### Recommendation

Choose **A1 (hide for me)** for the release if messaging ships: it gives users the
control they expect, harms nobody, and keeps retention decisions for later.
If messaging is not a launch feature, choose **B** and make sure no screen
implies deletion. **Please decide before I implement anything.**
