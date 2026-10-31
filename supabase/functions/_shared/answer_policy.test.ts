import { assertEquals } from 'https://deno.land/std@0.208.0/assert/mod.ts';
import {
  acceptRoute,
  answerMetaInstruction,
  asksAboutWarningSigns,
  decideNotice,
  extractAnswerMeta,
  normalizeRoutedFrom,
} from './answer_policy.ts';

Deno.test('extractAnswerMeta — strips trailing markers in any order and reads their values', () => {
  const meta = extractAnswerMeta('جواب قصير.\n\n[[used: HL-1, HL-2]]\n[[topic: health]]\n[[verify: yes]]\n[[route: fiqh]]');
  assertEquals(meta.text, 'جواب قصير.');
  assertEquals(meta.topic, 'health');
  assertEquals(meta.verify, true);
  assertEquals([...meta.usedIds!], ['HL-1', 'HL-2']);
  assertEquals(meta.route, 'fiqh');
});

Deno.test('extractAnswerMeta — a marker inside the text is removed too, and unknown values are ignored', () => {
  const meta = extractAnswerMeta('أولًا [[topic: banana]] جواب.\n[[route: dreams]]');
  assertEquals(meta.text, 'أولًا  جواب.');
  assertEquals(meta.topic, null);
  assertEquals(meta.route, null);
  assertEquals(meta.usedIds, null);
  assertEquals(meta.verify, false);
});

Deno.test('extractAnswerMeta — [[used: none]] is an empty set, not "unknown"', () => {
  assertEquals(extractAnswerMeta('x\n[[used: none]]').usedIds, new Set());
});

Deno.test('decideNotice — health/fiqh without citations is AI-generated; with citations it is not', () => {
  assertEquals(decideNotice({ topic: 'health', fallbackTopic: 'general', verify: false, citationCount: 0 }), {
    aiGenerated: true,
    verify: null,
    topic: 'health',
  });
  assertEquals(decideNotice({ topic: 'fiqh', fallbackTopic: 'fiqh', verify: true, citationCount: 2 }), {
    aiGenerated: false,
    verify: 'fiqh',
    topic: 'fiqh',
  });
  assertEquals(decideNotice({ topic: 'health', fallbackTopic: 'health', verify: true, citationCount: 0 }).verify, 'medical');
});

Deno.test('decideNotice — greetings and general answers carry nothing; a missing topic falls back to the chat subject', () => {
  assertEquals(decideNotice({ topic: 'social', fallbackTopic: 'health', verify: true, citationCount: 0 }), {
    aiGenerated: false,
    verify: null,
    topic: 'social',
  });
  assertEquals(decideNotice({ topic: null, fallbackTopic: 'fiqh', verify: false, citationCount: 0 }).aiGenerated, true);
  assertEquals(decideNotice({ topic: null, fallbackTopic: 'general', verify: false, citationCount: 0 }).aiGenerated, false);
});

Deno.test('acceptRoute — never to itself, never back to where she came from', () => {
  assertEquals(acceptRoute('fiqh', 'general', null), 'fiqh');
  assertEquals(acceptRoute('fiqh', 'fiqh', null), null);
  assertEquals(acceptRoute('health', 'fiqh', 'health'), null);
  assertEquals(acceptRoute(null, 'general', null), null);
  assertEquals(normalizeRoutedFrom('dream'), null);
  assertEquals(normalizeRoutedFrom('general'), 'general');
});

Deno.test('asksAboutWarningSigns — only warning/emergency questions search the safety library', () => {
  assertEquals(asksAboutWarningSigns('هل الجماع وقت الدورة له أضرار؟'), false);
  assertEquals(asksAboutWarningSigns('ما علاج اللون الأحمر الغامق للدم؟'), false);
  assertEquals(asksAboutWarningSigns('متى أروح الطوارئ إذا زاد النزول؟'), true);
  assertEquals(asksAboutWarningSigns('what are the warning signs in pregnancy'), true);
});

Deno.test('answerMetaInstruction — asks for used IDs only when there is a library, and only the allowed routes', () => {
  const general = answerMetaInstruction({ knowledge: false, routes: ['fiqh', 'health'] });
  assertEquals(general.includes('[[used:'), false);
  assertEquals(general.includes('[[route: fiqh]] or [[route: health]]'), true);
  const doctor = answerMetaInstruction({ knowledge: true, routes: ['fiqh'] });
  assertEquals(doctor.includes('[[used:'), true);
  assertEquals(doctor.includes('[[route: health]]'), false);
});
