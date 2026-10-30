// Live evaluation of the four AI chats against a deployed environment.
// Runs every case in ai_eval_cases.json REPEATS times as a synthetic test
// account, records each reply with automatic checks, and leaves the rubric
// scores (relevance, helpfulness, Arabic naturalness, concision, grounding,
// clarification, safety) blank for a reviewer.
//
// Staging only. Never point this at production or at a real person's
// account: it writes chat threads and messages as the signed-in user.
//
//   NISWAH_EVAL_URL=https://<staging-ref>.supabase.co \
//   NISWAH_EVAL_ANON_KEY=... NISWAH_EVAL_EMAIL=... NISWAH_EVAL_PASSWORD=... \
//   REPEATS=3 deno run --allow-net --allow-env --allow-read --allow-write \
//     supabase/functions/_evals/live_eval.ts > eval-results.jsonl
//
// Not yet run: it needs a staging test account and model credentials on
// staging, which this change does not provision.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const PRODUCTION_REF = 'jkmjobvxfrmuwafczvtw';

interface EvalCase {
  id: string;
  feature: 'ai-assistant-chat' | 'dr-niswah-chat' | 'fiqh-advisor-chat' | 'dream-interpreter-chat';
  turns: string[];
  madhhab?: string;
  checks: Record<string, unknown>;
}

const url = Deno.env.get('NISWAH_EVAL_URL') ?? '';
if (!url || url.includes(PRODUCTION_REF)) {
  console.error('Set NISWAH_EVAL_URL to a staging project. Production is refused.');
  Deno.exit(2);
}
const client = createClient(url, Deno.env.get('NISWAH_EVAL_ANON_KEY')!);
const { error: signInError } = await client.auth.signInWithPassword({
  email: Deno.env.get('NISWAH_EVAL_EMAIL')!,
  password: Deno.env.get('NISWAH_EVAL_PASSWORD')!,
});
if (signInError) {
  console.error('Sign-in failed:', signInError.message);
  Deno.exit(2);
}
const userId = (await client.auth.getUser()).data.user!.id;
const repeats = Number(Deno.env.get('REPEATS') ?? '3');
const { cases } = JSON.parse(
  await Deno.readTextFile(new URL('./ai_eval_cases.json', import.meta.url)),
) as { cases: EvalCase[] };

const sentences = (t: string) => t.split(/[.!؟?\n]+/).filter((s) => s.trim().length > 2).length;
const questions = (t: string) => (t.match(/[؟?]/g) ?? []).length;
const isArabic = (t: string) => /[\u{0600}-\u{06FF}]/u.test(t);

for (const c of cases) {
  for (let run = 1; run <= repeats; run++) {
    const threadId = crypto.randomUUID();
    if (c.feature === 'dr-niswah-chat') {
      await client.from('chat_threads').insert({
        id: threadId, user_id: userId, title: `eval ${c.id}`, thread_type: 'drNiswah', status: 'active', metadata: { eval: true },
      });
    }
    const history: { role: string; content: string }[] = [];
    const transcript: string[] = [];
    for (const [index, turn] of c.turns.entries()) {
      const requestId = crypto.randomUUID();
      const started = Date.now();
      const body = c.feature === 'dr-niswah-chat'
        ? { threadId, content: turn, clientMessageId: requestId, history }
        : c.feature === 'fiqh-advisor-chat'
        ? { question: turn, madhhab: c.madhhab, madhhab_state: 'selected', history }
        : c.feature === 'dream-interpreter-chat'
        ? { prompt: [...transcript, `User: ${turn}`, 'Assistant:'].join('\n') }
        : { content: turn, madhhab: null, madhhab_state: 'unset', history };
      const { data, error } = await client.functions.invoke(c.feature, {
        body,
        headers: { 'x-niswah-request-id': requestId },
      });
      const reply: string = data?.reply ?? data?.text ?? '';
      const citations: { url?: string }[] = data?.citations ?? [];
      const urls = citations.map((x) => x.url ?? '');
      console.log(JSON.stringify({
        case: c.id, feature: c.feature, run, turn: index + 1, message: turn, requestId,
        ms: Date.now() - started,
        error: error ? String(error.message ?? error) : null,
        kind: data?.kind ?? null, route: data?.route ?? null, urgent: data?.urgent ?? null,
        reply,
        auto: {
          arabic: isArabic(reply),
          sentences: sentences(reply),
          questions: questions(reply),
          citations: citations.length,
          unique_citation_urls: new Set(urls).size === urls.length,
          markdown: /(^|\n)\s*([#*-]|\d+\.)\s|\*\*/.test(reply),
        },
        rubric: Object.fromEntries(
          ['relevance', 'helpfulness', 'arabic_naturalness', 'concision', 'grounding', 'clarification', 'safety']
            .map((k) => [k, null]),
        ),
      }));
      history.push({ role: 'user', content: turn }, { role: 'assistant', content: reply });
      transcript.push(`User: ${turn}`, `Assistant: ${reply}`);
    }
    if (c.feature === 'dr-niswah-chat') {
      await client.from('chat_threads').delete().eq('id', threadId).eq('user_id', userId);
    }
  }
}
await client.auth.signOut();
