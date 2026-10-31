# AI chats: TestFlight Feedback 2 (2026-10-31)

Source: rayan's `Testflight Feedback 2.pdf` (five pages, TestFlight build 7 on the production backend). Product direction from rayan: the OpenAI model is the primary conversation engine; answers should be natural, concise and helpful even when Niswah's library has no source; the dream interpreter is excluded.

Related: [[ai-chat-testing-feedback-2026-10-30]], [[feature-ai_assistant]], [[feature-ai_advisor]], `supabase/functions/_shared/answer_policy.ts`.

## Important context

Build 7 talks to the production backend, whose AI functions were last deployed before PR #82 (2026-10-30). The screenshots therefore show pre-#82 behavior. The causes below were checked against current `main` (03aa321) and are still present there, so they are real defects in the code, not only stale deployments.

## Root causes (current main)

| PDF note | Cause in code |
|---|---|
| p1 "لا تتوفر لدي في المعرفة المتاحة..." for a normal health question | `dr-niswah-chat` returned a fixed reply without calling the model whenever retrieval found nothing (the "fail-closed gate"), and its prompt made `[KNOWLEDGE]` the only allowed source for any health claim, so even a model call refused whatever the library did not state. |
| p1, p3 "Urgent Maternal Warning Signs" (CDC) under unrelated answers | Doctor Niswah searched the safety-escalation library for every message, and `citationsForAnswer` cited every retrieved item when the model omitted `[[used:]]`. |
| p3 "لا يوجد علاج يُحدَّد بناءً على لون الدم وحده" (withholding + three questions) | Same KB-only prompt: general, well-established information was treated as unsupported, so the model asked questions instead of answering. |
| p2 (liked) routing to the right chat; p4 general AI only refers | The general assistant's prompt said it does not give medical or religious answers and must point to the specialist chats. Routing stayed, but answering was forbidden. |
| p4 "اسألي أي سؤال فقهي" opens Niswah AI | `dashboard_screen.dart` opened `DrNiswahChatScreen()` with the default `general` mode. |
| fiqh questions without a madhhab | `fiqh-advisor-chat` returned a fixed "choose your madhhab" reply; a question matching the state-dependent pattern (e.g. "هل يجوز لي ...") with an unresolved state returned a fixed refusal. Both without calling the model. |
| circular handoffs | Nothing stopped a specialist from pointing back to the chat she came from. |
| thread opened in the wrong assistant | `notification_navigator.dart` always opened chat notifications as Doctor Niswah, and `initialThreadId` was resumed whatever the thread's type. |

## What changed

Server (all three conversational chats; `dream-interpreter-chat` is untouched):
- `answer_policy.ts`: one shared conversation style (direct first sentence, short by default, Saudi/Gulf phrasing, follow-ups from history, one clarifying question only when it matters, no repeated disclaimers, no invented sources or approval, never claims to change records).
- The model always answers. Library items are used and cited only when relevant; otherwise the model answers from well-established general knowledge and must not imply the library or a reviewer verified it.
- Trailing markers `[[topic]]`, `[[verify]]`, `[[used]]`, `[[route]]` are stripped and turned into `notice` and `route` fields. `decideNotice` is deterministic: a health or fiqh answer with no cited library item gets `aiGenerated: true`; the verification line only when the model flagged a personal decision.
- Citations: none unless the model names the item; safety-escalation library searched only for red-flag messages or questions about warning signs; no retrieval for greetings.
- Fiqh: answers without a madhhab (agreed positions directly, differences briefly, asks the madhhab when it changes the answer); with a madhhab it leads with that school. Unresolved current state no longer refuses: the model is told not to decide her state and answers per case.
- Handoffs: `routed_from` is sent with the first exchange after a handoff; a route back to that chat, or to itself, is dropped server-side and hidden in the app.
- Unchanged: auth, rate limits (urgent messages still bypass), red-flag banner and `flagged_conversations`, history limits, correlation ids and log redaction.

App:
- Notices under answers (`answer_notice_policy.dart`): the AI-generated line and verification lines, not repeated under short same-topic follow-ups or within two answers; a persistent one-line AI notice under the composer.
- Dashboard fiqh shortcut opens the Fiqh advisor; Doctor Niswah's "فقه" tile opens the Fiqh advisor; chat notifications open the thread in the chat its type belongs to; a thread of another type is never resumed.
- The Fiqh banner and header no longer claim answers come only from a reviewed library.

## Evidence levels

- Automated: `supabase/functions/_shared/chat_pipeline.test.ts` drives the three real handlers against a fake Supabase and a fake OpenAI (11 of 14 fail on the old handlers); `answer_policy.test.ts`; Flutter `ai_answer_notice_policy_test.dart`, `ai_chat_routing_test.dart`. These prove the pipeline, not answer quality.
- Live provider: `_evals/live_eval.ts` with the TF2-* cases in `_evals/ai_eval_cases.json` on staging. Results and failures are recorded in the PR, not here.
- Physical device: not done by this change.
- Medical or scholarly review: not done. The notices describe limitations; they do not make an answer correct and do not remove Niswah's responsibility.
