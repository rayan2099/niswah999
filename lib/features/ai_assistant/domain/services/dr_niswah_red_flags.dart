/// Lightweight keyword check for red-flag symptoms, run independently of
/// the LLM call so the urgent-care banner always shows for a matching
/// message — even if the Gemini request fails or times out.
class DrNiswahRedFlags {
  const DrNiswahRedFlags._();

  static const _bleeding = ['نزيف', 'دم كثير', 'bleeding', 'hemorrhage'];
  static const _severePain = ['ألم حاد', 'ألم شديد', 'severe pain', 'sharp pain'];
  static const _reducedMovement = [
    'تقلص حركة الجنين',
    'الجنين لا يتحرك',
    'حركة الجنين قلت',
    'reduced fetal movement',
    'baby not moving',
    'baby stopped moving',
  ];
  static const _headache = ['صداع شديد', 'severe headache'];
  static const _visionChange = ['تشوش رؤية', 'رؤية ضبابية', 'blurred vision', 'vision changes'];
  static const _fever = ['حمى مرتفعة', 'حمى شديدة', 'high fever', 'severe fever'];
  static const _fluidLeak = [
    'تسرب سائل',
    'نزول ماء',
    'الماء نزل',
    'fluid leakage',
    'water broke',
    'my water broke',
  ];

  static bool matches(String message) {
    final text = message.toLowerCase();
    bool any(List<String> keywords) =>
        keywords.any((keyword) => text.contains(keyword.toLowerCase()));

    if (any(_bleeding)) return true;
    if (any(_severePain)) return true;
    if (any(_reducedMovement)) return true;
    if (any(_fever)) return true;
    if (any(_fluidLeak)) return true;
    if (any(_headache) && any(_visionChange)) return true;

    return false;
  }

  static const bannerTextEn =
      'This may be a red-flag symptom. Please contact your doctor or emergency services now.';
  static const bannerTextAr =
      'قد يكون هذا من علامات الخطر. يُرجى التواصل مع طبيبتك أو الطوارئ الآن.';
}
