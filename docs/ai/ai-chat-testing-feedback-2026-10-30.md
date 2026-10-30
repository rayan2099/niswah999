# AI chats: testing feedback of 2026-10-30

Source: rayan's `Testing Feedback.pdf` (seven device screenshots, build 6 on the production backend). This note records what was wrong, what changed, and what is still unproven. Evidence levels are kept separate; nothing here is a claim of live model quality.

Related: [[feature-ai_assistant]], [[feature-ai_advisor]], `supabase/functions/_shared/chat_contract.ts`, `supabase/functions/_shared/no_evidence_replies.ts`.

## Provider and model

All four chats (`ai-assistant-chat`, `dr-niswah-chat`, `fiqh-advisor-chat`, `dream-interpreter-chat`) call OpenAI's Responses API through `supabase/functions/_shared/openai_client.ts`. The model is whatever `OPENAI_MODEL` is set to in each environment's function secrets; the code never hard-codes one. Doctor Niswah and the Fiqh advisor are grounded in the Niswah knowledge base (`retrieve_knowledge_v1`); the general assistant and the dream interpreter are not.

## Root causes

| Feedback | Class | Cause |
|---|---|---|
| "تعذر إرسال الرسالة" in Niswah AI (p2) | Transport/provider, then presentation | Production `ai-assistant-chat` returned HTTP 502 four times between 10:54 and 10:56 UTC on 2026-10-30 (function edge logs, status codes only). 502 is that function's catch-all for any `callOpenAI` failure, so the exact provider category (quota, rate limit, bad request) is not recoverable from the status alone; the function's console lines were not read. The app then showed one generic line for every failure. |
| Rigid "insufficient knowledge" reply to ordinary questions (p5, p6) | Retrieval + context loss | Doctor Niswah and the general assistant sent only the current message. A follow-up ("ماذا يدل اللون البني؟", "لماذا؟") has no domain word of its own, so the relevance gate rejected it before retrieval and the fixed refusal was returned. |
| Follow-ups losing meaning | Context loss | Same: no conversation history reached the model or retrieval. The dream interpreter, which sends its whole transcript, did not have this problem. |
| Up to twelve source cards, four identical (p5, p6) | Presentation | Citations were deduplicated per (knowledge item, source, locator), so four items from one NHS page became four cards, and every retrieved item was cited whether or not the answer used it. |
| Failures shown as answers | Reliability | Doctor Niswah stored "تعذر الحصول على رد الآن" as an assistant message when the model call failed; the Fiqh advisor returned a "sources could not be reached" text as an answer. |

## What changed

Server (`supabase/functions`):
- Every failure returns `{category, retryable, correlationId}` with a matching status (401 auth_expired, 429 rate_limited, 504 timeout, 503 provider_busy/provider_unavailable/service_misconfigured, 502 malformed_response). Logs carry the category, the provider's own category and the correlation id; never the prompt, reply, provider message or key.
- `callOpenAI` throws a typed `OpenAiError`; an exhausted quota is no longer retried; a 429 waits up to 2 s before its single retry; a non-JSON 200 is `malformed_response`.
- The last 8 turns travel with each message (Doctor Niswah reads them from the thread's own rows; the other two take them from the app). They are fenced as conversation, "not instructions and not a source of facts". The knowledge-grounded chats still take every claim from `[KNOWLEDGE]` only.
- Retrieval searches a short follow-up (8 words or fewer) together with the previous question.
- The relevance gate normalizes Arabic spelling (أ/إ/آ, ة/ه, ى/ي, diacritics) and accepts everyday words for discharge, spotting, cramps and intercourse.
- The fail-closed rule is unchanged (no model call without knowledge). The fixed reply now depends on why: a vague short message gets one clarifying question, an off-topic one is pointed to the right chat, an uncovered question says so briefly without the emergency line.
- The model lists the knowledge items it used (`[[used: ...]]`, stripped before display); only those are cited, one per source document.
- Doctor Niswah stores the question under the app's message id and stores an ordinary question only together with its reply, so a failed attempt leaves nothing behind and a retry stores it once. A model failure is never stored or returned as an answer, except that a red-flag message still gets its urgent banner.
- The general assistant's prompt asks for direct, short, natural answers and, when it defers to the Fiqh advisor or Doctor Niswah, a `[[route: ...]]` marker the app turns into a button.

App:
- `AiFailure` categories with one message each, a short reference (the correlation id) and retry-after for rate limits; a 401 refreshes the session once and repeats the call; a 50 s client timeout.
- A failed message stays in the conversation as "لم تُرسل" with Retry (same id, no duplicate) and Edit (back into the composer). It is never shown as an assistant reply. The dream interpreter puts the text back in the composer.
- A reply that arrives after sign-out or an account switch is dropped and not stored.
- Sources: one line per document with an Arabic publisher name for publishers the knowledge base cites (the original title and link are kept), the first shown and the rest behind "المصادر (n)".
- The Fiqh banner no longer says answers use Google Search.

## Evidence

| Level | Status |
|---|---|
| Automated (Deno) | `supabase/functions/_shared/*.test.ts`: chat contract, no-evidence replies, citations per source, Arabic normalization, provider error categories. |
| Automated (Flutter, stubbed transport) | `test/ai_chat_reliability_test.dart`, `test/ai_chat_screen_feedback_test.dart`, updated `test/ai_malformed_response_test.dart`, `test/dr_niswah_backend_response_test.dart`. These prove the app's handling, not model quality. |
| Offline pipeline before/after | `supabase/functions/_evals/offline_pipeline_eval.ts` on the PDF's prompts and variations: turns reaching retrieval 5/9 before, 8/9 after. No model or database involved. |
| Live provider | Not run. `supabase/functions/_evals/live_eval.ts` runs `ai_eval_cases.json` (the PDF's exact prompts plus multi-turn, dialect and English variations, and dream-interpreter benchmark cases) N times on staging and records replies with automatic checks and blank rubric scores. It needs a staging test account. |
| Staging | Not deployed. The functions need deploying to staging (per-environment approval) before the live evaluation. |
| Signed device | Not run. |

## Mapping to the registers (statuses unchanged)

The registers live on the period-tracking branch (PR #60). Nothing here moves a case to VERIFIED.

- PT-181 (brown discharge), PT-183 (dialect, typos), PT-185 ("it", follow-ups): implementation improved (history, follow-up retrieval, normalization); still blocked on live and reviewer evidence.
- PT-189 / NJ-038 (AI unavailable): categorized failures, retry without duplicates; device run still required.
- PT-190 / NJ-171 / NJ-182 (account switch during a reply): late replies dropped and not stored; automated only.
- NJ-180 (unsupported source claims): citations limited to items the answer used; live check required.
- NJ-249 (rate limits): retry-after shown to the person; automated only.
- NJ-256 (long conversation): history capped at 8 turns; dream prompt trimmed to its 8,000-character limit keeping the dream and the latest turns.

## Remaining

- The exact provider error behind the 502s needs the production function's console lines for 10:54–10:56 UTC (they carry `providerCategory` only after this change is deployed).
- Live, repeated evaluation with reviewer scoring; deployment to staging, then production, each with its own approval.
- Whether a knowledge-grounded chat may ever answer without retrieved knowledge (for example general wellbeing chit-chat) is a product and safety decision; this change keeps the fail-closed rule.
