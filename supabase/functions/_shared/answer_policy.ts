// How Niswah AI, Doctor Niswah and the Fiqh advisor answer (TestFlight
// Feedback 2, 2026-10-31). Not used by the dream interpreter.
//
// The feedback: answers were refusals or referrals ("لا تتوفر لدي في
// المعرفة المتاحة...", "اسألي المستشارة الفقهية") instead of answers, and
// carried sources that had nothing to do with the question. The causes
// were in the pipeline, not in the wording:
//   1. A fail-closed gate returned fixed text without calling the model
//      whenever the knowledge search found nothing.
//   2. The prompts made the retrieved library the ONLY allowed source, so
//      even when the model was called it refused whatever the library did
//      not literally state, and the general assistant was told to refer
//      every health or fiqh question elsewhere.
//   3. Citations fell back to every retrieved item when the model did not
//      list the ones it used, and Doctor Niswah always searched the safety
//      escalation library, so "Urgent Maternal Warning Signs" was attached
//      to unrelated questions.
//
// Now the model answers from well-established general knowledge when the
// library has nothing relevant, uses library items only when they actually
// support the answer, and says so honestly: an answer with no supporting
// library item carries a short "AI-generated general information" notice
// instead of a citation. This module holds the shared prompt text, the
// trailing-marker parser and the deterministic notice decision.

/** Conversation style shared by the three assistants. */
export const CONVERSATION_STYLE = `How to talk with her:
- Answer the actual question directly, in the first sentence, whenever you reasonably can. Then add what matters in practice.
- Default to a short paragraph or a few short lines. Go longer only when the question needs it or she asks for detail.
- Understand Saudi and Gulf dialect, colloquial phrasing and typos (for example "وش أسوي", "طيب", "مره", "ابي"). Reply in clear, natural Arabic when she writes Arabic (light dialect is fine) and in English when she writes English.
- Earlier turns of this conversation may come before her message. Use them to understand follow-ups such as "لماذا؟", "واللون البني؟", "طيب وش أسوي؟": answer what she means in that context. Never ask her to repeat something already said.
- Ask a clarifying question only when the answer would materially change. When you can, give useful general information first, then ask one short question.
- Do not end every answer with a disclaimer or a referral. Mention a doctor, a scholar or another chat only when it changes what she should do.
- Never invent sources, links, quotations, studies, statistics, scholars or scholarly approval. If you are not confident, say what is uncertain and what would settle it, instead of guessing.
- Never claim to have changed her records, settings or account. You cannot change anything in the app; if she asks, tell her where in the app she can do it.
- Plain text only: no markdown symbols such as #, ** or list bullets. Use short separate lines instead of bullets.`;

/** Instruction for the trailing metadata lines every answer ends with. */
export function answerMetaInstruction(options: {
  knowledge: boolean;
  routes: ReadonlyArray<'fiqh' | 'health'>;
}): string {
  const lines = [
    'After your answer, add these lines at the very end, each on its own line. They are removed before she sees the answer; never mention them:',
    '[[topic: X]] where X is health (her body, symptoms, pregnancy, sexual or mental health), fiqh (a religious ruling or worship question), social (greetings, thanks, small talk) or general (anything else).',
    '[[verify: yes]] only when your answer touches a personal medical or religious decision she is about to make (a treatment, a medication, whether her own prayer or fast is valid) and checking with a doctor or a scholar would genuinely help; otherwise [[verify: no]].',
  ];
  if (options.knowledge) {
    lines.push(
      '[[used: ID1, ID2]] listing ONLY the [KNOWLEDGE] items whose content your answer actually relies on, or [[used: none]]. Never list an item just because it was supplied.',
    );
  }
  if (options.routes.length > 0) {
    const names = options.routes.map((r) => (r === 'fiqh' ? '[[route: fiqh]]' : '[[route: health]]')).join(' or ');
    lines.push(
      `${names} only when you suggest she continue in that other chat in this app (at most once, and only when it would genuinely help her); otherwise leave it out.`,
    );
  }
  return lines.join('\n');
}

/** How a knowledge-backed assistant treats the retrieved library. */
export const KNOWLEDGE_USE_RULES = `Using Niswah's library:
- A [KNOWLEDGE] block may follow with items from Niswah's reviewed library that matched her message by search. Some may be irrelevant to what she actually asked.
- When an item is relevant, prefer it over your general knowledge, keep any QUALIFICATION it carries, and list its ID in [[used: ...]].
- When no item is relevant (or there is no item), answer from well-established general knowledge. Do not refuse because the library is silent, and do not mention the library at all in that case.
- Never say or imply that an answer from your general knowledge comes from Niswah's library, was verified, or was reviewed by a doctor or scholar. Never write source names, links or quotations yourself: the app shows the sources of the items you list.
- Library items are evidence-checked but not personally reviewed by a doctor or scholar for her case (HUMAN_REVIEW_STATUS); never describe them as approved.`;

// ---------------------------------------------------------------------------
// Trailing markers
// ---------------------------------------------------------------------------

export type AnswerTopic = 'health' | 'fiqh' | 'social' | 'general';

export interface AnswerMeta {
  text: string;
  topic: AnswerTopic | null;
  verify: boolean;
  /** null when the model gave no [[used:]] line at all. */
  usedIds: Set<string> | null;
  route: 'fiqh' | 'health' | null;
}

