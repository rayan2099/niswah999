// Offline, deterministic before/after evaluation of the parts of the AI
// pipeline that decide whether a message can be answered at all: what
// retrieval searches with, whether the relevance gate lets it through, and
// which fixed reply a no-evidence message gets. It calls no model and no
// database, so it says nothing about live answer quality.
//
//   deno run --allow-read supabase/functions/_evals/offline_pipeline_eval.ts [old_gate.ts]
//
// "before" is the pre-2026-10-30 behavior: the message alone through the
// old gate. "after" is the message plus, for a short follow-up, the previous
// question, through the current gate.

import { checkQueryRelevance } from '../_shared/kb_relevance_gate.ts';
import { type ChatTurn, retrievalQueryFor } from '../_shared/chat_contract.ts';
import { classifyNoEvidence } from '../_shared/no_evidence_replies.ts';

interface Case {
  id: string;
  feature: string;
  turns: string[];
}

// The gate as it was before this change, from a path given on the command
// line (git show origin/main:supabase/functions/_shared/kb_relevance_gate.ts
// > /tmp/old_gate.ts). Without it only the "after" columns are filled.
const beforePath = Deno.args[0];
const beforeGate: ((q: string) => { allow: boolean }) | null = beforePath
  ? (await import(new URL(beforePath, `file://${Deno.cwd()}/`).href)).checkQueryRelevance
  : null;

const { cases } = JSON.parse(
  await Deno.readTextFile(new URL('./ai_eval_cases.json', import.meta.url)),
) as { cases: Case[] };

let beforePass = 0;
let afterPass = 0;
let total = 0;
console.log('case\tturn\tbefore_gate\tafter_gate\tafter_no_evidence_kind\tmessage');
for (const c of cases) {
  if (c.feature !== 'dr-niswah-chat' && c.feature !== 'fiqh-advisor-chat') continue;
  const history: ChatTurn[] = [];
  c.turns.forEach((turn, i) => {
    const before = beforeGate ? beforeGate(turn).allow : null;
    const query = retrievalQueryFor(history, turn);
    const after = checkQueryRelevance(query).allow;
    const kind = after ? '-' : classifyNoEvidence(query, turn);
    console.log(`${c.id}\t${i + 1}\t${before}\t${after}\t${kind}\t${turn}`);
    total++;
    if (before) beforePass++;
    if (after) afterPass++;
    history.push({ role: 'user', content: turn }, { role: 'assistant', content: '(reply)' });
  });
}
console.log(
  `\nturns reaching retrieval: before ${beforeGate ? `${beforePass}/${total}` : 'n/a'}, after ${afterPass}/${total}`,
);
