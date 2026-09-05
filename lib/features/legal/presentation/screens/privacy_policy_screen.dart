import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/theme/app_theme.dart';

String _pr(String en, String ar) => AppLocaleController.instance.text(en, ar);

/// A factual, technical description of what Niswah actually does with
/// personal data, derived directly from the current implementation
/// (Privacy/Compliance remediation, PC-003/PC-004/RD-007). Deliberately
/// **not** a substitute for legal review — see the disclaimer section at
/// the top. Shown in-app (no external hosting dependency) so the sign-up
/// consent flow and account/settings screens have a real, reachable
/// destination; a publicly-hosted copy is still required for app-store
/// privacy-policy URL fields — see the remediation report for that
/// specific OWNER_ACTION.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(_pr('Privacy Policy', 'سياسة الخصوصية')),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Notice(
                text: _pr(
                  'This document describes, factually, what data Niswah '
                  'collects and how it is actually used, based on the '
                  'app\'s current implementation. It is not a substitute '
                  'for legal advice and does not itself constitute a legal '
                  'compliance guarantee.',
                  'يصف هذا المستند بشكل واقعي البيانات التي يجمعها تطبيق '
                  'نِسوة وكيفية استخدامها فعلياً، استناداً إلى التطبيق '
                  'الحالي. لا يُغني هذا عن الاستشارة القانونية ولا يُعدّ '
                  'بحد ذاته ضماناً للامتثال القانوني.',
                ),
              ),
              const SizedBox(height: 24),
              _Section(
                title: _pr('Data we collect', 'البيانات التي نجمعها'),
                body: _pr(
                  '• Account data: email or phone number, display name, and '
                  'your chosen fiqh madhhab.\n'
                  '• Cycle/haid data: dates, flow level, symptoms, and notes '
                  'you log.\n'
                  '• Pregnancy data: tracking basis, reference dates, week, '
                  'and related fields you provide.\n'
                  '• Prayer tracking: which prayers you mark completed, '
                  'missed, or excused, and when.\n'
                  '• Chat messages: what you write to Dr. Niswah, the Fiqh '
                  'Advisor, the Dream Interpreter, and the general '
                  'assistant, plus the replies you receive.\n'
                  '• Community content: posts and comments you choose to '
                  'publish, and whether you post anonymously.\n'
                  '• Device location: only if you grant permission, used to '
                  'compute local prayer times — stored only on your device, '
                  'never sent to our servers.',
                  '• بيانات الحساب: البريد الإلكتروني أو رقم الهاتف، الاسم '
                  'الظاهر، والمذهب الفقهي الذي تختارينه.\n'
                  '• بيانات الدورة/الحيض: التواريخ، شدة التدفق، الأعراض، '
                  'والملاحظات التي تسجلينها.\n'
                  '• بيانات الحمل: أساس التتبع، التواريخ المرجعية، الأسبوع، '
                  'والحقول المرتبطة التي تُدخلينها.\n'
                  '• تتبع الصلاة: الصلوات التي تُعلّمينها كمُصلّاة أو '
                  'فائتة أو معذورة، ووقت ذلك.\n'
                  '• رسائل المحادثة: ما تكتبينه للطبيبة نِسوة، المستشار '
                  'الفقهي، مفسّر الأحلام، والمساعد العام، بالإضافة إلى '
                  'الردود التي تتلقينها.\n'
                  '• محتوى المجتمع: المنشورات والتعليقات التي تختارين '
                  'نشرها، وما إذا كنتِ تنشرين بشكل مجهول.\n'
                  '• موقع الجهاز: فقط إذا منحتِ الإذن، ويُستخدم لحساب '
                  'أوقات الصلاة المحلية — يُخزَّن على جهازكِ فقط، ولا '
                  'يُرسل إلى خوادمنا أبداً.',
                ),
              ),
              _Section(
                title: _pr('Where your data goes', 'إلى أين تذهب بياناتكِ'),
                body: _pr(
                  'Account, cycle, pregnancy, prayer, chat, and community '
                  'data are stored on Supabase (our backend database and '
                  'authentication provider). Cycle and prayer data are also '
                  'cached on your device so the app works offline, and sync '
                  'to your account when a connection is available.\n\n'
                  'When you use an AI feature (Dr. Niswah, Fiqh Advisor, '
                  'Dream Interpreter, or the general assistant), the '
                  'relevant message content and the minimum profile/health '
                  'context that feature needs is sent to Google\'s Gemini '
                  'API through our own server (never directly from your '
                  'device) to generate a reply.\n\n'
                  'When the app reports a technical error, diagnostic '
                  'information (never your health data, chat content, or '
                  'credentials — see "Error reporting" below) may be sent '
                  'to Sentry, our crash/error-monitoring provider.',
                  'تُخزَّن بيانات الحساب والدورة والحمل والصلاة والمحادثة '
                  'والمجتمع على Supabase (قاعدة بياناتنا الخلفية ومزوّد '
                  'المصادقة). كما تُخزَّن بيانات الدورة والصلاة مؤقتاً على '
                  'جهازكِ ليعمل التطبيق دون اتصال، وتتم مزامنتها مع '
                  'حسابكِ عند توفر الاتصال.\n\n'
                  'عند استخدام إحدى ميزات الذكاء الاصطناعي (الطبيبة نِسوة، '
                  'المستشار الفقهي، مفسّر الأحلام، أو المساعد العام)، '
                  'يُرسل محتوى الرسالة والحد الأدنى من سياق الملف '
                  'الشخصي/الصحي الذي تحتاجه تلك الميزة إلى واجهة Gemini من '
                  'Google عبر خادمنا الخاص (وليس مباشرة من جهازكِ) لإنشاء '
                  'الرد.\n\n'
                  'عند إبلاغ التطبيق عن خطأ تقني، قد تُرسل معلومات '
                  'تشخيصية (ليست بياناتكِ الصحية أو محتوى محادثاتكِ أو '
                  'بيانات اعتمادكِ أبداً — انظري "الإبلاغ عن الأخطاء" '
                  'أدناه) إلى Sentry، مزوّد مراقبة الأعطال والأخطاء لدينا.',
                ),
              ),
              _Section(
                title: _pr(
                  'Third parties that process your data',
                  'الأطراف الثالثة التي تعالج بياناتكِ',
                ),
                body: _pr(
                  '• Supabase — hosts our database, authentication, and '
                  'server-side functions.\n'
                  '• Google (Gemini API) — generates AI replies for Dr. '
                  'Niswah, Fiqh Advisor, Dream Interpreter, and the general '
                  'assistant. Message content and minimum necessary '
                  'profile/health context are sent server-side for this '
                  'purpose only.\n'
                  '• Sentry — receives technical error reports (see above) '
                  'to help us find and fix bugs.\n\n'
                  'We do not sell your data, and we do not share it with '
                  'any other third party for advertising.',
                  '• Supabase — تستضيف قاعدة بياناتنا والمصادقة والوظائف '
                  'الخلفية.\n'
                  '• Google (واجهة Gemini) — تُنشئ ردود الذكاء الاصطناعي '
                  'للطبيبة نِسوة والمستشار الفقهي ومفسّر الأحلام والمساعد '
                  'العام. يُرسل محتوى الرسالة والحد الأدنى الضروري من '
                  'سياق الملف الشخصي/الصحي لهذا الغرض فقط.\n'
                  '• Sentry — تتلقى تقارير الأخطاء التقنية (انظري أعلاه) '
                  'لمساعدتنا في اكتشاف الأخطاء وإصلاحها.\n\n'
                  'نحن لا نبيع بياناتكِ، ولا نشاركها مع أي طرف ثالث آخر '
                  'لأغراض إعلانية.',
                ),
              ),
              _Section(
                title: _pr('Your control over your data', 'تحكّمكِ في بياناتكِ'),
                body: _pr(
                  '• You can update or delete individual cycle, pregnancy, '
                  'and prayer entries from within the app.\n'
                  '• You can delete your entire account from Profile → '
                  'Delete Account. This permanently removes your account '
                  'and all associated data from our database — this action '
                  'cannot be undone.\n'
                  '• You can export curated PDF reports of your data from '
                  'Profile → Data Export.',
                  '• يمكنكِ تحديث أو حذف إدخالات فردية للدورة والحمل '
                  'والصلاة من داخل التطبيق.\n'
                  '• يمكنكِ حذف حسابكِ بالكامل من الملف الشخصي ← حذف '
                  'الحساب. يؤدي هذا إلى إزالة حسابكِ وجميع البيانات '
                  'المرتبطة به نهائياً من قاعدة بياناتنا — لا يمكن '
                  'التراجع عن هذا الإجراء.\n'
                  '• يمكنكِ تصدير تقارير PDF منسّقة لبياناتكِ من الملف '
                  'الشخصي ← تصدير البيانات.',
                ),
              ),
              _Section(
                title: _pr('Error reporting', 'الإبلاغ عن الأخطاء'),
                body: _pr(
                  'When the app encounters a technical error, we may send a '
                  'diagnostic report containing the error type, an opaque '
                  'record identifier where relevant, and environment/app '
                  'version information — never full health-record content, '
                  'chat message text, passwords, or authentication tokens.',
                  'عند مواجهة التطبيق لخطأ تقني، قد نرسل تقريراً تشخيصياً '
                  'يحتوي على نوع الخطأ، ومعرّف سجل مجرّد عند الحاجة، '
                  'ومعلومات البيئة/إصدار التطبيق — وليس أبداً محتوى '
                  'السجلات الصحية الكاملة، أو نص رسائل المحادثة، أو كلمات '
                  'المرور، أو رموز المصادقة.',
                ),
              ),
              _Section(
                title: _pr('Retention', 'الاحتفاظ بالبيانات'),
                body: _pr(
                  'Your data is retained for as long as your account '
                  'exists, unless you delete individual entries yourself. '
                  'We have not yet defined a fixed maximum retention period '
                  'for each data category — this policy will be updated '
                  'once one is set.',
                  'تُحفظ بياناتكِ طالما بقي حسابكِ قائماً، ما لم تحذفي '
                  'إدخالات فردية بنفسكِ. لم نُحدّد بعد فترة احتفاظ قصوى '
                  'ثابتة لكل فئة من البيانات — سيتم تحديث هذه السياسة '
                  'عند تحديدها.',
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFEF3C7),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFFDE68A)),
    ),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12.5, height: 1.6, color: Color(0xFF92400E)),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          style: const TextStyle(
            fontSize: 13,
            height: 1.7,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    ),
  );
}
