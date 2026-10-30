// Replies for a knowledge-grounded chat when no reviewed knowledge supports
// an answer. The fail-closed rule is unchanged: the model is never called to
// answer from its own knowledge. What changed (testing feedback 2026-10-30)
// is that one rigid sentence answered three different situations:
//   - a vague message ("ممكن تجاوب؟" with nothing before it): ask what she
//     means instead of refusing;
//   - a question outside this chat's subject: say where it belongs;
//   - a real question the reviewed library does not cover: say so briefly,
//     without the emergency line on every non-urgent message.
// The texts are fixed: no model call, no health or fiqh claim. Red-flag
// messages never reach these replies; they keep the urgent banner.

import { checkQueryRelevance } from './kb_relevance_gate.ts';

export type NoEvidenceKind = 'clarify' | 'out_of_scope' | 'not_covered';
export type NoEvidencePersona = 'dr_niswah' | 'fiqh_advisor';

const SHORT_MESSAGE_MAX_WORDS = 8;

/** Why there is nothing to ground an answer on. [retrievalQuery] is the text
 * retrieval searched with (the message plus, for a short follow-up, the
 * previous user message). */
export function classifyNoEvidence(retrievalQuery: string, message: string): NoEvidenceKind {
  if (checkQueryRelevance(retrievalQuery).allow) return 'not_covered';
  const words = message.trim().split(/\s+/).filter(Boolean).length;
  return words <= SHORT_MESSAGE_MAX_WORDS ? 'clarify' : 'out_of_scope';
}

const REPLIES: Record<NoEvidencePersona, Record<NoEvidenceKind, { ar: string; en: string }>> = {
  dr_niswah: {
    clarify: {
      ar: 'لم أفهم سؤالكِ تمامًا. هل تقصدين شيئًا عن الدورة، أو الحمل، أو ما بعد الولادة؟ اكتبي لي التفاصيل وسأساعدكِ.',
      en: "I didn't quite catch your question. Is it about your cycle, pregnancy or postpartum? Tell me a bit more and I'll help.",
    },
    out_of_scope: {
      ar: 'هذا السؤال خارج اختصاص الطبيبة نسوة؛ فأنا أجيب عن الدورة والحمل وما بعد الولادة والصحة النفسية المرتبطة بها. للأسئلة العامة جرّبي نسوة AI.',
      en: 'That is outside what Doctor Niswah covers: cycles, pregnancy, postpartum and the emotional health around them. For general questions, try Niswah AI.',
    },
    not_covered: {
      ar: 'مكتبة نسوة الصحية المراجَعة لا تغطي هذه النقطة بالتحديد، ولا أريد أن أعطيكِ معلومة غير موثّقة. إذا ذكرتِ تفاصيل أكثر، مثل المدة أو الأعراض المصاحبة، أحاول مرة أخرى، ويمكنكِ أيضًا سؤال طبيبتكِ.',
      en: "Niswah's reviewed health library doesn't cover this specific point, and I don't want to give you something unverified. If you add details, such as how long it has lasted or other symptoms, I'll try again; your doctor can also help.",
    },
  },
  fiqh_advisor: {
    clarify: {
      ar: 'لم يتضح لي السؤال. هل تسألين عن حكم يتعلق بالحيض، أو النفاس، أو الاستحاضة، أو الصلاة والصيام؟ اكتبي لي التفاصيل.',
      en: "I didn't quite catch the question. Is it about a ruling on menstruation, postpartum bleeding, istihadah, prayer or fasting? Tell me more.",
    },
    out_of_scope: {
      ar: 'هذا السؤال خارج ما تغطيه المستشارة الفقهية؛ فهي تجيب عن أحكام الحيض والنفاس والاستحاضة وما يتعلق بها من طهارة وصلاة وصيام.',
      en: 'That is outside what the Fiqh advisor covers: rulings on menstruation, postpartum bleeding and istihadah, and the purity, prayer and fasting questions around them.',
    },
    not_covered: {
      ar: 'لا تتضمن مكتبة نسوة الفقهية المراجَعة نصًا يغطي هذه الحالة في مذهبكِ، لذلك لن أعطيكِ حكمًا غير موثّق. يمكنكِ سؤال عالِمة أو جهة إفتاء تثقين بها.',
      en: "Niswah's reviewed fiqh library has no text covering this case in your madhhab, so I won't give you an unverified ruling. A scholar or fatwa authority you trust can help.",
    },
  },
};

export function noEvidenceReply(
  kind: NoEvidenceKind,
  persona: NoEvidencePersona,
  language: 'ar' | 'en',
): string {
  return REPLIES[persona][kind][language];
}
