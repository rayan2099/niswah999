import '../../core/services/gemini_service.dart';
import '../cycle_tracking/domain/services/madhhab_rule_evaluator.dart';

class AiAdvisorService {
  const AiAdvisorService._();

  static const instance = AiAdvisorService._();

  Future<GeminiResult> askFiqh({
    required String question,
    required Madhhab madhhab,
  }) async {
    final GeminiResult result;
    try {
      result = await GeminiService.instance.generateText(
        prompt: question,
        useGoogleSearch: true,
        systemInstruction:
            '''
You are Niswah's Fiqh research assistant. The user's selected school is ${madhhab.name}.
Answer in the user's language and stay within that school unless comparison is explicitly requested.
Use Google Search for every substantive ruling. Prefer recognized, attributable scholarly sources and structured fatwa repositories such as islamweb.net and dorar.net, then verified school-specific primary or institutional references.
Never infer a ruling from cycle arithmetic alone. Clearly distinguish factual tracking data from a religious ruling.
Include inline citations for every material ruling. If reliable sources conflict, are absent, or the case involves irregular habit transitions, pregnancy, miscarriage, nifas, retrospective prayer/fasting obligations, or danger to health, say that the case needs a qualified scholar and do not give a definitive ruling.
Do not diagnose medical conditions. Urgent or dangerous symptoms must be escalated to licensed medical care.
Do not claim certainty beyond the cited evidence.
Write in plain prose only. Never use markdown syntax: no #, ##, ###, **, *, or numbered/bulleted list characters. The app displays raw text, not rendered markdown.
''',
      );
    } catch (_) {
      return const GeminiResult(
        text: 'تعذر الوصول إلى المصادر الموثقة الآن. لا يمكن إصدار توجيه فقهي آلي دون مصادر؛ يُرجى المحاولة لاحقاً أو سؤال عالِمة أو جهة إفتاء مؤهلة.',
      );
    }
    final trusted = result.citations.where(_isTrustedCitation).toList();
    if (trusted.isEmpty) {
      return const GeminiResult(
        text: 'لم أجد مصادر فقهية موثقة وكافية لهذه الحالة. يُرجى عرض التفاصيل على عالِمة أو جهة إفتاء مؤهلة، ولا تعتمدي على إجابة آلية لاتخاذ حكم العبادة.',
      );
    }
    return GeminiResult(text: result.text, citations: trusted);
  }

  bool _isTrustedCitation(GeminiCitation citation) {
    final host = Uri.tryParse(citation.url)?.host.toLowerCase() ?? '';
    const trustedDomains = {'islamweb.net', 'dorar.net'};
    return trustedDomains.any(
      (domain) => host == domain || host.endsWith('.$domain'),
    );
  }
}
