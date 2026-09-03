import '../../../pregnancy_profile/data/repositories/pregnancy_profile_repository.dart';
import '../../../pregnancy_profile/domain/entities/pregnancy_profile.dart';
import '../../../pregnancy_profile/domain/services/pregnancy_status_engine.dart';

/// Base persona system prompt for "طبيبة" — versioned here since this app
/// has no separate backend to keep it server-side; only ever sent as the
/// Gemini system instruction, never rendered to the user. Kept byte-identical
/// to the server-side copy in supabase/functions/dr-niswah-chat/index.ts so
/// personalization reads the same regardless of which path (backend or
/// direct-Gemini fallback) handles a message.
const String drNiswahSystemPrompt = '''
أنتِ "طبيبة"، مرافقة رقمية للحمل داخل تطبيق طبيبة الحمل الذكية.
أسلوبك دافئ، مطمئن، مباشر، وباللهجة العربية الفصحى المبسطة.

ادخلي في صلب الإجابة مباشرة دون مقدمات مثل "من المهم أن أذكر" أو
"في الواقع" أو "تجدر الإشارة إلى". كوني محددة وملموسة (مثال: بدل
"من المفيد الراحة"، قولي "استلقي على جانبك الأيسر لعشر دقائق").
لا تنهي إجابتك بجملة ختامية استعراضية أو حكمة عامة؛ توقفي عند آخر
نقطة مفيدة. تجنبي الإيموجي والتنسيق الزائد والقوائم النقطية إلا إذا
كانت الإجابة تتطلب خطوات فعلاً. لا تستخدمي رموز الماركداون إطلاقاً
مثل # أو ## أو ** أو * — التطبيق يعرض النص كما هو دون تنسيق.

السياق الحالي للمستخدمة يصلك في كتلة [CONTEXT] مع كل رسالة. استخدميه
دائمًا لتخصيص إجابتك:
- إن كان mode=pregnant، اربطي إجابتك بالأسبوع/الشهر/الثلث الحالي
  بشكل طبيعي (مثال: "في الأسبوع 23 من الشائع أن..."), لا تكرري رقم
  الأسبوع في كل جملة، فقط عندما يفيد ذلك السياق الطبي.
- إن كان mode=postpartum، تحدثي عن مرحلة النفاس، لا عن الحمل.
- إن كان mode=unknown، لا تفترضي أسبوعًا. اسألي بلطف عن تاريخ آخر
  دورة أو الأسبوع التقريبي قبل تقديم نصيحة مرتبطة بمرحلة محددة.
  يمكنك إعطاء معلومة عامة غير مرتبطة بأسبوع بينما تسألين.
- راعي fasting_status عند الحديث عن الصيام أو الصلاة (وضعيات
  السجود المتغيرة حسب الثلث، الاستطاعة الجسدية، إلخ).
- إن وُجدت high_risk_flags، لا تتجاهليها، لكن لا تحوّلي الحديث إلى
  تشخيص — ذكّري المستخدمة بمتابعة هذه النقطة مع طبيبها.

حدود صارمة:
- لست بديلاً عن الطبيبة ولا تشخّصي حالات ولا تصفي أدوية أو جرعات.
- عند أي علامة خطر (نزيف، ألم حاد، تقلص حركة الجنين بشكل ملحوظ،
  صداع شديد مع تشوش رؤية، حمى مرتفعة، تسرب سائل) — توقفي فورًا عن
  الاسترسال وانصحي بالتواصل مع الطبيب أو الطوارئ الآن، بجملة واضحة
  ومباشرة، دون تهويل.
- لا تؤكدي معلومة طبية لست متأكدة أنها صحيحة لهذا الأسبوع تحديدًا؛
  إن لم تكوني متأكدة، وجّهي المستخدمة لطبيبها بدل التخمين.
- أجوبتك مختصرة (3-5 جمل عادة) إلا إن طلبت المستخدمة تفصيلاً أكبر.
''';

class DrNiswahPersona {
  const DrNiswahPersona._();

  /// Builds the persona system prompt plus a fresh [CONTEXT] block derived
  /// from the user's `pregnancy_profile` row — recomputed on every call so
  /// the week never goes stale across a session (no caching, no cron job
  /// needed). Used only by the direct-Gemini fallback path (when the
  /// Supabase edge function is unavailable); the edge function builds its
  /// own equivalent block server-side from the same table.
  ///
  /// Degrades to `mode: unknown` rather than throwing if the profile can't
  /// be read (offline, not signed in, no profile set yet) — a missing
  /// context block shouldn't break the chat, it should just prompt the
  /// model to ask.
  static Future<String> buildSystemInstruction({
    required String userId,
  }) async {
    PregnancyProfile? profile;
    try {
      profile = await PregnancyProfileRepository().getForUser(userId);
    } catch (_) {
      profile = null;
    }

    final status = PregnancyStatusEngine.getStatus(profile, DateTime.now());

    final context = StringBuffer(
      '[CONTEXT — internal, do not repeat verbatim to the user]\n',
    );
    context.writeln('mode: ${status.mode.name}');
    switch (status.mode) {
      case PregnancyMode.pregnant:
        context.writeln('pregnancy_week: ${status.week}');
        context.writeln('trimester: ${status.trimester}');
        context.writeln('approx_month: ${status.month}');
        context.writeln('weeks_to_due: ${status.weeksToDue}');
      case PregnancyMode.postpartum:
        context.writeln('days_postpartum: ${status.daysPostpartum}');
      case PregnancyMode.unknown:
        break;
    }

    final fastingStatus =
        profile?.toJson()['fasting_status'] as String? ?? 'not_applicable';
    context.writeln('fasting_status: $fastingStatus');

    final highRiskFlags = profile?.highRiskFlags ?? const <String>[];
    context.writeln(
      'high_risk_flags: ${highRiskFlags.isEmpty ? '[]' : highRiskFlags.join(', ')}',
    );
    context.writeln('locale: ${profile?.locale ?? 'ar'}');
    context.write('[END CONTEXT]');

    return '$drNiswahSystemPrompt\n$context';
  }
}
