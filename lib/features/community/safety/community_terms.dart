import '../../../core/config/support_contact.dart';
import '../../../core/localization/app_locale_controller.dart';

String _t(String en, String ar) => AppLocaleController.instance.text(en, ar);

/// The community terms every member accepts before posting, commenting or
/// messaging (App Store Review Guideline 1.2).
///
/// [version] must equal `public.community_terms_version()` in
/// supabase/migrations/20261030090000_community_ugc_safety.sql — the
/// database refuses writes from members who have not accepted that exact
/// version. test/community_safety_contract_test.dart keeps them equal.
/// Changing the wording materially means bumping both, which asks every
/// member to accept again.
abstract final class CommunityTerms {
  static const String version = '2026-10-30';

  static String get title =>
      _t('Community guidelines and terms', 'إرشادات المجتمع وشروطه');

  static String get summary => _t(
    'Niswah Community is a safe space for women. We have zero tolerance '
        'for objectionable content or abusive members.',
    'مجتمع نِسوة مساحة آمنة للنساء. لا نتسامح إطلاقاً مع المحتوى المسيء '
        'أو العضوات المسيئات.',
  );

  /// Each rule as one short paragraph, shown in the acceptance gate and on
  /// the full guidelines screen.
  static List<String> get rules => [
    _t(
      'No harassment, bullying, threats, hate speech, or insults about '
          'anyone\'s faith, madhhab, body, or choices.',
      'لا تحرّش ولا تنمّر ولا تهديد ولا خطاب كراهية ولا إساءة لدين أحد أو '
          'مذهبه أو جسده أو اختياراته.',
    ),
    _t(
      'No sexual, explicit, violent, or self-harm content, and no spam, '
          'scams, or advertising.',
      'لا محتوى جنسياً أو فاضحاً أو عنيفاً أو يشجع على إيذاء النفس، ولا '
          'رسائل مزعجة أو احتيال أو إعلانات.',
    ),
    _t(
      'Do not share anyone\'s personal information, including your own '
          'contact details, address, or photos of others.',
      'لا تشاركي معلومات شخصية لأي أحد، بما في ذلك بيانات تواصلكِ أو '
          'عنوانكِ أو صور الآخرين.',
    ),
    _t(
      'Community posts are peer support, not medical or fiqh rulings. '
          'Ask a doctor or a qualified scholar for those.',
      'منشورات المجتمع دعم بين الأخوات، وليست فتاوى أو تشخيصاً طبياً. '
          'اسألي الطبيبة أو العالِمة المؤهلة عن ذلك.',
    ),
    _t(
      'Messages with banned words are blocked automatically. You can '
          'report any post, comment, message, or member, and block anyone '
          'who bothers you.',
      'تُمنع تلقائياً الرسائل التي تحتوي على كلمات محظورة. يمكنكِ الإبلاغ '
          'عن أي منشور أو تعليق أو رسالة أو عضوة، وحظر من يزعجكِ.',
    ),
    _t(
      'Our moderators review reports within 24 hours. Content that breaks '
          'these rules is removed, and members who post it are suspended '
          'from Community.',
      'تراجع المشرفات البلاغات خلال 24 ساعة. يُحذف المحتوى المخالف لهذه '
          'القواعد، وتُوقف العضوات اللواتي ينشرنه عن المجتمع.',
    ),
  ];

  static String get contactLine {
    final email = SupportContact.email;
    if (email == null) {
      return _t(
        'To reach the Niswah team, use Report on any post or member.',
        'للتواصل مع فريق نِسوة، استخدمي زر الإبلاغ على أي منشور أو عضوة.',
      );
    }
    return _t(
      'To reach the Niswah team about safety or anything else, email $email.',
      'للتواصل مع فريق نِسوة بخصوص الأمان أو أي أمر آخر، راسلينا على $email.',
    );
  }
}
