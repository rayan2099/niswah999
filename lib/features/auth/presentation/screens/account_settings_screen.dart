import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../viewmodels/profile_view_model.dart';
import 'profile_screen.dart';

String _ac(String en, String ar) => AppLocaleController.instance.text(en, ar);

class AccountSettingsScreen extends StatelessWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_ac('Account settings', 'إعدادات الحساب'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: Text(_ac('Profile details', 'تفاصيل الملف الشخصي')),
              subtitle: Text(
                _ac(
                  'Edit your public details and contact info',
                  'عدّلي بياناتكِ العامة ومعلومات التواصل',
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ProfileScreen(),
                  ),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.security_rounded),
              title: Text(_ac('Privacy & security', 'الخصوصية والأمان')),
              subtitle: Text(
                _ac(
                  'Protected access and session handling',
                  'وصول محمي وإدارة آمنة للجلسة',
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _ac(
                        'Your session is securely managed.',
                        'تتم إدارة جلستكِ بأمان.',
                      ),
                    ),
                  ),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: Colors.red),
              title: Text(_ac('Log out', 'تسجيل الخروج')),
              subtitle: Text(
                _ac('End the current session', 'إنهاء الجلسة الحالية'),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                final viewModel = ProfileViewModel();
                try {
                  await viewModel.signOut();
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(error.toString())));
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
