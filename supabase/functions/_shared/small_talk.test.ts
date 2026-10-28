import { assertEquals } from 'https://deno.land/std@0.208.0/assert/mod.ts';
import { detectSmallTalk, smallTalkReply } from './small_talk.ts';

Deno.test('detectSmallTalk — thanks in Arabic, with diacritics and punctuation', () => {
  assertEquals(detectSmallTalk('شكرا'), 'thanks');
  assertEquals(detectSmallTalk('شكرًا!'), 'thanks');
  assertEquals(detectSmallTalk('  جزاكِ الله خيرًا 🌸 '), 'thanks');
  assertEquals(detectSmallTalk('Thank you.'), 'thanks');
});

Deno.test('detectSmallTalk — greetings and acknowledgements', () => {
  assertEquals(detectSmallTalk('السلام عليكم ورحمة الله وبركاته'), 'greeting');
  assertEquals(detectSmallTalk('مرحباً'), 'greeting');
  assertEquals(detectSmallTalk('ok'), 'acknowledgement');
  assertEquals(detectSmallTalk('تمام'), 'acknowledgement');
});

Deno.test('detectSmallTalk — a real question is never small talk', () => {
  assertEquals(detectSmallTalk('شكرا، متى يستدعي ألم الدورة مراجعة الطبيبة؟'), null);
  assertEquals(detectSmallTalk('hi, is spotting before my period normal?'), null);
  assertEquals(detectSmallTalk('متى أوقف الصلاة؟'), null);
  assertEquals(detectSmallTalk(''), null);
});

Deno.test('smallTalkReply — matches language and persona', () => {
  const ar = smallTalkReply('thanks', 'dr_niswah', 'ar');
  assertEquals(/[\u{0600}-\u{06FF}]/u.test(ar), true);
  const en = smallTalkReply('greeting', 'fiqh_advisor', 'en');
  assertEquals(/[\u{0600}-\u{06FF}]/u.test(en), false);
});
