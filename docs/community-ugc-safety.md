---
type: decision
status: implemented, not yet applied to any database
date: 2026-10-30
---

# Community user-generated-content safety (App Store guideline 1.2)

Decision (rayan, 2026-10-29): Community stays in the launch, so it must
meet App Store Review Guideline 1.2 for user-generated content. Community
posts, comments and member-to-member private messages are all UGC.

Related: [Community feature map](../project-hub/generated/feature-community.md),
journeys NJ-183 (block) and NJ-184 (report).

## What 1.2 asks for, and where it is

| Requirement | Server (authoritative) | App |
| --- | --- | --- |
| Filter objectionable material before it is posted | `community_blocked_terms` + `community_text_violation()`; triggers on posts, comments, author names and private messages raise `NSW01` | Plain-language error; the composer keeps the text so she can edit it |
| Report offensive content | `report_community_content()` (post, comment, private message, member); snapshot kept for moderators; idempotent; 20 a day per reporter; 3 different reporters auto-hide a post/comment pending review | ••• menu on posts and comments, post detail menu, member preview sheet, chat menu, long-press a received message |
| Block abusive users | `user_blocks`; SELECT policies hide a blocked member's posts and comments from the blocker; triggers refuse comments on each other's posts, new conversations and messages in either direction (`NSW04`) | Block in the same menus; content disappears at once; conversations with blocked members hidden; Profile → Blocked members to undo |
| Timely response to reports; remove content and eject the user | `community_moderation_queue()`, `resolve_community_report()` (dismiss / remove content / remove and suspend), `lift_community_suspension()`, all `is_admin()` only; suspended members cannot post, comment or message (`NSW03`) | Profile → Moderation queue, visible to moderators only, oldest first, flags reports older than 20 h |
| Terms (EULA) with no tolerance for objectionable content or abusive users | `community_terms_acceptances`; posting, commenting and messaging need the current `community_terms_version()` (`NSW02`) | Non-dismissible acceptance gate (checkbox + "Agree and continue") before the Community tab and Profile → Messages; full text at Community → Community guidelines and Profile → Community guidelines |
| Published contact information | — | Guidelines screen shows `NISWAH_SUPPORT_EMAIL` (dart-define) |

Code:
[migration](../supabase/migrations/20261030090000_community_ugc_safety.sql),
[terms text](../lib/features/community/safety/community_terms.dart),
[safety repository](../lib/features/community/safety/community_safety_repository.dart),
[controller](../lib/features/community/safety/community_safety_controller.dart),
[report/block actions](../lib/features/community/safety/community_safety_actions.dart),
[terms gate](../lib/features/community/safety/community_terms_gate.dart),
[moderation queue](../lib/features/community/safety/moderation_queue_screen.dart).

Verification:
[SQL check](../test/security/community_ugc_safety.sql) (run with
`test/security/run_sql_checks.sh`; fails with
`EXCLUDE_MIGRATION=20261030090000_community_ugc_safety.sql`),
[contract test](../test/community_safety_contract_test.dart) (app names and
terms version equal the migration's),
[flow tests](../test/community_safety_flows_test.dart).

## Before release (owner actions)

1. Apply `20261030090000_community_ugc_safety.sql` to staging, verify, then
   prod, each with explicit approval. Until it is applied, the app's report,
   block and terms calls fail against that environment.
2. Make at least one moderator account: in the SQL Editor,
   `update public.users set role = 'admin' where id = '<auth user id>';`
   (clients cannot set `role`; see 20261021090000).
3. Build with `--dart-define=NISWAH_SUPPORT_EMAIL=<address>`; the guidelines
   screen falls back to "use Report" copy without it.
4. In App Store Connect: support URL and the same contact address; in Review
   Notes, say where Report/Block/Guidelines are and offer a moderator demo
   account if asked.
5. Someone checks the moderation queue at least daily; the guidelines promise
   a response within 24 hours.

## Moderation runbook

- Queue: Profile → Moderation queue, or
  `select * from public.community_moderation_queue(200);` as a moderator.
- Dismiss restores a post/comment that was only auto-hidden by reports.
  Remove hides a post/comment (deletes a private message). Remove and
  suspend also suspends the author from posting and messaging.
- Lift a suspension: `select public.lift_community_suspension('<user id>');`.
- Extend the word filter (whole words, Arabic diacritics/tatweel and alef
  forms are normalised):
  `insert into public.community_blocked_terms (term) values ('...');`
  Keep terms unambiguous; the list blocks the whole post.

## Open questions

- Support email address for the dart-define (not in the repo).
- The starter word list is deliberately short; a native-speaker review of
  the Arabic terms is worth doing before launch.
- Data export (Profile → Export My Data) does not yet include the member's
  own blocks and reports.
