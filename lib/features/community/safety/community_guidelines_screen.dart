import 'package:flutter/material.dart';

import '../../../core/config/support_contact.dart';
import '../../../core/localization/app_locale_controller.dart';
import 'community_terms.dart';

String _t(String en, String ar) => AppLocaleController.instance.text(en, ar);

/// The full community guidelines (terms of use for user-generated content)
/// and the published contact for the Niswah team.
class CommunityGuidelinesScreen extends StatelessWidget {
  const CommunityGuidelinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final email = SupportContact.email;
    return Scaffold(
      appBar: AppBar(title: Text(CommunityTerms.title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                CommunityTerms.summary,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              for (final rule in CommunityTerms.rules)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text('• $rule', style: textTheme.bodyMedium),
                ),
              const SizedBox(height: 8),
              Text(
                _t('How to report or block', 'كيف تبلّغين أو تحظرين'),
                style: textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Text(
                _t(
                  'Tap ••• on any post, comment, or member, or the menu in a '
                      'private chat, and choose Report or Block. Long-press a '
                      'message to report it. Manage blocked members from '
                      'Profile → Blocked members.',
                  'اضغطي ••• على أي منشور أو تعليق أو عضوة، أو القائمة في '
                      'المحادثة الخاصة، واختاري إبلاغ أو حظر. اضغطي مطولاً '
                      'على رسالة للإبلاغ عنها. تُدار العضوات المحظورات من '
                      'الملف الشخصي ← العضوات المحظورات.',
                ),
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              Text(
                _t('Contact us', 'تواصلي معنا'),
                style: textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              if (email != null)
                SelectableText(email, style: textTheme.bodyLarge),
              Text(CommunityTerms.contactLine, style: textTheme.bodyMedium),
              const SizedBox(height: 20),
              Text(
                _t(
                  'Version ${CommunityTerms.version}',
                  'الإصدار ${CommunityTerms.version}',
                ),
                style: textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
