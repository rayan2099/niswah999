import { assert, assertEquals } from 'https://deno.land/std@0.208.0/assert/mod.ts';
import { classifyNoEvidence, noEvidenceReply } from './no_evidence_replies.ts';

Deno.test('classifyNoEvidence — a vague short message gets a clarifying question', () => {
  assertEquals(classifyNoEvidence('ممكن تجاوب على السؤال؟', 'ممكن تجاوب على السؤال؟'), 'clarify');
  assertEquals(classifyNoEvidence('ماذا يدل اللون البني؟', 'ماذا يدل اللون البني؟'), 'clarify');
});

Deno.test('classifyNoEvidence — a long off-topic message is out of scope', () => {
  const q = 'أبغى وصفة كيكة شوكولاتة سهلة وسريعة للضيوف بدون فرن لو سمحتي ضروري اليوم';
  assertEquals(classifyNoEvidence(q, q), 'out_of_scope');
});

Deno.test('classifyNoEvidence — an in-domain question with no knowledge is not_covered', () => {
  const q = 'هل الإفرازات البنية بعد الدورة طبيعية؟';
  assertEquals(classifyNoEvidence(q, q), 'not_covered');
});

Deno.test('noEvidenceReply — no emergency line, no ruling, in her language', () => {
  for (const persona of ['dr_niswah', 'fiqh_advisor'] as const) {
    for (const kind of ['clarify', 'out_of_scope', 'not_covered'] as const) {
      const ar = noEvidenceReply(kind, persona, 'ar');
      const en = noEvidenceReply(kind, persona, 'en');
      assert(/[\u{0600}-\u{06FF}]/u.test(ar));
      assert(!/[\u{0600}-\u{06FF}]/u.test(en));
      assert(!ar.includes('الطوارئ'), `${persona}/${kind} repeats the emergency line`);
    }
  }
});