const MARKER_RE = /\[\[\s*(topic|verify|used|route)\s*:\s*([^\]]*)\]\]/gi;

/**
 * Removes every [[topic|verify|used|route: ...]] marker wherever the model
 * put it (normally the last lines) and returns their values. Unknown values
 * are ignored, never guessed.
 */
export function extractAnswerMeta(raw: string): AnswerMeta {
  let topic: AnswerTopic | null = null;
  let verify = false;
  let usedIds: Set<string> | null = null;
  let route: 'fiqh' | 'health' | null = null;
  const text = raw.replace(MARKER_RE, (_m, key: string, value: string) => {
    const v = value.trim().toLowerCase();
    switch (key.toLowerCase()) {
      case 'topic':
        if (v === 'health' || v === 'fiqh' || v === 'social' || v === 'general') topic = v;
        break;
      case 'verify':
        verify = v === 'yes';
        break;
      case 'used': {
        const ids = value.split(',').map((id) => id.trim()).filter((id) => id && id.toLowerCase() !== 'none');
        usedIds = new Set([...(usedIds ?? []), ...ids]);
        break;
      }
      case 'route':
        if (v === 'fiqh' || v === 'health') route = v;
        break;
    }
    return '';
  })
    .replace(/[ \t]+\n/g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
  return { text, topic, verify, usedIds, route };
}

// ---------------------------------------------------------------------------
// Notice under an answer
// ---------------------------------------------------------------------------

export type VerifyKind = 'medical' | 'fiqh';

/** What the app shows under an answer. Codes only; the app holds the text
 * in both languages (see [NOTICE_TEXT] for the exact wording). */
export interface AnswerNotice {
  /** "معلومة عامة مولّدة بالذكاء الاصطناعي، وقد تحتمل الخطأ." */
  aiGenerated: boolean;
  /** Which verification line to add, if any. */
  verify: VerifyKind | null;
  topic: AnswerTopic | null;
}

export const NOTICE_TEXT = {
  aiGenerated: {
    ar: 'معلومة عامة مولّدة بالذكاء الاصطناعي، وقد تحتمل الخطأ.',
    en: 'General information generated by AI; it may contain mistakes.',
  },
  verify: {
    medical: {
      ar: 'تأكدي من طبيبة مختصة قبل اتخاذ قرار علاجي.',
      en: 'Check with a qualified doctor before making a treatment decision.',
    },
    fiqh: {
      ar: 'وللتأكد من الحكم في حالتك، راجعي جهة إفتاء موثوقة أو عالمة تثقين بها.',
      en: 'To confirm the ruling for your own situation, ask a trusted fatwa authority or a scholar you trust.',
    },
  },
} as const;

/**
 * Deterministic: a health or fiqh answer with no supporting library item is
 * marked as AI-generated general information. The verification line is
 * added only when the model judged it a personal decision. Greetings and
 * general answers carry nothing. [fallbackTopic] is the assistant's own
 * subject, used when the model omitted [[topic:]], so a health or fiqh
 * answer is never left unmarked by a missing line.
 */
export function decideNotice(options: {
  topic: AnswerTopic | null;
  fallbackTopic: AnswerTopic;
  verify: boolean;
  citationCount: number;
}): AnswerNotice {
  const topic = options.topic ?? options.fallbackTopic;
  if (topic !== 'health' && topic !== 'fiqh') {
    return { aiGenerated: false, verify: null, topic };
  }
  return {
    aiGenerated: options.citationCount === 0,
    verify: options.verify ? (topic === 'health' ? 'medical' : 'fiqh') : null,
    topic,
  };
}

// ---------------------------------------------------------------------------
// Handoffs between the chats
// ---------------------------------------------------------------------------

export type AssistantId = 'general' | 'health' | 'fiqh';

export function normalizeRoutedFrom(raw: unknown): AssistantId | null {
  return raw === 'general' || raw === 'health' || raw === 'fiqh' ? raw : null;
}

/** A suggested handoff is dropped when it points at this chat or back at
 * the chat she was just sent from, so she can never be bounced in a loop. */
export function acceptRoute(
  route: 'fiqh' | 'health' | null,
  self: AssistantId,
  routedFrom: AssistantId | null,
): 'fiqh' | 'health' | null {
  if (!route || route === self || route === routedFrom) return null;
  return route;
}

export function routedFromInstruction(routedFrom: AssistantId | null): string {
  if (!routedFrom) return '';
  const name = routedFrom === 'general' ? 'Niswah AI' : routedFrom === 'health' ? 'Doctor Niswah' : 'the Fiqh advisor';
  return `She was sent to this chat from ${name} with this question. Answer it here; do not send her back to ${name}.`;
}

/** Whether a non-urgent health message asks about warning signs or when to
 * seek care. Only then is the safety-escalation library searched, so its
 * "Urgent Maternal Warning Signs" items are no longer attached to unrelated
 * questions such as intercourse during the period. */
export function asksAboutWarningSigns(text: string): boolean {
  return /(طوارئ|خطر|خطير|عاجل|اسعاف|إسعاف|متى (?:أ|ا)راجع|متى (?:أ|ا)روح|علامات|warning|emergency|urgent|danger|when (?:should|to) (?:i )?(?:see|call|go))/i
    .test(text);
}
