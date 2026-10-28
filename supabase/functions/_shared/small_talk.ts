// Short social messages ("شكرا", "hi", "تمام") are not questions, so the
// KB-grounded chats must not answer them with the "no verified knowledge"
// refusal (2026-10-28 device run, A6). A message counts only when the WHOLE
// message is one of the phrases below once punctuation, emoji and Arabic
// diacritics are removed, so any real question still goes through retrieval
// and the fail-closed gate. The replies are fixed text: no model call, no
// health or fiqh claim.

export type SmallTalkKind = 'thanks' | 'greeting' | 'acknowledgement';
export type SmallTalkPersona = 'dr_niswah' | 'fiqh_advisor';

const PHRASES: Record<SmallTalkKind, string[]> = {
  thanks: [
    'شكرا', 'شكرا لك', 'شكرا لكي', 'شكرا جزيلا', 'شكرا كثير', 'مشكوره', 'مشكورة',
    'جزاك الله خير', 'جزاك الله خيرا', 'جزاكي الله خير', 'جزاكم الله خير', 'الله يجزاك خير',
    'الله يعطيك العافيه', 'يعطيك العافيه', 'تسلمين', 'تسلمي', 'thanks', 'thank you',
    'thank you so much', 'thanks a lot', 'thx', 'ty',
  ],
  greeting: [
    'السلام عليكم', 'السلام عليكم ورحمه الله', 'السلام عليكم ورحمه الله وبركاته', 'سلام',
    'مرحبا', 'اهلا', 'اهلا وسهلا', 'هلا', 'صباح الخير', 'مساء الخير', 'hi', 'hello', 'hey',
    'salam', 'assalamu alaikum', 'good morning', 'good evening',
  ],
  acknowledgement: [
    'تمام', 'طيب', 'اوكي', 'حسنا', 'فهمت', 'واضح', 'ok', 'okay', 'got it', 'great', 'cool',
  ],
};

export function normalizeSmallTalk(text: string): string {
  return text
    .toLowerCase()
    .replace(/[\u{064B}-\u{065F}\u{0670}\u{0640}]/gu, '') // harakat, tatweel
    .replace(/[أإآ]/g, 'ا')
    .replace(/ة/g, 'ه')
    .replace(/ى/g, 'ي')
    .replace(/[^\p{L}\p{N}\s]/gu, ' ') // punctuation, emoji
    .replace(/\s+/g, ' ')
    .trim();
}

const LOOKUP = new Map<string, SmallTalkKind>();
for (const [kind, phrases] of Object.entries(PHRASES) as [SmallTalkKind, string[]][]) {
  for (const phrase of phrases) LOOKUP.set(normalizeSmallTalk(phrase), kind);
}

export function detectSmallTalk(text: string): SmallTalkKind | null {
  const normalized = normalizeSmallTalk(text);
  if (!normalized || normalized.length > 40) return null;
  return LOOKUP.get(normalized) ?? null;
}

const REPLIES: Record<SmallTalkPersona, Record<SmallTalkKind, { ar: string; en: string }>> = {
  dr_niswah: {
    thanks: {
      ar: 'العفو، سعيدة بمساعدتكِ. إذا كان لديكِ سؤال آخر عن صحتكِ فأنا هنا.',
      en: "You're welcome, I'm glad to help. If you have another question about your health, I'm here.",
    },
    greeting: {
      ar: 'أهلًا بكِ. اسأليني عن الدورة أو الحمل أو ما بعد الولادة أو صحتكِ النفسية.',
      en: 'Hello. Ask me about your cycle, pregnancy, postpartum or emotional wellbeing.',
    },
    acknowledgement: {
      ar: 'تمام. إذا احتجتِ أي توضيح آخر فاسأليني.',
      en: 'Okay. If you need anything else clarified, just ask.',
    },
  },
  fiqh_advisor: {
    thanks: {
      ar: 'العفو، وجزاكِ الله خيرًا. إذا كان لديكِ سؤال آخر عن أحكام الحيض أو الطهارة فأنا هنا.',
      en: "You're welcome. If you have another question about menstruation or purity rulings, I'm here.",
    },
    greeting: {
      ar: 'وعليكم السلام، أهلًا بكِ. اسأليني عن أحكام الحيض أو النفاس أو الاستحاضة أو الصلاة والصيام.',
      en: 'Hello. Ask me about the rulings of menstruation, postpartum bleeding, istihadah, prayer or fasting.',
    },
    acknowledgement: {
      ar: 'تمام. إذا احتجتِ أي توضيح آخر فاسأليني.',
      en: 'Okay. If you need anything else clarified, just ask.',
    },
  },
};

export function smallTalkReply(
  kind: SmallTalkKind,
  persona: SmallTalkPersona,
  language: 'ar' | 'en',
): string {
  return REPLIES[persona][kind][language];
}
